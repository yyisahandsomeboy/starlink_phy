function [fig, info] = plotCapture(context, options)
%PLOTCAPTURE 从已经读入的capture MAT观察输入，不重复读取BIN。
fig=slrx.viz.newFigure('输入IQ：时间、频谱与非调制星座散点',options.show_figures);
fig.Position(4)=1100;
layout=tiledlayout(fig,3,2,'TileSpacing','compact');cfg=context.cfg;
info=struct('available',isfield(context,'capture'),'raw_scatter_is_modulation_constellation',false,'raw_bin_reads',0);
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无01_capture.mat');return;end
capture=context.capture;n=numel(capture.iq);block=min(10000,n);count=floor(n/block);
power=mean(abs(reshape(capture.iq(1:count*block),block,[])).^2,1);
rawCenters=capture.first_complex_sample+(0:count-1)*block+(block-1)/2;
ax=nexttile(layout);plot(ax,slrx.diag.coordinates('capture_to_ms',rawCenters,cfg),10*log10(max(power,realmin)));grid(ax,'on');hold(ax,'on');
if isfield(context,'sync')
    for k=1:numel(context.sync.candidates)
        raw=context.sync.candidates(k).start_sample_capture;
        xline(ax,slrx.diag.coordinates('capture_to_ms',raw,cfg),':');
    end
    xline(ax,slrx.diag.coordinates('capture_to_ms',context.sync.selected.start_sample_capture,cfg),'g-','选中帧头');
end
xlabel(ax,'原始文件时间 / ms');ylabel(ax,sprintf('%d点分箱平均 |IQ|^2 / dB',block));title(ax,'分析窗口能量与保存的候选帧头');
ax=nexttile(layout);plot(ax,capture.psd_frequency_hz/1e6,10*log10(capture.psd_linear));grid(ax,'on');
xlabel(ax,'相对采集中心的基带频率 / MHz');ylabel(ax,'PSD / dB/Hz（归一化IQ）');title(ax,'已保存的Welch PSD：不重新计算，也不证明星座正确');
first=1;
if isfield(context,'sync'),first=max(1,round(context.sync.selected.start_sample_capture-capture.first_complex_sample+1));end
indices=first:min(n,first+4095);raw=capture.first_complex_sample+indices-1;
ax=nexttile(layout);plot(ax,slrx.diag.coordinates('capture_to_ms',raw,cfg),real(capture.iq(indices)), ...
    slrx.diag.coordinates('capture_to_ms',raw,cfg),imag(capture.iq(indices)));grid(ax,'on');
xlabel(ax,'原始文件时间 / ms');ylabel(ax,'归一化IQ幅度（非电压标定）');legend(ax,{'I','Q'});title(ax,'帧头附近I/Q概览：连线仅导视；采样细节见下排');
ax=nexttile(layout);plot(ax,real(capture.iq(indices)),imag(capture.iq(indices)),'.');axis(ax,'equal');grid(ax,'on');
xlabel(ax,'I：原始时域实部');ylabel(ax,'Q：原始时域虚部');title(ax,'原始时域IQ散点图（非子载波调制星座）');
view=slrx.diag.sampleView(context,first,32);info.sample_view=view;
ax=nexttile(layout);stem(ax,view.raw_time_ns,real(view.raw_values),'o','MarkerSize',4,'DisplayName','原始I','Tag','slrx-capture-I');hold(ax,'on');
stem(ax,view.raw_time_ns,imag(view.raw_values),'s','MarkerSize',4,'DisplayName','原始Q','Tag','slrx-capture-Q');grid(ax,'on');
xlabel(ax,'相对首个显示原采样 / ns');ylabel(ax,'原始I/Q幅度');legend(ax,'Location','best');
title(ax,sprintf('%d个原始复采样；间隔 %.6g ns；文件位置%.12g起',numel(view.raw_indices),view.raw_spacing_ns,view.anchor_raw_sample));
ax=nexttile(layout);
stem(ax,view.raw_time_ns,real(view.raw_values),'o','MarkerSize',4,'DisplayName','原ADC的I','Tag','slrx-sampling-raw');hold(ax,'on');
if view.model_available&&~isempty(view.model_indices)
    stem(ax,view.model_time_ns,real(view.model_values),'s','MarkerSize',4,'DisplayName','重采样后的I','Tag','slrx-sampling-model');
    title(ax,sprintf('同一时间轴：原%d点/模型%d点；%.6g / %.6g ns', ...
        numel(view.raw_indices),numel(view.model_indices),view.raw_spacing_ns,view.model_spacing_ns));
elseif view.model_available,title(ax,'该时间窗内没有已保存的模型采样，不补造点');
else,title(ax,'尚无重采样检查点：只显示已有原采样，不补造模型点');end
grid(ax,'on');xlabel(ax,'同一原文件时间基准的相对时间 / ns');ylabel(ax,'I幅度（含既有FIR/DC处理差异）');legend(ax,'Location','best');
info.raw_samples=[raw(1) raw(end)];info.time_ms=slrx.diag.coordinates('capture_to_ms',info.raw_samples,cfg);
info.rms=capture.rms;info.clipped_fraction=capture.clipped_fraction;info.dc=capture.dc;
sgtitle(layout,sprintf('输入%d份复采样；Fs=%.6gHz；RMS=%.6g；截幅比例=%.3g；I/Q不能直接读成业务位',n,capture.fs_hz,capture.rms,capture.clipped_fraction));
end
