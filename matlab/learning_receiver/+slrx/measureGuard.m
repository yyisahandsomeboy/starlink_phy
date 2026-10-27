% 定义measureGuard函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function guard = measureGuard(capture, synchronization, offsets, cfg)
    %MEASUREGUARD 补充观察：预测帧末保护区，并读取该区原IQ的能量。
    % 这是模型边界，不是独立检测出的噪声边缘。名义长度1088/240MHz。
    % 所有区间使用连续一基、左闭右开[start,end)。整数中心ceil(start):ceil(end)-1。
    % 单帧不足以确认相邻时隙或波束身份，所以本函数不把空隙解释为漏帧。

    % 由最终SFO算时间轴缩放因子，把名义模型时长换成实际采样长度。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    scale = 1 / (1 + offsets.sfo_ppm * 1e-6);

    % 取得原文件连续一基帧起点；允许小数，不强行取整。
    start = synchronization.selected.start_sample_capture;

    % 302×1056是帧占用的模型采样数，包含PSS、SSS和300列数据。
    occupied = cfg.frame_symbol_count * (cfg.nfft + cfg.cp_length);

    % 把占用部分末尾投影到原250Msps文件，得到模型预测的保护区起点。
    guardStart = start + occupied * cfg.capture_fs_hz / cfg.model_fs_hz * scale;

    % 把下一个名义750Hz时隙起点投影回原采样轴，作为右端点。
    guardEnd = start + cfg.capture_fs_hz / cfg.slot_rate_hz * scale;

    % 保护区左右端点相减，得到原采样坐标上的连续宽度。
    width = guardEnd - guardStart;

    % 把原文件全局坐标改成本次读取窗口的一基局部坐标。
    localStart = guardStart - capture.first_complex_sample + 1;

    % 同样换算保护区右端点；它不包含在左闭右开区间内。
    localEnd = guardEnd - capture.first_complex_sample + 1;

    % ceil向上取整；读取[start,end)内整数采样中心，并限制在已有窗口中。
    % 单独的'对复数做共轭转置，与.'不同。
    % 冒号给出索引序列；单独:取整维全部位置。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    indices = (max(1, ceil(localStart)):min(numel(capture.iq), ...
        ceil(localEnd) - 1))';  % 续接同一调用的其余参数或表达式。

    % 取保护区之前同样长的一段，作为功率对照，不把它当噪声真值。
    preIndices = (max(1, ceil(localStart - width)):min(numel(capture.iq), ...
        ceil(localStart) - 1))';  % 续接同一调用的其余参数或表达式。

    % 保存保护区起点的原始文件坐标。
    guard.start_sample_capture = guardStart;

    % 保存不包含的右端点，明确区间是左闭右开。
    guard.end_sample_capture_exclusive = guardEnd;

    % 把实际读取的窗口索引转换回原文件复采样坐标。
    guard.sample_indices_capture = indices + capture.first_complex_sample - 1;

    % 用整数索引读取保护区真实短IQ；不是补零或合成信号。
    guard.samples = capture.iq(indices);

    % 保存前一段对照短IQ，方便检查保护区功率变化。
    guard.preguard_samples = capture.iq(preIndices);

    % 只有两个端点都在窗口内才为true；&&表示两个标量条件都成立。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    guard.in_capture = localStart >= 1 && localEnd <= numel(capture.iq) + 1;

    % 复幅度平方的均值，就是保护区平均功率。
    % .^是对各元素分别乘方。
    guard.mean_power = mean(abs(guard.samples) .^ 2);

    % 按同样公式计算前一对照区间的平均功率。
    guard.preguard_mean_power = mean(abs(guard.preguard_samples) .^ 2);

    % 保护区功率除以前一段功率；这是观测，不是独立边缘检测。
    guard.power_ratio = guard.mean_power / guard.preguard_mean_power;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    % 单引号里的文字是字符数据，不是同名变量。
    guard.summary = struct('endpoint_source', 'model_predicted', ...
        'edge_detection_performed', false, 'duration_us', ...  % 后续字段/选项名称及对应取值。
        width / cfg.capture_fs_hz * 1e6, 'start_sample_capture', ...  % 续接同一调用的其余参数或表达式。
        guardStart, 'end_sample_capture_exclusive', guardEnd, ...  % 续接同一调用的其余参数或表达式。
        'in_capture', guard.in_capture, 'power_ratio', ...  % 后续字段/选项名称及对应取值。
        guard.power_ratio);  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
