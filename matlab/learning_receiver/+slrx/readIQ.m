% 定义readIQ函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function capture = readIQ(cfg)
    %READIQ 第1步：把文件中的交织整数转换成复数IQ，并检查输入质量。
    % 文件顺序 I0,Q0,I1,Q1...；每复采样4字节。/32768仅改变幅度单位。
    % 输出 iq 为复列向量；first_complex_sample 是该窗口在原BIN中的位置。
    % 本步不找帧头。默认4ms只是分析窗口，帧头要由下一阶段独立检测。

    % 以只读、小端字节顺序打开原始IQ；fopen返回文件编号，失败时为负数。
    % 单引号里的文字是字符数据，不是同名变量。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    fid = fopen(cfg.input_file, 'r', 'ieee-le');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0, '无法打开原始IQ文件');

    % 创建退出时自动关文件的清理对象；@()表示稍后才执行括号后的任务。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    closer = onCleanup(@() fclose(fid));

    % 从文件开头跳到指定复采样；每份I/Q占4字节，一基位置先减1。
    status = fseek(fid, 4 * (cfg.first_complex_sample - 1), 'bof');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(status == 0, '无法移动到指定复采样位置');

    % 采样秒数乘采样率得到所需复采样数；round把它四舍五入为整数。
    requested = round(cfg.read_duration_s * cfg.capture_fs_hz);

    % 读成2行矩阵：第1行I、第2行Q；按int16取字节，再转double计算。
    components = fread(fid, [2 requested], 'int16=>double');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(size(components, 2) == requested, '读取窗口超出原始文件，不能补零冒充采集');

    % 第1、2行组成I+jQ；.'只换行列不共轭，/32768归一化幅度。
    % .'只转置行列，不对复数取共轭。
    % (行号,:)表示这些行的全部列。
    % 冒号给出索引序列；单独:取整维全部位置。
    iq = complex(components(1, :), components(2, :)).' / 32768;

    % 把复数列向量放入capture结构的iq字段；“点”用于访问结构字段。
    capture.iq = iq;

    % 记录原采集采样率250e6，单位是每秒复采样数。
    capture.fs_hz = cfg.capture_fs_hz;

    % 记录本窗口第一份复采样在原文件中的一基位置。
    capture.first_complex_sample = cfg.first_complex_sample;

    % 样本个数除以采样率得到窗口时长，单位秒；numel统计元素总数。
    capture.duration_s = numel(iq) / capture.fs_hz;

    % abs取复数幅度，.^2逐元素平方，mean取平均后开方得到RMS。
    capture.rms = sqrt(mean(abs(iq) .^ 2));

    % 对复采样求均值，估计直流偏置；此处只记录，还不减去它。
    capture.dc = mean(iq);

    % 逐点判断I或Q是否接近int16满量程；逻辑均值就是截幅比例。
    % |对数组各元素分别取逻辑“或者”。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    capture.clipped_fraction = mean(abs(real(iq)) >= 32767 / 32768 ...
        | abs(imag(iq)) >= 32767 / 32768);  % I或Q任一分量到达满量程都记为截幅。
    % PSD只使用本窗口，pwelch的频率单位为Hz，不是12GHz射频载波。

    % 用4096点Hann窗作Welch功率谱估计；方括号同时接收功率谱与频率轴。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [capture.psd_linear, capture.psd_frequency_hz] = pwelch(iq, hann(4096), ...
        2048, 8192, capture.fs_hz, 'centered');  % 2048是重叠点数，8192是PSD的FFT长度，fs给频率单位。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    capture.summary = struct('complex_samples', numel(iq), 'duration_s', ...
        capture.duration_s, 'fs_hz', capture.fs_hz, 'rms', capture.rms, ...  % 续接同一调用的其余参数或表达式。
        'clipped_fraction', capture.clipped_fraction);  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
