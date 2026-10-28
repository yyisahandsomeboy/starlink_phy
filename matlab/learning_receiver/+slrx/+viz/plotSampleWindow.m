function fig = plotSampleWindow(iq, fs, caption, visible)
%PLOTSAMPLEWINDOW 大范围连线帮助看趋势，局部32个采样分别显示I和Q。
fig=slrx.viz.newFigure(caption,visible);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');
n=min(5000,numel(iq));count=min(32,n);indices=1:count;
ax=nexttile(layout,[1 2]);plot(ax,(0:n-1)/fs*1e6,real(iq(1:n)), ...
    (0:n-1)/fs*1e6,imag(iq(1:n)));grid(ax,'on');
xlabel(ax,'窗口内时间 / us');ylabel(ax,'归一化IQ幅度');legend(ax,{'I','Q'});
title(ax,sprintf('前%d点概览：连线只作导视，不是模拟波形重建',n));
t=(indices-1)/fs*1e9;
ax=nexttile(layout);stem(ax,t,real(iq(indices)),'o','MarkerSize',4,'Tag','slrx-window-I');grid(ax,'on');
xlabel(ax,'相对窗口起点 / ns');ylabel(ax,'I');title(ax,sprintf('前%d个离散采样：实部',count));
ax=nexttile(layout);stem(ax,t,imag(iq(indices)),'s','MarkerSize',4,'Tag','slrx-window-Q');grid(ax,'on');
xlabel(ax,'相对窗口起点 / ns');ylabel(ax,'Q');title(ax,sprintf('前%d个离散采样：虚部',count));
sgtitle(layout,sprintf('%s；Fs=%.6gHz；采样间隔=%.6g ns',caption,fs,1e9/fs),'Interpreter','none');
end
