function output = interpolateSinc(input, positions)
%INTERPOLATESINC 在一基、可为小数的样本位置上读取带限信号。
% 输入 input：复列向量；positions：以input采样为单位，不是秒。
% 输出与positions同长。256抽头的加窗sinc保留靠近带边的公开导频。
% 权重 w=sinc(p-n)*(0.5+0.5*cos(pi*(p-n)/128))，|p-n|>=128取0。
% 每次处理2048个位置控制内存；边界外的抽头不使用，不能当完整采集。
% 数学与原bandlimited_sample一致；保持求和次序方便逐值核对。

input = input(:);
positions = positions(:);
output = zeros(size(positions), 'like', input);
offsets = -127:128;
for first = 1:2048:numel(positions)
    last = min(numel(positions), first+2047);
    requested = positions(first:last);
    indices = floor(requested) + offsets;
    distance = requested - indices;
    weights = sinc(distance) .* (0.5 + 0.5*cos(pi*distance/128));
    weights(abs(distance) >= 128) = 0;
    valid = indices >= 1 & indices <= numel(input);
    indices = max(1, min(numel(input), indices));
    weights = weights .* valid;
    output(first:last) = sum(input(indices).*weights, 2);
end
end
