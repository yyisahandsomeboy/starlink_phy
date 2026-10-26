function report=plot_ofdm_diagnostics(root,run_dir,out)
% Read-only postprocessing of real receiver outputs; never changes receiver/evaluator.
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
if nargin<3,out=fullfile(run_dir,'diagnostics','ofdm-v1');end
assert(~exist(fullfile(out,'diagnostics.json'),'file'),'view:Immutable','Use a new output directory');
if ~exist(out,'dir'),mkdir(out);end
D=load(fullfile(run_dir,'result.mat'),'result');R=D.result;clear D;
assert(~isempty(R.frames),'view:NoFrames','No receiver frames to display');
a=author_sequences(root);count=numel(R.frames);data=struct([]);
tracking_label='导频跟踪';phase_label='拟合导频驱动的相位修正量';
if isfield(R,'receiver_version') && strcmp(R.receiver_version,'author-ml-v1')
 tracking_label='ML 残余同步';phase_label='数据 ML 与整帧拟合的相位修正量';
end
try
 set(groot,'defaultAxesFontName','Noto Sans CJK SC','defaultTextFontName','Noto Sans CJK SC');
catch
end
for k=1:count
 f=R.frames(k);d=ofdm_view_data(f,a);
 item=struct('frame',k,'start_time_ms',(f.start_sample_capture-1)/250e6*1e3,...
  'stage_names',{d.stage_names},'heldout_evm',d.stage_evm,...
  'symbol_evm',d.symbol_evm,'heldout_phase_deg',d.heldout_phase_deg,...
  'payload_mean_power',d.payload_mean_power,'payload_fourth_moment',d.payload_fourth_moment);
 if isempty(data),data=item;else,data(end+1)=item;end
end
% Fixed first chronological frame, not a post-hoc prettiest frame.
f=R.frames(1);d=ofdm_view_data(f,a);
newfig();tiledlayout(2,2,'TileSpacing','compact');
for k=1:4
 nexttile;imagesc(1:301,d.frequency_mhz,d.power_db{k});axis xy;caxis([-12 6]);colorbar;
 xlabel('OFDM 网格列（第 1 列 SSS）');ylabel('基带频率 / MHz');title(d.stage_names{k});
 hold on;yline(mean(a.freq(a.rows(1:8)))*240e6/1024/1e6,'w:');
 yline(mean(a.freq(a.rows(9:16)))*240e6/1024/1e6,'w:');
end
sgtitle('帧 1：OFDM 功率资源网格；相同色标，幅度图不用于判定调制');
finish(out,'02_ofdm_resource_grid.png');

newfig();tiledlayout(2,3,'TileSpacing','compact');
indices=[1 3 4];lim=1.2;
for k=indices,lim=max(lim,max(abs(d.derotated_pilots{k}),[],'all')*1.05);end
for k=indices
 nexttile;U=d.derotated_pilots{k};plot(real(U(:)),imag(U(:)),'.','MarkerSize',4);hold on;
 plot(1,0,'rx','MarkerSize',12,'LineWidth',2);axis equal;axis([-lim lim -lim lim]);grid on;
 xlabel('Re(Z/P)');ylabel('Im(Z/P)');title(sprintf('%s；EVM %.1f%%',d.stage_names{k},100*d.stage_evm(k)));
