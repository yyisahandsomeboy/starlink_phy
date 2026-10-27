% 定义cardinality函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function record = cardinality(points, replicates, seed)
    %CARDINALITY 判断一列接收点更像4/8/16/32个簇，不直接解释业务位。
    % 每个K运行kmeans多次，以点轮廓系数silhouette的中位数选择K。
    % silhouette=(最近其他簇平均距离-本簇平均距离)/两者较大值。
    % 保留各K得分、标签、中心、SSE；1004×1004距离矩阵只作临时计算。
    % 固定并恢复RNG，使结果只依赖输入、seed和参数，不污染后续实验。

    % 将1004个接收点统一为列向量，以便构造二维坐标和距离矩阵。
    % (:)把全部元素按列顺序排成一列。
    % 冒号给出索引序列；单独:取整维全部位置。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    points = points(:);

    % 把复数的实部、虚部分别作为两列坐标，供kmeans处理。
    xy = [real(points) imag(points)];

    % 指定四个候选簇数：4、8、16、32；它们是模型候选，不是已知协议标签。
    counts = [4 8 16 32];

    % 为四个候选K预留中位轮廓分数。
    scores = zeros(1, 4);

    % 保存MATLAB当前随机数发生器状态，避免本函数影响外面的随机实验。
    previous = rng;

    % 函数结束自动恢复原随机状态；@()是供onCleanup稍后调用的任务。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    restore = onCleanup(@() rng(previous));

    % 固定本函数用的随机种子及twister算法，让重复运行能够复现。
    % 单引号里的文字是字符数据，不是同名变量。
    rng(seed, 'twister');

    % 用能量和内积展开计算两两欧氏距离，形成1004×1004矩阵。
    % .^是对各元素分别乘方。
    % .'只转置行列，不对复数取共轭。
    % 单独的'对复数做共轭转置，与.'不同。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    distance = sqrt(max(abs(points) .^ 2 + abs(points).' .^ 2 - 2 ...
        * real(points * points'), 0));  % 续接同一调用的其余参数或表达式。

    % cell为不同K的点标签留位置；每格可存一个完整数组。
    labels = cell(1, 4);

    % cell保存不同K的聚类中心，各格长度可以不同。
    centers = cell(1, 4);

    % cell保存各候选下每个点的轮廓系数。
    silhouettes = cell(1, 4);

    % 预分配四种K对应的簇内平方误差和。
    sse = zeros(1, 4);

    % 逐个处理当前列表中的元素，k是从1开始的整数索引；for后面的=给出本轮编号序列。
    for k = 1:4
        % kmeans多次随机初始化，输出逐点簇号、二维中心和各簇误差。
        % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
        [ids, centroid, sumDistance] = kmeans(xy, counts(k), 'Replicates', ...
            replicates, 'MaxIter', 100, 'Display', 'off', 'EmptyAction', ...  % 续接同一调用的其余参数或表达式。
            'singleton');  % 续接同一调用的其余参数或表达式。

        % 构造稀疏0/1成员矩阵：一行一个点，一列一个簇。
        membership = sparse(1:numel(points), ids, 1, numel(points), counts(k));

        % 沿点方向求和，得到各簇包含的点数；full将稀疏结果变成普通数组。
        sizes = full(sum(membership, 1));

        % 距离矩阵乘成员矩阵，得到到各簇的距离和，再除簇大小得到均值。
        % ./是对应元素相除，列向量可自动扩展到各列。
        average = (distance * membership) ./ sizes;

        % 取到本簇的平均距离并排除点到自身的0距离，得到轮廓公式中的a。
        % .*是对应元素相乘，不是矩阵乘法。
        within = sum(average .* full(membership), ...
            2) .* sizes(ids).' ./ max(sizes(ids).' - 1, 1);  % 续接同一调用的其余参数或表达式。

        % 标记只含一个点的簇；这种情况不能按普通轮廓公式解释。
        singleton = sizes(ids).' == 1;

        % 把点到自身簇的候选均距设为Inf，下一步只从其他簇中找最近者。
        average(sub2ind(size(average), (1:numel(points))', ids)) = Inf;

        % 每行找最近其他簇的平均距离，得到轮廓公式中的b。
        other = min(average, [], 2);

        % (b-a)/max(a,b)是点轮廓系数；大值表示本簇更紧、其他簇更远。
        silhouette = (other - within) ./ max(other, within);

        % 单点簇的轮廓值按约定设为0，避免误当成最优分离。
        silhouette(singleton) = 0;

        % 用全部点轮廓系数的中位数给当前K打分，降低异常点影响。
        scores(k) = median(silhouette);

        % 把当前K的逐点簇号放入第k个cell。
        % {编号}取得cell格子内部的数据，()则取得格子外壳。
        labels{k} = ids;

        % 把中心的横纵坐标重新组成复数，方便以后画星座。
        % (:,1)表示第一列的全部行。
        % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
        centers{k} = centroid(:, 1) + 1j * centroid(:, 2);

        % 保存每个点的轮廓值，而不仅保留最终一个得分。
        silhouettes{k} = silhouette;

        % 把当前K所有簇的误差相加，保存另一项聚类诊断量。
        sse(k) = sum(sumDistance);
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 只保留得分最高的候选在四种K中的位置；~丢弃最大分数。
    [~, chosen] = max(scores);

    % 汇总候选得分和选中K的详细依据；struct按“字段名、值”成对建立结构。
    record = struct('candidate_cardinalities', counts, 'median_silhouette', ...
        scores, 'within_cluster_sum_squares', sse, 'selected_index', chosen, ...  % 续接同一调用的其余参数或表达式。
        'cardinality', counts(chosen), 'labels', labels{chosen}, ...  % 后续字段/选项名称及对应取值。
        'centroids', centers{chosen}, 'silhouette', ...  % 后续字段/选项名称及对应取值。
        silhouettes{chosen}, 'replicates', replicates, 'seed', seed);  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
