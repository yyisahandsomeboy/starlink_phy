function record = cardinality(points, replicates, seed)
%CARDINALITY 判断一列接收点更像4/8/16/32个簇，不直接解释业务位。
% 每个K运行kmeans多次，以点轮廓系数silhouette的中位数选择K。
% silhouette=(最近其他簇平均距离-本簇平均距离)/两者较大值。
% 保留各K得分、标签、中心、SSE；1004×1004距离矩阵只作临时计算。
% 固定并恢复RNG，使结果只依赖输入、seed和参数，不污染后续实验。

points = points(:);
xy = [real(points) imag(points)];
counts = [4 8 16 32];
scores = zeros(1,4);
previous = rng;
restore = onCleanup(@() rng(previous)); %#ok<NASGU>
rng(seed,'twister');
distance = sqrt(max(abs(points).^2+abs(points).'.^2-2*real(points*points'),0));
labels = cell(1,4);
centers = cell(1,4);
silhouettes = cell(1,4);
sse = zeros(1,4);
for k = 1:4
    [ids, centroid, sumDistance] = kmeans(xy,counts(k),'Replicates',replicates, ...
        'MaxIter',100,'Display','off','EmptyAction','singleton');
    membership = sparse(1:numel(points),ids,1,numel(points),counts(k));
    sizes = full(sum(membership,1));
    average = (distance*membership)./sizes;
    within = sum(average.*full(membership),2).*sizes(ids).'./max(sizes(ids).'-1,1);
    singleton = sizes(ids).'==1;
    average(sub2ind(size(average),(1:numel(points))',ids)) = Inf;
    other = min(average,[],2);
    silhouette = (other-within)./max(other,within);
    silhouette(singleton) = 0;
    scores(k) = median(silhouette);
    labels{k} = ids;
    centers{k} = centroid(:,1)+1j*centroid(:,2);
    silhouettes{k} = silhouette;
    sse(k) = sum(sumDistance);
end
[~, chosen] = max(scores);
record = struct('candidate_cardinalities',counts,'median_silhouette',scores, ...
    'within_cluster_sum_squares',sse,'selected_index',chosen,'cardinality',counts(chosen), ...
    'labels',labels{chosen},'centroids',centers{chosen},'silhouette',silhouettes{chosen}, ...
    'replicates',replicates,'seed',seed);
end
