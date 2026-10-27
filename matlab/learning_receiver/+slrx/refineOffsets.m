% 定义refineOffsets函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function offsets = refineOffsets(synchronization, tracked, initialOffsets, cfg)
    %REFINEOFFSETS 第12步：从整帧斜率更新CFO/SFO，供第二轮重新取样。
    % delaySlope/1056是每模型采样积累的残余时间比例。
    % SFO_total=((1+SFO0*1e-6)*(1-beta)-1)*1e6。
    % CFO_residual=phaseSlope*Fs*(1+SFO0*1e-6)/(2*pi*1056)。
    % 更新后重新进行第4～11步，而不是只把最终星座旋转一下。

    % 每个数据OFDM符号占1056个模型采样，用来把“每列斜率”换成时钟比例。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    symbolLength = cfg.nfft + cfg.cp_length;

    % 取时延直线的斜率项(1)，除1056得到每模型采样积累的残余比例。
    beta = tracked.delay_line_coefficients(1) / symbolLength;

    % 按原算法组合初始SFO与残余比例，最后乘1e6还原成ppm。
    offsets.sfo_ppm = ((1 + initialOffsets.sfo_ppm * 1e-6) * (1 - beta) - 1) * 1e6;

    % 把每列相位增长rad/列换成Hz，并纳入原采样步长的修正。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    offsets.residual_cfo_hz = tracked.phase_line_coefficients(1) ...
        * cfg.model_fs_hz * (1 + initialOffsets.sfo_ppm * 1e-6) / (2 * pi ...  % 续接同一调用的其余参数或表达式。
        * symbolLength);  % 续接同一调用的其余参数或表达式。

    % 把粗CFO和第一轮剩余CFO相加，作为第二轮的总补偿值。
    offsets.cfo_hz = synchronization.selected.coarse_cfo_hz ...
        + offsets.residual_cfo_hz;  % 续接同一调用的其余参数或表达式。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    % 单引号里的文字是字符数据，不是同名变量。
    assert(isfinite(offsets.sfo_ppm) && abs(offsets.sfo_ppm) < 100, ...
        '采样速率估计超出当前模型范围');  % 继续同一检查条件/失败时的说明。

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    offsets.summary = struct('initial_cfo_hz', initialOffsets.cfo_hz, ...
        'initial_sfo_ppm', initialOffsets.sfo_ppm, 'residual_cfo_hz', ...  % 后续字段/选项名称及对应取值。
        offsets.residual_cfo_hz, 'final_cfo_hz', offsets.cfo_hz, ...  % 续接同一调用的其余参数或表达式。
        'final_sfo_ppm', offsets.sfo_ppm);  % 后续字段/选项名称及对应取值。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
