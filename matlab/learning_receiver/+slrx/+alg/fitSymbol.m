function estimate = fitSymbol(received, bins, constellation, variance, seed, known, nfft)
%FITSYMBOL 给定一列星座几何，估计残余时延/相位。
% 在导频初值附近检查9个起点，只精化代价最小的两个，避免完整笛卡尔大搜。
% Newton方向用Hessian，必要时增加正对角，限制步长并回溯确保代价下降。
% 输出theta、初/终代价、梯度、Hessian及迭代数，让失败能被观察。
% 该局部数值优化不负责解码业务；K的选择在前一步已经单独完成。

if nargin < 6, known = []; end
if nargin < 7, nfft = 1024; end
seed = seed(:);
initial = zeros(2,9);
scores = zeros(1,9);
index = 0;
for delayOffset = [-0.15 0 0.15]
    for phaseOffset = [-pi/4 0 pi/4]
        index = index+1;
        initial(:,index) = seed+[delayOffset;phaseOffset];
        scores(index) = slrx.alg.marginalNLL(initial(:,index),received,bins,constellation,variance,known,nfft);
    end
end
[~, order] = sort(scores);
bestValue = Inf;
bestTheta = seed;
bestIterations = 0;
for start = order(1:2)
    theta = initial(:,start);
    for iteration = 1:30
        [value,g,H] = slrx.alg.marginalNLL(theta,received,bins,constellation,variance,known,nfft);
        smallestEigenvalue = min(eig(H));
        H = H+eye(2)*max(0,1e-5-smallestEigenvalue);
        change = -H\g;
        change = change/max([1 abs(change(1))/0.2 abs(change(2))/0.3]);
        accepted = false;
        for scale = 2.^-(0:10)
            proposal = theta+scale*change;
            if abs(proposal(1)-seed(1))>2, continue; end
            nextValue = slrx.alg.marginalNLL(proposal,received,bins,constellation,variance,known,nfft);
            if nextValue<=value-1e-4*scale*max(0,-g'*change)
                accepted = true;
                break;
            end
        end
        if ~accepted || norm(scale*change)<1e-7, break; end
        theta = proposal;
    end
    value = slrx.alg.marginalNLL(theta,received,bins,constellation,variance,known,nfft);
    if value<bestValue
        bestValue = value;
        bestTheta = theta;
        bestIterations = iteration;
    end
end
[~,gradient,H] = slrx.alg.marginalNLL(bestTheta,received,bins,constellation,variance,known,nfft);
estimate = struct('theta',bestTheta,'negative_log_likelihood',bestValue, ...
    'initial_negative_log_likelihood',slrx.alg.marginalNLL(seed,received,bins,constellation,variance,known,nfft), ...
    'gradient',gradient,'hessian',H,'iterations',bestIterations,'seed',seed, ...
    'finite',all(isfinite(bestTheta)) && isfinite(bestValue));
end
