% 定义decideSymbols函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function decisions = decideSymbols(tracked, channel, refs, cfg)
    %DECIDESYMBOLS 第14步：在最终网格上作条件最近星座点判决。
    % 对每列使用第11步选定的几何和幅度。未知/K8列保留NaN及−1，不强制猜测。
    % 输出1004×300矩阵按物理频率排序，并保留原FFT行号/网格列号。
    % posterior为当前几何与噪声模型下的诊断量；不将它冒称真实业务位概率。
    % 与旧导出器一样，已识别列全部导出，未知列擦除；没有真实业务位映射。

    % 取按物理频率排序的1004个载荷行，方便最终判决与频率位置对应。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    rows = refs.payload_rows_frequency_order;

    % 提取所有300个数据列；列1是SSS，因此使用2:301。
    % 冒号给出索引序列；单独:取整维全部位置。
    received = tracked.values(rows, 2:301);

    % 取跟踪阶段每列选择的几何编号；0表示当前模型未知。
    geometry = tracked.geometry_id;

    % 取每列估计的载荷幅度，用于把理想星座缩放到观测尺度。
    gains = tracked.gain_per_data_symbol;

    % 取各载荷行均衡后噪声方差；max与eps避免除零。
    variance = max(channel.noise_variance_equalized(rows), eps);

    % 建立同尺寸复NaN矩阵；没有判决的地方保留NaN而不是假填0。
    points = complex(nan(size(received)), nan(size(received)));

    % 另建一个结果矩阵，保存乘列增益后的理想星座点。
    observedScale = points;

    % 预填int16类型的-1，作为尚未判决/擦除的点编号。
    % 单引号里的文字是字符数据，不是同名变量。
    pointId = -ones(size(received), 'int16');

    % 预分配当前模型下的诊断后验值；它不是已校准的业务位概率。
    posterior = zeros(size(received));

    % 预填false，只有确实做了条件判决的位置才改为true。
    valid = false(size(received));

    % 依次处理一个数据OFDM列，不把300列星座全部混在一起；for后面的=给出本轮编号序列。
    for column = 1:cfg.data_column_count
        % 取当前列的几何编号；普通圆括号读取数值数组中的元素。
        model = geometry(column);

        % 未知几何的列跳过判决，保留NaN与-1擦除记录。
        if model == 0
            % 跳过当前这一轮循环剩余语句，转去处理下一个候选/偏移。
            continue;
        % 结束这一组条件分支，之后接着执行同层的下一条语句。
        end

        % 用{model}取cell内的实际星座向量，而不是取得一个cell外壳。
        % {编号}取得cell格子内部的数据，()则取得格子外壳。
        constellation = refs.constellations{model};

        % 计算每个接收点到每个候选点的平方距离；.'不共轭转置，自动扩展成距离表。
        % .^是对各元素分别乘方。
        % .'只转置行列，不对复数取共轭。
        distance = abs(received(:, column) - gains(column) * constellation.') .^ 2;

        % min(...,[],2)逐行找最近星座；同时取得最小距离和候选点索引。
        % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
        [minimum, assigned] = min(distance, [], 2);

        % 先减最小距离再取指数，避免所有指数过小而数值下溢。
        % ./是对应元素相除，列向量可自动扩展到各列。
        weights = exp( -(distance - minimum) ./ variance);

        % 按行归一化，使各候选权重之和为1。
        weights = weights ./ sum(weights, 2);

        % 把每个位置最近的归一化理想星座点写入结果矩阵。
        points(:, column) = constellation(assigned);

        % 保留乘了实际列增益的最近理想点，用于和接收散点叠加显示。
        observedScale(:, column) = gains(column) * constellation(assigned);

        % assigned从1开始；减1保存内部零基点号，再转成int16。
        pointId(:, column) = int16(assigned - 1);

        % 保存每个接收点最大的候选权重，只作为条件模型诊断。
        posterior(:, column) = max(weights, [], 2);

        % 这一列已识别几何，因此标记所有位置已得到条件判决。
        valid(:, column) = true;
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 保存按物理频率排序的真实接收载荷复数矩阵；之后用“结构名.received”读取。
    decisions.received = received;

    % 保存归一化的最近理想星座点，未知处为NaN；之后用“结构名.hard_symbols”读取。
    decisions.hard_symbols = points;

    % 保存乘了列增益的最近理想星座点；之后用“结构名.hard_symbols_observed_scale”读取。
    decisions.hard_symbols_observed_scale = observedScale;

    % 保存本代码星座列表中的零基编号，擦除为-1；之后用“结构名.point_id_0based”读取。
    decisions.point_id_0based = pointId;

    % 保存给出了条件判决的位置，true有效、false未知；之后用“结构名.valid_mask”读取。
    decisions.valid_mask = valid;

    % 保存擦除位置掩码，是有效掩码的逻辑取反；之后用“结构名.erasure_mask”读取。
    decisions.erasure_mask = ~valid;

    % 保存给定候选几何/噪声假设的诊断后验值；之后用“结构名.conditional_model_posterior”读取。
    decisions.conditional_model_posterior = posterior;

    % 保存1004个载荷位置对应的原FFT一基行号；之后用“结构名.payload_matlab_rows”读取。
    decisions.payload_matlab_rows = rows;

    % 保存每个载荷位置的有符号FFT bin；之后用“结构名.frequency_bins_signed”读取。
    decisions.frequency_bins_signed = refs.frequency_bins(rows);

    % 保存判决数据对应原网格的列号2:301；之后用“结构名.source_grid_columns”读取。
    decisions.source_grid_columns = 2:301;

    % 保存每个数据列采用的条件星座几何；之后用“结构名.geometry_id_per_column”读取。
    decisions.geometry_id_per_column = geometry;

    % 保存几何名称与编号的对应表；之后用“结构名.constellation_names”读取。
    decisions.constellation_names = refs.constellation_names;

    % 保存实际使用的各组候选复数星座点；之后用“结构名.candidate_geometries”读取。
    decisions.candidate_geometries = refs.constellations;

    % 保存是否恢复商业业务位；此接收机保持false；之后用“结构名.business_bits_available”读取。
    decisions.business_bits_available = false;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    decisions.summary = struct('payload_positions', numel(valid), ...
        'valid_decisions', nnz(valid), 'erased_positions', nnz(~valid), ...  % 后续字段/选项名称及对应取值。
        'heldout_pilot_evm', tracked.heldout_pilot_evm, ...  % 摘要字段：不参与参数拟合的EVAL导频上的EVM。
        'business_bits_available', false, 'MCS_status', 'unknown', ...  % 摘要字段：是否恢复商业业务位；此接收机保持false。
        'FEC_status', 'unknown', 'CRC_status', 'unknown');  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
