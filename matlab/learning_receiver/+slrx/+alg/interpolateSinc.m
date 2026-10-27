% 定义interpolateSinc函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function output = interpolateSinc(input, positions)
    %INTERPOLATESINC 在一基、可为小数的样本位置上读取带限信号。
    % 输入 input：复列向量；positions：以input采样为单位，不是秒。
    % 输出与positions同长。256抽头的加窗sinc保留靠近带边的公开导频。
    % 权重 w=sinc(p-n)*(0.5+0.5*cos(pi*(p-n)/128))，|p-n|>=128取0。
    % 每次处理2048个位置控制内存；边界外的抽头不使用，不能当完整采集。
    % 数学与原bandlimited_sample一致；保持求和次序方便逐值核对。

    % (:)把任意行/列输入统一拉成列向量，后续矩阵维度才一致。
    % (:)把全部元素按列顺序排成一列。
    % 冒号给出索引序列；单独:取整维全部位置。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    input = input(:);

    % 把要读取的连续一基位置也变成列向量；位置可带小数。
    positions = positions(:);

    % 预分配与位置同长的输出，'like'让数值类型与输入一致。
    % 单引号里的文字是字符数据，不是同名变量。
    output = zeros(size(positions), 'like', input);

    % -127:128生成256个相邻整数抽头的相对位置。
    offsets = -127:128;

    % 按固定批次依次处理，限制临时矩阵占用的内存；for后面的=给出本轮编号序列。
    for first = 1:2048:numel(positions)
        % 每批最多2048个输出位置，最后一批不越界。
        last = min(numel(positions), first + 2047);

        % 只取当前批次需要插值的位置。
        requested = positions(first:last);

        % floor先向下取整，再自动扩展加256个偏移，生成“位置×抽头”的索引表。
        indices = floor(requested) + offsets;

        % 每个连续位置减去各整数抽头坐标，得到插值距离。
        distance = requested - indices;

        % sinc(distance)乘余弦窗，得到256抽头有限带限插值权重。
        % .*是对应元素相乘，不是矩阵乘法。
        weights = sinc(distance) .* (0.5 + 0.5 * cos(pi * distance / 128));

        % 用逻辑条件选择超出窗支持的权重，并将它们设为0。
        weights(abs(distance) >= 128) = 0;

        % 逐元素判断各抽头是否在输入范围内；&逐元素同时满足两侧条件。
        % &对数组各元素分别取逻辑“并且”。
        valid = indices >= 1 & indices <= numel(input);

        % 把越界索引夹回合法范围以便安全访问；下一行会将对应权重清零。
        indices = max(1, min(numel(input), indices));

        % 逻辑valid自动转为0/1，逐元素乘后剔除越界抽头的贡献。
        weights = weights .* valid;

        % 按每行256个抽头求加权和，写入当前批次的插值输出。
        output(first:last) = sum(input(indices) .* weights, 2);
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end
