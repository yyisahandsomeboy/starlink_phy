function trace = tracePoint(context, pass, symbol, row)
%TRACEPOINT FFT点依赖一整段时域采样；不能谎称对应唯一原IQ点。
cfg=context.cfg;refs=context.refs;
validateattributes(pass,{'numeric'},{'scalar','integer','>=',1,'<=',2});
validateattributes(symbol,{'numeric'},{'scalar','integer','>=',1,'<=',cfg.data_column_count});
validateattributes(row,{'numeric'},{'scalar','integer','>=',1,'<=',cfg.nfft});
field=sprintf('time%d',pass);
trace=struct('round',pass,'data_symbol',symbol,'grid_column',symbol+1, ...
    'matlab_fft_row',row,'signed_bin',refs.frequency_bins(row), ...
    'frequency_mhz',slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(row),cfg), ...
    'available',isfield(context,field),'unique_raw_sample',false, ...
    'meaning','一个FFT点组合1024个插值时域样本；不是一个ADC采样点', ...
    'filter_support_note','还经过256抽头sinc插值和名义重采样FIR；以下为有效区名义时间坐标，不冒充全部FIR支持', ...
    'dependency_note','均衡/跟踪输出还依赖SSS信道与整帧参数估计；以下不是全部算法依赖');
if ~trace.available, return; end
time=context.(field);
indices=(symbol+1)*(cfg.nfft+cfg.cp_length)+cfg.cp_length+(1:cfg.nfft);
positions=time.sample_positions_nominal(indices);
raw=slrx.diag.coordinates('model_to_capture',positions,cfg);
trace.model_positions=positions;
trace.capture_positions=raw;
trace.raw_interval=[raw(1) raw(end)];
trace.nearest_raw_integers=round(trace.raw_interval);
trace.nearest_byte_offsets=4*(trace.nearest_raw_integers-1);
trace.capture_time_ms=slrx.diag.coordinates('capture_to_ms',trace.raw_interval,cfg);
trace.input_file=cfg.input_file;
trace.checkpoint_time_field=field;
end
