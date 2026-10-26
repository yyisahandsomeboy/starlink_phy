function frameTime = extractFrame(sampled, synchronization, offsets, cfg)
%EXTRACTFRAME 第4步：按帧起点和采样步长读取完整帧，再补偿CFO。
% offsets.cfo_hz：Hz；offsets.sfo_ppm：相对采样率ppm。
% 取样位置 = start + n/(1+sfo*1e-6)，n为模型采样数。
% CFO以帧起点为时间零点补偿：r*exp(-j*2*pi*CFO*time)。
% 输出time_raw仍在名义模型流上，不是原BIN的250Msps数组。

count = cfg.frame_symbol_count*(cfg.nfft+cfg.cp_length);
nominalOffset = (0:count-1)'/(1+offsets.sfo_ppm*1e-6);
start = synchronization.selected.start_sample_nominal;
positions = start + nominalOffset;
assert(positions(1)>=1 && positions(end)<=numel(sampled.iq), '完整帧超出已读取窗口');
frameTime.time_raw = slrx.alg.interpolateSinc(sampled.iq, positions);
frameTime.time_cfo_compensated = frameTime.time_raw.*exp(-1j*2*pi*offsets.cfo_hz*nominalOffset/cfg.model_fs_hz);
frameTime.sample_positions_nominal = positions;
frameTime.sample_position_start = start;
frameTime.sample_position_step = 1/(1+offsets.sfo_ppm*1e-6);
frameTime.cfo_hz = offsets.cfo_hz;
frameTime.sfo_ppm = offsets.sfo_ppm;
frameTime.summary = struct('complex_samples',count,'cfo_hz',offsets.cfo_hz, ...
    'sfo_ppm',offsets.sfo_ppm,'sample_position_start',start,'sample_position_step',frameTime.sample_position_step);
end
