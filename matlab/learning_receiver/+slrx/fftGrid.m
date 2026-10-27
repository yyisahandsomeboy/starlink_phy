% 定义fftGrid函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function grid = fftGrid(ofdmTime, refs, cfg)
    %FFTGRID 第6步：每个普通OFDM列作FFT，把时间采样变成子载波网格。
    % Y=fft(x)/sqrt(N)，与旧接收机的/32相同。矩阵不fftshift；显示时才shift。
    % grid.values：1024×301；行是原FFT行，列1是SSS、列2:301为数据。

    % FFT的[]沿用输入长度，1表示逐列变换；再除sqrt(1024)，得到1024个子载波。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    grid.values = fft(ofdmTime.without_cp, [], 1) / sqrt(cfg.nfft);

    % 保存未fftshift的有符号bin顺序：0:511，再接-512:-1。
    grid.frequency_bins = refs.frequency_bins;

    % bin乘Fs/N变成相对中心频率，单位Hz；不是12GHz射频频率。
    grid.frequency_hz = refs.frequency_bins * cfg.model_fs_hz / cfg.nfft;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    % 单引号里的文字是字符数据，不是同名变量。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    grid.summary = struct('grid_size', size(grid.values), 'FFT_normalization', ...
        '1/sqrt(N)', 'first_column', 'SSS', 'data_columns', ...  % 后续字段/选项名称及对应取值。
        cfg.data_column_count, 'fftshift_applied', false);  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
