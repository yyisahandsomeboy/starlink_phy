function fig = plotGuard(context, options)
%PLOTGUARD 只显示模型预测区的真实IQ；不称为独立噪声边缘检测。
fig=slrx.viz.newFigure('帧末预测保护窗：幅度和功率',options.show_figures);
layout=tiledlayout(fig,2,1,'TileSpacing','compact');
if ~isfield(context,'guard'),ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'保护区步骤尚未执行');return;end
g=context.guard;cfg=context.cfg;
indices=g.sample_indices_capture(:);preCount=numel(g.preguard_samples);
if isempty(indices),ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'预测保护区没有落入保存窗口的整数样本');return;end
preIndices=indices(1)-preCount+(0:preCount-1)';
allIndices=[preIndices;indices];samples=[g.preguard_samples(:);g.samples(:)];
t=(allIndices-g.start_sample_capture)/cfg.capture_fs_hz*1e6;
ax=nexttile(layout);plot(ax,t,abs(samples));grid(ax,'on');hold(ax,'on');xline(ax,0,'r--','模型占用末端');
xline(ax,(g.end_sample_capture_exclusive-g.start_sample_capture)/cfg.capture_fs_hz*1e6,'k:','模型参考窗末端');
xlabel(ax,'相对模型占用末端 / us');ylabel(ax,'|原始IQ|');title(ax,'同一已保存采样窗；不是检测出的静默边缘');
ax=nexttile(layout);normalized=abs(samples).^2/max(g.preguard_mean_power,realmin);
plot(ax,t,10*log10(max(normalized,realmin)),'.','MarkerSize',4);hold(ax,'on');
plot(ax,t,10*log10(max(movmean(normalized,31),realmin)),'LineWidth',1.3);grid(ax,'on');
xline(ax,0,'r--');xlabel(ax,'相对模型占用末端 / us');ylabel(ax,'相对前窗均功率 / dB');
title(ax,sprintf('保护窗/前窗均功率=%.6g（%.3f dB）；窗口完整=%d',g.power_ratio,10*log10(max(g.power_ratio,realmin)),g.in_capture));
legend(ax,{'逐点功率','31点显示滑动平均','模型边界'},'Location','best');
sgtitle(layout,'边界来自750Hz时隙和最终SFO模型；其它信号可贡献能量，不据此认定丢帧或正确解码');
end
