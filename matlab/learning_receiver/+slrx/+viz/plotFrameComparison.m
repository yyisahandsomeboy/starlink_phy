function comparison = plotFrameComparison(records, out, options)
%PLOTFRAMECOMPARISON 选择所有帧共有的同一阶段，不能把不同阶段混为一组。
available=cell2mat(cellfun(@(r)[r.constellations.stages.available],records(:),'UniformOutput',false));
stage=find(all(available,1),1,'last');
comparison=struct('available',~isempty(stage),'stage_index',stage,'frame_count',numel(records), ...
    'policy','使用所有帧共有的同一处理阶段；同一个跨帧显示除数；几何筛选只代表模型假设');
if isempty(stage),return;end
views=cell(size(records));extent=eps;totalEnergy=0;totalPoints=0;
for k=1:numel(records)
    data=load(fullfile(out,sprintf('frame_%02d',k),'diagnostics_data.mat'),'view');views{k}=data.view;
    z=views{k}.stages(stage).raw_values;totalEnergy=totalEnergy+sum(abs(z).^2,'all');totalPoints=totalPoints+numel(z);
    extent=max(extent,max([abs(real(z(:)));abs(imag(z(:)))]));
end
factor=1;if strcmp(options.normalization,'common_rms'),factor=max(sqrt(totalEnergy/max(totalPoints,1)),eps);end
comparison.display_divisor=factor;
comparison.exact_resource_pairing=all(cellfun(@(v)isequal(v.rows,views{1}.rows)&&isequal(v.symbols,views{1}.symbols),views));
fig=slrx.viz.newFigure('多帧：同一处理阶段与同类资源',options.show_figures);
layout=tiledlayout(fig,ceil(numel(records)/3),min(3,numel(records)),'TileSpacing','compact');
for k=1:numel(records)
    ax=nexttile(layout);view=views{k};z=view.stages(stage).raw_values(view.display_flat_indices)/factor;
    plot(ax,real(z),imag(z),'.','MarkerSize',4);grid(ax,'on');axis(ax,'equal');
    xlim(ax,[-extent extent]*1.1/factor);ylim(ax,[-extent extent]*1.1/factor);
    xlabel(ax,'I / 跨帧共同显示除数');ylabel(ax,'Q / 跨帧共同显示除数');
    title(ax,sprintf('目录%d，帧rank=%d，阶段%s\n%d列×%d子载波；原RMS=%.5g',k,records{k}.frame_rank,view.stages(stage).source, ...
        numel(view.symbols),numel(view.rows),view.stages(stage).raw_rms));
end
sgtitle(layout,sprintf('跨帧显示除数=%.7g；资源一一配对=%d；候选几何同类不等于商业MCS已知',factor,comparison.exact_resource_pairing));
slrx.viz.saveFigure(fig,out,'multi_frame_constellations.png',options.show_figures);
fig=slrx.viz.newFigure('多帧留出导频阶段指标',options.show_figures);ax=axes(fig);E=NaN(numel(records),6);
for k=1:numel(records),E(k,:)=[records{k}.pilots.records.calibrated_evm];end
plot(ax,1:numel(records),100*E,'-o');grid(ax,'on');xlabel(ax,'输入运行目录编号');ylabel(ax,'SSS约定的留出导频EVM / %');
legend(ax,{'1 FFT','1 均衡','1 跟踪','2 FFT','2 均衡','2 跟踪'},'Location','best');
title(ax,'各阶段保持相同参考标定约定；缺失结果为NaN，不能当成0');
slrx.viz.saveFigure(fig,out,'multi_frame_metrics.png',options.show_figures);
end
