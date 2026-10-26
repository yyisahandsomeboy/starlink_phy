function [value, gradient, hessian] = marginalNLL(theta, received, bins, constellation, variance, known, nfft)
%MARGINALNLL 未知载荷星座的高斯混合负对数似然，以及解析梯度/Hessian。
% theta=[delay;phase]，delay是模型采样，phase是rad；bins是有符号FFT bin。
% 前向模型 y=c*exp(j*phase-j*2*pi*bin*delay/N)+noise。
% 将每个未知c在候选星座上求和，而不是先把所有点硬判成真值。
% known为可选FIT导频结构(y/k/reference/variance)，不包含EVAL导频。
% variance表示E|n|^2，已经按载荷幅度归一化；不是单独实部方差。
% 先减去每行最大指数再求和，防止exp下溢。下面导数与旧接收机同式。

if nargin < 6, known = []; end
if nargin < 7, nfft = 1024; end
received = received(:);
bins = bins(:);
constellation = constellation(:).';
variance = max(variance(:),1e-8);
assert(numel(received)==numel(bins));
angularBins = 2*pi*bins/nfft;
aligned = received.*exp(1j*(angularBins*theta(1)-theta(2)));
distance = abs(aligned-constellation).^2;
logWeight = -distance./variance;
largest = max(logWeight,[],2);
weight = exp(logWeight-largest);
normalizer = sum(weight,2);
weight = weight./normalizer;
terms = log(pi*variance*numel(constellation))-largest-log(normalizer);
% 已知导频不需要对星座求和；其参考幅度必须与观测一起归一化。
if ~isempty(known)
    pilotAngular = 2*pi*known.k(:)/nfft;
    pilotAligned = known.y(:).*exp(1j*(pilotAngular*theta(1)-theta(2)));
    pilotVariance = max(known.variance(:),1e-8);
    pilotProduct = conj(pilotAligned).*known.reference(:);
    extra = log(pi*pilotVariance)+abs(pilotAligned-known.reference(:)).^2./pilotVariance;
else
    extra = zeros(0,1);
    pilotAngular = zeros(0,1);
    pilotProduct = complex(zeros(0,1));
    pilotVariance = zeros(0,1);
end
count = numel(received)+numel(extra);
value = (sum(terms)+sum(extra))/count;
if nargout < 2, return; end
product = conj(aligned).*constellation;
imaginary = imag(product);
meanImaginary = sum(weight.*imaginary,2);
first = 2*meanImaginary./variance;
direction = [-angularBins ones(size(angularBins))];
pilotDirection = [-pilotAngular ones(size(pilotAngular))];
gradient = (sum(first.*direction,1)+sum((2*imag(pilotProduct)./pilotVariance).*pilotDirection,1)).'/count;
if nargout < 3, return; end
second = 2*sum(weight.*real(product),2)./variance - ...
    4*(sum(weight.*imaginary.^2,2)-meanImaginary.^2)./variance.^2;
hessian = (direction'*(second.*direction) + ...
    pilotDirection'*((2*real(pilotProduct)./pilotVariance).*pilotDirection))/count;
hessian = (hessian+hessian')/2;
end
