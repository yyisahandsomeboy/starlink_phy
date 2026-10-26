function classes = classifyColumns(equalized, refs, cfg, seedBase)
%CLASSIFYCOLUMNS 第10步：逐列估计星座点数，保存识别依据。
% 使用原FFT顺序的1004个非导频/非gutter位置，与旧算法保持同一输入顺序。
% K=4仍需下一步结合相位区分QPSK/4QAM；K=8作为未处理复合模型保留。
% 这是主要耗时阶段之一。每25列报告进度，不把数组打印到终端。

classes.records = cell(1,cfg.data_column_count);
classes.selected_cardinality = zeros(1,cfg.data_column_count);
classes.scores = zeros(4,cfg.data_column_count);
classes.payload_rows = refs.payload_rows;
for column = 1:cfg.data_column_count
    points = equalized.values(refs.payload_rows,column+1);
    record = slrx.alg.cardinality(points,cfg.kmeans_replicates,seedBase+column);
    classes.records{column} = record;
    classes.selected_cardinality(column) = record.cardinality;
    classes.scores(:,column) = record.median_silhouette;
    if mod(column,25)==0
        fprintf('LEARN_CARDINALITY %d/%d\n',column,cfg.data_column_count);
    end
end
classes.summary = struct('data_columns',cfg.data_column_count, ...
    'count_K4',nnz(classes.selected_cardinality==4),'count_K8',nnz(classes.selected_cardinality==8), ...
    'count_K16',nnz(classes.selected_cardinality==16),'count_K32',nnz(classes.selected_cardinality==32), ...
    'seed_base',seedBase,'business_mapping_known',false);
end
