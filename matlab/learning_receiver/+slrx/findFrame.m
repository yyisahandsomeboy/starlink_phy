% 定义findFrame函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function synchronization = findFrame(sampled, refs, cfg)
    %FINDFRAME 第3步：独立搜索PSS/SSS，按时间选一个合格完整帧。
    % 输入为240Msps窗口。这里不读sliceInfo、旧接收结果或作者TOA。
    % 先用PSS重复段提出便宜候选，再搜索有限的频偏/时间邻域，最后细化CFO。
    % 输出 candidates/rejected/local_curve，并明确本窗口与原BIN两种坐标。

    % 接收三个输出：通过的同步候选、拒绝记录、粗搜索曲线；不用作者TOA。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    [candidates, rejected, scan] = slrx.alg.detectSync(sampled.iq, refs, cfg);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    % 单引号里的文字是字符数据，不是同名变量。
    assert(~isempty(candidates), '没有找到完整同步候选，请检查PSD、窗口长度和采样率');
    % 先保留原检测次序，以重现原接收机的随机种子约定；然后按时间排序。

    % 逐个处理当前列表中的元素，k是从1开始的整数索引；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for k = 1:numel(candidates)
        % 保留检测时的原次序，后面据此固定随机数种子。
        candidates(k).detection_index = k;

        % 把本窗口240Msps起点换成原BIN的250Msps连续一基坐标。
        % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
        candidates(k).start_sample_capture = ...
            sampled.first_complex_sample_capture ...  % 续接同一调用的其余参数或表达式。
            + (candidates(k).start_sample_nominal - 1) * cfg.capture_fs_hz ...  % 续接同一调用的其余参数或表达式。
            / cfg.model_fs_hz;  % 续接同一调用的其余参数或表达式。
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 提取各候选起点后排序，只保留时间排序的原候选索引。
    [~, order] = sort([candidates.start_sample_nominal]);

    % 用时间排列重排结构数组，不改变每个候选的原始检测编号。
    candidates = candidates(order);

    % find返回SSS相关达到处理门限的候选编号；并非所有粗峰都值得处理。
    qualified = find([candidates.sss_metric] >= cfg.minimum_processing_sss);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(numel(qualified) >= cfg.frame_rank, '所选序号没有足够的SSS质量合格帧');

    % 从时间排序的合格列表取frame_rank指定的完整帧。
    selected = candidates(qualified(cfg.frame_rank));

    % 保存本次按时间序号选择的独立合格帧；之后用“结构名.selected”读取。
    synchronization.selected = selected;

    % 保存独立捕获到的候选帧及其同步依据；之后用“结构名.candidates”读取。
    synchronization.candidates = candidates;

    % 保存被拒绝的候选及原因，不把它们强行当完整帧；之后用“结构名.rejected”读取。
    synchronization.rejected = rejected;

    % 保存稀疏保存的全窗口粗搜索相关分数；之后用“结构名.scan”读取。
    synchronization.scan = scan;

    % 保存采样率，单位Hz，即每秒复采样数；之后用“结构名.fs_hz”读取。
    synchronization.fs_hz = sampled.fs_hz;

    % 保存供JSON记录的小型摘要，完整数组仍保存在MAT里；之后用“结构名.summary”读取。
    synchronization.summary = struct('candidate_count', numel(candidates), ...
        'processing_qualified_count', numel(qualified), ...  % 后续字段/选项名称及对应取值。
        'selected_start_sample_capture', selected.start_sample_capture, ...  % 后续字段/选项名称及对应取值。
        'selected_pss_correlation', selected.pss_metric, ...  % 后续字段/选项名称及对应取值。
        'selected_sss_correlation', selected.sss_metric, ...  % 后续字段/选项名称及对应取值。
        'coarse_cfo_hz', selected.coarse_cfo_hz, ...  % 摘要字段：完整同步参考细化后的粗CFO，单位Hz。
        'annotations_used', false);  % 摘要字段：是否使用作者标注参与检测；保持false。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
