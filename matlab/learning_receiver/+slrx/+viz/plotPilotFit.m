function fig = plotPilotFit(data,cfg)
%PLOTPILOTFIT FIT初始化的相位/时延及预览残差，不冒充留出验证。
fig=slrx.viz.newFigure('FIT导频初始化：相位、时延与预览残差',cfg.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');m=1:numel(data.raw_phase_rad);
observed={data.raw_phase_rad,data.raw_delay_samples};fitted={data.line_phase_rad,data.line_delay_samples};
labels={'相位 / rad','时延 / 模型采样'};
for k=1:2
    ax=nexttile(layout,k);plot(ax,m,observed{k},'.',m,fitted{k},'-');grid(ax,'on');
    xlabel(ax,'数据符号编号');ylabel(ax,labels{k});legend(ax,{'FIT逐列初值','已有线性预览'});
    ax=nexttile(layout,k+2);plot(ax,m,observed{k}-fitted{k},'.');grid(ax,'on');yline(ax,0,'k:');
    xlabel(ax,'数据符号编号');ylabel(ax,['相对预览残差：' labels{k}]);
end
sgtitle(layout,sprintf('FIT参与初值估计；预览FIT EVM %.4g%% 不是独立EVAL，ML仍使用raw初值',100*data.fit_evm),'FontSize',11);
end
