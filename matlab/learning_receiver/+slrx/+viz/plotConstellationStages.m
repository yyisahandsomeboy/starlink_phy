function [fig, view] = plotConstellationStages(context, options)
%PLOTCONSTELLATIONSTAGES 每行一个处理轮次，FFT/均衡/跟踪严格同资源比较。
view=slrx.diag.constellationData(context,options);
fig=slrx.viz.newFigure('同一资源的两轮星座处理对照',options.show_figures);
if ~isfield(options,'stage_indices'),options.stage_indices=1:6;end
indices=options.stage_indices;
if numel(indices)==1,layout=tiledlayout(fig,1,1,'TileSpacing','compact','Padding','compact');
else,layout=tiledlayout(fig,ceil(numel(indices)/3),min(3,numel(indices)),'TileSpacing','compact','Padding','compact');end
extent=1e-6;
for k=1:6
    z=view.stages(k).display_values;
    if ~isempty(z),extent=max(extent,max([abs(real(z(:)));abs(imag(z(:)))]));end
end
extent=extent*1.08;
traceContext=struct('cfg',context.cfg,'refs',context.refs);
frameRank=context.cfg.frame_rank;
for pass=1:2
    field=sprintf('time%d',pass);
    if isfield(context,field)
        traceContext.(field)=struct('sample_positions_nominal',context.(field).sample_positions_nominal);
    end
end
for k=indices
    ax=nexttile(layout);stage=view.stages(k);
    if ~stage.available
        axis(ax,'off');text(ax,.1,.5,sprintf('第%d轮：%s\n尚无检查点，未执行/不可用',stage.round,stage.name),'Interpreter','none');continue;
    end
    z=stage.display_values(view.display_flat_indices);
    h=plot(ax,real(z),imag(z),'.','MarkerSize',5);grid(ax,'on');axis(ax,'equal');
    xlim(ax,[-extent extent]);ylim(ax,[-extent extent]);
    xlabel(ax,'I（接收输出 / 显示除数）');ylabel(ax,'Q（接收输出 / 显示除数）');
    title(ax,sprintf('第%d轮 %s\n原RMS=%.5g；显示除数=%.5g', ...
        stage.round,stage.name,stage.raw_rms,stage.display_divisor));
    h.UserData=struct('round',stage.round,'stage',stage.source,'rows',view.display_rows, ...
        'columns',view.display_columns,'display_divisor',stage.display_divisor);
end
if numel(view.symbols)==1,symbolLabel=sprintf('%d',view.symbols);
else,symbolLabel=sprintf('%d..%d（%d列，可能混合几何）',view.symbols(1),view.symbols(end),numel(view.symbols));end
sgtitle(layout,sprintf(['帧rank=%d；数据符号%s；网格列=数据号+1；子载波=%d个\n' ...
    '频段[%.3g, %.3g]MHz；%s；每个可用阶段显示%d/%d点；不覆盖理想点；各面板同坐标'], ...
    context.cfg.frame_rank,symbolLabel,numel(view.rows),options.frequency_band_mhz, ...
    options.normalization,numel(view.display_flat_indices),view.total_selected_points),'FontSize',12);
mode=datacursormode(fig);mode.UpdateFcn=@cursorInfo;
fig.UserData=struct('diagnostic','constellation_stages','view',view);
    function lines=cursorInfo(~,event)
        data=event.Target.UserData;
        if ~isstruct(data)||~isfield(data,'rows'),lines={'非接收点对象'};return;end
        index=event.DataIndex;row=data.rows(index);column=data.columns(index);
        trace=slrx.diag.tracePoint(traceContext,data.round,column-1,row);
        lines={sprintf('帧rank=%d，第%d轮 %s',frameRank,data.round,data.stage), ...
            sprintf('数据符号%d；网格列%d',column-1,column), ...
            sprintf('FFT行%d；signed bin=%d；%.6g MHz',row,trace.signed_bin,trace.frequency_mhz), ...
            sprintf('显示除数=%.9g（仅显示）',data.display_divisor), ...
            sprintf('显示I=%.8g Q=%.8g',event.Position(1),event.Position(2)), ...
            sprintf('原复数I=%.8g Q=%.8g',event.Position(1)*data.display_divisor,event.Position(2)*data.display_divisor)};
        if trace.available
            lines{end+1}=sprintf('直接FFT有效区原文件坐标[%.9f, %.9f]',trace.raw_interval);
            lines{end+1}=sprintf('对应文件时间[%.9f, %.9f]ms',trace.capture_time_ms);
            lines{end+1}='这是1024点组合及插值支持，不是唯一ADC点';
        end
    end
end
