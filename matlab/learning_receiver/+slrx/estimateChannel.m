function channel = estimateChannel(grid, refs, cfg, sharedShape)
%ESTIMATECHANNEL 第7步：只用已知SSS估计频率响应H及均衡后的噪声。
% H_LS=Y_SSS/X_SSS。在物理频率顺序上先去小的线性相位斜坡，
% 再Savitzky-Golay平滑，最后恢复时延斜坡与帧复增益。
% 默认sharedShape=[]：本帧独立估计。可选参数仅供高级同输入比较，
% 是1024×1归一化共享响应；单帧教学流程不会从别的帧偷读它。
% 输出H与grid行号一致；noise_variance_equalized为E|noise|^2/|H|^2。

if nargin < 4, sharedShape = []; end
received = grid.values(:,1);
active = find(abs(refs.sss_grid)>eps);
frequency = refs.frequency_bins(active);
[frequency, order] = sort(frequency);
rows = active(order);
lsResponse = received(rows)./refs.sss_grid(rows);
angularBins = 2*pi*frequency/cfg.nfft;
trials = -2:0.02:2;
profile = abs(sum(lsResponse.*exp(1j*angularBins*trials),1)).^2;
[~, peak] = max(profile);
low = max(-2,trials(peak)-0.04);
high = min(2,trials(peak)+0.04);
delay = fminbnd(@(d)-abs(sum(lsResponse.*exp(1j*angularBins*d)))^2,low,high, ...
    optimset('TolX',1e-10,'Display','off'));
deramped = lsResponse.*exp(1j*angularBins*delay);
smoothed = sgolayfilt(deramped,cfg.smoothing_degree,cfg.smoothing_window);
zeroFrequency = interp1(frequency,smoothed,0,'linear');
assert(abs(zeroFrequency)>1e-10,'SSS信道归一化处接近零');
normalized = smoothed/zeroFrequency;
if ~isempty(sharedShape)
    normalized = sharedShape(rows);
    normalized = normalized/interp1(frequency,normalized,0,'linear');
end
gain = sqrt(mean(abs((received(rows).*exp(1j*angularBins*delay))./normalized).^2));
phase = angle(sum((received(rows).*exp(1j*angularBins*delay)./normalized).*conj(refs.sss_grid(rows))));
frameGain = gain*exp(1j*phase);
H = zeros(cfg.nfft,1);
H(rows) = frameGain*normalized.*exp(-1j*angularBins*delay);
H([1 2]) = H(3);
H([1023 1024]) = H(1022);
% 极深衰落处设置数值幅度下限，防止除零；不是估计出了真实无噪信道。
floorAmplitude = max(median(abs(H(active)))*1e-3,realmin);
small = abs(H)<floorAmplitude;
H(small) = floorAmplitude*exp(1j*angle(H(small)));
residual = received(rows)-H(rows).*refs.sss_grid(rows);
noisePower = max(median(abs(residual).^2)/log(2),1e-12);
normalizedFull = zeros(cfg.nfft,1);
normalizedFull(rows) = normalized;
channel.H = H;
channel.noise_variance_equalized = noisePower./max(abs(H).^2,eps);
channel.channel_normalized = normalizedFull;
channel.frequency_order_rows = rows;
channel.sss_ls_frequency_order = lsResponse;
channel.sss_deramped_ls = deramped;
channel.channel_smoothed_frequency_order = smoothed;
channel.frame_complex_gain = frameGain;
channel.sss_delay_samples = delay;
channel.sss_delay_trial_samples = trials;
channel.sss_delay_profile = profile;
channel.sss_residual_frequency_order = residual;
channel.noise_power_before_equalization = noisePower;
channel.shared_channel_used = ~isempty(sharedShape);
channel.frequency_bins = refs.frequency_bins;
channel.summary = struct('H_size',size(H),'sss_delay_model_samples',delay, ...
    'noise_power_before_equalization',noisePower,'shared_channel_used',channel.shared_channel_used);
end
