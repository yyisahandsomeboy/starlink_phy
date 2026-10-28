function view = sampleView(context, first, count)
%SAMPLEVIEW 同一真实时间区间的原采样和已保存重采样；不执行插值或读BIN。
cfg=context.cfg;capture=context.capture;
validateattributes(first,{'numeric'},{'scalar','integer','>=',1,'<=',numel(capture.iq)});
validateattributes(count,{'numeric'},{'scalar','integer','positive'});
indices=(first:min(numel(capture.iq),first+count-1)).';
raw=capture.first_complex_sample+indices-1;anchor=raw(1);
view=struct('raw_indices',indices,'raw_positions',raw,'raw_values',capture.iq(indices), ...
    'raw_time_ns',(raw-anchor)/cfg.capture_fs_hz*1e9,'anchor_raw_sample',anchor, ...
    'file_time_ms',slrx.diag.coordinates('capture_to_ms',anchor,cfg), ...
    'raw_spacing_ns',1e9/cfg.capture_fs_hz,'model_spacing_ns',1e9/cfg.model_fs_hz, ...
    'model_available',isfield(context,'sampled'),'model_indices',[],'model_positions_capture',[], ...
    'model_time_ns',[],'model_values',[], ...
    'meaning','采样中心为离散位置；幅度仍为复数。重采样包含原FIR和DC移除，不是复制原ADC点。');
if ~view.model_available,return;end
limits=slrx.diag.coordinates('capture_to_model',raw([1 end]),cfg);
tolerance=32*eps(max(1,max(abs(limits))));
model=(max(1,ceil(limits(1)-tolerance)):min(numel(context.sampled.iq),floor(limits(2)+tolerance))).';
view.model_indices=model;
view.model_positions_capture=slrx.diag.coordinates('model_to_capture',model,cfg);
view.model_time_ns=(view.model_positions_capture-anchor)/cfg.capture_fs_hz*1e9;
view.model_values=context.sampled.iq(model);
end
