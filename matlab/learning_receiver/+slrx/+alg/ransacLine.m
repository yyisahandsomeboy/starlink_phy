% 定义ransacLine函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function inliers = ransacLine(x, y, valid, tolerance, seed)
    %RANSACLINE 用有限随机点对拟合直线，拒绝偏离过大的逐列时延估计。
    % 输入x为数据列号，y为模型采样单位的时延；valid排除未识别列。
    % 同一组时延内点随后也用于相位拟合，保持旧接收机的算法约定。
    % 本函数只返回内点掩码，不把被排除的原始观测删除。

    % 保存原随机数状态，本函数内部随机抽点结束后会恢复它。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    previous = rng;

    % 建立退出时恢复随机状态的任务，避免污染其他学习步骤。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    restore = onCleanup(@() rng(previous));

    % 固定本函数用的随机种子及twister算法，让重复运行能够复现。
    % 单引号里的文字是字符数据，不是同名变量。
    rng(seed, 'twister');

    % find把true/false有效掩码转换成可用数据列的整数编号。
    ids = find(valid);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(numel(ids) >= 2, 'RANSAC至少需要两个有效数据列');

    % 记录迄今最多的直线内点数，初值0。
    bestCount = 0;

    % 在内点数量相同时比较残差平方和，先用Inf表示尚无最佳值。
    bestError = Inf;

    % 先把所有有效观测作为后备掩码；不会删除原始逐列估计。
    inliers = valid;

    % 最多150次随机抽点对，寻找稳健直线的内点集；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for trial = 1:150
        % randperm不重复地抽两个有效点，作为本次直线假设。
        pair = ids(randperm(numel(ids), 2));

        % polyfit(...,1)用两个抽中点拟合一阶直线，返回[斜率 截距]。
        coefficients = polyfit(x(pair), y(pair), 1);

        % polyval计算直线预测，再求所有观测到直线的绝对偏差。
        residual = abs(y - polyval(coefficients, x));

        % 只有原来有效且残差不超过容差的点才成为本次内点。
        % &对数组各元素分别取逻辑“并且”。
        mask = valid & residual <= tolerance;

        % nnz统计逻辑掩码中true的个数，也就是内点数。
        count = nnz(mask);

        % 取出内点残差并逐元素平方求和，比较同样内点数的候选。
        % .^是对各元素分别乘方。
        error = sum(residual(mask) .^ 2);

        % 优先选择内点更多的直线；同样多时选内点误差更小的一条。
        % &&要求两侧标量条件都为真，并按需计算右侧。
        % ||是两个标量条件的逻辑“或者”。
        if count > bestCount || (count == bestCount && error < bestError)
            % 当前假设内点更多，或同样多但误差更小时，更新最好内点数。
            bestCount = count;

            % 同时保存该假设的内点平方误差。
            bestError = error;

            % 保存当前最优内点掩码，供整帧时延/相位拟合共用。
            inliers = mask;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 内点不足2个时回退到原有效点，不能用不足两点拟合直线。
    if nnz(inliers) < 2
        % 若随机搜索留下不足两点，则退回原有效掩码，避免无法拟合直线。
        inliers = valid;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end