end
nexttile;plot(2:301,100*d.symbol_evm(indices,:).');grid on;
 xlabel('OFDM 网格列');ylabel('留出导频 EVM / %');legend('粗 CFO','ZF 均衡',tracking_label,'Location','northwest');
nexttile;imagesc(2:301,1:8,d.heldout_error_magnitude);axis xy;colorbar;
yticks(1:8);yticklabels(string(a.eval));xlabel('OFDM 网格列');ylabel('留出导频 MATLAB 行');title('|Z-P|，跟踪后');
nexttile;plot(2:301,squeeze(d.heldout_phase_deg(3,:,:)).','--');hold on;
plot(2:301,squeeze(d.heldout_phase_deg(4,:,:)).');grid on;
xlabel('OFDM 网格列');ylabel('留出导频平均残余相位 / 度');
legend('正频带，均衡','负频带，均衡','正频带，跟踪','负频带，跟踪','Location','best');
sgtitle('帧 1：只使用 8 条留出导频；参考去旋转后目标均为 (1,0)');
finish(out,'03_heldout_pilot_validation.png');

% Retrieve nominal IQ only for physical CP and acquisition diagnostics.
prepared=fullfile(run_dir,'01_prepare_capture.mat');
if exist(prepared,'file')
 V=load(prepared,'d');v=V.d.v;clear V;
else
 y=read_capture(root);v=resample(y,24,25,50);v=v-mean(v);clear y;
end
n=(0:31)'+(1:301)*1056;times=n/(1+f.sfo_ppm*1e-6);
cp=reshape(bandlimited_sample(v,f.start_sample_nominal+times(:)),32,301);
tail_times=(n+1024)/(1+f.sfo_ppm*1e-6);
tail=reshape(bandlimited_sample(v,f.start_sample_nominal+tail_times(:)),32,301);
raw_corr=sum(tail.*conj(cp),1)./max(sqrt(sum(abs(cp).^2,1).*sum(abs(tail).^2,1)),eps);
cp=cp.*exp(-1j*2*pi*f.cfo_hz*times/240e6);
tail=tail.*exp(-1j*2*pi*f.cfo_hz*tail_times/240e6);
corrected_corr=sum(tail.*conj(cp),1)./max(sqrt(sum(abs(cp).^2,1).*sum(abs(tail).^2,1)),eps);
% Full-reference timing curves about independently detected start, at fixed CFO.
lags=-16:16;pss=zeros(size(lags));sss=pss;
for k=1:numel(lags)
 n0=(0:2111)';w=v(f.start_sample_nominal+lags(k)+n0).*exp(-1j*2*pi*f.cfo_hz*n0/240e6);
 pss(k)=abs(a.pss'*w(1:1056))/(norm(a.pss)*norm(w(1:1056))+eps);
 sss(k)=abs(a.sss'*w(1057:2112))/(norm(a.sss)*norm(w(1057:2112))+eps);
end
clear v;
newfig();tiledlayout(2,3,'TileSpacing','compact');
nexttile;plot(lags,pss,'-o',lags,sss,'-s');grid on;xlabel('相对接收机起点 / 模型样本');ylabel('归一化相关');legend('PSS','SSS');title('同步局部峰，不使用作者 TOA');
nexttile;plot(d.frequency_mhz,20*log10(abs(fftshift(f.channel_response))));grid on;
xlabel('基带频率 / MHz');ylabel('|H| / dB');title('SSS 信道幅度');
nexttile;plot(d.frequency_mhz,unwrap(angle(fftshift(f.channel_response))));grid on;
xlabel('基带频率 / MHz');ylabel('展开相位 / rad');title('SSS 信道相位');
nexttile;plot(f.tracking.symbol_index,f.tracking.phase_intercept_rad);grid on;
xlabel('OFDM 网格列');ylabel('拟合相位 / rad');title(phase_label);
nexttile;plot(f.tracking.symbol_index,f.tracking.residual_delay_s*1e9);grid on;
xlabel('OFDM 网格列');ylabel('拟合残余时延 / ns');title('拟合时延修正量，不是真值');
nexttile;yyaxis left;plot(1:301,abs(corrected_corr));ylim([0 1]);ylabel('CP 归一化相关幅度');
yyaxis right;plot(1:301,angle(raw_corr)*180/pi,'--','Color',[.85 .33 .1]);hold on;
plot(1:301,angle(corrected_corr)*180/pi,'Color',[.47 .15 .67]);ylabel('CP 相关相位 / 度');
xlabel('OFDM 网格列');grid on;title('原始采样的 CP 一致性');legend('相关幅度','载波未补偿','总 CFO 补偿','Location','northwest','FontSize',8);
sgtitle('帧 1：同步、信道和物理 CP 诊断；CP 相关不是新增通过门限');
finish(out,'04_channel_and_synchronization.png');

newfig();tiledlayout(2,3,'TileSpacing','compact');extent=max(1.6,max(abs(d.payload_points),[],'all')*1.05);
for k=1:numel(d.selected_grid_columns)
 nexttile;z=d.payload_points(:,k);positive=d.payload_frequency_sign;
 plot(real(z(~positive)),imag(z(~positive)),'.','MarkerSize',4);hold on;
 plot(real(z(positive)),imag(z(positive)),'.','MarkerSize',4);axis equal;axis([-extent extent -extent extent]);grid on;
 xlabel('I（原接收机输出）');ylabel('Q');title(sprintf('网格列 %d / 数据符号 %d',d.selected_grid_columns(k),d.selected_grid_columns(k)-1));
 if k==1,legend('负频率载荷','正频率载荷','Location','best');end
end
sgtitle('帧 1：固定单符号局部星座；无额外旋转/归一化，调制未确证');
finish(out,'05_fixed_symbol_constellations.png');

newfig();tiledlayout(2,2,'TileSpacing','compact');E=vertcat(data.heldout_evm);
nexttile;plot(1:count,100*E,'-o');grid on;xlabel('完整接收网格编号');ylabel('留出导频 EVM / %');legend('粗 CFO','CFO/SFO','ZF 均衡',tracking_label,'Location','best');title('全部帧的数值比较');
nexttile;plot(2:301,100*d.symbol_evm(3:4,:).');grid on;xlabel('OFDM 网格列');ylabel('留出导频 EVM / %');legend('均衡','跟踪');title('帧 1：均衡与跟踪，允许局部变差');
nexttile;plot(2:301,d.payload_mean_power);grid on;xlabel('OFDM 网格列');ylabel('非导频平均 |Z|^2');title('帧 1：载荷功率变化，不识别调制');
nexttile;plot(2:301,d.payload_fourth_moment);grid on;xlabel('OFDM 网格列');ylabel('E|Z|^4 / (E|Z|^2)^2');title('帧 1：幅度分布形态，不识别调制');
sgtitle('总体诊断：导频正确性与载荷调制可解释性分别展示');
finish(out,'06_all_frame_metrics.png');

y=read_capture(root);Fs=250e6;bin=10000;trim=floor(numel(y)/bin)*bin;
power=mean(abs(reshape(y(1:trim),bin,[])).^2,1);t=((0:numel(power)-1)*bin+bin/2)/Fs*1e3;
[P,ff]=pwelch(y(1:min(end,1000000)),hann(4096),2048,8192,Fs,'centered');clear y;
newfig();tiledlayout(2,1,'TileSpacing','compact');
nexttile;plot(t,10*log10(max(power,realmin)));hold on;grid on;
for k=1:count,xline(data(k).start_time_ms,':',sprintf('%d',k));end
xlim([0 50]);xlabel('原始采集时间 / ms');ylabel('40 us 分箱功率 / dB');title('50 ms 原始 IQ 功率与独立检出起点');
nexttile;plot(ff/1e6,10*log10(P));grid on;xlabel('基带频率 / MHz');ylabel('PSD / dB/Hz（归一化 IQ 单位）');title('原始采集前 4 ms 功率谱；不是星座');
finish(out,'01_capture_overview.png');

selected=struct('frame',1,'reference_rows',a.eval,'stage_names',{d.stage_names},...
 'derotated_pilots',{d.derotated_pilots},'power_db',{d.power_db},'frequency_mhz',d.frequency_mhz,...
 'heldout_error_magnitude',d.heldout_error_magnitude,'selected_grid_columns',d.selected_grid_columns,...
 'payload_points',d.payload_points,'payload_rows',d.payload_rows,...
 'cp_correlation_before',raw_corr,'cp_correlation_after',corrected_corr,...
 'timing_lags_model_samples',lags,'pss_local_correlation',pss,'sss_local_correlation',sss);
save(fullfile(out,'diagnostics_data.mat'),'data','selected','-v7');
if isfield(f,'frame_guard')
 selected.frame_guard=f.frame_guard;
 selected.frame_guard_plot_moving_average_raw_samples=31;
 plot_guard(R.frames,out);
 save(fullfile(out,'diagnostics_data.mat'),'data','selected','-v7');
end
report=struct('status','created','visualization_version','ofdm-v1','receiver_results_modified',false,...
 'frame_count',count,'detailed_frame_indices',1,'payload_modulation_status','unknown',...
 'payload_BER_available',false,'stage_names',{d.stage_names},'heldout_evm',E,...
 'selected_grid_columns',d.selected_grid_columns,'cp_median_magnitude',median(abs(corrected_corr)),...
 'cp_median_phase_after_deg',median(angle(corrected_corr))*180/pi,...
 'cp_phase_median_abs_after_deg',median(abs(angle(corrected_corr)))*180/pi,...
 'capture_power_bin_samples',bin,'capture_psd_sample_count',1000000,...
 'reference_policy','Eight heldout pilots only; no evaluation-pilot fitting, no extra payload rotations/scaling',...
 'interpretation','This is a visualization artifact, not a new receiver acceptance or modulation classifier');
report.frame_guard_present=isfield(f,'frame_guard');
if report.frame_guard_present
 report.frame_guard_raw_power_db=arrayfun(@(x)x.frame_guard.raw_guard_to_preguard_power_db,R.frames);
 report.frame_guard_interpretation='Sample-mapped nominal window, not detected noise edges; frame/sample clock equality unverified';
end
fid=fopen(fullfile(out,'diagnostics.json'),'w');fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));fclose(fid);
fprintf('OFDM_DIAGNOSTICS_CREATED frames=%d after EVM range %.6f..%.6f, CP median %.4f\n',count,min(E(:,4)),max(E(:,4)),median(abs(corrected_corr)));
end
function plot_guard(frames,out)
g=frames(1).frame_guard;
indices=[g.raw_preguard.sample_indices(:);g.raw_guard.sample_indices(:)];
samples=[g.raw_preguard.samples(:);g.raw_guard.samples(:)];
t=(indices-g.guard_start_sample_capture)/g.fs_capture_hz*1e6;
power=abs(samples).^2/max(g.raw_preguard.mean_power,realmin);
newfig();tiledlayout(2,1,'TileSpacing','compact');nexttile;
plot(t,10*log10(max(power,realmin)),'.','Color',[.75 .79 .84],'MarkerSize',3);hold on;
plot(t,10*log10(max(movmean(power,31),realmin)),'b','LineWidth',1.2);
xline(0,'k--','占用末端：模型推算','LabelOrientation','horizontal');
xline(g.mapped_guard_duration_s*1e6,'k:','参考窗末端','LabelOrientation','horizontal');
plot([-g.mapped_guard_duration_s*1e6 0],[0 0],'Color',[.9 .4 .1],'LineWidth',2);
plot([0 g.mapped_guard_duration_s*1e6],g.raw_guard_to_preguard_power_db*[1 1],'Color',[.9 .4 .1],'LineWidth',2);
grid on;xlabel('相对模型占用末端 / 微秒');ylabel('功率相对前窗平均 / dB');
title(sprintf('帧1：预测保护窗 %.6f 微秒；窗平均比前窗 %.2f dB',g.mapped_guard_duration_s*1e6,g.raw_guard_to_preguard_power_db));
legend('原始逐采样功率','31点滑动平均','模型占用末端','参考窗末端','前窗均值','保护窗均值','Location','southoutside','Orientation','horizontal');
nexttile;raw=arrayfun(@(x)x.frame_guard.raw_guard_to_preguard_power_db,frames);
nominal=arrayfun(@(x)x.frame_guard.nominal_guard_to_preguard_power_db,frames);
bar(1:numel(frames),[raw(:) nominal(:)]);yline(0,'k:');grid on;
xlabel('按时间排序的独立检出帧');ylabel('保护窗 / 等长前窗平均功率 / dB');
legend('原始250 Msps','名义240 Msps','Location','southoutside','Orientation','horizontal');
title('所有帧的预测窗功率；静默时其它信号仍可能贡献能量');
sgtitle('帧末保护间隔：名义1088点；边界由模型推算，采样/帧时钟共同速率假设未核实');
finish(out,'07_frame_guard.png');
end
function y=read_capture(root)
fid=fopen(fullfile(root,'data','raw','exemplar250-257','exemplar250-257.bin'),'r','ieee-le');assert(fid>=0);
z=fread(fid,[2 Inf],'int16=>double');fclose(fid);y=complex(z(1,:),z(2,:)).'/32768;
end
function newfig()
figure('Visible','off','Position',[40 40 1600 1000],'Color','w');
end
function finish(out,name)
exportgraphics(gcf,fullfile(out,name),'Resolution',120);close(gcf);
end
