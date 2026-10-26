function sampled = resampleCapture(capture, cfg)
%RESAMPLECAPTURE 第2步：把250Msps的窗口变成240Msps的名义模型采样。
% y=resample(x,24,25,50)包含抗混叠FIR及其标称延时处理。
% 这只是名义比例；实际采样速率偏差SFO在整帧跟踪后另外估计。
% 输出 iq 仍为时域复采样，尚未去CP或FFT。保留FIR与移除的DC供检查。

[iq, filterCoefficients] = resample(capture.iq, cfg.resample_p, cfg.resample_q, cfg.resample_filter_half_length);
removedDc = mean(iq);
sampled.iq = iq - removedDc;
sampled.fs_hz = cfg.model_fs_hz;
sampled.first_complex_sample_capture = capture.first_complex_sample;
sampled.capture_fs_hz = capture.fs_hz;
sampled.filter = filterCoefficients;
sampled.removed_dc = removedDc;
sampled.ratio = [cfg.resample_p cfg.resample_q];
sampled.summary = struct('complex_samples', numel(iq), 'fs_hz', sampled.fs_hz, ...
    'ratio', sampled.ratio, 'removed_dc_real', real(removedDc), 'removed_dc_imag', imag(removedDc));
end
