function tracked = trackFrame(equalized, channel, pilots, classes, refs, cfg, seedBase)
%TRACKFRAME 第11步：逐列ML估计，再拟合整帧相位/时延并补偿。
% 第10步已经单独算出点数，本步不重复kmeans。
% 延迟单位为模型采样，phase为rad。相位具有90°歧义，结合FIT导频选分支。
% 保留原始逐列估计、RANSAC内点和拟合残差；不要只留下最终星座图。

count = cfg.data_column_count;
delay = nan(1,count);
phase = delay;
gain = delay;
geometry = zeros(1,count);
cost = delay;
iterations = zeros(1,count);
records = cell(1,count);
for column = 1:count
    result = slrx.alg.fitColumn(equalized.values(:,column+1),channel,refs, ...
        classes.records{column},pilots.raw_delay_samples(column),pilots.raw_phase_rad(column),column,cfg);
    delay(column) = result.delay_samples;
    phase(column) = result.phase_rad;
    gain(column) = result.gain;
    geometry(column) = result.geometry_id;
    cost(column) = result.cost;
    iterations(column) = result.iterations;
    records{column} = result.record;
    if mod(column,50)==0
        fprintf('LEARN_ML %d/%d\n',column,count);
    end
end
valid = geometry>0 & isfinite(delay) & isfinite(phase);
assert(nnz(valid)>=cfg.minimum_simple_symbols,'简单星座列不足，不能可靠拟合整帧趋势');
columns = 1:count;
inliers = slrx.alg.ransacLine(columns,delay,valid,cfg.ransac_delay_threshold_samples,seedBase);
% 先以90°为周期展开，再移到导频给出的相位分支，避免把歧义当真实CFO。
unwrapped = nan(size(phase));
unwrapped(valid) = unwrap(4*phase(valid))/4;
unwrapped(valid) = unwrapped(valid) + ...
    round((pilots.raw_phase_rad(valid)-unwrapped(valid))/(pi/2))*(pi/2);
delayFit = polyfit(columns(inliers),delay(inliers),1);
phaseFit = polyfit(columns(inliers),unwrapped(inliers),1);
delayLine = polyval(delayFit,columns);
phaseLine = polyval(phaseFit,columns);
tracked.values = equalized.values;
tracked.values(:,2:301) = equalized.values(:,2:301).*exp(1j*( ...
    2*pi*refs.frequency_bins/cfg.nfft*delayLine-ones(cfg.nfft,1)*phaseLine));
tracked.ml_delay_samples = delay;
tracked.ml_phase_rad = phase;
tracked.ml_phase_unwrapped_rad = unwrapped;
tracked.ml_inlier_mask = inliers;
tracked.ml_delay_residual_samples = delay-delayLine;
tracked.ml_phase_residual_rad = unwrapped-phaseLine;
tracked.delay_line_coefficients = delayFit;
tracked.phase_line_coefficients = phaseFit;
tracked.delay_line_samples = delayLine;
tracked.phase_line_rad = phaseLine;
tracked.geometry_id = geometry;
tracked.gain_per_data_symbol = gain;
tracked.cardinality_scores = classes.scores;
tracked.records = records;
tracked.ml_negative_log_likelihood = cost;
tracked.ml_iterations = iterations;
reference = refs.pilots(refs.eval_rows,2:301);
tracked.heldout_pilot_evm = sqrt(mean(abs(tracked.values(refs.eval_rows,2:301)-reference).^2,'all'));
tracked.summary = struct('simple_columns',nnz(valid),'inlier_columns',nnz(inliers), ...
    'heldout_pilot_evm',tracked.heldout_pilot_evm,'delay_slope_per_column',delayFit(1), ...
    'phase_slope_rad_per_column',phaseFit(1));
end
