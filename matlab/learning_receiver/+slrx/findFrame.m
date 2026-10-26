function synchronization = findFrame(sampled, refs, cfg)
%FINDFRAME 第3步：独立搜索PSS/SSS，按时间选一个合格完整帧。
% 输入为240Msps窗口。这里不读sliceInfo、旧接收结果或作者TOA。
% 先用PSS重复段提出便宜候选，再搜索有限的频偏/时间邻域，最后细化CFO。
% 输出 candidates/rejected/local_curve，并明确本窗口与原BIN两种坐标。

[candidates, rejected, scan] = slrx.alg.detectSync(sampled.iq, refs, cfg);
assert(~isempty(candidates), '没有找到完整同步候选，请检查PSD、窗口长度和采样率');
% 先保留原检测次序，以重现原接收机的随机种子约定；然后按时间排序。
for k = 1:numel(candidates)
    candidates(k).detection_index = k;
    candidates(k).start_sample_capture = sampled.first_complex_sample_capture + ...
        (candidates(k).start_sample_nominal-1)*cfg.capture_fs_hz/cfg.model_fs_hz;
end
[~, order] = sort([candidates.start_sample_nominal]);
candidates = candidates(order);
qualified = find([candidates.sss_metric] >= cfg.minimum_processing_sss);
assert(numel(qualified) >= cfg.frame_rank, '所选序号没有足够的SSS质量合格帧');
selected = candidates(qualified(cfg.frame_rank));
synchronization.selected = selected;
synchronization.candidates = candidates;
synchronization.rejected = rejected;
synchronization.scan = scan;
synchronization.fs_hz = sampled.fs_hz;
synchronization.summary = struct('candidate_count', numel(candidates), ...
    'processing_qualified_count', numel(qualified), 'selected_start_sample_capture', selected.start_sample_capture, ...
    'selected_pss_correlation', selected.pss_metric, 'selected_sss_correlation', selected.sss_metric, ...
    'coarse_cfo_hz', selected.coarse_cfo_hz, 'annotations_used', false);
end
