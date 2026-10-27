function fig = plotConditionalModels(context, options, view)
%PLOTCONDITIONALMODELS 与无理想点版本分开；候选模型不冒称发射真值。
fig=slrx.viz.newFigure('条件几何判决：观测与候选模型',options.show_figures);
layout=tiledlayout(fig,1,2,'TileSpacing','compact');
for pass=1:2
    ax=nexttile(layout);field=sprintf('track%d',pass);
    if ~isfield(context,field)
        axis(ax,'off');text(ax,.1,.5,sprintf('第%d轮跟踪尚未执行',pass));continue;
    end
    stage=view.stages(pass*3);z=stage.display_values(view.display_flat_indices);
    plot(ax,real(z),imag(z),'.','DisplayName','实际接收观测');hold(ax,'on');
    item=context.(field);extent=max([abs(real(z(:)));abs(imag(z(:)));eps]);
    if ismember(options.carrier_mode,{'fit_pilots','eval_pilots'})
        p=context.refs.pilots(view.rows,view.grid_columns)/stage.display_divisor;
        plot(ax,real(p(:)),imag(p(:)),'ro','DisplayName','已知导频参考');
    else
        for j=1:numel(view.symbols)
            symbol=view.symbols(j);geometry=item.geometry_id(symbol);
            if geometry==0,continue;end
            p=item.gain_per_data_symbol(symbol)*context.refs.constellations{geometry}/stage.display_divisor;
            plot(ax,real(p),imag(p),'ro','HandleVisibility','off');
            extent=max(extent,max([abs(real(p(:)));abs(imag(p(:)))]));
        end
        plot(ax,NaN,NaN,'ro','DisplayName','当前列候选几何×估计增益（非真值）');
    end
    axis(ax,'equal');extent=extent*1.1;xlim(ax,[-extent extent]);ylim(ax,[-extent extent]);grid(ax,'on');
    xlabel(ax,'I / 显示除数');ylabel(ax,'Q / 显示除数');legend(ax,'Location','best');
    title(ax,sprintf('第%d轮；%d列；%d个子载波；显示除数%.5g',pass,numel(view.symbols),numel(view.rows),stage.display_divisor));
end
sgtitle(layout,'红圈来自候选几何和接收机增益；没有真实业务比特、商业MCS、FEC或CRC证明');
end
