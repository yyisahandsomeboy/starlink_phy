% 定义trackFrame函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
% 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
function tracked = trackFrame(equalized, channel, pilots, classes, refs, cfg, ...
    seedBase)  % 继续列出本函数的输入参数。
    %TRACKFRAME 第11步：逐列ML估计，再拟合整帧相位/时延并补偿。
    % 第10步已经单独算出点数，本步不重复kmeans。
    % 延迟单位为模型采样，phase为rad。相位具有90°歧义，结合FIT导频选分支。
    % 保留原始逐列估计、RANSAC内点和拟合残差；不要只留下最终星座图。

    % 本帧有300个数据OFDM列；SSS不包含在这个计数中。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    count = cfg.data_column_count;

    % nan(1,count)建立未知时延数组，未识别列继续保留NaN。
    delay = nan(1, count);

    % 复制全NaN数组作为相位存储；不是把相位设成实际时延。
    phase = delay;

    % 同样预留逐列幅度，初值为未知。
    gain = delay;

    % 几何编号先设0；只有成功识别才写入1:4。
    geometry = zeros(1, count);

    % 为逐列代价预留NaN，失败列不能当作低代价。
    cost = delay;

    % 为300列的迭代次数预分配全0数组。
    iterations = zeros(1, count);

    % cell容器每格存一列的识别、初值与ML细节。
    records = cell(1, count);

    % 依次处理一个数据OFDM列，不把300列星座全部混在一起；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for column = 1:count
        % 处理当前数据列；(:,column+1)跳过第1列SSS，结合该列FIT导频初值。
        % {编号}取得cell格子内部的数据，()则取得格子外壳。
        result = slrx.alg.fitColumn(equalized.values(:, column + 1), channel, ...
            refs, classes.records{column}, pilots.raw_delay_samples(column), ...  % 续接同一调用的其余参数或表达式。
            pilots.raw_phase_rad(column), column, cfg);  % 续接同一调用的其余参数或表达式。

        % 将本列ML时延写入相应数组元素，单位模型采样。
        delay(column) = result.delay_samples;

        % 保存当前列的相位，单位rad。
        phase(column) = result.phase_rad;

        % 保存当前列的载荷幅度估计。
        gain(column) = result.gain;

        % 保存当前列几何编号；不支持的模型保持0。
        geometry(column) = result.geometry_id;

        % 记录本列优化代价，便于发现异常列。
        cost(column) = result.cost;

        % 记录本列优化的迭代次数。
        iterations(column) = result.iterations;

        % 用花括号存入该列的完整结构记录。
        records{column} = result.record;

        % 每隔固定列数才报告进度，避免把大数组打印到终端。
        if mod(column, 50) == 0
            % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
            % 单引号里的文字是字符数据，不是同名变量。
            fprintf('LEARN_ML %d/%d\n', column, count);
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 逐元素检查几何已识别、时延和相位均有限，生成有效列掩码。
    % &对数组各元素分别取逻辑“并且”。
    valid = geometry > 0 & isfinite(delay) & isfinite(phase);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(nnz(valid) >= cfg.minimum_simple_symbols, '简单星座列不足，不能可靠拟合整帧趋势');

    % 建立300个数据OFDM列号，作为整帧趋势拟合的时间横坐标。
    columns = 1:count;

    % 用RANSAC挑选时延内点；相位拟合随后使用同一组列。
    inliers = slrx.alg.ransacLine(columns, delay, valid, ...
        cfg.ransac_delay_threshold_samples, seedBase);  % 续接同一调用的其余参数或表达式。
    % 先以90°为周期展开，再移到导频给出的相位分支，避免把歧义当真实CFO。

    % 为解除周期模糊后的相位预留NaN。
    unwrapped = nan(size(phase));

    % 先相位乘4再unwrap再除4，相当于按90度而不是360度周期展开。
    unwrapped(valid) = unwrap(4 * phase(valid)) / 4;

    % 结合导频初值选择最接近的π/2分支，避免把几何歧义当成真实CFO。
    unwrapped(valid) = unwrapped(valid) + round((pilots.raw_phase_rad(valid) ...
        - unwrapped(valid)) / (pi / 2)) * (pi / 2);  % 续接同一调用的其余参数或表达式。

    % 只用内点拟合时延对列号的一阶直线，返回[斜率 截距]。
    delayFit = polyfit(columns(inliers), delay(inliers), 1);

    % 用同一组内点拟合展开相位，保持时延和相位采用相同有效观测。
    phaseFit = polyfit(columns(inliers), unwrapped(inliers), 1);

    % 在全部300列上计算拟合时延，作为实际整帧补偿轨迹。
    delayLine = polyval(delayFit, columns);

    % 同样计算所有列的相位补偿轨迹。
    phaseLine = polyval(phaseFit, columns);

    % 先保留完整均衡网格，包括第1列SSS。
    tracked.values = equalized.values;

    % 只对数据列乘相位模型的反向复指数，撤销公共相位与频率斜坡。
    % .*是对应元素相乘，不是矩阵乘法。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    tracked.values(:, 2:301) = equalized.values(:, ...
        2:301) .* exp(1j * ( 2 * pi * refs.frequency_bins / cfg.nfft ...  % 补偿相位斜坡与公共旋转，保留原符号约定。
        * delayLine - ones(cfg.nfft, 1) * phaseLine));  % 补偿相位斜坡与公共旋转，保留原符号约定。

    % 保存每个数据列的原始ML时延，单位模型采样；之后用“结构名.ml_delay_samples”读取。
    tracked.ml_delay_samples = delay;

    % 保存每个数据列的原始ML相位，单位rad；之后用“结构名.ml_phase_rad”读取。
    tracked.ml_phase_rad = phase;

    % 保存处理90度模糊后的逐列相位，单位rad；之后用“结构名.ml_phase_unwrapped_rad”读取。
    tracked.ml_phase_unwrapped_rad = unwrapped;

    % 保存哪些数据列参与整帧直线拟合的逻辑掩码；之后用“结构名.ml_inlier_mask”读取。
    tracked.ml_inlier_mask = inliers;

    % 保存逐列时延与整帧拟合线之间的差；之后用“结构名.ml_delay_residual_samples”读取。
    tracked.ml_delay_residual_samples = delay - delayLine;

    % 保存逐列相位与整帧拟合线之间的差；之后用“结构名.ml_phase_residual_rad”读取。
    tracked.ml_phase_residual_rad = unwrapped - phaseLine;

    % 保存时延拟合直线的[斜率 截距]；之后用“结构名.delay_line_coefficients”读取。
    tracked.delay_line_coefficients = delayFit;

    % 保存相位拟合直线的[斜率 截距]；之后用“结构名.phase_line_coefficients”读取。
    tracked.phase_line_coefficients = phaseFit;

    % 保存整帧每列实际采用的时延补偿轨迹；之后用“结构名.delay_line_samples”读取。
    tracked.delay_line_samples = delayLine;

    % 保存整帧每列实际采用的相位补偿轨迹；之后用“结构名.phase_line_rad”读取。
    tracked.phase_line_rad = phaseLine;

    % 保存本代码的几何编号；0表示未识别，不是MCS号；之后用“结构名.geometry_id”读取。
    tracked.geometry_id = geometry;

    % 保存每个数据列的载荷幅度估计；之后用“结构名.gain_per_data_symbol”读取。
    tracked.gain_per_data_symbol = gain;

    % 保存四种候选星座点数的得分表；之后用“结构名.cardinality_scores”读取。
    tracked.cardinality_scores = classes.scores;

    % 保存每列的详细识别/优化依据；之后用“结构名.records”读取。
    tracked.records = records;

    % 保存每列优化得到的负对数似然代价；之后用“结构名.ml_negative_log_likelihood”读取。
    tracked.ml_negative_log_likelihood = cost;

    % 保存各列数值优化的迭代次数；之后用“结构名.ml_iterations”读取。
    tracked.ml_iterations = iterations;

    % 从未参加FIT的8条EVAL导频取已知符号作独立误差参考。
    reference = refs.pilots(refs.eval_rows, 2:301);

    % 对最终网格的留出导频计算EVM，不用参与ML拟合的点证明自己。
    % .^是对各元素分别乘方。
    tracked.heldout_pilot_evm = sqrt(mean(abs(tracked.values(refs.eval_rows, ...
        2:301) - reference) .^ 2, 'all'));  % 误差能量按参考能量归一化后开方。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    tracked.summary = struct('simple_columns', nnz(valid), 'inlier_columns', ...
        nnz(inliers), 'heldout_pilot_evm', tracked.heldout_pilot_evm, ...  % 续接同一调用的其余参数或表达式。
        'delay_slope_per_column', delayFit(1), ...  % 后续字段/选项名称及对应取值。
        'phase_slope_rad_per_column', phaseFit(1));  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
