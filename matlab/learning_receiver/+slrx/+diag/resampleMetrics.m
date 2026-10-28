function info = resampleMetrics(context)
%RESAMPLEMETRICS 只读N/Fs、同时间窗PSD、原FIR响应及DC；不重新resample。
cfg=context.cfg;info=struct('available',isfield(context,'sampled'),'capture_available',isfield(context,'capture'), ...
    'input_count',NaN,'output_count',NaN,'input_fs_hz',cfg.capture_fs_hz,'output_fs_hz',cfg.model_fs_hz, ...
    'input_duration_s',NaN,'output_duration_s',NaN,'input_dc',NaN,'before_dc_removal',NaN,'after_dc_removal',NaN, ...
    'sample_view',struct(),'psd',struct(),'filter',struct(),'raw_bin_reads',0);
if ~info.available,return;end
s=context.sampled;info.output_count=numel(s.iq);info.output_fs_hz=s.fs_hz;
info.output_duration_s=numel(s.iq)/s.fs_hz;info.after_dc_removal=mean(s.iq);
info.before_dc_removal=info.after_dc_removal+s.removed_dc;
info.ratio=s.ratio;
if info.capture_available
    c=context.capture;info.input_count=numel(c.iq);info.input_duration_s=numel(c.iq)/c.fs_hz;info.input_dc=c.dc;
    first=min(2001,max(1,numel(c.iq)-31));info.sample_view=slrx.diag.sampleView(context,first,32);
    count=min(numel(c.iq),262144);duration=count/c.fs_hz;modelCount=min(numel(s.iq),floor(duration*s.fs_hz));
    if min(count,modelCount)>=256
        window=min(4096,2^floor(log2(min(count,modelCount))));
        [a,f]=pwelch(c.iq(1:count),hann(window),floor(window/2),8192,c.fs_hz,'centered');
        [b,g]=pwelch(s.iq(1:modelCount),hann(window),floor(window/2),8192,s.fs_hz,'centered');
        info.psd=struct('input',a,'input_frequency_hz',f,'output',b,'output_frequency_hz',g, ...
            'input_count',count,'output_count',modelCount,'duration_s',duration,'window_samples',window, ...
            'meaning','相同文件起点、近似同一物理时长、相同样本窗长度；频率轴各用真实Fs，分辨率可能不同');
    end
end
upsampledFs=cfg.capture_fs_hz*s.ratio(1);
[h,f]=freqz(s.filter,1,8192,upsampledFs);
keep=f<=min(1.5*cfg.capture_fs_hz,upsampledFs/2);
info.filter=struct('frequency_hz',f(keep),'response',h(keep)/s.ratio(1), ...
    'upsampled_fs_hz',upsampledFs,'normalization',s.ratio(1),'coefficients_count',numel(s.filter), ...
    'meaning','原FIR在上采样时间轴的频响，除插值增益p用于显示；不是又执行一次滤波');
end
