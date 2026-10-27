function [fig, info] = plotOFDM(context, options)
%PLOTOFDM 同一数据符号的1056点分解与1024点FFT；不重复解调。
fig=slrx.viz.newFigure('单个OFDM符号：CP、有效区与FFT',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;symbol=options.symbols(1);column=symbol+1;
pass=1;if isfield(context,'time2'),pass=2;end
timeField=sprintf('time%d',pass);ofdmField=sprintf('ofdm%d',pass);fftField=sprintf('fft%d',pass);
info=struct('round',pass,'data_symbol',symbol,'grid_column',column,'cp_length',cfg.cp_length, ...
    'nfft',cfg.nfft,'symbol_length',cfg.cp_length+cfg.nfft,'available',isfield(context,timeField));
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无取帧检查点');return;end
d=context.(timeField);L=cfg.cp_length+cfg.nfft;block=reshape(d.time_cfo_compensated,L,cfg.frame_symbol_count);
z=block(:,column+1);ax=nexttile(layout);plot(ax,0:L-1,real(z),0:L-1,imag(z));hold(ax,'on');grid(ax,'on');
xline(ax,cfg.cp_length-.5,'r--','CP/有效区');xline(ax,L-cfg.cp_length-.5,'k:','有效区末尾复制段');
xlabel(ax,'本符号内零基采样编号');ylabel(ax,'CFO补偿后I/Q幅度');legend(ax,{'I','Q','CP结束','复制段开始'},'Location','best');
title(ax,sprintf('带CP：%d=%d+%d；前%d点为CP',L,cfg.cp_length,cfg.nfft,cfg.cp_length));
ax=nexttile(layout);valid=z(cfg.cp_length+1:end);plot(ax,0:cfg.nfft-1,real(valid),0:cfg.nfft-1,imag(valid));grid(ax,'on');
xlabel(ax,'有效区零基时间采样编号');ylabel(ax,'有效区I/Q幅度');title(ax,sprintf('去CP后%d份复采样，尚不是%d个独立星座点',cfg.nfft,cfg.nfft));
if isfield(context,ofdmField),assert(isequal(valid,context.(ofdmField).without_cp(:,column)),'slrx:DiagnosticCP','时域重排与保存结果不符');end
ax=nexttile(layout);
if isfield(context,fftField)
    gridValue=context.(fftField).values(:,column);[bins,order]=sort(context.refs.frequency_bins);
    plot(ax,slrx.diag.coordinates('bin_to_mhz',bins,cfg),abs(gridValue(order)));grid(ax,'on');
    xlabel(ax,'有符号子载波对应基带频率 / MHz');ylabel(ax,'|FFT(x)/sqrt(N)|');title(ax,'相同有效区的已保存FFT；频率排序仅用于显示');
else,axis(ax,'off');text(ax,.1,.5,'FFT尚未执行');end
ax=nexttile(layout);axis(ax,'off');
trace=slrx.diag.tracePoint(context,pass,symbol,context.refs.payload_rows(1));
text(ax,0,1,sprintf(['第%d轮，数据OFDM符号%d，FFT网格列%d\nCP=%d，FFT=%d，合计=%d模型采样\n' ...
    '有效区组合产生FFT的一列，不是一点对一点\n原文件有效区连续坐标：[%.9f, %.9f]\n' ...
    'FFT任一频点还依赖插值/FIR支持；详细见point_trace'], ...
    pass,symbol,column,cfg.cp_length,cfg.nfft,L,trace.raw_interval),'VerticalAlignment','top','Interpreter','none');
info.trace=trace;
sgtitle(layout,'同一符号的时间采样与频率位置：CP复制不等于所有接收步骤都正确');
end
