% 定义extractFrame函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function frameTime = extractFrame(sampled, synchronization, offsets, cfg)
    %EXTRACTFRAME 第4步：按帧起点和采样步长读取完整帧，再补偿CFO。
    % offsets.cfo_hz：Hz；offsets.sfo_ppm：相对采样率ppm。
    % 取样位置 = start + n/(1+sfo*1e-6)，n为模型采样数。
    % CFO以帧起点为时间零点补偿：r*exp(-j*2*pi*CFO*time)。
    % 输出time_raw仍在名义模型流上，不是原BIN的250Msps数组。

    % 计算完整帧的时间采样总数：302个时隙，每个1024+32点，共318912点。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    count = cfg.frame_symbol_count * (cfg.nfft + cfg.cp_length);

    % 生成从0开始的帧内位置，再按SFO调整步长；'把实数行向量转为列向量。
    % 单独的'对复数做共轭转置，与.'不同。
    % 冒号给出索引序列；单独:取整维全部位置。
    nominalOffset = (0:count - 1)' / (1 + offsets.sfo_ppm * 1e-6);

    % 取独立检测给出的240Msps窗口帧起点，不读取作者标注。
    start = synchronization.selected.start_sample_nominal;

    % 帧起点加相对位置，得到需要从模型流读取的连续一基坐标。
    positions = start + nominalOffset;

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    % 索引里的end指这一维最后的位置，不是结束if/for。
    % 单引号里的文字是字符数据，不是同名变量。
    assert(positions(1) >= 1 && positions(end) <= numel(sampled.iq), '完整帧超出已读取窗口');

    % 在可带小数的位置做sinc插值；这里raw表示尚未乘CFO补偿。
    frameTime.time_raw = slrx.alg.interpolateSinc(sampled.iq, positions);

    % 逐样本乘反向旋转exp(-j2πft)，撤销CFO积累的相位；.*为逐元素乘。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    frameTime.time_cfo_compensated = frameTime.time_raw .* exp( -1j * 2 * pi ...
        * offsets.cfo_hz * nominalOffset / cfg.model_fs_hz);  % 模型采样位置除Fs变成秒，CFO以Hz乘时间形成旋转角。

    % 保存所有实际插值位置，方便把结果追溯到输入时间轴。
    frameTime.sample_positions_nominal = positions;

    % 保存帧在当前名义重采样流中的起点。
    frameTime.sample_position_start = start;

    % 保存相邻模型点对应的实际读取步长；ppm先乘1e-6变成比例。
    frameTime.sample_position_step = 1 / (1 + offsets.sfo_ppm * 1e-6);

    % 记录本轮实际采用的CFO补偿值，单位Hz。
    frameTime.cfo_hz = offsets.cfo_hz;

    % 记录本轮采用的SFO，单位百万分之一，即ppm。
    frameTime.sfo_ppm = offsets.sfo_ppm;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    frameTime.summary = struct('complex_samples', count, 'cfo_hz', ...
        offsets.cfo_hz, 'sfo_ppm', offsets.sfo_ppm, 'sample_position_start', ...  % 续接同一调用的其余参数或表达式。
        start, 'sample_position_step', frameTime.sample_position_step);  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
