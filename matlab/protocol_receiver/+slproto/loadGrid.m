function [grid,source] = loadGrid(runDir,frame)
%LOADGRID 只加载最终网格所在的单个检查点；拒绝整份九帧巨型result.mat回退。
if isfile(fullfile(runDir,'lesson_config.mat'))
    assert(frame==1,'slproto:FrameIndex','学习运行每目录只有一帧');file=fullfile(runDir,'13h_tracking.mat');
    digest=slrx.sha256(file);x=load(file,'data');grid=x.data.values;
else
    summary=jsondecode(fileread(fullfile(runDir,'result.json')));assert(frame>=1&&frame<=summary.frame_count);
    start=summary.estimates(frame).start_sample_capture;list=dir(fullfile(runDir,'frame_candidate_*.mat'));file='';
    for j=1:numel(list)
        p=fullfile(runDir,list(j).name);position=h5read(p,'/completed_frame/start_sample_capture');
        if abs(double(position)-start)<1e-6,assert(isempty(file),'slproto:AmbiguousFrame','同一起点出现多个检查点');file=p;end
    end
    assert(~isempty(file),'slproto:MissingCheckpoint','需要逐候选MAT，避免一次加载完整九帧数组');
    digest=slrx.sha256(file);x=load(file,'completed_frame');grid=x.completed_frame.grid_after;
end
assert(isequal(size(grid),[1024 301]));
source=struct('checkpoint',file,'sha256',digest,'frame_index',frame,'raw_BIN_reads',0);
end
