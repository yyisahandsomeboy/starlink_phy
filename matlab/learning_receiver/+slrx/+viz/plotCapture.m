function [fig,info] = plotCapture(context,options)
%PLOTCAPTURE 默认先看统计量、PSD、功率和短采样；密集波形另存debug。
fig=slrx.viz.newFigure('输入IQ质量：统计量、能量、PSD与离散样本',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;
info=struct('available',isfield(context,'capture'),'raw_scatter_is_modulation_constellation',false,'raw_bin_reads',0);
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无输入检查点');return;end
d=context.capture;n=numel(d.iq);block=min(10000,n);count=floor(n/block);
power=mean(abs(reshape(d.iq(1:count*block),block,[])).^2,1);
raw=d.first_complex_sample+(0:count-1)*block+(block-1)/2;
ax=nexttile(layout);plot(ax,slrx.diag.coordinates('capture_to_ms',raw,cfg),10*log10(max(power,realmin)));hold(ax,'on');grid(ax,'on');
if isfield(context,'sync')
    for k=1:numel(context.sync.candidates),xline(ax,slrx.diag.coordinates('capture_to_ms',context.sync.candidates(k).start_sample_capture,cfg),':');end
    xline(ax,slrx.diag.coordinates('capture_to_ms',context.sync.selected.start_sample_capture,cfg),'g-','选中帧头');
end
xlabel(ax,'原文件时间 / ms');ylabel(ax,sprintf('%d点分箱平均功率 / dB',block));title(ax,'整窗能量与实际保存的候选位置；不是逐点波形');
ax=nexttile(layout);plot(ax,d.psd_frequency_hz/1e6,10*log10(max(d.psd_linear,realmin)));grid(ax,'on');
xlabel(ax,'基带频率 / MHz');ylabel(ax,'已保存Welch PSD / dB/Hz');title(ax,'检查频率占用和异常；PSD不证明业务解码');
first=min(2001,max(1,n-31));if isfield(context,'sync'),first=max(1,min(n,round(context.sync.selected.start_sample_capture-d.first_complex_sample+1)));end
v=slrx.diag.sampleView(context,first,32);info.sample_view=v;
ax=nexttile(layout);stem(ax,v.raw_time_ns,real(v.raw_values),'o','MarkerSize',4,'DisplayName','I','Tag','slrx-capture-I');hold(ax,'on');
stem(ax,v.raw_time_ns,imag(v.raw_values),'s','MarkerSize',4,'DisplayName','Q','Tag','slrx-capture-Q');grid(ax,'on');legend(ax,'Location','best');
xlabel(ax,'相对所示首个原采样 / ns');ylabel(ax,'归一化I/Q幅度（非V）');
title(ax,sprintf('%d个采样；间隔%.6gns；文件一基起点%.12g',numel(v.raw_indices),v.raw_spacing_ns,v.anchor_raw_sample));
ax=nexttile(layout);axis(ax,'off');text(ax,0,1,sprintf(['实际Fs=%.9g Hz；N=%d；时长N/Fs=%.9gms\n' ...
    'RMS=%.8g；截幅比例=%.8g\nDC均值=%.8g + j%.8g；|DC|=%.8g\n' ...
    '所示首点文件时间=%.9fms\n短采样用于识别幅度、零段和饱和，不是子载波星座。\n' ...
    '密集波形和原始时域散点仅在DebugPlots中另存。'],d.fs_hz,n,n/d.fs_hz*1e3,d.rms,d.clipped_fraction, ...
    real(d.dc),imag(d.dc),abs(d.dc),v.file_time_ms),'VerticalAlignment','top','FontSize',11);
info.raw_samples=v.raw_positions([1 end]).';info.time_ms=slrx.diag.coordinates('capture_to_ms',info.raw_samples,cfg);
info.rms=d.rms;info.clipped_fraction=d.clipped_fraction;info.dc=d.dc;
sgtitle(layout,'输入可观测性：功率、频谱、DC和截幅是质量检查，短采样不用于判定QAM或业务位','FontSize',12);
end
