% 定义resampleCapture函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function sampled = resampleCapture(capture, cfg)
    %RESAMPLECAPTURE 第2步：把250Msps的窗口变成240Msps的名义模型采样。
    % y=resample(x,24,25,50)包含抗混叠FIR及其标称延时处理。
    % 这只是名义比例；实际采样速率偏差SFO在整帧跟踪后另外估计。
    % 输出 iq 仍为时域复采样，尚未去CP或FFT。保留FIR与移除的DC供检查。

    % 按24/25重采样到240Msps，并接收抗混叠FIR系数作为第二个输出。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    [iq, filterCoefficients] = resample(capture.iq, cfg.resample_p, ...
        cfg.resample_q, cfg.resample_filter_half_length);  % 最后参数50控制抗混叠FIR长度；采样率仍由24/25决定。

    % 计算重采样窗口的复均值，作为下一行要减去的DC偏置。
    removedDc = mean(iq);

    % 从每个复采样减去同一个DC；标量会自动作用到所有元素。
    sampled.iq = iq - removedDc;

    % 给输出时域流标记240Msps模型采样率，单位Hz。
    sampled.fs_hz = cfg.model_fs_hz;

    % 保留窗口在原BIN中的起点，供后面换算全局坐标。
    sampled.first_complex_sample_capture = capture.first_complex_sample;

    % 保留原250Msps采样率，不能把它误写成输出的240Msps。
    sampled.capture_fs_hz = capture.fs_hz;

    % 保存重采样FIR系数，方便追查滤波器和边界过渡。
    sampled.filter = filterCoefficients;

    % 保存实际减去的复DC，后续可检查处理是否过强。
    sampled.removed_dc = removedDc;

    % 方括号建立二元素行向量[24 25]，依次表示上采样/下采样因子。
    sampled.ratio = [cfg.resample_p cfg.resample_q];

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    % 单引号里的文字是字符数据，不是同名变量。
    sampled.summary = struct('complex_samples', numel(iq), 'fs_hz', ...
        sampled.fs_hz, 'ratio', sampled.ratio, 'removed_dc_real', ...  % 续接同一调用的其余参数或表达式。
        real(removedDc), 'removed_dc_imag', imag(removedDc));  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
