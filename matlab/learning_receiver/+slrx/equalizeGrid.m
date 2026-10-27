% 定义equalizeGrid函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function equalized = equalizeGrid(grid, channel, refs)
    %EQUALIZEGRID 第8步：撤销每个频率位置的信道幅度/相位变化。
    % Z[k,m]=Y[k,m]/H[k]。本模型整帧用同一个SSS频率响应。
    % 评价导频在本步骤不参与H拟合；保存均衡前后EVM作数值观察。

    % 每行的频域观测除以同一行的H；./逐元素除，H列向量自动扩展到各列。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    equalized.values = grid.values ./ channel.H;

    % 保留频率行的物理含义，使后续补偿不会混淆FFT顺序。
    equalized.frequency_bins = refs.frequency_bins;

    % 取EVAL导频行、数据列2:301的均衡前观测；列1的SSS不参加本项评价。
    % 冒号给出索引序列；单独:取整维全部位置。
    receivedBefore = grid.values(refs.eval_rows, 2:301);

    % 取相同EVAL资源位置的均衡后观测，便于公平比较。
    receivedAfter = equalized.values(refs.eval_rows, 2:301);

    % 取这些位置已知的公开导频，作为独立误差参考。
    reference = refs.pilots(refs.eval_rows, 2:301);

    % 误差能量除参考能量再开方，得到均衡前的无量纲EVM。
    % .^是对各元素分别乘方。
    % 单引号里的文字是字符数据，不是同名变量。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    equalized.heldout_pilot_evm_before = sqrt(sum(abs(receivedBefore ...
        - reference) .^ 2, 'all') / sum(abs(reference) .^ 2, 'all'));  % 误差能量按参考能量归一化后开方。

    % 按同一公式计算均衡后EVM；这里未做后续相位/时延跟踪。
    equalized.heldout_pilot_evm_after = sqrt(sum(abs(receivedAfter ...
        - reference) .^ 2, 'all') / sum(abs(reference) .^ 2, 'all'));  % 误差能量按参考能量归一化后开方。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    equalized.summary = struct('grid_size', size(equalized.values), ...
        'heldout_pilot_evm_before', equalized.heldout_pilot_evm_before, ...  % 后续字段/选项名称及对应取值。
        'heldout_pilot_evm_after', equalized.heldout_pilot_evm_after);  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
