% 定义observePilots函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function pilots = observePilots(equalized, refs, cfg)
    %OBSERVEPILOTS 第9步：从FIT导频看残余相位/时延，并给ML提供初值。
    % 左右导频相位的差表示频率方向的斜率，共同部分表示整体旋转。
    % raw_*是每列原始导频初值；line_*是跨列线性拟合，仅用于预览/质量观察。
    % ML采用raw_*，不要误把平滑预览当成最终未知数据ML结果。

    % 只取8条FIT导频，把接收值./已知值，留下残余复增益；EVAL不参与。
    % 冒号给出索引序列；单独:取整维全部位置。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    ratio = equalized.values(refs.fit_rows, ...
        2:301) ./ refs.pilots(refs.fit_rows, 2:301);  % 续接同一调用的其余参数或表达式。

    % 对左侧4条FIT先平均再取相位，unwrap展开相邻列的2π跳变。
    % (行号,:)表示这些行的全部列。
    left = unwrap(angle(mean(ratio(1:4, :), 1)));

    % 对右侧4条FIT同样处理，得到另一侧逐列相位观测。
    right = unwrap(angle(mean(ratio(5:8, :), 1)));

    % 计算左侧FIT导频的平均有符号bin，作为直线的横坐标。
    leftBin = mean(refs.frequency_bins(refs.fit_rows(1:4)));

    % 计算右侧FIT导频的平均有符号bin。
    rightBin = mean(refs.frequency_bins(refs.fit_rows(5:8)));

    % 左右相位差除bin差，得到相位对频率索引的斜率。
    slope = (right - left) / (rightBin - leftBin);

    % 由两端相位外推到bin=0，得到每列公共旋转初值，单位rad。
    pilots.raw_phase_rad = (left * rightBin - right * leftBin) / (rightBin ...
        - leftBin);  % 续接同一调用的其余参数或表达式。

    % 用负斜率×N/(2π)把相位斜坡换成模型采样单位的时延。
    pilots.raw_delay_samples = -slope * cfg.nfft / (2 * pi);

    % 1:300生成各数据OFDM符号的编号；MATLAB默认索引从1开始。
    columns = 1:cfg.data_column_count;

    % polyfit(...,1)拟合一阶直线，polyval在300个列号上求其值。
    leftLine = polyval(polyfit(columns, left, 1), columns);

    % 同样拟合右侧导频相位，产生仅用于预览的平滑轨迹。
    rightLine = polyval(polyfit(columns, right, 1), columns);

    % 用左右拟合直线重新计算相位随bin的斜率。
    lineSlope = (rightLine - leftLine) / (rightBin - leftBin);

    % 保存直线预览的公共相位，不替代逐列raw初值。
    pilots.line_phase_rad = (leftLine * rightBin - rightLine * leftBin) ...
        / (rightBin - leftBin);  % 续接同一调用的其余参数或表达式。

    % 把直线预览的相位斜率换成时延，单位模型采样。
    pilots.line_delay_samples = -lineSlope * cfg.nfft / (2 * pi);

    % 复制均衡网格作为预览；原equalized.values保持不变。
    pilots.preview_grid = equalized.values;

    % 只补偿300列数据：乘相位模型的反向复指数；第1列SSS不改。
    % .*是对应元素相乘，不是矩阵乘法。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    pilots.preview_grid(:, 2:301) = equalized.values(:, ...
        2:301) .* exp( -1j * ( refs.frequency_bins * lineSlope + ones(cfg.nfft, ...  % 续接同一调用的其余参数或表达式。
        1) * pilots.line_phase_rad));  % 续接同一调用的其余参数或表达式。

    % 计算预览网格在FIT导频上的误差，仅作初始化质量观察，不作留出证明。
    % .^是对各元素分别乘方。
    % 单引号里的文字是字符数据，不是同名变量。
    pilots.fit_evm = sqrt(mean(abs(pilots.preview_grid(refs.fit_rows, ...
        2:301) - refs.pilots(refs.fit_rows, 2:301)) .^ 2, 'all'));  % 续接同一调用的其余参数或表达式。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    pilots.summary = struct('fit_rows', refs.fit_rows, 'eval_rows_not_fitted', ...
        refs.eval_rows, 'fit_evm_after_pilot_preview', pilots.fit_evm, ...  % 续接同一调用的其余参数或表达式。
        'delay_unit', '240Msps model samples');  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
