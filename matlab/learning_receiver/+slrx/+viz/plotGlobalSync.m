function [fig, model] = plotGlobalSync(sync, cfg, visible)
%PLOTGLOBALSYNC 抽取轨迹与精确事件分层显示，避免把精细位置当粗峰坐标。
if nargin<3, visible=cfg.show_figures; end
model=slrx.diag.syncSummary(sync,cfg,cfg.run_dir);
fig=slrx.viz.newFigure('全局PSS搜索：轨迹与精确候选位置',visible);
layout=tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
layout.OuterPosition=[0 .05 1 .90];
ax1=nexttile(layout); lineTrace=plot(ax1,1,1,'LineWidth',1);hold(ax1,'on');grid(ax1,'on');
ylabel(ax1,'PSS片段非相干粗搜索分数');
if isfinite(model.coarse_threshold)
    yline(ax1,model.coarse_threshold,'k--',sprintf('原算法粗门限 %.3g',model.coarse_threshold));
end
ax2=nexttile(layout);hold(ax2,'on');grid(ax2,'on');
yticks(ax2,[1 2 3]);yticklabels(ax2,{'已拒绝','已接受候选','最终选中'});ylim(ax2,[.5 3.5]);
ylabel(ax2,'精细帧头事件（纵轴不是相关分数）');
events=gobjects(1,numel(model.candidates));
for k=1:numel(events)
    item=model.candidates(k); y=2;color=[.1 .5 .65];
    if strcmp(item.status,'rejected'),y=1;color=[.7 .35 .2];end
    if item.selected,y=3;color=[.1 .6 .25];end
    events(k)=plot(ax2,1,y,'o','MarkerFaceColor',color,'Color',color,'MarkerSize',7);
    events(k).UserData=item;
end
selected1=xline(ax1,1,'g-','精细选定帧头','LineWidth',1.4);
selected2=xline(ax2,1,'g-','LineWidth',1.4);
menu=uicontrol(fig,'Style','popupmenu','Units','normalized','Position',[.04 .955 .48 .03], ...
    'String',{'原始文件时间/ms','原文件一基复采样','模型窗口内一基复采样'}, ...
    'Tag','slrx-global-coordinate','Callback',@changeAxis);
uicontrol(fig,'Style','text','Units','normalized','Position',[.53 .955 .45 .035], ...
    'String',sprintf('轨迹每%d点取1点；事件标线来自精确候选',model.trace_decimation),'BackgroundColor','w');
fig.UserData=struct('diagnostic','global_sync','model',model,'axes',[ax1 ax2],'trace',lineTrace);
cursor=datacursormode(fig);cursor.UpdateFcn=@eventInfo;
changeAxis(menu,[]);
    function changeAxis(control,~)
        modes={'model_to_ms','model_to_capture','identity'};
        labels={'原始采集文件时间 / ms（文件第1份复采样为t=0）', ...
            '原始文件一基复采样坐标（不是I/Q分量编号）',sprintf('%.6g MSps模型分析窗口内一基复采样坐标',cfg.model_fs_hz/1e6)};
        choice=control.Value;
        if choice==3
            x=sync.scan.score_sample_nominal;
            convert=@(v)v;
        else
            convert=@(v)slrx.diag.coordinates(modes{choice},v,cfg);
            x=convert(sync.scan.score_sample_nominal);
        end
        lineTrace.XData=x;lineTrace.YData=sync.scan.score_decimated;
        for j=1:numel(events),events(j).XData=convert(model.candidates(j).model_sample);end
        selected1.Value=convert(sync.selected.start_sample_nominal);
        selected2.Value=selected1.Value;
        if numel(x)>1,xlim(ax1,[x(1) x(end)]);xlim(ax2,[x(1) x(end)]);end
        xlabel(ax1,labels{choice});xlabel(ax2,labels{choice});
        title(ax1,sprintf('抽取的全局粗搜索轨迹；不能把抽取最大值当完整分辨率最大值（步长%d）',model.trace_decimation));
        title(ax2,'保存的精确候选帧头；算法未记录粗峰原始位置，不能把事件点冒称粗峰最大值');
        state=fig.UserData;state.coordinate_mode=choice;fig.UserData=state;
    end
    function lines=eventInfo(~,event)
        item=event.Target.UserData;
        if isstruct(item)&&isfield(item,'candidate_id')
            lines={item.candidate_id,item.status,sprintf('raw=%.12g model=%.12g t=%.9fms',item.raw_sample,item.model_sample,item.time_ms), ...
                sprintf('PSS %.6f SSS %.6f joint %.6f',item.pss_score,item.sss_score,item.joint_score), ...
                sprintf('CFO %.6fHz',item.cfo_hz),item.reason};
        else,lines={sprintf('显示坐标=%.12g；抽取粗分数=%.6g',event.Position(1),event.Position(2)), ...
                '抽取轨迹点，不保证是完整分辨率峰值'};end
    end
end
