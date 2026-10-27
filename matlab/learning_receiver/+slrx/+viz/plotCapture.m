function [fig, info] = plotCapture(context, options)
%PLOTCAPTURE 从已经读入的capture MAT观察输入，不重复读取BIN。
fig=slrx.viz.newFigure('输入IQ：时间、频谱与非调制星座散点',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;
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
xlabel(ax,'原始文件时间 / ms');ylabel(ax,'归一化IQ幅度（非电压标定）');legend(ax,{'I','Q'});title(ax,'所选帧头附近的实际I/Q；缺少同步时使用窗口起点');
ax=nexttile(layout);plot(ax,real(capture.iq(indices)),imag(capture.iq(indices)),'.');axis(ax,'equal');grid(ax,'on');
xlabel(ax,'I：原始时域实部');ylabel(ax,'Q：原始时域虚部');title(ax,'原始时域IQ散点图（非子载波调制星座）');
info.raw_samples=[raw(1) raw(end)];info.time_ms=slrx.diag.coordinates('capture_to_ms',info.raw_samples,cfg);
info.rms=capture.rms;info.clipped_fraction=capture.clipped_fraction;info.dc=capture.dc;
sgtitle(layout,sprintf('输入%d份复采样；Fs=%.6gHz；RMS=%.6g；截幅比例=%.3g；I/Q不能直接读成业务位',n,capture.fs_hz,capture.rms,capture.clipped_fraction));
end
