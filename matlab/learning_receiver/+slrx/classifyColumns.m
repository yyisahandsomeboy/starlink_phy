% 定义classifyColumns函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function classes = classifyColumns(equalized, refs, cfg, seedBase)
    %CLASSIFYCOLUMNS 第10步：逐列估计星座点数，保存识别依据。
    % 使用原FFT顺序的1004个非导频/非gutter位置，与旧算法保持同一输入顺序。
    % K=4仍需下一步结合相位区分QPSK/4QAM；K=8作为未处理复合模型保留。
    % 这是主要耗时阶段之一。每25列报告进度，不把数组打印到终端。

    % 建立1×300的cell，每格存一列的聚类中心、标签和评分等完整记录。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    classes.records = cell(1, cfg.data_column_count);

    % 预分配300个数，依次保存每列选定的K。
    classes.selected_cardinality = zeros(1, cfg.data_column_count);

    % 预分配4×300评分表：4行对应K=4/8/16/32，300列对应数据列。
    classes.scores = zeros(4, cfg.data_column_count);

    % 保留聚类实际使用的1004个原FFT行号。
    classes.payload_rows = refs.payload_rows;

    % 依次处理一个数据OFDM列，不把300列星座全部混在一起；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for column = 1:cfg.data_column_count
        % 取当前数据列的1004个点；+1跳过频域网格第1列SSS。
        points = equalized.values(refs.payload_rows, column + 1);

        % 分别尝试四种K；每列seed不同但固定，使重新运行能够复现。
        % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
        record = slrx.alg.cardinality(points, cfg.kmeans_replicates, ...
            seedBase + column);  % 续接同一调用的其余参数或表达式。

        % 用{column}把整份结构放进cell；花括号表示读写格子里面的内容。
        % {编号}取得cell格子内部的数据，()则取得格子外壳。
        classes.records{column} = record;

        % 把当前列选中的点数放进300元素数组的相应位置。
        classes.selected_cardinality(column) = record.cardinality;

        % 冒号表示全部4行；将本列四个候选得分一起保存。
        classes.scores(:, column) = record.median_silhouette;

        % 每隔固定列数才报告进度，避免把大数组打印到终端。
        if mod(column, 25) == 0
            % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
            % 单引号里的文字是字符数据，不是同名变量。
            fprintf('LEARN_CARDINALITY %d/%d\n', column, cfg.data_column_count);
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    classes.summary = struct('data_columns', cfg.data_column_count, 'count_K4', ...
        nnz(classes.selected_cardinality == 4), 'count_K8', ...  % 续接同一调用的其余参数或表达式。
        nnz(classes.selected_cardinality == 8), 'count_K16', ...  % 续接同一调用的其余参数或表达式。
        nnz(classes.selected_cardinality == 16), 'count_K32', ...  % 续接同一调用的其余参数或表达式。
        nnz(classes.selected_cardinality == 32), 'seed_base', ...  % 续接同一调用的其余参数或表达式。
        seedBase, 'business_mapping_known', false);  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
