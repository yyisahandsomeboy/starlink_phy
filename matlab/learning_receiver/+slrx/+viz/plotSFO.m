function [fig, info] = plotSFO(context, options)
%PLOTSFO 直接使用实际取样坐标，分清时钟比例、固定起点与ML时延。
fig=slrx.viz.newFigure('SFO：实际采样位置与累积漂移',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;
info=struct('model_fs_hz',cfg.model_fs_hz,'rounds',struct('available',{},'sfo_ppm',{}, ...
    'sample_clock_ratio',{},'last_drift_model_samples',{},'last_drift_ns',{}), ...
    'interpretation','SFO为接收机等效时间尺度估计，不独立识别ADC时钟或Doppler');
ax=nexttile(layout);hold(ax,'on');
for pass=1:2
    field=sprintf('time%d',pass);item=struct('available',isfield(context,field),'sfo_ppm',NaN, ...
        'sample_clock_ratio',NaN,'last_drift_model_samples',NaN,'last_drift_ns',NaN);
    if item.available
        d=context.(field);ideal=d.sample_position_start+(0:numel(d.sample_positions_nominal)-1)';
        drift=d.sample_positions_nominal-ideal;
        display=unique(round(linspace(1,numel(drift),min(2000,numel(drift)))));
        plot(ax,(display-1)/cfg.model_fs_hz*1e3,drift(display),'DisplayName',sprintf('第%d轮',pass));
        item.sfo_ppm=d.sfo_ppm;item.sample_clock_ratio=1+d.sfo_ppm*1e-6;
        item.last_drift_model_samples=drift(end);item.last_drift_ns=drift(end)/cfg.model_fs_hz*1e9;
    end
    info.rounds(end+1)=item; %#ok<AGROW>
end
grid(ax,'on');xlabel(ax,'名义帧内时间 / ms');ylabel(ax,'实际位置 - 名义位置 / 模型采样');legend(ax,'Location','best');title(ax,'已有取样坐标的累积漂移；统一帧头锚点');
ax=nexttile(layout);
if isfield(context,'time1')&&isfield(context,'time2')
    delta=context.time2.sample_positions_nominal-context.time1.sample_positions_nominal;
    display=unique(round(linspace(1,numel(delta),min(2000,numel(delta)))));
    plot(ax,(display-1)/cfg.model_fs_hz*1e3,delta(display)/cfg.model_fs_hz*1e9);grid(ax,'on');
    xlabel(ax,'名义帧内时间 / ms');ylabel(ax,'第二轮 - 第一轮取样时刻 / ns');title(ax,'更新SFO改变时间坐标，不是只旋转星座');
else,axis(ax,'off');text(ax,.1,.5,'第二轮取样尚未生成，不能显示轮间漂移');end
ax=nexttile(layout);hold(ax,'on');
for pass=1:2
    field=sprintf('track%d',pass);
    if isfield(context,field)
        d=context.(field);plot(ax,1:cfg.data_column_count,d.ml_delay_samples,'.','DisplayName',sprintf('第%d轮逐列ML',pass));
        plot(ax,1:cfg.data_column_count,d.delay_line_samples,'LineWidth',1.3,'DisplayName',sprintf('第%d轮拟合',pass));
    end
end
grid(ax,'on');xlabel(ax,'数据OFDM符号编号');ylabel(ax,'残余时延 / 模型采样');legend(ax,'Location','best');title(ax,'等效时延估计，不是绝对传播时延');
ax=nexttile(layout);axis(ax,'off');lines={sprintf('名义模型Fs = %.6g Hz',cfg.model_fs_hz)};
for pass=1:2
    d=info.rounds(pass);
    if d.available,lines=[lines,{sprintf('第%d轮SFO=%.9f ppm；时钟比例=%.12f',pass,d.sfo_ppm,d.sample_clock_ratio), ...
            sprintf('帧末漂移=%.6f模型采样 = %.6f ns',d.last_drift_model_samples,d.last_drift_ns)}];end %#ok<AGROW>
end
lines=[lines,{'初始SFO来自CFO/中心频率的启发式换算。','固定起点偏移、时钟尺度、多径等效时延不能混为一谈。'}];
text(ax,0,1,strjoin(lines,newline),'VerticalAlignment','top','Interpreter','none');
sgtitle(layout,'SFO观察：所有漂移来自已保存sample_positions_nominal，不引入新的接收修正');
end
