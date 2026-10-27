% 定义validate_learning_modules函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function report = validate_learning_modules(projectRoot, outputDir)
    %VALIDATE_LEARNING_MODULES 用旧真实检查点作工程对照，验证拆分没有换公式。
    % 这里只把已有网格作为测试输入，不将旧帧头/标注给学习版的捕获步骤。
    % 依次核对参考序列、插值、CP/FFT、信道、似然导数、300列MSS和ML。
    % 参考是原接收机实际保存的首次均衡和跟踪结果，不再运行9帧接收机。

    % 把指定目录加入MATLAB搜索路径，使其中函数可以按名字调用；+slrx包只加父目录。
    % 单引号里的文字是字符数据，不是同名变量。
    addpath(fullfile(projectRoot, 'matlab', 'learning_receiver'));

    % 把指定目录加入MATLAB搜索路径，使其中函数可以按名字调用；+slrx包只加父目录。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    addpath(fullfile(projectRoot, 'matlab', 'baseline'), fullfile(projectRoot, ...
        'matlab', 'visualization'));  % 后续字段/选项名称及对应取值。

    % 建立学习版配置，用固定数值参数与旧接收机做同输入工程对照。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    cfg = slrx.defaultConfig(projectRoot);

    % 设置是否弹出图形窗口；批处理设false但可照常保存PNG。
    cfg.show_figures = false;

    % 只读取先前冻结的学习检查规则，不随结果好坏改门限。
    limits = jsondecode(fileread(fullfile(projectRoot, 'config', ...
        'learning_validation_v1.json')));  % 续接同一调用的其余参数或表达式。

    % 生成学习版公开参考，先确认序列和点序没有因重排而改变。
    refs = slrx.references(cfg);

    % 调用原接收机公开序列接口，作为当前学习版的同输入对照。
    oldRefs = author_sequences(projectRoot);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    assert(isequal(refs.pss, oldRefs.pss) && isequal(refs.sss, ...
        oldRefs.sss) && isequal(refs.pilots, oldRefs.pilots));  % 继续同一检查条件/失败时的说明。

    % 取原接收机使用的四组星座几何，检查学习版候选点及顺序一致。
    C = payload_models();

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(isequaln(refs.constellations, C), '星座几何或内部点序改变');

    % 定位已保存的原接收机检查点；它只用于工程测试，不进入新捕获。
    runDir = fullfile(projectRoot, 'runs', ...
        'codex-author-real-20261014-170603-942987');  % 续接同一调用的其余参数或表达式。

    % 只加载原结果的第1帧，避免为同输入比较重跑全部50ms接收。
    f = load_payload_frame(runDir, 1);

    % 用原同步窗口测试插值模块，输入复数与原函数完全相同。
    window = f.sync_window_raw;

    % 建立固定带小数的采样位置，验证插值而不只是整数索引。
    % 单独的'对复数做共轭转置，与.'不同。
    % 冒号给出索引序列；单独:取整维全部位置。
    positions = (130.125:0.99:1500.25)';

    % 调用学习版sinc插值，得到本轮被测结果。
    x = slrx.alg.interpolateSinc(window, positions);

    % 用相同输入调用原bandlimited_sample，得到对照结果。
    y = bandlimited_sample(window, positions);

    % 对插值结果求归一化差异；max(...,eps)避免零范数除零。
    interpolationError = norm(x - y) / max(norm(y), eps);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(interpolationError <= limits.interpolation_relative_error_max);

    % 直接取原保存的同一时间区间，隔离捕获差异，只比较去CP/FFT数学。
    time.time_cfo_compensated = ...
        f.intermediates.time_initial_doppler.frame_time_cfo_compensated;  % 续接同一调用的其余参数或表达式。

    % 用学习版模块分符号并去CP，PSS依然单独保留。
    ofdm = slrx.removeCP(time, cfg);

    % 对同一有效区逐列FFT，得到学习版1024×301网格。
    frequency = slrx.fftGrid(ofdm, refs, cfg);

    % 与原保存FFT网格计算相对Frobenius误差，检查索引和归一化。
    fftError = norm(frequency.values - f.intermediates.grid_initial_doppler, ...
        'fro') / norm(frequency.values, 'fro');  % 续接同一调用的其余参数或表达式。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fftError <= limits.fft_relative_error_max);

    % 换入原保存的同一再取样网格，接下来只比较信道算法。
    frequency.values = f.grid_resampled;

    % 取原测试所用共享信道形状；默认真实单帧学习入口不会读取它。
    shared = f.intermediates.channel_final.channel_normalized;

    % 显式传相同共享响应做工程对照，不把不同配置的结果强求逐值一样。
    channel = slrx.estimateChannel(frequency, refs, cfg, shared);

    % 原DSP用相同SSS、索引和平滑参数估计H，作为独立对照。
    % (:,1)表示第一列的全部行。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [oldH, oldChannel] = author_receiver_dsp('channel', frequency.values(:, 1), ...
        refs.sss_grid, refs.frequency_bins, cfg.smoothing_window, ...  % 续接同一调用的其余参数或表达式。
        cfg.smoothing_degree, shared);  % 续接同一调用的其余参数或表达式。

    % 比较两份H的归一化差异，检验重写未改变信道估计数学。
    channelError = norm(channel.H - oldH) / norm(oldH);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(channelError <= limits.channel_relative_error_max);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(norm(channel.noise_variance_equalized ...
        - oldChannel.noise_variance_equalized) < 1e-8);  % 继续同一检查条件/失败时的说明。
    % 在同一真实列上核对似然、梯度与Hessian，防止相位/时延符号被重构改反。

    % 取两套算法一致的1004个原FFT载荷行号。
    rows = refs.payload_rows;

    % 选择原首次均衡的第50数据列，即网格第51列，作为似然输入。
    points = f.intermediates.grid_first_equalized(rows, 51);

    % 取对应原信道输出的逐频点噪声方差，避免输入不同造成伪差异。
    variance = f.intermediates.channel_first.noise_variance_equalized(rows);

    % 分号建立2×1参数向量：0.13采样时延、0.21rad相位。
    theta = [0.13; 0.21];

    % 同时计算学习版代价、梯度和Hessian，测试相位/时延的符号与导数。
    % {编号}取得cell格子内部的数据，()则取得格子外壳。
    [v, g, H] = slrx.alg.marginalNLL(theta, points, refs.frequency_bins(rows), ...
        C{3}, variance, [], cfg.nfft);  % 续接同一调用的其余参数或表达式。

    % 用同一输入求原函数的三个返回值，供下面逐项比较。
    [ov, og, oH] = author_receiver_dsp('ml_cost', theta, points, ...
        refs.frequency_bins(rows), C{3}, variance);  % 续接同一调用的其余参数或表达式。

    % 把代价差、梯度差与Hessian差合在一列，再取最大绝对误差。
    % (:)把全部元素按列顺序排成一列。
    likelihoodError = max([abs(v-ov); abs(g-og); abs(H(:)-oH(:))]);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(likelihoodError <= limits.likelihood_absolute_error_max);

    % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
    fprintf('LEARN_PARITY_BASIC_OK fft=%.3g channel=%.3g nll=%.3g\n', fftError, ...
        channelError, likelihoodError);  % 续接同一调用的其余参数或表达式。
    % 拆开的300列识别和跟踪在完全相同输入下应重现旧首次ML。

    % 取原保存的第一轮均衡网格，后续300列测试使用完全相同的输入。
    equalized.values = f.intermediates.grid_first_equalized;

    % 换成第一轮同一噪声估计，保持ML权重一致。
    channel.noise_variance_equalized = ...
        f.intermediates.channel_first.noise_variance_equalized;  % 续接同一调用的其余参数或表达式。

    % 从旧记录恢复同一个基础种子，避免kmeans随机初始化不同。
    seedBase = f.intermediates.first_modulation.records{1}.seed - 1;

    % 学习版从同一网格计算FIT导频初值，EVAL仍不用于拟合。
    pilots = slrx.observePilots(equalized, refs, cfg);

    % 实际重新计算300列K识别，不直接复制旧标签。
    classes = slrx.classifyColumns(equalized, refs, cfg, seedBase);

    % 取旧的300列识别记录，只供验收比较。
    oldModulation = f.intermediates.first_modulation;

    % 比较所有4×300个MSS得分，max(...,'all')在整个矩阵中取最大值。
    scoreError = max(abs(classes.scores - oldModulation.cardinality_scores), ...
        [], 'all');  % 续接同一调用的其余参数或表达式。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(scoreError < 1e-10, '星座点数识别的同输入结果改变');

    % 实际重新运行逐列ML与整帧补偿，不由旧结果替代计算。
    tracked = slrx.trackFrame(equalized, channel, pilots, classes, refs, cfg, ...
        seedBase);  % 续接同一调用的其余参数或表达式。

    % 取旧首次ML趋势作为同输入参考。
    oldTracking = f.intermediates.first_ml_tracking;

    % 比较每列实际使用的相位补偿轨迹，单位rad。
    phaseError = max(abs(tracked.phase_line_rad - oldTracking.phase_intercept_rad));

    % 比较时延拟合直线的斜率/截距，单位沿用模型采样。
    delayError = max(abs(tracked.delay_line_coefficients ...
        - oldTracking.delay_line_coefficients));  % 续接同一调用的其余参数或表达式。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(phaseError <= limits.tracking_absolute_error_max ...
        && delayError <= limits.tracking_absolute_error_max);  % 继续同一检查条件/失败时的说明。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(isequal(tracked.geometry_id, oldModulation.geometry_id_per_data_symbol));

    % 复制同一均衡网格，接下来用原保存参数独立构造预期补偿结果。
    expectedGrid = equalized.values;

    % 对数据列乘原趋势的反向复指数，显式检查补偿符号和FFT索引。
    % .*是对应元素相乘，不是矩阵乘法。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    expectedGrid(:, 2:301) = expectedGrid(:, ...
        2:301) .* exp(1j * ( 2 * pi * refs.frequency_bins / cfg.nfft ...  % 续接同一调用的其余参数或表达式。
        * polyval(oldTracking.delay_line_coefficients, ...  % 续接同一调用的其余参数或表达式。
        1:300) - ones(cfg.nfft, 1) * oldTracking.phase_intercept_rad));  % 续接同一调用的其余参数或表达式。

    % 将学习版补偿网格与独立构造结果求相对误差。
    trackedError = norm(tracked.values - expectedGrid, ...
        'fro') / norm(expectedGrid, 'fro');  % 续接同一调用的其余参数或表达式。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(trackedError < 1e-10, '整帧补偿符号或索引改变');

    % 汇总每项同输入误差，明确这些检查不代表业务译码成功。
    report = struct('status', 'passed', 'version', limits.version, 'owner', ...
        'codex_baseline', 'interpolation_relative_error', interpolationError, ...  % 后续字段/选项名称及对应取值。
        'FFT_relative_error', fftError, 'channel_relative_error', ...  % 摘要字段：保存FFT与独立重算之间的相对误差。
        channelError, 'likelihood_gradient_hessian_max_difference', ...  % 续接同一调用的其余参数或表达式。
        likelihoodError, 'cardinality_score_max_difference', ...  % 续接同一调用的其余参数或表达式。
        scoreError, 'tracking_phase_max_difference_rad', ...  % 续接同一调用的其余参数或表达式。
        phaseError, ...  % 续接同一调用的其余参数或表达式。
        'tracking_delay_coefficient_max_difference', ...  % 后续字段/选项名称及对应取值。
        delayError, 'tracked_grid_relative_error', ...  % 续接同一调用的其余参数或表达式。
        trackedError, 'all_300_geometry_labels_identical', ...  % 续接同一调用的其余参数或表达式。
        true, ...  % 续接同一调用的其余参数或表达式。
        'reference_checkpoint_used_only_for_validation', ...  % 后续字段/选项名称及对应取值。
        true, 'original_evaluator_changed', false, ...  % 续接同一调用的其余参数或表达式。
        'payload_decoded', false);  % 后续字段/选项名称及对应取值。

    % 路径/变量尚不存在时才创建，不覆盖已有运行或用户配置。
    if ~exist(outputDir, 'dir')
        % mkdir创建所需目录；已有原IQ与历史结果不因建目录而覆盖。
        mkdir(outputDir);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 打开工程对照的JSON输出文件，完整接收数组不写进这里。
    fid = fopen(fullfile(outputDir, 'module_parity.json'), 'w');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0);

    % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
    fprintf(fid, '%s', jsonencode(report));

    % 关闭这个文件编号，确保写入完成并释放文件句柄。
    fclose(fid);

    % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
    fprintf('LEARN_ALL_MODULE_PARITY_OK grid=%.3g\n', trackedError);
% 结束这个函数，输出变量按函数声明返回给调用者。
end
