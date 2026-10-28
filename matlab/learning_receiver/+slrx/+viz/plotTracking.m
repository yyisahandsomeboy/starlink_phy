function [fig,info] = plotTracking(context,options)
%PLOTTRACKING 读取原ML拟合、残差和内点标志；不重拟合或重分类。
fig=slrx.viz.newFigure('ML跟踪：观测、拟合、残差与可靠性',options.show_figures);fig.Position=[30 30 1450 1050];
layout=tiledlayout(fig,3,2,'TileSpacing','compact');info=struct('available',false,'rounds',struct([]));
for pass=1:2
    field=sprintf('track%d',pass);if ~isfield(context,field),continue;end
    d=context.(field);info.available=true;n=numel(d.ml_delay_samples);m=1:n;
    good=d.ml_inlier_mask&isfinite(d.ml_delay_samples)&isfinite(d.ml_phase_unwrapped_rad);bad=~good;
    fields={'ml_phase_unwrapped_rad','ml_delay_samples','ml_phase_residual_rad','ml_delay_residual_samples'};
    units={'相位 / rad','时延 / 模型采样','相位拟合残差 / rad','时延拟合残差 / 模型采样'};
    lines={'phase_line_rad','delay_line_samples','',''};
    for k=1:4
        ax=nexttile(layout,k);hold(ax,'on');v=d.(fields{k});
        plot(ax,m(good),v(good),'.','DisplayName',sprintf('第%d轮内点',pass));
        plot(ax,m(bad),v(bad),'x','DisplayName',sprintf('第%d轮非内点/异常',pass));
        if k<=2,plot(ax,m,d.(lines{k}),'DisplayName',sprintf('第%d轮已有拟合',pass));else,yline(ax,0,'k:','HandleVisibility','off');end
        grid(ax,'on');xlabel(ax,'数据符号编号');ylabel(ax,units{k});legend(ax,'Location','best','FontSize',8);
    end
    ax=nexttile(layout,5);hold(ax,'on');plot(ax,m,d.ml_negative_log_likelihood,'.','DisplayName',sprintf('第%d轮代价',pass));
    grid(ax,'on');xlabel(ax,'数据符号编号');ylabel(ax,'各轮自身ML代价');legend(ax,'Location','best');
    title(ax,'模型/噪声约定可变，跨轮代价不是独立质量分数','FontSize',10);
    item=struct('round',pass,'inlier_count',nnz(good),'noninlier_count',nnz(bad), ...
        'phase_inlier_rms_rad',rmsFinite(d.ml_phase_residual_rad(good)), ...
        'delay_inlier_rms_samples',rmsFinite(d.ml_delay_residual_samples(good)), ...
        'eval_evm',d.heldout_pilot_evm,'iterations_median',median(d.ml_iterations));
    if isempty(info.rounds),info.rounds=item;else,info.rounds(end+1)=item;end %#ok<AGROW>
end
ax=nexttile(layout,6);axis(ax,'off');textLines={'原ML内点掩码、拟合线和残差直接读取，未重新拟合。'};
for k=1:numel(info.rounds)
    d=info.rounds(k);textLines{end+1}=sprintf('第%d轮：内点%d / 非内点%d；相位RMS %.4g rad；时延RMS %.4g采样；EVAL %.4g%%', ...
        d.round,d.inlier_count,d.noninlier_count,d.phase_inlier_rms_rad,d.delay_inlier_rms_samples,100*d.eval_evm);
end
textLines=[textLines,{'小残差仅支持当前趋势模型；EVAL是留出导频，业务BER仍未知。', ...
    '时延、固定相位、CFO与SFO含义不同；不能将拟合线全部称作CFO。'}];
text(ax,0,1,strjoin(textLines,newline),'VerticalAlignment','top','FontSize',10,'Interpreter','none');
sgtitle(layout,'ML跟踪：将逐列估计、拟合和被排除点同时保留，结合独立EVAL判断接收质量','FontSize',12);
fig.UserData=struct('diagnostic','tracking','info',info);
end
function v=rmsFinite(x)
x=x(isfinite(x));if isempty(x),v=NaN;else,v=sqrt(mean(abs(x).^2));end
end
