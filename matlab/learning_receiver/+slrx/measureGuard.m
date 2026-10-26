function guard = measureGuard(capture, synchronization, offsets, cfg)
%MEASUREGUARD 补充观察：预测帧末保护区，并读取该区原IQ的能量。
% 这是模型边界，不是独立检测出的噪声边缘。名义长度1088/240MHz。
% 所有区间使用连续一基、左闭右开[start,end)。整数中心ceil(start):ceil(end)-1。
% 单帧不足以确认相邻时隙或波束身份，所以本函数不把空隙解释为漏帧。

scale = 1/(1+offsets.sfo_ppm*1e-6);
start = synchronization.selected.start_sample_capture;
occupied = cfg.frame_symbol_count*(cfg.nfft+cfg.cp_length);
guardStart = start+occupied*cfg.capture_fs_hz/cfg.model_fs_hz*scale;
guardEnd = start+cfg.capture_fs_hz/cfg.slot_rate_hz*scale;
width = guardEnd-guardStart;
localStart = guardStart-capture.first_complex_sample+1;
localEnd = guardEnd-capture.first_complex_sample+1;
indices = (max(1,ceil(localStart)):min(numel(capture.iq),ceil(localEnd)-1))';
preIndices = (max(1,ceil(localStart-width)):min(numel(capture.iq),ceil(localStart)-1))';
guard.start_sample_capture = guardStart;
guard.end_sample_capture_exclusive = guardEnd;
guard.sample_indices_capture = indices+capture.first_complex_sample-1;
guard.samples = capture.iq(indices);
guard.preguard_samples = capture.iq(preIndices);
guard.in_capture = localStart>=1 && localEnd<=numel(capture.iq)+1;
guard.mean_power = mean(abs(guard.samples).^2);
guard.preguard_mean_power = mean(abs(guard.preguard_samples).^2);
guard.power_ratio = guard.mean_power/guard.preguard_mean_power;
guard.summary = struct('endpoint_source','model_predicted','edge_detection_performed',false, ...
    'duration_us',width/cfg.capture_fs_hz*1e6,'start_sample_capture',guardStart, ...
    'end_sample_capture_exclusive',guardEnd,'in_capture',guard.in_capture,'power_ratio',guard.power_ratio);
end
