function [fig, info] = plotOFDM(context, options)
%PLOTOFDM 概览保留连线；CP边界和局部FFT用离散采样，不重算接收结果。
fig=slrx.viz.newFigure('单个OFDM符号：采样、CP边界与FFT频点',options.show_figures);
fig.Position(4)=1100;
layout=tiledlayout(fig,3,2,'TileSpacing','compact');cfg=context.cfg;symbol=options.symbols(1);column=symbol+1;
pass=1;if isfield(context,'time2'),pass=2;end
timeField=sprintf('time%d',pass);ofdmField=sprintf('ofdm%d',pass);fftField=sprintf('fft%d',pass);
info=struct('round',pass,'data_symbol',symbol,'grid_column',column,'cp_length',cfg.cp_length, ...
    'nfft',cfg.nfft,'symbol_length',cfg.cp_length+cfg.nfft,'available',isfield(context,timeField));
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无取帧检查点');return;end
d=context.(timeField);L=cfg.cp_length+cfg.nfft;block=reshape(d.time_cfo_compensated,L,cfg.frame_symbol_count);
z=block(:,column+1);valid=z(cfg.cp_length+1:end);
if isfield(context,ofdmField),assert(isequal(valid,context.(ofdmField).without_cp(:,column)),'slrx:DiagnosticCP','时域重排与保存结果不符');end
ax=nexttile(layout);plot(ax,0:L-1,real(z),0:L-1,imag(z));hold(ax,'on');grid(ax,'on');
xline(ax,cfg.cp_length-.5,'r--','CP/有效区','HandleVisibility','off');xline(ax,L-cfg.cp_length-.5,'k:','末尾复制段','HandleVisibility','off');
xlabel(ax,'本符号内零基采样编号 n');ylabel(ax,'CFO补偿后I/Q幅度');legend(ax,{'I','Q'},'Location','best');
title(ax,sprintf('概览：%d=%d+%d；连线只作导视',L,cfg.cp_length,cfg.nfft));

boundary=0:min(L-1,2*cfg.cp_length-1);
ax=nexttile(layout);stem(ax,boundary,real(z(boundary+1)),'o','MarkerSize',3,'DisplayName','I','Tag','slrx-cp-boundary-I');hold(ax,'on');
stem(ax,boundary,imag(z(boundary+1)),'s','MarkerSize',3,'DisplayName','Q','Tag','slrx-cp-boundary-Q');
xline(ax,cfg.cp_length-.5,'r--','去CP边界','HandleVisibility','off');grid(ax,'on');xlim(ax,[-.5 boundary(end)+.5]);
xlabel(ax,'同一符号零基采样编号 n');ylabel(ax,'实际I/Q幅度');legend(ax,'Location','best');
title(ax,sprintf('逐点看边界：CP n=0..%d；有效区从n=%d开始',cfg.cp_length-1,cfg.cp_length));
info.cp_boundary=struct('indices_0based',boundary,'values',z(boundary+1));

ax=nexttile(layout);plot(ax,0:cfg.nfft-1,real(valid),0:cfg.nfft-1,imag(valid));grid(ax,'on');
xlabel(ax,'去CP后零基时间采样编号 p');ylabel(ax,'有效区I/Q幅度');legend(ax,{'I','Q'},'Location','best');
title(ax,sprintf('去CP后%d份复采样；整体概览',cfg.nfft));
local=0:min(31,cfg.nfft-1);
ax=nexttile(layout);stem(ax,local,real(valid(local+1)),'o','MarkerSize',4,'DisplayName','I','Tag','slrx-valid-I');hold(ax,'on');
stem(ax,local,imag(valid(local+1)),'s','MarkerSize',4,'DisplayName','Q','Tag','slrx-valid-Q');grid(ax,'on');
xlabel(ax,sprintf('有效区编号 p（原符号编号 n=p+%d）',cfg.cp_length));ylabel(ax,'有效区I/Q幅度');legend(ax,'Location','best');
title(ax,sprintf('前%d点：重新从p=0编号，数值未改变',numel(local)));
info.valid_local=struct('indices_0based',local,'values',valid(local+1));

row=context.refs.payload_rows(1);
if isfield(options,'selected_row')&&~isempty(options.selected_row),row=options.selected_row;end
info.trace=slrx.diag.tracePoint(context,pass,symbol,row);
if isfield(context,fftField)
    gridValue=context.(fftField).values(:,column);[bins,order]=sort(context.refs.frequency_bins);
    ax=nexttile(layout);plot(ax,slrx.diag.coordinates('bin_to_mhz',bins,cfg),abs(gridValue(order)));grid(ax,'on');
    xlabel(ax,'基带频率 / MHz');ylabel(ax,'|FFT(x)/sqrt(N)|');title(ax,'FFT全频带概览；频率排序仅显示');
    center=find(order==row,1);count=min(32,cfg.nfft);first=max(1,min(center-floor(count/2),cfg.nfft-count+1));
    chosen=first:first+count-1;rows=order(chosen);k=bins(chosen);values=gridValue(rows);
    ax=nexttile(layout);stem(ax,k,abs(values),'o','MarkerSize',4,'Tag','slrx-local-fft');hold(ax,'on');
    xline(ax,context.refs.frequency_bins(row),'r:','选中bin','HandleVisibility','off');grid(ax,'on');
    xlim(ax,[k(1)-.5 k(end)+.5]);xticks(ax,unique([k(1):4:k(end) k(end)]));
    xlabel(ax,'signed FFT bin k（非MATLAB行号）');ylabel(ax,'该频点FFT幅度');
    title(ax,sprintf('局部%d个离散FFT频点；不是模拟频谱只含这些线',count));
    info.local_fft=struct('matlab_rows',rows,'signed_bins',k,'values',values, ...
        'frequency_mhz',slrx.diag.coordinates('bin_to_mhz',k,cfg),'selected_row',row);
else
    for k=1:2,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'FFT尚未执行，不补造频点');end
end
info.display_style='overview_with_discrete_details';fig.UserData=info;
sgtitle(layout,sprintf('第%d轮 数据符号%d / 网格列%d：一整段1024点共同产生各FFT频点；不逐点对应', ...
    pass,symbol,column),'FontSize',12);
end
