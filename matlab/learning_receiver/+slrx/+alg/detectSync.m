function [candidates, rejected, scan] = detectSync(iq, refs, cfg)
%DETECTSYNC PSS重复结构检测与PSS+SSS相干确认的具体算法。
% 粗分数是8个128点参考片段的相关幅度之和，降低粗频偏带来的抵消。
% 精确认使用连续2112点参考[PSS;SSS]，同时估计时间与CFO。
% 重复段CFO的角度只确定模Fs/128，因此显式检查有限的alias候选。
% 所有索引均为当前240Msps窗口的一基位置；转换原采样坐标由findFrame做。

sampleCount = numel(iq);
fs = cfg.model_fs_hz;
segment = refs.pss(161:288);
score = zeros(sampleCount-1055, 1);
blockLength = 1000000;
for first = 1:blockLength:numel(score)
    last = min(numel(score), first+blockLength-1);
    chunk = iq(first:last+1055);
    fftLength = 2^nextpow2(numel(chunk)+127);
    correlation = ifft(fft(chunk, fftLength).*fft(conj(flipud(segment)), fftLength));
    correlation = correlation(128:numel(chunk));
    summed = zeros(last-first+1, 1);
    for repeat = 0:7
        indices = 33 + repeat*128 + (0:numel(summed)-1);
        summed = summed + abs(correlation(indices));
    end
    energy = sqrt(movsum(abs(chunk).^2, [0 1055]));
    score(first:last) = summed ./ max(energy(1:numel(summed))*sqrt(128)*8, eps);
end
scan = struct('score_sample_nominal', (1:100:numel(score))', ...
    'score_decimated', score(1:100:end), 'trace_decimation', 100);
candidates = struct([]);
rejected = struct([]);
reference = [refs.pss; refs.sss];
for attempt = 1:36
    [coarseMetric, coarseStart] = max(score);
    if coarseMetric < 0.07, break; end
    score(max(1,coarseStart-1100):min(numel(score),coarseStart+1100)) = 0;
    if ~isempty(candidates) && any(abs([candidates.start_sample_nominal]-coarseStart) < 200000)
        continue;
    end
    bestMetric = -Inf;
    bestStart = NaN;
    bestCfo = NaN;
    for offset = -1024:128:1024
        start = coarseStart + offset;
        if start < 1 || start+2111 > sampleCount, continue; end
        repeats = reshape(iq(start+32+(0:1023)), 128, 8);
        repeats(:,1) = -repeats(:,1); % PSS第一个片段的反号不能当普通OFDM忽略
        repeatProduct = sum(repeats(:,2:end).*conj(repeats(:,1:end-1)), 'all');
        ambiguousCfo = angle(repeatProduct)*fs/(2*pi*128);
        for alias = -2:2
            cfo = ambiguousCfo + alias*fs/128;
            for delta = -4:4
                trialStart = start + delta;
                if trialStart < 1 || trialStart+2111 > sampleCount, continue; end
                corrected = iq(trialStart+(0:2111)).*exp(-1j*2*pi*cfo*(0:2111)'/fs);
                metric = abs(reference'*corrected)/(norm(reference)*norm(corrected)+eps);
                if metric > bestMetric
                    bestMetric = metric;
                    bestStart = trialStart;
                    bestCfo = cfo;
                end
            end
        end
    end
    if ~isfinite(bestStart), continue; end
    raw = iq(bestStart+(0:2111));
    time = (0:2111)'/fs;
    objective = @(f) -abs(reference'*(raw.*exp(-1j*2*pi*f*time)))^2;
    bestCfo = fminbnd(objective, bestCfo-10000, bestCfo+10000, ...
        optimset('TolX',0.001,'Display','off'));
    corrected = raw.*exp(-1j*2*pi*bestCfo*time);
    pssMetric = abs(refs.pss'*corrected(1:1056))/(norm(refs.pss)*norm(corrected(1:1056))+eps);
    sssMetric = abs(refs.sss'*corrected(1057:2112))/(norm(refs.sss)*norm(corrected(1057:2112))+eps);
    item = struct('start_sample_nominal', bestStart, 'start_sample_capture', ...
        (bestStart-1)*cfg.capture_fs_hz/fs+1, 'coarse_cfo_hz', bestCfo, ...
        'pss_metric', pssMetric, 'sss_metric', sssMetric, 'coarse_metric', coarseMetric, ...
        'coherent_pss_sss_metric', abs(reference'*corrected)/(norm(reference)*norm(corrected)+eps));
    if pssMetric < cfg.minimum_pss || sssMetric < cfg.minimum_sss || bestStart+cfg.frame_symbol_count*1056+64 > sampleCount
        item.reason = 'sync_quality_or_incomplete_window';
        if isempty(rejected), rejected=item; else, rejected(end+1)=item; end %#ok<AGROW>
        continue;
    end
    lags = -8:8;
    pssCurve = zeros(size(lags));
    sssCurve = pssCurve;
    jointCurve = pssCurve;
    for k = 1:numel(lags)
        start = bestStart + lags(k);
        if start < 1 || start+2111 > sampleCount, continue; end
        window = iq(start+(0:2111)).*exp(-1j*2*pi*bestCfo*time);
        pssCurve(k) = abs(refs.pss'*window(1:1056))/(norm(refs.pss)*norm(window(1:1056))+eps);
        sssCurve(k) = abs(refs.sss'*window(1057:2112))/(norm(refs.sss)*norm(window(1057:2112))+eps);
        jointCurve(k) = abs(reference'*window)/(norm(reference)*norm(window)+eps);
    end
    item.sync_window_raw = raw;
    item.sync_window_compensated = corrected;
    item.sync_local_curve = struct('lag_model_samples',lags,'pss',pssCurve, ...
        'sss',sssCurve,'coherent_pss_sss',jointCurve,'cfo_hz',bestCfo);
    if isempty(candidates), candidates=item; else, candidates(end+1)=item; end %#ok<AGROW>
    if numel(candidates) >= cfg.max_sync_candidates, break; end
end
end
