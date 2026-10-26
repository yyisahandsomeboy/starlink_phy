function inliers = ransacLine(x, y, valid, tolerance, seed)
%RANSACLINE 用有限随机点对拟合直线，拒绝偏离过大的逐列时延估计。
% 输入x为数据列号，y为模型采样单位的时延；valid排除未识别列。
% 同一组时延内点随后也用于相位拟合，保持旧接收机的算法约定。
% 本函数只返回内点掩码，不把被排除的原始观测删除。

previous = rng;
restore = onCleanup(@() rng(previous)); %#ok<NASGU>
rng(seed,'twister');
ids = find(valid);
assert(numel(ids)>=2,'RANSAC至少需要两个有效数据列');
bestCount = 0;
bestError = Inf;
inliers = valid;
for trial = 1:150
    pair = ids(randperm(numel(ids),2));
    coefficients = polyfit(x(pair),y(pair),1);
    residual = abs(y-polyval(coefficients,x));
    mask = valid & residual<=tolerance;
    count = nnz(mask);
    error = sum(residual(mask).^2);
    if count>bestCount || (count==bestCount && error<bestError)
        bestCount = count;
        bestError = error;
        inliers = mask;
    end
end
if nnz(inliers)<2, inliers=valid; end
end
