function [fig, model] = plotLocalSync(sync, cfg, visible)
%PLOTLOCALSYNC 三条实际保存的局部曲线，0只表示相对已检出帧头的偏移。
if nargin<3,visible=cfg.show_figures;end
model=slrx.diag.syncSummary(sync,cfg,cfg.run_dir);s=model.selected;
curve=sync.selected.sync_local_curve;
fig=slrx.viz.newFigure('精细同步：局部零点与全局坐标',visible);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');
ax=nexttile(layout,[1 2]);
stem(ax,curve.lag_model_samples,curve.pss,'o','LineWidth',1,'MarkerSize',5,'DisplayName','PSS','Tag','slrx-local-pss');hold(ax,'on');
stem(ax,curve.lag_model_samples,curve.sss,'s','LineWidth',1,'MarkerSize',5,'DisplayName','SSS');
stem(ax,curve.lag_model_samples,curve.coherent_pss_sss,'^','LineWidth',1,'MarkerSize',5,'DisplayName','联合PSS+SSS');
xline(ax,0,'k:','当前选定帧头','HandleVisibility','off');ylim(ax,[0 1.05]);grid(ax,'on');
xticks(ax,curve.lag_model_samples);xlabel(ax,'Δn = n − n₀（整数模型采样偏移）');ylabel(ax,'归一化相关幅度（非相关功率）');
legend(ax,'Location','best');
title(ax,'每根茎对应一个已计算偏移；局部0是选中帧头，不插值峰间分数');
axInfo=nexttile(layout);axis(axInfo,'off');
text(axInfo,0,1,sprintf(['模型Fs = %.6g Hz\n模型帧头 n_0 = %.12g\n原文件一基坐标 = %.12g\n' ...
    '最近原整数点 = %.0f；含小数位置 = %d\n采集时间 = %.9f ms'], ...
    cfg.model_fs_hz,s.model_sample,s.raw_sample,s.nearest_raw_integer,s.has_fractional_raw_position,s.time_ms), ...
    'VerticalAlignment','top','Interpreter','none','FontSize',12);
axInfo2=nexttile(layout);axis(axInfo2,'off');
text(axInfo2,0,1,sprintf(['PSS = %.9f\nSSS = %.9f\n联合 = %.9f\n粗CFO = %.6f Hz\n' ...
    '选择规则：第%d个时间排序后SSS合格候选\n局部0仅是相对选中帧头的偏移'], ...
    s.pss_score,s.sss_score,s.joint_score,s.coarse_cfo_hz,cfg.frame_rank), ...
    'VerticalAlignment','top','Interpreter','none','FontSize',12);
fig.UserData=struct('diagnostic','local_sync','model',model,'local_axes',ax);
end
