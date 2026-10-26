function offsets = refineOffsets(synchronization, tracked, initialOffsets, cfg)
%REFINEOFFSETS 第12步：从整帧斜率更新CFO/SFO，供第二轮重新取样。
% delaySlope/1056是每模型采样积累的残余时间比例。
% SFO_total=((1+SFO0*1e-6)*(1-beta)-1)*1e6。
% CFO_residual=phaseSlope*Fs*(1+SFO0*1e-6)/(2*pi*1056)。
% 更新后重新进行第4～11步，而不是只把最终星座旋转一下。

symbolLength = cfg.nfft+cfg.cp_length;
beta = tracked.delay_line_coefficients(1)/symbolLength;
offsets.sfo_ppm = ((1+initialOffsets.sfo_ppm*1e-6)*(1-beta)-1)*1e6;
offsets.residual_cfo_hz = tracked.phase_line_coefficients(1)*cfg.model_fs_hz* ...
    (1+initialOffsets.sfo_ppm*1e-6)/(2*pi*symbolLength);
offsets.cfo_hz = synchronization.selected.coarse_cfo_hz+offsets.residual_cfo_hz;
assert(isfinite(offsets.sfo_ppm) && abs(offsets.sfo_ppm)<100,'采样速率估计超出当前模型范围');
offsets.summary = struct('initial_cfo_hz',initialOffsets.cfo_hz,'initial_sfo_ppm',initialOffsets.sfo_ppm, ...
    'residual_cfo_hz',offsets.residual_cfo_hz,'final_cfo_hz',offsets.cfo_hz,'final_sfo_ppm',offsets.sfo_ppm);
end
