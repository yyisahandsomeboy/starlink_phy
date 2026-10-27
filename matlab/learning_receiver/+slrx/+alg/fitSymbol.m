% 定义fitSymbol函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
% 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
function estimate = fitSymbol(received, bins, constellation, variance, seed, ...
    known, nfft)  % 继续列出本函数的输入参数。
    %FITSYMBOL 给定一列星座几何，估计残余时延/相位。
    % 在导频初值附近检查9个起点，只精化代价最小的两个，避免完整笛卡尔大搜。
    % Newton方向用Hessian，必要时增加正对角，限制步长并回溯确保代价下降。
    % 输出theta、初/终代价、梯度、Hessian及迭代数，让失败能被观察。
    % 该局部数值优化不负责解码业务；K的选择在前一步已经单独完成。

    % nargin是实际输入参数个数；少于6个时在下面补这个可选参数的默认值。
    if nargin < 6
        % 少于6个输入时设空数组，表示本次只拟合未知载荷。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        known = [];
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % nargin是实际输入参数个数；少于7个时在下面补这个可选参数的默认值。
    if nargin < 7
        % 少于7个输入时采用1024点FFT，保持模型约定。
        nfft = 1024;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 把时延/相位初值统一成2×1列向量。
    % (:)把全部元素按列顺序排成一列。
    % 冒号给出索引序列；单独:取整维全部位置。
    seed = seed(:);

    % 为9组初值预分配2×9矩阵；每列存[时延;相位]。
    initial = zeros(2, 9);

    % 为9组初值的负对数似然分数预留存储。
    scores = zeros(1, 9);

    % 从0开始计数，进入双循环后先加1再作MATLAB下标。
    index = 0;

    % 枚举3种时延初值偏移，单位模型采样；for后面的=给出本轮编号序列。
    for delayOffset = [-0.15 0 0.15]
        % 枚举3种相位初值偏移，单位rad；for后面的=给出本轮编号序列。
        for phaseOffset = [-pi/4 0 pi/4]
            % 递增候选编号，使3个时延偏移×3个相位偏移依次占据9列。
            index = index + 1;

            % 用分号把时延和相位偏移上下拼成2×1列，再加到初值上。
            initial(:, index) = seed + [delayOffset; phaseOffset];

            % 计算当前初值的边缘似然代价；这里还没有开始迭代优化。
            scores(index) = slrx.alg.marginalNLL(initial(:, index), received, ...
                bins, constellation, variance, known, nfft);  % 续接同一调用的其余参数或表达式。
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 按代价从小到大排序；只保留候选的原编号顺序。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [~, order] = sort(scores);

    % 用正无穷初始化最小代价，让任何合法有限解都能更新它。
    bestValue = Inf;

    % 在找到更优解前，先保留调用者给出的时延/相位初值。
    bestTheta = seed;

    % 初始化被选中解的迭代次数。
    bestIterations = 0;

    % 只对代价最好的2个初值分别进行局部数值优化；for后面的=给出本轮编号序列。
    for start = order(1:2)
        % 从9个初值里取当前较优的一个，作为本轮Newton搜索起点。
        theta = initial(:, start);

        % 最多进行30轮Newton更新，不无限增加迭代次数；for后面的=给出本轮编号序列。
        for iteration = 1:30
            % 同时取代价、2×1梯度g、2×2 Hessian H，用来决定参数更新方向。
            [value, g, H] = slrx.alg.marginalNLL(theta, received, bins, ...
                constellation, variance, known, nfft);  % 续接同一调用的其余参数或表达式。

            % eig返回H的特征值；最小值用来判断局部曲率是否适合下降。
            smallestEigenvalue = min(eig(H));

            % 必要时给H加正对角项，使Newton方向更稳定；eye(2)是2×2单位阵。
            H = H + eye(2) * max(0, 1e-5 - smallestEigenvalue);

            % -H\g解线性方程，不是逐元素相除；得到时延/相位的建议改变量。
            % 反斜杠解线性方程组，不是逐元素除。
            change = -H \ g;

            % 限制单次时延和相位变化的大小，避免一步跳离合理局部范围。
            change = change / max([1 abs(change(1))/0.2 abs(change(2))/0.3]);

            % 先标记本次建议尚未被接受，只有代价下降足够才设为true。
            accepted = false;

            % 从1、1/2、1/4依次缩小步长，寻找确实降低代价的更新；for后面的=给出本轮编号序列。
            for scale = 2. ^ -(0:10)
                % 当前参数加缩放后的建议改变量，得到一个待试探的新点。
                proposal = theta + scale * change;

                % 候选时延离初值超过2采样时跳过，限制局部搜索范围。
                if abs(proposal(1) - seed(1)) > 2
                    % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
                    continue;
                % 结束这一组条件分支，之后接着执行同层的下一条语句。
                end

                % 只计算新参数的代价，不取梯度/Hessian，节省回溯尝试的时间。
                nextValue = slrx.alg.marginalNLL(proposal, received, bins, ...
                    constellation, variance, known, nfft);  % 续接同一调用的其余参数或表达式。

                % 只有试探代价满足下降条件，下面才接受这个缩放步长。
                % 单独的'对复数做共轭转置，与.'不同。
                if nextValue <= value - 1e-4 * scale * max(0, -g' * change)
                    % 这个缩放步长满足下降条件，将它标记为已接受。
                    accepted = true;

                    % 退出最内层循环；它不代表退出整个接收机。
                    break;
                % 结束这一组条件分支，之后接着执行同层的下一条语句。
                end
            % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
            end

            % 没有可接受下降或更新量已经很小时，停止当前Newton循环。
            % ||是两个标量条件的逻辑“或者”。
            if ~accepted || norm(scale * change) < 1e-7
                % 退出最内层循环；它不代表退出整个接收机。
                break;
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 采用回溯接受的新参数，开始下一轮迭代。
            theta = proposal;
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end

        % 本轮结束后重新计算最终参数的实际代价，用于和另一初值比较。
        value = slrx.alg.marginalNLL(theta, received, bins, constellation, ...
            variance, known, nfft);  % 续接同一调用的其余参数或表达式。

        % 当前初值得到更小代价时，更新全局保留的最佳局部解。
        if value < bestValue
            % 当前初值搜索所得更优，更新最小负对数似然代价。
            bestValue = value;

            % 同时保存取得该代价的2个参数，保证参数和代价一一对应。
            bestTheta = theta;

            % 记录这组最佳参数实际迭代了多少轮。
            bestIterations = iteration;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 在最佳参数处取梯度/Hessian用于诊断，~忽略重复返回的代价。
    [~, gradient, H] = slrx.alg.marginalNLL(bestTheta, received, bins, ...
        constellation, variance, known, nfft);  % 续接同一调用的其余参数或表达式。

    % 输出参数、初末代价、梯度、曲率和迭代信息，便于追溯优化是否可靠。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    % 单引号里的文字是字符数据，不是同名变量。
    estimate = struct('theta', bestTheta, 'negative_log_likelihood', bestValue, ...
        'initial_negative_log_likelihood', slrx.alg.marginalNLL(seed, received, ...  % 后续字段/选项名称及对应取值。
        bins, constellation, variance, known, nfft), 'gradient', gradient, ...  % 续接同一调用的其余参数或表达式。
        'hessian', H, 'iterations', bestIterations, 'seed', seed, ...  % 后续字段/选项名称及对应取值。
        'finite', all(isfinite(bestTheta)) && isfinite(bestValue));  % 摘要字段：本次参数和代价是否均为有限数。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
