function batchDir = RUN_MULTIPLE_FRAMES(frameCount, throughStep)
%RUN_MULTIPLE_FRAMES 学完一帧后，用同一套模块顺序检查多帧。
% 直接运行默认只取前2个独立检测合格帧，先做到第8步，避免一上来很耗时。
% RUN_MULTIPLE_FRAMES(3,14)可处理3帧完整链路，耗时相应增加。
% 每帧独立SSS估计，不自动开启旧接收机的跨帧共享信道假设。
% 每帧都建立独立目录，主脚本不复制；这里为易读重复读50ms而不引入缓存服务。

if nargin<1,frameCount=2;end
if nargin<2,throughStep=8;end
learningRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(learningRoot));
addpath(learningRoot);
stamp = char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'));
batchDir = fullfile(projectRoot,'runs',['codex-learning-batch-' stamp]);
mkdir(batchDir);
records = cell(1,frameCount);
for rank = 1:frameCount
    cfg = slrx.defaultConfig(projectRoot);
    cfg.read_duration_s = 0.05;
    cfg.frame_rank = rank;
    cfg.stop_after = throughStep;
    cfg.show_figures = false;
    cfg.run_dir = fullfile(batchDir,sprintf('frame_%02d',rank));
    slrx.runOne(cfg);
    records{rank} = slrx.validateRun(cfg.run_dir);
end
fid = fopen(fullfile(batchDir,'batch_validation.json'),'w');
assert(fid>=0);fprintf(fid,'%s',jsonencode(records,'PrettyPrint',true));fclose(fid);
fprintf('多帧学习结果：%s\n',batchDir);
end
