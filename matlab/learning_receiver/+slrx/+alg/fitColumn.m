% 定义fitColumn函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
% 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
function output = fitColumn(column, channel, refs, classification, pilotDelay, ...
    pilotPhase, dataColumn, cfg)  % 继续列出本函数的输入参数。
    %FITCOLUMN 把点数识别、几何选择和两次局部ML连接起来。
    % column是1024×1均衡后数据列，含导频；classification来自第10步。
    % 对K=4用相对导频相位区分QPSK/4QAM；K=8不强行套简单星座。
    % 最终增益只用于载荷显示/判决，不重缩放公开导频。

    % 先设0表示未知几何，不能提前把每列都认作QPSK。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    output.geometry_id = 0;

    % 用NaN表示尚无有效时延估计，NaN不是0采样误差。
    output.delay_samples = NaN;

    % 相位同样先置未知NaN，避免失败列被当作已同步。
    output.phase_rad = NaN;

    % 先不假设载荷幅度，等待识别和ML后再写入。
    output.gain = NaN;

    % 未知列的代价先为NaN，不把0冒充完美拟合。
    output.cost = NaN;

    % 初始化迭代计数；遇到不支持的K时保持0。
    output.iterations = 0;

    % 保留上一模块的点数识别记录，再往其中补充ML证据。
    output.record = classification;

    % K=8尚不在简单星座模型中，保留未知并退出本列处理。
    if classification.cardinality == 8
        % 保存本代码的几何编号；0表示未识别，不是MCS号；之后用“结构名.geometry_id”读取。
        output.record.geometry_id = 0;

        % 保存机器可读状态；unknown/partial不等于恢复成功；之后用“结构名.status”读取。
        % 单引号里的文字是字符数据，不是同名变量。
        output.record.status = 'composite_cardinality_8';

        % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
        return;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 识别为四点时先进入QPSK/4QAM歧义处理分支。
    if classification.cardinality == 4
        % 四点先尝试QPSK几何，后面结合导频相位判断是否应换成4QAM。
        model = 1;
    % 前一分支不满足时再检查这个条件；同一组if只会执行其中一个分支。
    elseif classification.cardinality == 16
        % 16点对应refs.constellations中的第3组归一化16QAM几何。
        model = 3;
    % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
    else
        % 其余已支持的32点对应第4组cross32QAM几何。
        model = 4;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 取原FFT顺序的1004个载荷行，保持与原接收机的计算顺序相同。
    rows = refs.payload_rows;

    % 用聚类中心的RMS估初始载荷幅度，设置0.05下限避免除零。
    % .^是对各元素分别乘方。
    gain = max(sqrt(mean(abs(classification.centroids) .^ 2)), 0.05);

    % 将载荷点除以幅度，匹配单位平均功率的理想星座。
    normalized = column(rows) / gain;

    % 幅度除以gain时噪声功率要除gain²，再施加配置中的方差下限。
    variance = max(channel.noise_variance_equalized(rows) / gain ^ 2, ...
        cfg.noise_variance_floor);  % 续接同一调用的其余参数或表达式。

    % 先仅用未知载荷的边缘似然估计时延/相位，输入导频给出的初值。
    % {编号}取得cell格子内部的数据，()则取得格子外壳。
    estimate = slrx.alg.fitSymbol(normalized, refs.frequency_bins(rows), ...
        refs.constellations{model}, variance, [pilotDelay; pilotPhase], [], ...  % 续接同一调用的其余参数或表达式。
        cfg.nfft);  % 续接同一调用的其余参数或表达式。

    % theta的第2个元素是相位估计，单位rad。
    phase = estimate.theta(2);

    % 仅四点候选需要这里的45度几何切换检查。
    if model == 1
        % 把相位与导频初值之差折回[-π/4,π/4)，处理四点几何的90度模糊。
        difference = mod(phase - pilotPhase + pi / 4, pi / 2) - pi / 4;

        % 相位差超过π/8时更接近另一种相差45度的四点几何。
        if abs(difference) > pi / 8
            % 差值更接近45度旋转时改用作者4QAM几何，而不是强称全部QPSK。
            model = 2;

            % 随几何切换同步修正π/4相位，避免重复旋转。
            phase = phase - sign(difference) * pi / 4;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 将相位移到最接近导频初值的90度分支，减少相位模糊。
    phase = pilotPhase + mod(phase - pilotPhase + pi / 4, pi / 2) - pi / 4;
    % 已知参考和观测一起除以gain，噪声方差除以gain^2；不能只缩放其中一项。
    % 参考导频按列由上层传入，避免将第一个数据列模板错误地重复使用。

    % 组织8条FIT导频的观测、bin、参考和方差；观测与参考必须同除gain。
    known = struct('y', column(refs.fit_rows) / gain, 'k', ...
        refs.frequency_bins(refs.fit_rows), 'reference', ...  % 续接同一调用的其余参数或表达式。
        refs.pilots(refs.fit_rows, dataColumn + 1) / gain, 'variance', ...  % 续接同一调用的其余参数或表达式。
        max(channel.noise_variance_equalized(refs.fit_rows) / gain ^ 2, ...  % 续接同一调用的其余参数或表达式。
        cfg.noise_variance_floor / gain ^ 2));  % 续接同一调用的其余参数或表达式。

    % 加入FIT已知符号项再次局部ML细化；EVAL导频仍完全不参与。
    estimate = slrx.alg.fitSymbol(normalized, refs.frequency_bins(rows), ...
        refs.constellations{model}, variance, [estimate.theta(1); phase], ...  % 续接同一调用的其余参数或表达式。
        known, cfg.nfft);  % 续接同一调用的其余参数或表达式。

    % 把细化相位再次对齐到导频选定的90度分支。
    phase = pilotPhase + mod(estimate.theta(2) - pilotPhase + pi / 4, ...
        pi / 2) - pi / 4;  % 续接同一调用的其余参数或表达式。

    % 按最终时延/相位对齐归一化载荷，供最近点和增益重估使用。
    % .*是对应元素相乘，不是矩阵乘法。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    aligned = normalized .* exp(1j * (2 * pi * refs.frequency_bins(rows) ...
        / cfg.nfft * estimate.theta(1) - phase));  % 续接同一调用的其余参数或表达式。

    % 逐行选择最近候选点，只取其索引，不把它当商业业务比特。
    % .'只转置行列，不对复数取共轭。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [~, ids] = min(abs(aligned - refs.constellations{model}.') .^ 2, [], 2);

    % 根据最近点索引取出实际理想星座复数。
    points = refs.constellations{model}(ids);

    % 用理想点与对齐观测的相关估计列幅度，并保持正幅度下限。
    updatedGain = max(real(sum(conj(points) .* aligned)) * gain ...
        / sum(abs(points) .^ 2), 0.05);  % 续接同一调用的其余参数或表达式。

    % 把最终选择的几何编号写回本列输出。
    output.geometry_id = model;

    % 保存ML参数第1项，即模型采样单位的残余时延。
    output.delay_samples = estimate.theta(1);

    % 保存选定歧义分支后的最终相位。
    output.phase_rad = phase;

    % 保存重估后的载荷增益，供展示和条件符号判决。
    output.gain = updatedGain;

    % 保留最后一次ML的负对数似然代价。
    output.cost = estimate.negative_log_likelihood;

    % 保存细化优化的迭代次数，供收敛诊断。
    output.iterations = estimate.iterations;

    % 保存本代码的几何编号；0表示未识别，不是MCS号；之后用“结构名.geometry_id”读取。
    output.record.geometry_id = model;

    % 保存机器可读状态；unknown/partial不等于恢复成功；之后用“结构名.status”读取。
    output.record.status = 'author_simple_constellation';

    % 保存当前列优化所得的参数、代价和导数；之后用“结构名.ml”读取。
    output.record.ml = estimate;

    % 保存当前列的幅度估计；之后用“结构名.gain”读取。
    output.record.gain = updatedGain;
% 结束这个函数，输出变量按函数声明返回给调用者。
end
