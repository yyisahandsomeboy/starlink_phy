function output = fitColumn(column, channel, refs, classification, pilotDelay, pilotPhase, dataColumn, cfg)
%FITCOLUMN 把点数识别、几何选择和两次局部ML连接起来。
% column是1024×1均衡后数据列，含导频；classification来自第10步。
% 对K=4用相对导频相位区分QPSK/4QAM；K=8不强行套简单星座。
% 最终增益只用于载荷显示/判决，不重缩放公开导频。

output.geometry_id = 0;
output.delay_samples = NaN;
output.phase_rad = NaN;
output.gain = NaN;
output.cost = NaN;
output.iterations = 0;
output.record = classification;
if classification.cardinality==8
    output.record.geometry_id = 0;
    output.record.status = 'composite_cardinality_8';
    return;
end
if classification.cardinality==4
    model = 1;
elseif classification.cardinality==16
    model = 3;
else
    model = 4;
end
rows = refs.payload_rows;
gain = max(sqrt(mean(abs(classification.centroids).^2)),0.05);
normalized = column(rows)/gain;
variance = max(channel.noise_variance_equalized(rows)/gain^2,cfg.noise_variance_floor);
estimate = slrx.alg.fitSymbol(normalized,refs.frequency_bins(rows),refs.constellations{model}, ...
    variance,[pilotDelay;pilotPhase],[],cfg.nfft);
phase = estimate.theta(2);
if model==1
    difference = mod(phase-pilotPhase+pi/4,pi/2)-pi/4;
    if abs(difference)>pi/8
        model = 2;
        phase = phase-sign(difference)*pi/4;
    end
end
phase = pilotPhase + mod(phase-pilotPhase+pi/4,pi/2)-pi/4;
% 已知参考和观测一起除以gain，噪声方差除以gain^2；不能只缩放其中一项。
% 参考导频按列由上层传入，避免将第一个数据列模板错误地重复使用。
known = struct('y',column(refs.fit_rows)/gain,'k',refs.frequency_bins(refs.fit_rows), ...
    'reference',refs.pilots(refs.fit_rows,dataColumn+1)/gain,'variance', ...
    max(channel.noise_variance_equalized(refs.fit_rows)/gain^2,cfg.noise_variance_floor/gain^2));
estimate = slrx.alg.fitSymbol(normalized,refs.frequency_bins(rows),refs.constellations{model}, ...
    variance,[estimate.theta(1);phase],known,cfg.nfft);
phase = pilotPhase + mod(estimate.theta(2)-pilotPhase+pi/4,pi/2)-pi/4;
aligned = normalized.*exp(1j*(2*pi*refs.frequency_bins(rows)/cfg.nfft*estimate.theta(1)-phase));
[~, ids] = min(abs(aligned-refs.constellations{model}.').^2,[],2);
points = refs.constellations{model}(ids);
updatedGain = max(real(sum(conj(points).*aligned))*gain/sum(abs(points).^2),0.05);
output.geometry_id = model;
output.delay_samples = estimate.theta(1);
output.phase_rad = phase;
output.gain = updatedGain;
output.cost = estimate.negative_log_likelihood;
output.iterations = estimate.iterations;
output.record.geometry_id = model;
output.record.status = 'author_simple_constellation';
output.record.ml = estimate;
output.record.gain = updatedGain;
end
