% 定义validateRun函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function result = validateRun(runDir)
    %VALIDATERUN 独立回读学习结果，验证输入、尺寸、FFT/均衡和已运行步骤。
    % 原始IQ和已保存变量回读；不以作者TOA帮助检测，也不修改旧评价器。
    % 若只有前8步，只报告前端数值检查；不会把它记为完整接收成功。
    % 单帧完整学习检查也不替代原评价器至少2帧的要求，没有业务BER。

    % 回读本次学习运行的冻结配置，独立检查不采用屏幕上随手修改的参数。
    % 单引号里的文字是字符数据，不是同名变量。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    saved = load(fullfile(runDir, 'lesson_config.mat'), 'frozenConfig');

    % 从MAT文件的frozenConfig字段取出实际运行配置。
    cfg = saved.frozenConfig;

    % 读取学习版既定检查规则；这里只读，不根据失败降低门槛。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    limits = jsondecode(fileread(fullfile(cfg.project_root, 'config', ...
        'learning_validation_v1.json')));  % 续接同一调用的其余参数或表达式。

    % 生成同版本公开参考，用来独立重算导频误差和索引。
    refs = slrx.references(cfg);

    % 回读第1步MAT，准备与原BIN字节读取结果比较。
    capture = readStep(runDir, '01_capture');

    % 先标partial；只有完整链路和数值条件都满足才改为passed。
    result = struct('status', 'partial', 'version', limits.version, 'owner', ...
        'codex_baseline', 'single_frame_only', true, ...  % 后续字段/选项名称及对应取值。
        'original_evaluator_changed', false, 'payload_bits_available', false);  % 后续字段/选项名称及对应取值。
    % 原BIN中32个复采样的独立读取，确认没有把分量数当作复采样数。

    % 以小端方式独立打开原BIN，不使用主接收模块自报的摘要。
    fid = fopen(cfg.input_file, 'r', 'ieee-le');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0);

    % 从原BIN开头按字节移动读取位置；一份复采样占4字节。
    fseek(fid, 4 * (cfg.first_complex_sample - 1), 'bof');

    % 独立读取32份复采样的I/Q整数分量，用于精确回读检查。
    parts = fread(fid, [2 32], 'int16=>double');

    % 关闭这个文件编号，确保写入完成并释放文件句柄。
    fclose(fid);

    % 把两行整数转成复列向量并除32768，应与第1步前32点精确相同。
    % .'只转置行列，不对复数取共轭。
    % (行号,:)表示这些行的全部列。
    % 冒号给出索引序列；单独:取整维全部位置。
    expected = complex(parts(1, :), parts(2, :)).' / 32768;

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(isequal(capture.iq(1:32), expected), '原始I/Q读取或一基偏移错误');

    % 保存原BIN独立回读与第1步IQ是否逐值一致；之后用“结构名.raw_readback_exact”读取。
    result.raw_readback_exact = true;

    % 只有对应步骤的MAT已经生成才检查它，允许学习流程暂时停在前面某步。
    if exist(fullfile(runDir, '02_resampled.mat'), 'file')
        % 若已做第2步，则回读其实际数据，检查采样率标签。
        sampled = readStep(runDir, '02_resampled');

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(sampled.fs_hz == cfg.model_fs_hz);

        % 保存已检查的模型采样率，单位Hz；之后用“结构名.nominal_sample_rate_hz”读取。
        result.nominal_sample_rate_hz = sampled.fs_hz;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 只有对应步骤的MAT已经生成才检查它，允许学习流程暂时停在前面某步。
    if exist(fullfile(runDir, '03_sync.mat'), 'file')
        % 若已有同步文件，则回读独立检测输出，不调用标注来替它找帧。
        sync = readStep(runDir, '03_sync');

        % 按窗口起点和250/240比例独立重算原文件坐标。
        expectedCapture = cfg.first_complex_sample ...
            + (sync.selected.start_sample_nominal - 1) * cfg.capture_fs_hz ...  % 续接同一调用的其余参数或表达式。
            / cfg.model_fs_hz;  % 续接同一调用的其余参数或表达式。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(abs(sync.selected.start_sample_capture ...
            - expectedCapture) < 1e-8, '同步坐标转换错误');  % 继续同一检查条件/失败时的说明。

        % 保存是否由PSS/SSS独立检测得到，而非借用了标注；之后用“结构名.independent_detection”读取。
        result.independent_detection = ~sync.summary.annotations_used;

        % 保存原BIN连续一基帧起点；之后用“结构名.start_sample_capture”读取。
        result.start_sample_capture = sync.selected.start_sample_capture;

        % 保存两种采样时间轴的独立换算是否一致；之后用“结构名.model_and_capture_coordinate_identity”读
        % 取。
        result.model_and_capture_coordinate_identity = true;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 只有对应步骤的MAT已经生成才检查它，允许学习流程暂时停在前面某步。
    if exist(fullfile(runDir, '06_fft_grid.mat'), 'file')
        % 加载去CP后的时间矩阵，供下一行独立FFT重算。
        time = readStep(runDir, '05_without_cp');

        % 加载保存的FFT网格，而不是直接相信JSON里报告的尺寸。
        frequency = readStep(runDir, '06_fft_grid');

        % 对保存的有效区重新逐列FFT，使用同样的1/sqrt(N)归一化。
        independent = fft(time.without_cp, [], 1) / sqrt(cfg.nfft);

        % 两网格差的Frobenius范数除参考范数，得到无量纲相对误差。
        error = norm(frequency.values - independent, 'fro') / norm(independent, ...
            'fro');  % 续接同一调用的其余参数或表达式。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        % &&要求两侧标量条件都为真，并按需计算右侧。
        assert(isequal(size(frequency.values), ...
            [1024 301]) && error <= limits.fft_relative_error_max);  % 继续同一检查条件/失败时的说明。

        % 保存保存FFT与独立重算之间的相对误差；之后用“结构名.FFT_relative_error”读取。
        result.FFT_relative_error = error;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 只有对应步骤的MAT已经生成才检查它，允许学习流程暂时停在前面某步。
    if exist(fullfile(runDir, '08_equalized.mat'), 'file')
        % 回读实际SSS信道H，重算均衡除法关系。
        channel = readStep(runDir, '07_channel');

        % 回读实际均衡网格，准备与独立计算的Y/H核对。
        equalized = readStep(runDir, '08_equalized');

        % 将已保存均衡网格与Y./H比较，确认步骤输出与记录一致。
        error = norm(equalized.values - frequency.values ./ channel.H, ...
            'fro') / norm(equalized.values, 'fro');  % 续接同一调用的其余参数或表达式。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(error < 1e-12, '均衡除法与保存网格不一致');

        % 保存保存均衡网格与Y/H独立重算的相对误差；之后用“结构名.equalization_relative_error”读取。
        result.equalization_relative_error = error;

        % 保存刚完成均衡、尚未残余跟踪时的留出导频EVM；之后用“结构名.first_equalized_heldout_pilot_evm”
        % 读取。
        result.first_equalized_heldout_pilot_evm = ...
            equalized.heldout_pilot_evm_after;  % 误差能量按参考能量归一化后开方。

        % 保存已经执行的读取/坐标/FFT/均衡检查状态；之后用“结构名.front_end_checks”读取。
        result.front_end_checks = 'passed';
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 只有对应步骤的MAT已经生成才检查它，允许学习流程暂时停在前面某步。
    if exist(fullfile(runDir, '14_decisions.mat'), 'file')
        % 完整链路存在时，回读第二轮最终跟踪网格。
        tracked = readStep(runDir, '13h_tracking');

        % 回读实际条件判决矩阵及其有效/擦除掩码。
        decisions = readStep(runDir, '14_decisions');

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(isequal(size(tracked.values), ...
            [1024 301]) && isequal(size(decisions.hard_symbols), [1004 300]));  % 继续同一检查条件/失败时的说明。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(all(isnan(decisions.hard_symbols(~decisions.valid_mask))) ...
            && all(decisions.point_id_0based(~decisions.valid_mask) == - 1));  % 继续同一检查条件/失败时的说明。

        % 只取留出EVAL导频及300列数据的已知参考。
        reference = refs.pilots(refs.eval_rows, 2:301);

        % 从最终复数组独立重算留出导频EVM，不采用代理或模块自报结果。
        % .^是对各元素分别乘方。
        evm = sqrt(sum(abs(tracked.values(refs.eval_rows, ...
            2:301) - reference) .^ 2, 'all') / sum(abs(reference) .^ 2, 'all'));  % 误差能量按参考能量归一化后开方。

        % 以原FFT误差为分母计算相对改善；它不是业务符号正确率。
        improvement = 1 - evm / equalized.heldout_pilot_evm_before;

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(evm <= limits.real_heldout_pilot_evm_max ...
            && improvement >= limits.real_pilot_relative_improvement_min, ...  % 继续同一检查条件/失败时的说明。
            '留出导频没有达到沿用的真实数据数值规则；不降低门槛');  % 继续同一检查条件/失败时的说明。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(norm(tracked.values(refs.payload_rows, 2:301), 'fro') > 1e-6, ...
            '载荷网格被清零');  % 继续同一检查条件/失败时的说明。

        % 保存机器可读状态；unknown/partial不等于恢复成功；之后用“结构名.status”读取。
        result.status = 'passed';

        % 保存单帧完整链路和本版数值条件是否通过；之后用“结构名.complete_single_frame_pipeline”读取。
        result.complete_single_frame_pipeline = true;

        % 保存最终留出导频EVM，来自保存复数组的独立重算；之后用“结构名.final_heldout_pilot_evm”读取。
        result.final_heldout_pilot_evm = evm;

        % 保存相对原FFT误差的改善比例，不是业务正确率；之后用“结构名.relative_improvement_vs_raw_fft”读取。
        result.relative_improvement_vs_raw_fft = improvement;

        % 保存当前几何模型下实际给出条件判决的位置数；之后用“结构名.valid_hard_symbol_count”读取。
        result.valid_hard_symbol_count = nnz(decisions.valid_mask);

        % 保存本次单帧检查不能冒称原至少两帧的整体验收；之后用“结构名.original_full_multiframe_acceptance
        % ”读取。
        result.original_full_multiframe_acceptance = 'not_claimed_single_frame';
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 把本次实际已执行部分的数值检查写成JSON。
    fid = fopen(fullfile(runDir, 'learning_validation.json'), 'w');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0);

    % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
    fprintf(fid, '%s', jsonencode(result, 'PrettyPrint', true));

    % 关闭这个文件编号，确保写入完成并释放文件句柄。
    fclose(fid);

    % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
    fprintf('LEARNING_INDEPENDENT_CHECK %s\n', result.status);
% 结束这个函数，输出变量按函数声明返回给调用者。
end

% 定义readStep函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function data = readStep(runDir, key)
    %READSTEP 从本学习目录的独立MAT回读data，不从旧接收结果补造输出。

    % 回读指定步骤MAT里的data变量，不把文件内其他名字散到当前工作区。
    saved = load(fullfile(runDir, [key '.mat']), 'data');

    % 从刚读入的结构里取出data字段，返回该步骤真实保存的完整结果。
    data = saved.data;
% 结束这个函数，输出变量按函数声明返回给调用者。
end
