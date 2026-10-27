function [fig, info] = plotCP(context, options)
%PLOTCP 从已保存取帧数据比较CFO补偿前后；不再次读BIN或插值。
fig=slrx.viz.newFigure('CP与尾部复制：复数、幅度和相位',options.show_figures);
layout=tiledlayout(fig,2,2,'TileSpacing','compact');cfg=context.cfg;
pass=1;if isfield(context,'time2'),pass=2;end
field=sprintf('time%d',pass);symbol=options.symbols(1);column=symbol+1;
info=struct('available',isfield(context,field),'round',pass,'data_symbol',symbol,'grid_column',column);
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'没有取帧数据');return;end
time=context.(field);L=cfg.cp_length+cfg.nfft;
before=reshape(time.time_raw,L,cfg.frame_symbol_count);after=reshape(time.time_cfo_compensated,L,cfg.frame_symbol_count);
cp=after(1:cfg.cp_length,column+1);tail=after(end-cfg.cp_length+1:end,column+1);
rawCp=before(1:cfg.cp_length,column+1);rawTail=before(end-cfg.cp_length+1:end,column+1);
rho=@(a,b)sum(b.*conj(a))/max(sqrt(sum(abs(a).^2)*sum(abs(b).^2)),eps);
info.correlation_before=rho(rawCp,rawTail);info.correlation_after=rho(cp,tail);
info.cp=cp;info.tail=tail;
ax=nexttile(layout);plot(ax,0:cfg.cp_length-1,real(cp),'-o',0:cfg.cp_length-1,real(tail),'-s');grid(ax,'on');
xlabel(ax,'CP段内零基采样编号');ylabel(ax,'I');legend(ax,{'CP','有效区末尾'},'Location','best');title(ax,'复数实部：已按本轮CFO补偿');
ax=nexttile(layout);plot(ax,0:cfg.cp_length-1,imag(cp),'-o',0:cfg.cp_length-1,imag(tail),'-s');grid(ax,'on');
xlabel(ax,'CP段内零基采样编号');ylabel(ax,'Q');legend(ax,{'CP','有效区末尾'},'Location','best');title(ax,'复数虚部：同一对复制样本');
ax=nexttile(layout);plot(ax,0:cfg.cp_length-1,abs(cp),'-o',0:cfg.cp_length-1,abs(tail),'-s');grid(ax,'on');
xlabel(ax,'CP段内零基采样编号');ylabel(ax,'复幅度');legend(ax,{'CP','有效区末尾'},'Location','best');title(ax,'噪声、多径与时钟误差可使两者不重合');
ax=nexttile(layout);plot(ax,0:cfg.cp_length-1,angle(rawTail.*conj(rawCp))*180/pi,'-o', ...
    0:cfg.cp_length-1,angle(tail.*conj(cp))*180/pi,'-s');grid(ax,'on');
xlabel(ax,'CP段内零基采样编号');ylabel(ax,'尾部×conj(CP)相位 / 度');legend(ax,{'本轮CFO补偿前','本轮CFO补偿后'},'Location','best');
title(ax,sprintf('|rho| %.4f → %.4f；arg(rho) %.2f° → %.2f°', ...
    abs(info.correlation_before),abs(info.correlation_after),angle(info.correlation_before)*180/pi,angle(info.correlation_after)*180/pi));
sgtitle(layout,sprintf('第%d轮 数据符号%d：CP与有效区末尾%d点；相关高不能单独证明完整解调正确',pass,symbol,cfg.cp_length));
end
