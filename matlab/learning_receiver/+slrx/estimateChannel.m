% 定义estimateChannel函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function channel = estimateChannel(grid, refs, cfg, sharedShape)
    %ESTIMATECHANNEL 第7步：只用已知SSS估计频率响应H及均衡后的噪声。
    % H_LS=Y_SSS/X_SSS。在物理频率顺序上先去小的线性相位斜坡，
    % 再Savitzky-Golay平滑，最后恢复时延斜坡与帧复增益。
    % 默认sharedShape=[]：本帧独立估计。可选参数仅供高级同输入比较，
    % 是1024×1归一化共享响应；单帧教学流程不会从别的帧偷读它。
    % 输出H与grid行号一致；noise_variance_equalized为E|noise|^2/|H|^2。

    % nargin是实际输入参数个数；少于4个时在下面补这个可选参数的默认值。
    if nargin < 4
        % 未传第4个参数时用空数组，表示本帧独立估计H。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        sharedShape = [];
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 取FFT网格第1列全部行；(:,1)是SSS的1024个频域观测。
    % (:,1)表示第一列的全部行。
    % 冒号给出索引序列；单独:取整维全部位置。
    received = grid.values(:, 1);

    % find返回非零SSS参考的行号；eps是很小的正数，用来避免除零参考。
    active = find(abs(refs.sss_grid) > eps);

    % 用这些行号取出各SSS频点的有符号bin。
    frequency = refs.frequency_bins(active);

    % 同时得到从低到高的频率和对应排列；之后必须用同一排列对齐数据。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [frequency, order] = sort(frequency);

    % 按频率重排有效SSS的原FFT行号。
    rows = active(order);

    % 每个接收SSS点除以其已知发射参考，得到含噪声的LS信道估计。
    % ./是对应元素相除，列向量可自动扩展到各列。
    lsResponse = received(rows) ./ refs.sss_grid(rows);

    % 将FFT bin变成每模型采样的角频率2πk/N。
    angularBins = 2 * pi * frequency / cfg.nfft;

    % -2:0.02:2生成时延候选：从-2到2，每次增加0.02个模型采样。
    trials = -2:0.02:2;

    % 逐个补偿候选时延并累加响应；矩阵乘法构造“频点×候选”的相位表。
    % .*是对应元素相乘，不是矩阵乘法。
    % .^是对各元素分别乘方。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    profile = abs(sum(lsResponse .* exp(1j * angularBins * trials), 1)) .^ 2;

    % 只保留得分最大处的索引，~表示忽略最大值本身。
    [~, peak] = max(profile);

    % 在粗最优点左侧留0.04的细搜范围，并限制不低于-2。
    low = max( -2, trials(peak) - 0.04);

    % 在粗最优点右侧留0.04的细搜范围，并限制不高于2。
    high = min(2, trials(peak) + 0.04);

    % fminbnd最小化负相关能量，相当于找最大相关的亚采样时延。
    % 单引号里的文字是字符数据，不是同名变量。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    delay = fminbnd(@(d) - abs(sum(lsResponse .* exp(1j * angularBins ...
        * d))) ^ 2, low, high, optimset('TolX', 1e-10, 'Display', 'off'));  % 设置优化停止精度，并关闭迭代文字显示。

    % 乘正向时延斜坡，去掉LS中随频率快速旋转的部分，再进行平滑。
    deramped = lsResponse .* exp(1j * angularBins * delay);

    % 对去斜坡后的响应做Savitzky–Golay平滑，降低SSS噪声。
    smoothed = sgolayfilt(deramped, cfg.smoothing_degree, cfg.smoothing_window);

    % 在bin=0处线性插值出复响应，作为归一化参考。
    zeroFrequency = interp1(frequency, smoothed, 0, 'linear');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(abs(zeroFrequency) > 1e-10, 'SSS信道归一化处接近零');

    % 除以零频复响应，分离“响应形状”和“帧整体复增益”。
    normalized = smoothed / zeroFrequency;

    % 只有显式传入共享响应才使用它；默认单帧模式不走此分支。
    if ~isempty(sharedShape)
        % 仅在高级对照显式传入共享响应时，取它的有效频率行。
        normalized = sharedShape(rows);

        % 把传入共享响应同样归一化，避免幅度/相位尺度不一致。
        normalized = normalized / interp1(frequency, normalized, 0, 'linear');
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 计算撤销时延和响应形状后的RMS幅度，估计帧整体增益。
    gain = sqrt(mean(abs((received(rows) .* exp(1j * angularBins * delay)) ...
        ./ normalized) .^ 2));  % 续接同一调用的其余参数或表达式。

    % 对已知SSS求相干和后取angle，估计帧整体相位，单位rad。
    phase = angle(sum((received(rows) .* exp(1j * angularBins * delay) ...
        ./ normalized) .* conj(refs.sss_grid(rows))));  % 续接同一调用的其余参数或表达式。

    % 把幅度和相位合成一个复数增益A*exp(jφ)。
    frameGain = gain * exp(1j * phase);

    % 为1024个FFT行预分配复响应存储位置，初值为0。
    H = zeros(cfg.nfft, 1);

    % 恢复时延斜坡和帧增益，并写回原FFT行顺序。
    H(rows) = frameGain * normalized .* exp( -1j * angularBins * delay);

    % 两个低编号gutter行没有SSS参考，使用邻近第3行的响应填充。
    H([1 2]) = H(3);

    % 另外两个gutter行同样用邻近的第1022行填充。
    H([1023 1024]) = H(1022);
    % 极深衰落处设置数值幅度下限，防止除零；不是估计出了真实无噪信道。

    % 设一个数值幅度下限，避免极小H在均衡时产生除零或无限放大。
    floorAmplitude = max(median(abs(H(active))) * 1e-3, realmin);

    % 得到H幅度低于下限的位置；比较结果是true/false逻辑向量。
    small = abs(H) < floorAmplitude;

    % 只替换这些深衰落位置的幅度，仍保留原相位。
    H(small) = floorAmplitude * exp(1j * angle(H(small)));

    % 接收SSS减去H乘已知SSS，得到信道拟合残差。
    residual = received(rows) - H(rows) .* refs.sss_grid(rows);

    % 用残差功率中位数/log(2)估复高斯噪声功率，并设置数值下限。
    noisePower = max(median(abs(residual) .^ 2) / log(2), 1e-12);

    % 建立1024行的空响应形状，准备恢复原FFT索引。
    normalizedFull = zeros(cfg.nfft, 1);

    % 把有效频点的归一化响应按原行号写回。
    normalizedFull(rows) = normalized;

    % 保存每个FFT行的复信道响应，尺寸1024×1；之后用“结构名.H”读取。
    channel.H = H;

    % 保存均衡后每个频率位置的复噪声方差；之后用“结构名.noise_variance_equalized”读取。
    channel.noise_variance_equalized = noisePower ./ max(abs(H) .^ 2, eps);

    % 保存归一化后的频率响应形状；之后用“结构名.channel_normalized”读取。
    channel.channel_normalized = normalizedFull;

    % 保存频率排序结果回查原FFT行号的映射；之后用“结构名.frequency_order_rows”读取。
    channel.frequency_order_rows = rows;

    % 保存按物理频率排序的SSS原始LS信道估计；之后用“结构名.sss_ls_frequency_order”读取。
    channel.sss_ls_frequency_order = lsResponse;

    % 保存去掉线性时延相位斜坡后的LS估计；之后用“结构名.sss_deramped_ls”读取。
    channel.sss_deramped_ls = deramped;

    % 保存去斜坡之后平滑得到的复频率响应；之后用“结构名.channel_smoothed_frequency_order”读取。
    channel.channel_smoothed_frequency_order = smoothed;

    % 保存本帧整体的复数增益，包含幅度和相位；之后用“结构名.frame_complex_gain”读取。
    channel.frame_complex_gain = frameGain;

    % 保存SSS估计出的时延，单位240Msps模型采样；之后用“结构名.sss_delay_samples”读取。
    channel.sss_delay_samples = delay;

    % 保存搜索过的候选时延坐标，单位模型采样；之后用“结构名.sss_delay_trial_samples”读取。
    channel.sss_delay_trial_samples = trials;

    % 保存每个时延候选对应的相关得分；之后用“结构名.sss_delay_profile”读取。
    channel.sss_delay_profile = profile;

    % 保存SSS观测减去拟合响应后的复数残差；之后用“结构名.sss_residual_frequency_order”读取。
    channel.sss_residual_frequency_order = residual;

    % 保存均衡前的噪声功率估计；之后用“结构名.noise_power_before_equalization”读取。
    channel.noise_power_before_equalization = noisePower;

    % 保存是否使用了跨帧共享响应；默认学习版为false；之后用“结构名.shared_channel_used”读取。
    channel.shared_channel_used = ~isempty(sharedShape);

    % 保存未shift的有符号FFT频率索引；之后用“结构名.frequency_bins”读取。
    channel.frequency_bins = refs.frequency_bins;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    channel.summary = struct('H_size', size(H), 'sss_delay_model_samples', ...
        delay, 'noise_power_before_equalization', noisePower, ...  % 续接同一调用的其余参数或表达式。
        'shared_channel_used', channel.shared_channel_used);  % 摘要字段：是否使用了跨帧共享响应；默认学习版为false。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
