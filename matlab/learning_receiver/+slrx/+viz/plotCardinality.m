function fig = plotCardinality(classes, cfg)
%PLOTCARDINALITY 候选评分是离散类别；选中K按每个OFDM符号显示台阶。
fig=slrx.viz.newFigure('点数候选：整帧得分、单符号柱形与分类台阶',cfg.show_figures);
layout=tiledlayout(fig,3,1,'TileSpacing','compact');
column=cfg.display_data_column;counts=classes.records{column}.candidate_cardinalities;
symbols=1:numel(classes.selected_cardinality);
ax=nexttile(layout);imagesc(ax,symbols,1:numel(counts),classes.scores);axis(ax,'xy');colorbar(ax);
yticks(ax,1:numel(counts));yticklabels(ax,string(counts));xlabel(ax,'数据OFDM符号编号');ylabel(ax,'候选点数K');
title(ax,'MSS得分热力图：每个格子对应一个候选和一个符号');
ax=nexttile(layout);bar(ax,1:numel(counts),classes.scores(:,column),'Tag','slrx-cardinality-scores');
xticks(ax,1:numel(counts));xticklabels(ax,string(counts));grid(ax,'on');xlabel(ax,'离散候选K');ylabel(ax,'MSS轮廓得分');
title(ax,sprintf('数据符号%d（FFT列%d）：不在候选K之间插值',column,column+1));
ax=nexttile(layout);stairs(ax,[symbols symbols(end)+1], ...
    [classes.selected_cardinality classes.selected_cardinality(end)],'LineWidth',1,'Tag','slrx-cardinality-steps');
grid(ax,'on');xlim(ax,[1 symbols(end)+1]);yticks(ax,counts);xlabel(ax,'数据符号区间 [m,m+1)');ylabel(ax,'选中K');
title(ax,'每个台阶只表示该符号的分类；末端延长1格仅供显示');
sgtitle(layout,'候选点数是模型估计；K=8可能为未处理复合模型，K不等于已验证商业MCS或位映射','FontSize',11);
end
