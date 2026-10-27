function [fig, info] = plotCFO(context, options)
%PLOTCFO 使用已知PSS/SSS去参考后的分块相位；不用未知数据angle斜率冒称CFO。
fig=slrx.viz.newFigure('CFO：已知参考相位与实际估计',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;
reference=[context.refs.pss;context.refs.sss];
info=struct('block_samples',64,'reference','known PSS+SSS', ...
    'phase_interpretation','分块相干去参考相位仍含信道/噪声；不把该曲线直接当CFO真值', ...
    'rounds',struct('available',{},'cfo_hz',{},'time_us',{},'phase_before_rad',{},'phase_after_rad',{}));
for pass=1:2
    ax=nexttile(layout);field=sprintf('time%d',pass);item=struct('available',isfield(context,field), ...
        'cfo_hz',NaN,'time_us',[],'phase_before_rad',[],'phase_after_rad',[]);
    if item.available
        d=context.(field);n=floor(numel(reference)/info.block_samples)*info.block_samples;
        ref=reference(1:n);before=d.time_raw(1:n).*conj(ref);after=d.time_cfo_compensated(1:n).*conj(ref);
        before=sum(reshape(before,info.block_samples,[]),1);after=sum(reshape(after,info.block_samples,[]),1);
        t=(d.sample_positions_nominal(1:n)-d.sample_position_start)/cfg.model_fs_hz*1e6;
        t=mean(reshape(t,info.block_samples,[]),1);
        item.cfo_hz=d.cfo_hz;item.time_us=t;
        item.phase_before_rad=unwrap(angle(before));item.phase_after_rad=unwrap(angle(after));
        plot(ax,t,item.phase_before_rad,'-o',t,item.phase_after_rad,'-s');grid(ax,'on');
        xlabel(ax,'帧内实际取样时间 / us');ylabel(ax,'已知同步序列分块参考相位 / rad');
        legend(ax,{'补偿前','按本轮CFO补偿后'},'Location','best');
        title(ax,sprintf('第%d轮：实际使用CFO %.6f Hz；64点相干分块',pass,d.cfo_hz));
    else,axis(ax,'off');text(ax,.1,.5,sprintf('第%d轮取帧未执行',pass));end
    info.rounds(end+1)=item; %#ok<AGROW>
end
ax=nexttile(layout);hold(ax,'on');
for pass=1:2
    field=sprintf('track%d',pass);
    if isfield(context,field),plot(ax,1:cfg.data_column_count,context.(field).phase_line_rad,'DisplayName',sprintf('第%d轮ML相位修正',pass));end
end
grid(ax,'on');xlabel(ax,'数据OFDM符号编号');ylabel(ax,'算法采用的残余相位修正量 / rad');legend(ax,'Location','best');
title(ax,'相位随符号变化：已有ML估计，不是未知IQ的直接相位');
ax=nexttile(layout);axis(ax,'off');textLines={'CFO来自同步/ML估计，未拆分卫星Doppler和本振误差。'};
if isfield(context,'sync'),textLines{end+1}=sprintf('粗CFO = %.9f Hz',context.sync.selected.coarse_cfo_hz);end
if isfield(context,'offsets')
    d=context.offsets;
    textLines=[textLines,{sprintf('第一轮ML残余CFO = %.9f Hz',d.residual_cfo_hz), ...
        sprintf('第二轮使用总CFO = %.9f Hz',d.cfo_hz)}];
    info.coarse_cfo_hz=context.sync.selected.coarse_cfo_hz;
    info.ml_residual_cfo_hz=d.residual_cfo_hz;info.second_round_cfo_hz=d.cfo_hz;
end
textLines=[textLines,{'补偿：z_corr = z × exp(-j 2π CFO t)', ...
    '参考相位仍受信道、噪声和分块平均影响。','留出导频EVM请与同轮FFT/均衡/跟踪图配合判断。'}];
text(ax,0,1,strjoin(textLines,newline),'VerticalAlignment','top','Interpreter','none','FontSize',11);
sgtitle(layout,'CFO观察：已知同步参考的补偿前后对照；不改接收机，不以未知数据相位估频偏');
end
