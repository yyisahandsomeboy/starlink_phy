function [fig,info] = plotResampling(context,options)
info=slrx.diag.resampleMetrics(context);cfg=context.cfg;
fig=slrx.viz.newFigure('重采样：时长、采样网格、PSD、FIR与DC',options.show_figures);fig.Position=[30 30 1600 1050];
layout=tiledlayout(fig,2,3,'TileSpacing','compact');
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无重采样检查点');return;end
ax=nexttile(layout);axis(ax,'off');text(ax,0,1,sprintf(['采样率 %.9g → %.9g MSps\n复采样数 %.0f → %.0f\n' ...
    '窗口时长N/Fs %.9g → %.9g ms\n比例p/q = %g/%g\n首末采样中心跨度为(N−1)/Fs，与N/Fs区别。\n原FIR与DC移除已经执行，此处只读诊断。'], ...
    info.input_fs_hz/1e6,info.output_fs_hz/1e6,info.input_count,info.output_count, ...
    info.input_duration_s*1e3,info.output_duration_s*1e3,info.ratio),'VerticalAlignment','top','FontSize',11);
for component=1:2
    ax=nexttile(layout);hold(ax,'on');
    if info.capture_available
        v=info.sample_view;if component==1,a=real(v.raw_values);b=real(v.model_values);name='I';else,a=imag(v.raw_values);b=imag(v.model_values);name='Q';end
        stem(ax,v.raw_time_ns,a,'o','MarkerSize',4,'DisplayName','原ADC');
        stem(ax,v.model_time_ns,b,'s','MarkerSize',4,'DisplayName','已重采样');grid(ax,'on');legend(ax,'Location','best');
        xlabel(ax,'同一原文件锚点的相对时间 / ns');ylabel(ax,[name ' / 归一化幅度']);
        title(ax,sprintf('同一时间区间的%s；%.5g / %.5g ns',name,v.raw_spacing_ns,v.model_spacing_ns));
    else,axis(ax,'off');text(ax,.1,.5,'未提供原capture，不能补造前后采样比较');end
end
ax=nexttile(layout);
if ~isempty(fieldnames(info.psd))
    p=info.psd;plot(ax,p.input_frequency_hz/1e6,10*log10(max(p.input,realmin)), ...
        p.output_frequency_hz/1e6,10*log10(max(p.output,realmin)));grid(ax,'on');legend(ax,{'原输入','已重采样'});
    xlabel(ax,'基带频率 / MHz');ylabel(ax,'Welch PSD / dB/Hz');title(ax,sprintf('只读PSD比较，匹配物理窗约%.6gms',p.duration_s*1e3));
else,axis(ax,'off');text(ax,.1,.5,'样本不足/缺原输入，PSD对照不可用');end
ax=nexttile(layout);plot(ax,info.filter.frequency_hz/1e6,20*log10(max(abs(info.filter.response),realmin)));grid(ax,'on');
xline(ax,cfg.model_fs_hz/2/1e6,'r:');xline(ax,cfg.capture_fs_hz/2/1e6,'k:');
xlabel(ax,'原FIR上采样时间轴对应频率 / MHz');ylabel(ax,'20log10(|H|/p) / dB');
title(ax,{'原抗混叠FIR：仅显示归一化，不重滤波',sprintf('Nyquist：红线输出%g MHz；黑线输入%g MHz',cfg.model_fs_hz/2/1e6,cfg.capture_fs_hz/2/1e6)});
ax=nexttile(layout);z=[info.input_dc info.before_dc_removal info.after_dc_removal];
bar(ax,1:3,1e6*[real(z(:)) imag(z(:))]);grid(ax,'on');
xticks(ax,1:3);xticklabels(ax,{'原输入','重采样/去DC前','去DC后'});legend(ax,{'均值I','均值Q'},'Location','best');
xlabel(ax,'同一处理链的均值观测');ylabel(ax,'均值分量 / 1e-6（归一化幅度）');
title(ax,sprintf('DC前/后模长 %.5g → %.5g',abs(info.before_dc_removal),abs(info.after_dc_removal)));
sgtitle(layout,'采样网格变化、滤波与DC移除分开观察；波形仍有波动不能单独证明重采样正确','FontSize',12);
fig.UserData=struct('diagnostic','resampling','info',info);
end
