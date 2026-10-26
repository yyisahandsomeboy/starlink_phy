function report = validate_learning_modules(projectRoot, outputDir)
%VALIDATE_LEARNING_MODULES 用旧真实检查点作工程对照，验证拆分没有换公式。
% 这里只把已有网格作为测试输入，不将旧帧头/标注给学习版的捕获步骤。
% 依次核对参考序列、插值、CP/FFT、信道、似然导数、300列MSS和ML。
% 参考是原接收机实际保存的首次均衡和跟踪结果，不再运行9帧接收机。

addpath(fullfile(projectRoot,'matlab','learning_receiver'));
addpath(fullfile(projectRoot,'matlab','baseline'),fullfile(projectRoot,'matlab','visualization'));
cfg = slrx.defaultConfig(projectRoot);
cfg.show_figures = false;
limits = jsondecode(fileread(fullfile(projectRoot,'config','learning_validation_v1.json')));
refs = slrx.references(cfg);
oldRefs = author_sequences(projectRoot);
assert(isequal(refs.pss,oldRefs.pss) && isequal(refs.sss,oldRefs.sss) && isequal(refs.pilots,oldRefs.pilots));
C = payload_models();
assert(isequaln(refs.constellations,C),'星座几何或内部点序改变');
runDir = fullfile(projectRoot,'runs','codex-author-real-20261014-170603-942987');
f = load_payload_frame(runDir,1);
window = f.sync_window_raw;
positions = (130.125:0.99:1500.25)';
x = slrx.alg.interpolateSinc(window,positions);
y = bandlimited_sample(window,positions);
interpolationError = norm(x-y)/max(norm(y),eps);
assert(interpolationError<=limits.interpolation_relative_error_max);
time.time_cfo_compensated = f.intermediates.time_initial_doppler.frame_time_cfo_compensated;
ofdm = slrx.removeCP(time,cfg);
frequency = slrx.fftGrid(ofdm,refs,cfg);
fftError = norm(frequency.values-f.intermediates.grid_initial_doppler,'fro')/norm(frequency.values,'fro');
assert(fftError<=limits.fft_relative_error_max);
frequency.values = f.grid_resampled;
shared = f.intermediates.channel_final.channel_normalized;
channel = slrx.estimateChannel(frequency,refs,cfg,shared);
[oldH,oldChannel] = author_receiver_dsp('channel',frequency.values(:,1),refs.sss_grid,refs.frequency_bins, ...
    cfg.smoothing_window,cfg.smoothing_degree,shared);
channelError = norm(channel.H-oldH)/norm(oldH);
assert(channelError<=limits.channel_relative_error_max);
assert(norm(channel.noise_variance_equalized-oldChannel.noise_variance_equalized)<1e-8);
% 在同一真实列上核对似然、梯度与Hessian，防止相位/时延符号被重构改反。
rows = refs.payload_rows;
points = f.intermediates.grid_first_equalized(rows,51);
variance = f.intermediates.channel_first.noise_variance_equalized(rows);
theta = [0.13;0.21];
[v,g,H] = slrx.alg.marginalNLL(theta,points,refs.frequency_bins(rows),C{3},variance,[],cfg.nfft);
[ov,og,oH] = author_receiver_dsp('ml_cost',theta,points,refs.frequency_bins(rows),C{3},variance);
likelihoodError = max([abs(v-ov);abs(g-og);abs(H(:)-oH(:))]);
assert(likelihoodError<=limits.likelihood_absolute_error_max);
fprintf('LEARN_PARITY_BASIC_OK fft=%.3g channel=%.3g nll=%.3g\n',fftError,channelError,likelihoodError);
% 拆开的300列识别和跟踪在完全相同输入下应重现旧首次ML。
equalized.values = f.intermediates.grid_first_equalized;
channel.noise_variance_equalized = f.intermediates.channel_first.noise_variance_equalized;
seedBase = f.intermediates.first_modulation.records{1}.seed-1;
pilots = slrx.observePilots(equalized,refs,cfg);
classes = slrx.classifyColumns(equalized,refs,cfg,seedBase);
oldModulation = f.intermediates.first_modulation;
scoreError = max(abs(classes.scores-oldModulation.cardinality_scores),[],'all');
assert(scoreError<1e-10,'星座点数识别的同输入结果改变');
tracked = slrx.trackFrame(equalized,channel,pilots,classes,refs,cfg,seedBase);
oldTracking = f.intermediates.first_ml_tracking;
phaseError = max(abs(tracked.phase_line_rad-oldTracking.phase_intercept_rad));
delayError = max(abs(tracked.delay_line_coefficients-oldTracking.delay_line_coefficients));
assert(phaseError<=limits.tracking_absolute_error_max && delayError<=limits.tracking_absolute_error_max);
assert(isequal(tracked.geometry_id,oldModulation.geometry_id_per_data_symbol));
expectedGrid = equalized.values;
expectedGrid(:,2:301) = expectedGrid(:,2:301).*exp(1j*( ...
    2*pi*refs.frequency_bins/cfg.nfft*polyval(oldTracking.delay_line_coefficients,1:300) ...
    -ones(cfg.nfft,1)*oldTracking.phase_intercept_rad));
trackedError = norm(tracked.values-expectedGrid,'fro')/norm(expectedGrid,'fro');
assert(trackedError<1e-10,'整帧补偿符号或索引改变');
report = struct('status','passed','version',limits.version,'owner','codex_baseline', ...
    'interpolation_relative_error',interpolationError,'FFT_relative_error',fftError, ...
    'channel_relative_error',channelError,'likelihood_gradient_hessian_max_difference',likelihoodError, ...
    'cardinality_score_max_difference',scoreError,'tracking_phase_max_difference_rad',phaseError, ...
    'tracking_delay_coefficient_max_difference',delayError,'tracked_grid_relative_error',trackedError, ...
    'all_300_geometry_labels_identical',true,'reference_checkpoint_used_only_for_validation',true, ...
    'original_evaluator_changed',false,'payload_decoded',false);
if ~exist(outputDir,'dir'),mkdir(outputDir);end
fid = fopen(fullfile(outputDir,'module_parity.json'),'w');
assert(fid>=0);fprintf(fid,'%s',jsonencode(report));fclose(fid);
fprintf('LEARN_ALL_MODULE_PARITY_OK grid=%.3g\n',trackedError);
end
