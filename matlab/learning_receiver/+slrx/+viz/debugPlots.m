function names = debugPlots(context,options,folder)
%DEBUGPLOTS 旧密集时域图仅显式debug时生成，独立目录且不混作默认证据。
names={};
if ~isfield(options,'debug_plots')||~options.debug_plots,return;end
folder=fullfile(folder,'debug');if ~isfolder(folder),mkdir(folder);end
if isfield(context,'capture')
    d=context.capture;fig=slrx.viz.newFigure('调试：密集输入波形与原始时域散点',false);
    layout=tiledlayout(fig,1,2);ax=nexttile(layout);n=min(4096,numel(d.iq));
    plot(ax,(0:n-1)/d.fs_hz*1e6,real(d.iq(1:n)),(0:n-1)/d.fs_hz*1e6,imag(d.iq(1:n)));
    xlabel(ax,'窗口起点时间 / us');ylabel(ax,'归一化I/Q');title(ax,'调试概览：不用于判断CFO正确');
    ax=nexttile(layout);plot(ax,real(d.iq(1:n)),imag(d.iq(1:n)),'.');axis(ax,'equal');
    xlabel(ax,'I');ylabel(ax,'Q');title(ax,'原始时域IQ散点图（非子载波调制星座）');
    slrx.viz.saveFigure(fig,folder,'capture_dense.png',false);names{end+1}='debug/capture_dense.png';
end
for pass=1:2
    field=sprintf('time%d',pass);if ~isfield(context,field),continue;end
    d=context.(field);fig=slrx.viz.newFigure('调试：帧首密集I分量叠加',false);ax=axes(fig);n=min(2112,numel(d.time_raw));
    t=(d.sample_positions_nominal(1:n)-d.sample_position_start)/context.cfg.model_fs_hz*1e6;
    plot(ax,t,real(d.time_raw(1:n)),t,real(d.time_cfo_compensated(1:n)));legend(ax,{'补偿前I','补偿后I'});
    xlabel(ax,'实际帧内时间 / us');ylabel(ax,'I / 归一化幅度');title(ax,'仅调试：实部变化不能证明频偏估计正确');
    name=sprintf('cfo_dense_round%d.png',pass);slrx.viz.saveFigure(fig,folder,name,false);names{end+1}=['debug/' name];
end
end
