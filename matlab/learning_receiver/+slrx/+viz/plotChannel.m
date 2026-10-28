function [fig, info] = plotChannel(context, options)
%PLOTCHANNEL Y/H的复数意义与深衰落噪声增益代理；不更换均衡器。
fig=slrx.viz.newFigure('信道与均衡：复数除法和噪声增益',options.show_figures);
fig.Position(4)=1050;layout=tiledlayout(fig,3,2,'TileSpacing','compact');cfg=context.cfg;refs=context.refs;
pass=1;if isfield(context,'channel2'),pass=2;end
field=sprintf('channel%d',pass);info=struct('round',pass,'available',isfield(context,field));
if ~info.available,ax=nexttile(layout);axis(ax,'off');text(ax,.1,.5,'尚无信道估计');return;end
d=context.(field);rows=refs.active_rows(:);[bins,order]=sort(refs.frequency_bins(rows));rows=rows(order);
freq=slrx.diag.coordinates('bin_to_mhz',bins,cfg);H=d.H(rows);low=abs(H)<options.low_channel_fraction*max(abs(H));
info.low_threshold=options.low_channel_fraction*max(abs(H));info.low_threshold_is_diagnostic_only=true;info.low_rows=rows(low);
ax=nexttile(layout);plot(ax,freq,abs(H));hold(ax,'on');plot(ax,freq(low),abs(H(low)),'ro');yline(ax,info.low_threshold,'r:','相对幅度诊断线');grid(ax,'on');
xlabel(ax,'基带频率 / MHz');ylabel(ax,'|H|（接收归一化单位）');title(ax,'较小H区域仅作提示，原接收机下限/均衡策略保持不变');
ax=nexttile(layout);plot(ax,freq,unwrap(angle(H)));grid(ax,'on');xlabel(ax,'基带频率 / MHz');ylabel(ax,'展开相位 / rad');title(ax,'估计信道导致的频率相关旋转');
ax=nexttile(layout);yyaxis(ax,'left');plot(ax,freq,10*log10(1./max(abs(H).^2,realmin)));ylabel(ax,'1/|H|^2 / dB（噪声增益代理）');
yyaxis(ax,'right');plot(ax,freq,d.noise_variance_equalized(rows));ylabel(ax,'SSS模型估计的均衡后噪声方差');grid(ax,'on');xlabel(ax,'基带频率 / MHz');title(ax,'深衰落可能放大噪声；代理指标不等于已知真实载荷噪声');
ax=nexttile(layout);row=options.selected_row;symbol=options.symbols(1);column=symbol+1;
fftField=sprintf('fft%d',pass);eqField=sprintf('eq%d',pass);
if isfield(context,fftField)&&isfield(context,eqField)
    Y=context.(fftField).values(row,column);h=d.H(row);X=context.(eqField).values(row,column);
    plot(ax,real([0 Y]),imag([0 Y]),'-o','DisplayName','Y接收');hold(ax,'on');
    plot(ax,real([0 h]),imag([0 h]),'-s','DisplayName','H估计');plot(ax,real([0 X]),imag([0 X]),'-^','DisplayName','Xhat=Y/H');
    axis(ax,'equal');grid(ax,'on');xlabel(ax,'实部');ylabel(ax,'虚部');legend(ax,'Location','best');
    title(ax,sprintf('第%d轮 数据%d/列%d/行%d/bin%d\n|H|=%.5g，arg(H)=%.3f°；Y/H非已知发送真值', ...
        pass,symbol,column,row,refs.frequency_bins(row),abs(h),angle(h)*180/pi));
    info.selected=struct('data_symbol',symbol,'grid_column',column,'matlab_row',row, ...
        'signed_bin',refs.frequency_bins(row),'Y',Y,'H',h,'Xhat',X,'division_residual',abs(X-Y/h));
else,axis(ax,'off');text(ax,.1,.5,'缺少FFT或均衡结果，不能显示Y/H对照');end
ax=nexttile(layout);r=d.sss_residual_frequency_order;rowsResidual=d.frequency_order_rows;
plot(ax,slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(rowsResidual),cfg),abs(r),'.');grid(ax,'on');
xlabel(ax,'基带频率 / MHz');ylabel(ax,'|SSS观测−H×参考|');title(ax,'已保存SSS拟合残差：训练参考，非独立验证');
info.sss_residual_rms=sqrt(mean(abs(r).^2));
ax=nexttile(layout);axis(ax,'off');text(ax,0,1,sprintf('第%d轮SSS残差RMS=%.6g\n已有噪声估计=%.6g\n训练残差小不保证未知载荷正确。',pass,info.sss_residual_rms,d.noise_power_before_equalization),'VerticalAlignment','top');
sgtitle(layout,'信道幅相如何影响复数符号：只观察既有估计，不引入新的旋转、增益拟合或均衡算法','FontSize',11);
end
