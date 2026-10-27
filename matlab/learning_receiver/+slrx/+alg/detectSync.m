% 定义detectSync函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function [candidates, rejected, scan] = detectSync(iq, refs, cfg)
    %DETECTSYNC PSS重复结构检测与PSS+SSS相干确认的具体算法。
    % 粗分数是8个128点参考片段的相关幅度之和，降低粗频偏带来的抵消。
    % 精确认使用连续2112点参考[PSS;SSS]，同时估计时间与CFO。
    % 重复段CFO的角度只确定模Fs/128，因此显式检查有限的alias候选。
    % 所有索引均为当前240Msps窗口的一基位置；转换原采样坐标由findFrame做。

    % numel返回窗口复采样总数，用于控制搜索和完整帧边界。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    sampleCount = numel(iq);

    % 从配置取240Msps模型采样率；后面的CFO全部用这个时间轴。
    fs = cfg.model_fs_hz;

    % 取作者PSS第161:288点，共128点，作为重复片段参考。
    % 冒号给出索引序列；单独:取整维全部位置。
    segment = refs.pss(161:288);

    % 为每个能容纳1056点PSS的起点分配一个粗相关得分。
    score = zeros(sampleCount - 1055, 1);

    % 每次最多处理100万个候选起点，控制FFT相关的内存占用。
    blockLength = 1000000;

    % 按固定批次依次处理，限制临时矩阵占用的内存；for后面的=给出本轮编号序列。
    for first = 1:blockLength:numel(score)
        % 计算本批最后一个起点，min保证不会超过总搜索范围。
        last = min(numel(score), first + blockLength - 1);

        % 取本批输入并额外带1055点，使批末候选也拥有完整PSS窗口。
        chunk = iq(first:last + 1055);

        % 选不小于相关所需长度的2次幂，减少FFT相关计算量。
        fftLength = 2 ^ nextpow2(numel(chunk) + 127);

        % 把翻转共轭参考与输入作FFT卷积；.*是频域逐点乘。
        % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
        correlation = ifft(fft(chunk, fftLength) .* fft(conj(flipud(segment)), ...
            fftLength));  % 续接同一调用的其余参数或表达式。

        % 裁出有效相关区；128来自128点参考的卷积对齐偏移。
        correlation = correlation(128:numel(chunk));

        % 为本批每个候选起点准备一个幅度累加器。
        summed = zeros(last - first + 1, 1);

        % 依次累加PSS的8个128点重复片段；for后面的=给出本轮编号序列。
        for repeat = 0:7
            % CP之后从第33点开始，每128点取一段；这里构造各候选对应的索引。
            indices = 33 + repeat * 128 + (0:numel(summed) - 1);

            % 把8个重复段的相关幅度相加，减少粗频偏导致的相干抵消。
            summed = summed + abs(correlation(indices));
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end

        % 用1056点滑动能量开方，构造各候选的输入幅度归一化因子。
        % .^是对各元素分别乘方。
        energy = sqrt(movsum(abs(chunk) .^ 2, [0 1055]));

        % 写回本批归一化粗得分；max(...,eps)保护分母不为0。
        % ./是对应元素相除，列向量可自动扩展到各列。
        score(first:last) = summed ./ max(energy(1:numel(summed)) * sqrt(128) ...
            * 8, eps);  % 续接同一调用的其余参数或表达式。
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 只每100点保存一个粗分数，保留大范围检索依据而不过量存数组。
    % 单独的'对复数做共轭转置，与.'不同。
    % 索引里的end指这一维最后的位置，不是结束if/for。
    % 单引号里的文字是字符数据，不是同名变量。
    scan = struct('score_sample_nominal', (1:100:numel(score))', ...
        'score_decimated', score(1:100:end), 'trace_decimation', 100);  % 后续字段/选项名称及对应取值。

    % 建立空结构数组，之后逐个保存通过同步检查的完整候选。
    candidates = struct([]);

    % 建立被拒候选列表，保存拒绝原因而不是直接丢掉依据。
    rejected = struct([]);

    % 用分号把1056点PSS与1056点SSS上下拼接，得到2112点联合参考。
    reference = [refs.pss; refs.sss];

    % 最多尝试36个粗峰，避免找不到信号时无限搜索；for后面的=给出本轮编号序列。
    for attempt = 1:36
        % max同时给出当前最高粗分数和对应的一基起点。
        % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
        [coarseMetric, coarseStart] = max(score);

        % 粗峰低于0.07就不再继续搜索，避免把噪声峰强行当PSS。
        if coarseMetric < 0.07
            % 退出最内层循环；它不代表退出整个接收机。
            break;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % 把该峰附近粗分数置0，避免下次重复检查同一峰。
        score(max(1, coarseStart - 1100):min(numel(score), coarseStart + 1100)) = 0;

        % 检查与已有候选是否太近，避免重复计数同一帧。
        % &&要求两侧标量条件都为真，并按需计算右侧。
        if ~isempty(candidates) ...
            && any(abs([candidates.start_sample_nominal] - coarseStart) < 200000)  % 续接同一调用的其余参数或表达式。

            % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
            continue;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % 把当前最优得分设成负无穷，保证第一个有效候选能被选中。
        bestMetric = -Inf;

        % 先以NaN表示“还没有找到合法起点”，不能把0冒充检测结果。
        bestStart = NaN;

        % 先把频偏设为未知，等候选匹配后再写入Hz值。
        bestCfo = NaN;

        % 以128采样为间隔枚举附近的同步对齐；for后面的=给出本轮编号序列。
        for offset = -1024:128:1024
            % 把粗起点加一个128点倍数的候选偏移，检查PSS重复结构的对齐。
            start = coarseStart + offset;

            % 窗口越界就跳过这次对齐尝试，不补零伪造参考匹配。
            % ||是两个标量条件的逻辑“或者”。
            if start < 1 || start + 2111 > sampleCount
                % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
                continue;
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 把PSS有效1024点整形成128×8，每列为一个重复片段。
            repeats = reshape(iq(start + 32 + (0:1023)), 128, 8);

            % 第一段已知反号，先取负再与后续同向片段比较。
            % (:,1)表示第一列的全部行。
            repeats(:, 1) = -repeats(:, 1);
            % PSS第一个片段的反号不能当普通OFDM忽略

            % 后一重复段乘前一段共轭后求和；相位差反映128点间积累的CFO。
            repeatProduct = sum(repeats(:, 2:end) .* conj(repeats(:, ...
                1:end - 1)), 'all');  % 续接同一调用的其余参数或表达式。

            % 把相位差换成Hz；angle只给一个2π周期，因此结果仍有频偏模糊。
            ambiguousCfo = angle(repeatProduct) * fs / (2 * pi * 128);

            % 枚举重复段估频的有限模糊分支；for后面的=给出本轮编号序列。
            for alias = -2:2
                % 枚举加减Fs/128的有限分支，用完整PSS/SSS去判定哪个分支正确。
                cfo = ambiguousCfo + alias * fs / 128;

                % 枚举-4到4个模型采样的微小时间偏移；for后面的=给出本轮编号序列。
                for delta = -4:4
                    % 在当前对齐附近再移动-4:4个模型采样，精查时序。
                    trialStart = start + delta;

                    % 仅当“trialStart < 1 || trialStart+2111 > sampleCount”为true时执行下方缩进块，
                    % false则跳到else或end。
                    if trialStart < 1 || trialStart + 2111 > sampleCount
                        % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
                        continue;
                    % 结束这一组条件分支，之后接着执行同层的下一条语句。
                    end

                    % 从输入取2112点，并按当前候选CFO逐点乘反向旋转。
                    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
                    corrected = iq(trialStart + (0:2111)) .* exp( -1j * 2 * pi ...
                        * cfo * (0:2111)' / fs);  % 续接同一调用的其余参数或表达式。

                    % 参考共轭转置乘观测得到复内积，除两者范数后取归一化相关幅度。
                    metric = abs(reference' * corrected) / (norm(reference) ...
                        * norm(corrected) + eps);  % 续接同一调用的其余参数或表达式。

                    % 只有当前匹配优于已记录结果时才同时更新起点、CFO和得分。
                    if metric > bestMetric
                        % 发现更大的相关得分时更新当前最优分数。
                        bestMetric = metric;

                        % 同时保存该分数对应的时间起点，不能只更新分数。
                        bestStart = trialStart;

                        % 同时保存对应CFO，保证时间和频偏属于同一候选。
                        bestCfo = cfo;
                    % 结束这一组条件分支，之后接着执行同层的下一条语句。
                    end
                % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
                end
            % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
            end
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end

        % 最优起点不是有限数时，跳过当前粗峰继续检查其他候选。
        if ~isfinite(bestStart)
            % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
            continue;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % 取出最优起点之后2112点，留作最终频偏细化与原始观测记录。
        raw = iq(bestStart + (0:2111));

        % 生成同步窗口的秒坐标；从0开始，'将实数时间轴变成列向量。
        time = (0:2111)' / fs;

        % @(f)定义输入频率f的函数；负相关能量越小，就表示匹配越强。
        % @定义函数句柄，保存任务，之后加()才实际调用。
        objective = @(f) - abs(reference' * (raw .* exp( -1j * 2 * pi * f ...
            * time))) ^ 2;  % 续接同一调用的其余参数或表达式。

        % 在候选CFO前后10kHz内用fminbnd细化频偏，单位Hz。
        bestCfo = fminbnd(objective, bestCfo - 10000, bestCfo + 10000, ...
            optimset('TolX', 0.001, 'Display', 'off'));  % 设置优化停止精度，并关闭迭代文字显示。

        % 用细化后的CFO重新补偿同一个2112点同步窗口。
        corrected = raw .* exp( -1j * 2 * pi * bestCfo * time);

        % 只对前1056点算PSS相关幅度，独立保留这一项同步证据。
        pssMetric = abs(refs.pss' * corrected(1:1056)) / (norm(refs.pss) ...
            * norm(corrected(1:1056)) + eps);  % 续接同一调用的其余参数或表达式。

        % 只对后1056点算SSS相关幅度，不用PSS强峰替代SSS确认。
        sssMetric = abs(refs.sss' * corrected(1057:2112)) / (norm(refs.sss) ...
            * norm(corrected(1057:2112)) + eps);  % 续接同一调用的其余参数或表达式。

        % 把当前候选起点、CFO和三类相关指标组织为一个结构。
        item = struct('start_sample_nominal', bestStart, ...
            'start_sample_capture', ...  % 摘要字段：原BIN连续一基帧起点。
            (bestStart - 1) * cfg.capture_fs_hz / fs + 1, 'coarse_cfo_hz', ...  % 续接同一调用的其余参数或表达式。
            bestCfo, 'pss_metric', pssMetric, 'sss_metric', sssMetric, ...  % 续接同一调用的其余参数或表达式。
            'coarse_metric', coarseMetric, ...  % 后续字段/选项名称及对应取值。
            'coherent_pss_sss_metric', ...  % 后续字段/选项名称及对应取值。
            abs(reference' * corrected) / (norm(reference) ...  % 续接同一调用的其余参数或表达式。
            * norm(corrected) + eps));  % 续接同一调用的其余参数或表达式。

        % PSS/SSS质量不足或完整帧放不下时，下面记录拒绝原因。
        if pssMetric < cfg.minimum_pss || sssMetric < cfg.minimum_sss ...
            || bestStart + cfg.frame_symbol_count * 1056 + 64 > sampleCount  % 续接同一调用的其余参数或表达式。

            % 保存拒绝候选的具体原因标识；之后用“结构名.reason”读取。
            item.reason = 'sync_quality_or_incomplete_window';

            % 拒绝列表为空时直接初始化第一项，否则在末尾追加。
            if isempty(rejected)
                % 第一个被拒候选直接放入空的拒绝列表。
                rejected = item;
            % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
            else
                % 把新的被拒候选追加到列表，保留其起点、质量与原因。
                rejected(end + 1) = item;
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
            continue;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % -8:8建立检测起点附近17个模型采样偏移，供观察局部峰形。
        lags = -8:8;

        % 预分配PSS局部相关曲线；zeros(size(...))保持与横坐标同尺寸。
        pssCurve = zeros(size(lags));

        % 建立同尺寸SSS曲线，初值与PSS的全零数组相同。
        sssCurve = pssCurve;

        % 建立联合相关曲线，同样保留完整17点局部形状。
        jointCurve = pssCurve;

        % 逐个处理当前列表中的元素，k是从1开始的整数索引；for后面的=给出本轮编号序列。
        for k = 1:numel(lags)
            % 把最优起点加当前小偏移，检查局部峰是否集中。
            start = bestStart + lags(k);

            % 窗口越界就跳过这次对齐尝试，不补零伪造参考匹配。
            if start < 1 || start + 2111 > sampleCount
                % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
                continue;
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 按同一CFO补偿这个偏移窗口，避免各局部点使用不同频偏。
            window = iq(start + (0:2111)) .* exp( -1j * 2 * pi * bestCfo * time);

            % 把第k个偏移上的PSS归一化相关保存到曲线。
            pssCurve(k) = abs(refs.pss' * window(1:1056)) / (norm(refs.pss) ...
                * norm(window(1:1056)) + eps);  % 续接同一调用的其余参数或表达式。

            % 把相同偏移上的SSS归一化相关保存，方便交叉确认。
            sssCurve(k) = abs(refs.sss' * window(1057:2112)) / (norm(refs.sss) ...
                * norm(window(1057:2112)) + eps);  % 续接同一调用的其余参数或表达式。

            % 保存同一偏移上的PSS+SSS联合相关幅度。
            jointCurve(k) = abs(reference' * window) / (norm(reference) ...
                * norm(window) + eps);  % 续接同一调用的其余参数或表达式。
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end

        % 保存同步窗口中未乘CFO补偿的2112份模型采样；之后用“结构名.sync_window_raw”读取。
        item.sync_window_raw = raw;

        % 保存同步窗口乘了CFO补偿后的2112份模型采样；之后用“结构名.sync_window_compensated”读取。
        item.sync_window_compensated = corrected;

        % 保存帧头附近PSS、SSS和联合相关峰的曲线；之后用“结构名.sync_local_curve”读取。
        item.sync_local_curve = struct('lag_model_samples', lags, 'pss', ...
            pssCurve, 'sss', sssCurve, 'coherent_pss_sss', jointCurve, ...  % 续接同一调用的其余参数或表达式。
            'cfo_hz', bestCfo);  % 后续字段/选项名称及对应取值。

        % 候选列表为空时直接初始化第一项，否则在末尾追加。
        if isempty(candidates)
            % 第一个合格候选直接作为结构数组的第一个元素。
            candidates = item;
        % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
        else
            % end表示已有最后位置；end+1在结构数组末尾追加一个候选。
            candidates(end + 1) = item;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % 合格候选达到数量上限时，结束当前粗峰搜索循环。
        if numel(candidates) >= cfg.max_sync_candidates
            % 退出最内层循环；它不代表退出整个接收机。
            break;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end
