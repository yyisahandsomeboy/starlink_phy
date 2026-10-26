function decisions = decideSymbols(tracked, channel, refs, cfg)
%DECIDESYMBOLS 第14步：在最终网格上作条件最近星座点判决。
% 对每列使用第11步选定的几何和幅度。未知/K8列保留NaN及−1，不强制猜测。
% 输出1004×300矩阵按物理频率排序，并保留原FFT行号/网格列号。
% posterior为当前几何与噪声模型下的诊断量；不将它冒称真实业务位概率。
% 与旧导出器一样，已识别列全部导出，未知列擦除；没有真实业务位映射。

rows = refs.payload_rows_frequency_order;
received = tracked.values(rows,2:301);
geometry = tracked.geometry_id;
gains = tracked.gain_per_data_symbol;
variance = max(channel.noise_variance_equalized(rows),eps);
points = complex(nan(size(received)),nan(size(received)));
observedScale = points;
pointId = -ones(size(received),'int16');
posterior = zeros(size(received));
valid = false(size(received));
for column = 1:cfg.data_column_count
    model = geometry(column);
    if model==0, continue; end
    constellation = refs.constellations{model};
    distance = abs(received(:,column)-gains(column)*constellation.').^2;
    [minimum, assigned] = min(distance,[],2);
    weights = exp(-(distance-minimum)./variance);
    weights = weights./sum(weights,2);
    points(:,column) = constellation(assigned);
    observedScale(:,column) = gains(column)*constellation(assigned);
    pointId(:,column) = int16(assigned-1);
    posterior(:,column) = max(weights,[],2);
    valid(:,column) = true;
end
decisions.received = received;
decisions.hard_symbols = points;
decisions.hard_symbols_observed_scale = observedScale;
decisions.point_id_0based = pointId;
decisions.valid_mask = valid;
decisions.erasure_mask = ~valid;
decisions.conditional_model_posterior = posterior;
decisions.payload_matlab_rows = rows;
decisions.frequency_bins_signed = refs.frequency_bins(rows);
decisions.source_grid_columns = 2:301;
decisions.geometry_id_per_column = geometry;
decisions.constellation_names = refs.constellation_names;
decisions.candidate_geometries = refs.constellations;
decisions.business_bits_available = false;
decisions.summary = struct('payload_positions',numel(valid),'valid_decisions',nnz(valid), ...
    'erased_positions',nnz(~valid),'heldout_pilot_evm',tracked.heldout_pilot_evm, ...
    'business_bits_available',false,'MCS_status','unknown','FEC_status','unknown','CRC_status','unknown');
end
