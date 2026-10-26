function cfg = beginLesson(cfg)
%BEGINLESSON 创建/恢复一次学习目录，保存固定配置和源码快照。
% 不覆盖旧接收结果。恢复时DSP参数和学习代码必须与本次起点一致。
% 可改变stop_after、是否显示/画图及显示列，这些选项不改变数值处理。
% 若想修改算法或DSP参数，请清空cfg.run_dir建立新目录，保留旧记录比较。

assert(strcmp(cfg.channel_mode,'frame_local'),'当前学习入口仅支持frame_local；共享信道属于原多帧参考模式');
if isempty(cfg.run_dir)
    stamp = char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'));
    cfg.run_dir = fullfile(cfg.project_root,'runs',['codex-learning-' stamp]);
end
if ~exist(cfg.run_dir,'dir'), mkdir(cfg.run_dir); end
learningRoot = fullfile(cfg.project_root,'matlab','learning_receiver');
files = dir(fullfile(learningRoot,'**','*.m'));
code = struct('path',{},'sha256',{});
for k = 1:numel(files)
    source = fullfile(files(k).folder,files(k).name);
    code(k).path = erase(source,[learningRoot filesep]);
    code(k).sha256 = slrx.sha256(source);
end
configFile = fullfile(cfg.run_dir,'lesson_config.mat');
ignored = {'run_dir','stop_after','resume','show_figures','make_plots','display_data_column'};
if exist(configFile,'file')
    saved = load(configFile,'frozenConfig','code');
    assert(isequaln(rmfield(cfg,ignored),rmfield(saved.frozenConfig,ignored)), ...
        'DSP参数已变化，请使用新学习目录，避免混合旧中间变量');
    assert(isequaln(code,saved.code),'学习代码已变化，请新建学习目录；旧MAT仍可直接读取');
else
    frozenConfig = cfg;
    save(configFile,'frozenConfig','code');
    for k = 1:numel(code)
        source = fullfile(learningRoot,code(k).path);
        target = fullfile(cfg.run_dir,'source_code',code(k).path);
        parent = fileparts(target);
        if ~exist(parent,'dir'),mkdir(parent);end
        copyfile(source,target);
    end
    fid = fopen(fullfile(cfg.run_dir,'lesson_config.json'),'w');
    assert(fid>=0);fprintf(fid,'%s',jsonencode(cfg,'PrettyPrint',true));fclose(fid);
    record = struct('role','codex_baseline','version',cfg.version,'code',code, ...
        'input_sha256',slrx.sha256(cfg.input_file),'original_evaluator_lock_sha256', ...
        slrx.sha256(fullfile(cfg.project_root,'config','evaluator_lock.json')), ...
        'author_TOAs_used_for_detection',false,'online_model_calls',0);
    fid = fopen(fullfile(cfg.run_dir,'lesson_lock.json'),'w');
    assert(fid>=0);fprintf(fid,'%s',jsonencode(record,'PrettyPrint',true));fclose(fid);
end
fprintf('学习目录：%s\n',cfg.run_dir);
end
