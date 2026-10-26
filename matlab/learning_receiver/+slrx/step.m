function data = step(cfg, key, calculate, plotKind)
%STEP 学习流程的公共保存/恢复工具；数学处理在传入的具名函数里。
% 示例：capture=slrx.step(cfg,'01_capture',@()slrx.readIQ(cfg),1)。
% 第一次实际执行calculate，保存data到同名MAT；以后resume直接回读。
% 小型JSON只包含data.summary，不把IQ/网格写成巨大JSON。
% 异常写到单独error.json并停止，不让后续步骤使用不存在的结果。

matFile = fullfile(cfg.run_dir,[key '.mat']);
if cfg.resume && exist(matFile,'file')
    stored = load(matFile,'data');
    data = stored.data;
    fprintf('回读 %s\n',key);
else
    fprintf('执行 %s\n',key);
    started = tic;
    try
        data = calculate();
        save(matFile,'data','-v7.3');
        summary = struct('key',key,'elapsed_s',toc(started),'mat_file',matFile, ...
            'owner','codex_baseline','metrics',data.summary);
        fid = fopen(fullfile(cfg.run_dir,[key '.json']),'w');
        assert(fid>=0);fprintf(fid,'%s',jsonencode(summary,'PrettyPrint',true));fclose(fid);
    catch ME
        error = struct('key',key,'identifier',ME.identifier,'message',ME.message,'stack',ME.stack);
        fid = fopen(fullfile(cfg.run_dir,[key '_error.json']),'w');
        if fid>=0,fprintf(fid,'%s',jsonencode(error));fclose(fid);end
        rethrow(ME);
    end
end
if cfg.make_plots
    slrx.drawStep(cfg,key,plotKind,data);
end
end
