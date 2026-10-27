% 定义removeCP函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function ofdmTime = removeCP(frameTime, cfg)
    %REMOVECP 第5步：把连续帧分成符号，PSS单列保留，普通OFDM去32点CP。
    % 输入长度302*1056。输出without_cp为1024×301，第一列对应SSS。
    % PSS的特殊重复/反号结构不在这里按普通OFDM解释。
    % cp_correlation比较普通OFDM前32点和有效符号末32点，仅作诊断。

    % 有效区1024点加CP 32点，得到每个时隙1056点。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    symbolLength = cfg.nfft + cfg.cp_length;

    % reshape按列重新排数据为1056×302；只改组织，不改变样本先后。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    blocks = reshape(frameTime.time_cfo_compensated, symbolLength, ...
        cfg.frame_symbol_count);  % 续接同一调用的其余参数或表达式。

    % (:,1)取第一列所有行，单独保存PSS的1056个时间采样。
    % (:,1)表示第一列的全部行。
    % 冒号给出索引序列；单独:取整维全部位置。
    ofdmTime.pss_time = blocks(:, 1);

    % (1:32,2:end)取后301列前32行，即普通OFDM的CP。
    % 索引里的end指这一维最后的位置，不是结束if/for。
    ofdmTime.cp_samples = blocks(1:cfg.cp_length, 2:end);

    % (33:end,2:end)去掉普通OFDM的CP，得到1024×301有效区。
    ofdmTime.without_cp = blocks(cfg.cp_length + 1:end, 2:end);

    % (end-31:end,2:end)取普通OFDM有效区最后32点，与CP作比较。
    tail = blocks(end - cfg.cp_length + 1:end, 2:end);

    % 给已保存的CP起一个短变量名，后面的相关公式更易读。
    cp = ofdmTime.cp_samples;

    % 计算CP与尾部的归一化复相关；conj取共轭，sum(...,1)沿行求和。
    % .*是对应元素相乘，不是矩阵乘法。
    % ./是对应元素相除，列向量可自动扩展到各列。
    % .^是对各元素分别乘方。
    ofdmTime.cp_correlation = sum(tail .* conj(cp), ...
        1) ./ max(sqrt(sum(abs(tail) .^ 2, 1) .* sum(abs(cp) .^ 2, 1)), eps);  % 继续计算CP/尾部能量归一化分母。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    % 单引号里的文字是字符数据，不是同名变量。
    ofdmTime.summary = struct('without_cp_size', size(ofdmTime.without_cp), ...
        'cp_size', size(cp), 'mean_abs_cp_correlation', ...  % 后续字段/选项名称及对应取值。
        mean(abs(ofdmTime.cp_correlation)));  % 续接同一调用的其余参数或表达式。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
