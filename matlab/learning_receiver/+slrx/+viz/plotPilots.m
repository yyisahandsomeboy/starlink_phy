function figures = plotPilots(context, options, metrics)
%PLOTPILOTS EVAL独立观测；原单位与SSS标定单位同时保留，不以硬判决作真值。
cfg=context.cfg;records=metrics.records;labels={'1 FFT','1 均衡','1 跟踪','2 FFT','2 均衡','2 跟踪'};
figures=gobjects(1,3);
figures(1)=slrx.viz.newFigure('留出导频EVM：单位、阶段和逐列比较',options.show_figures);
layout=tiledlayout(figures(1),2,2,'TileSpacing','compact');
ax=nexttile(layout);bar(ax,100*[records.raw_evm]);xticks(ax,1:6);xticklabels(ax,labels);ylabel(ax,'EVM / %');grid(ax,'on');title(ax,'未经额外标定的接收输出：增益约定会影响跨阶段比较');
ax=nexttile(layout);bar(ax,100*[records.calibrated_evm]);xticks(ax,1:6);xticklabels(ax,labels);ylabel(ax,'EVM / %');grid(ax,'on');title(ax,'FFT仅用SSS整体复增益标定；均衡/跟踪不另拟合');
for pass=1:2
    ax=nexttile(layout);hold(ax,'on');found=false;
    for j=1:3
        k=(pass-1)*3+j;
        if records(k).available,plot(ax,1:cfg.data_column_count,100*records(k).per_symbol_evm,'DisplayName',labels{k});found=true;end
    end
    grid(ax,'on');xlabel(ax,'数据OFDM符号编号（网格列=编号+1）');ylabel(ax,'SSS约定下的留出导频EVM / %');
    if found,legend(ax,'Location','best');end
    title(ax,sprintf('第%d轮内部比较；允许某些列变差，不据图强改算法',pass));
end
sgtitle(layout,'EVM=sqrt(sum|Z-P|^2/sum|P|^2)；EVAL不参与标定；未知业务BER/SER不能由EVM代替','FontSize',11);

figures(2)=slrx.viz.newFigure('留出导频复数点云：已知参考不是候选载荷',options.show_figures);
layout=tiledlayout(figures(2),2,3,'TileSpacing','compact');extent=.5;
for k=1:6,if records(k).available,extent=max(extent,max(abs(records(k).derotated-1),[],'all')*1.05);end;end
for k=1:6
    ax=nexttile(layout);
    if ~records(k).available,axis(ax,'off');text(ax,.1,.5,'该阶段尚未执行');continue;end
    z=records(k).derotated;
    plot(ax,real(z(:)),imag(z(:)),'.','MarkerSize',4);hold(ax,'on');plot(ax,1,0,'rx','MarkerSize',11,'LineWidth',2);axis(ax,'equal');
    xlim(ax,[1-extent 1+extent]);ylim(ax,[-extent extent]);grid(ax,'on');xlabel(ax,'Re((Z/标定除数)/P)');ylabel(ax,'Im((Z/标定除数)/P)');
    title(ax,sprintf('%s；EVM %.3f%%',labels{k},100*records(k).calibrated_evm));
end
sgtitle(layout,'相同8条EVAL导频；参考去旋转后目标(1,0)；FFT的SSS标定仅供诊断，参数另存','FontSize',11);

figures(3)=slrx.viz.newFigure('留出导频：误差位置与残余相位',options.show_figures);
layout=tiledlayout(figures(3),2,2,'TileSpacing','compact');
for pass=1:2
    k=pass*3;ax=nexttile(layout);
    if records(k).available
        imagesc(ax,1:cfg.data_column_count,1:numel(metrics.eval_rows),records(k).error);axis(ax,'xy');colorbar(ax);
        yticks(ax,1:numel(metrics.eval_rows));yticklabels(ax,compose('row%d / k%d',metrics.eval_rows(:),context.refs.frequency_bins(metrics.eval_rows)));
        xlabel(ax,'数据OFDM符号编号');ylabel(ax,'EVAL资源（原MATLAB行 / signed bin）');title(ax,sprintf('第%d轮跟踪后 |Z-P|',pass));
    else,axis(ax,'off');text(ax,.1,.5,'该轮最终跟踪未执行');end
end
for pass=1:2
    ax=nexttile(layout);hold(ax,'on');found=false;
    positive=context.refs.frequency_bins(metrics.eval_rows)>0;
    for j=2:3
        k=(pass-1)*3+j;
        if ~records(k).available,continue;end
        z=records(k).derotated;
        plot(ax,1:cfg.data_column_count,angle(mean(z(positive,:),1))*180/pi,'DisplayName',[labels{k} ' 正频带']);
        plot(ax,1:cfg.data_column_count,angle(mean(z(~positive,:),1))*180/pi,'--','DisplayName',[labels{k} ' 负频带']);found=true;
    end
    grid(ax,'on');xlabel(ax,'数据OFDM符号编号');ylabel(ax,'已知导频平均残余相位 / 度（主值）');
    if found,legend(ax,'Location','best');end
    title(ax,sprintf('第%d轮均衡/跟踪：正负频率分开观察',pass));
end
sgtitle(layout,'留出参考验证与FIT初值分开；图中是实际误差，不能宣称商业位映射或CRC已通过','FontSize',11);
end
