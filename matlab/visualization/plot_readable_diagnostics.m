function report=plot_readable_diagnostics(root,run_dir,out)
% Replot saved diagnostics: one question per figure, no receiver recomputation.
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
assert(~exist(fullfile(out,'readable.json'),'file'),'readable:Immutable','Use a new output directory');
if ~exist(out,'dir'),mkdir(out);end
pointer=jsondecode(fileread(fullfile(run_dir,'diagnostics','latest.json')));
original=load(fullfile(root,pointer.output_dir,'diagnostics_data.mat'),'selected','data');
S=original.selected;D=original.data;f=load_payload_frame(run_dir,1);a=author_sequences(root);
summary=jsondecode(fileread(fullfile(run_dir,'result.json')));
evaluation=jsondecode(fileread(fullfile(run_dir,'evaluation.json')));
set(groot,'defaultAxesFontName','Noto Sans CJK SC','defaultTextFontName','Noto Sans CJK SC',...
 'defaultAxesFontSize',13,'defaultTextFontSize',13);
files={};
% Power bins were not saved in selected: read the raw file once for power/PSD.
fid=fopen(fullfile(root,'data/raw/exemplar250-257/exemplar250-257.bin'),'r','ieee-le');assert(fid>=0);
z=fread(fid,[2 Inf],'int16=>double');fclose(fid);y=complex(z(1,:),z(2,:)).'/32768;clear z;
bin=10000;count=floor(numel(y)/bin);power=mean(abs(reshape(y(1:count*bin),bin,[])).^2,1);
time=((0:count-1)*bin+bin/2)/250e6*1e3;
newfig();plot(time,10*log10(max(power,realmin)),'LineWidth',1.1);hold on;
for k=1:numel(summary.estimates)
 xline((summary.estimates(k).start_sample_capture-1)/250e6*1e3,':',sprintf('帧%d',k),'LabelOrientation','horizontal');
end
xlim([0 50]);xlabel('原始文件时间 / ms');ylabel('40 μs 分箱平均功率 / dB');title('50 ms采集：能量出现在哪里？');savefig('01_capture_power.png');
[P,ff]=pwelch(y(1:1000000),hann(4096),2048,8192,250e6,'centered');clear y;
newfig();plot(ff/1e6,10*log10(P),'LineWidth',1);xlabel('相对采集中心的基带频率 / MHz');ylabel('PSD / dB/Hz（归一化IQ单位）');title('前4 ms的频谱：带宽、带边与直流附近');savefig('02_capture_psd.png');

newfig();plot(S.timing_lags_model_samples,S.pss_local_correlation,'-o','LineWidth',1.4);hold on;
plot(S.timing_lags_model_samples,S.sss_local_correlation,'-s','LineWidth',1.4);
xline(0,':');xlabel('相对已检出帧头的偏移 / 240 Msps模型采样');ylabel('归一化相关幅度');ylim([0 1.05]);legend('PSS','SSS','已检出帧头','Location','northeast');title('帧1：PSS与SSS是否支持同一个帧头？');savefig('03_sync_correlation.png');

grid_names={'04_grid_coarse.png','05_grid_clock_corrected.png','06_grid_equalized.png','07_grid_final.png'};
grid_titles={'粗CFO补偿与FFT','CFO/SFO更新并重新提取','SSS信道均衡后','最终ML残余同步后'};
for k=1:4
 newfig();imagesc(1:301,S.frequency_mhz,S.power_db{k});axis xy;caxis([-12 6]);colorbar;
 xlabel('OFDM网格列（1=SSS，2～301=数据）');ylabel('基带频率 / MHz');title(['帧1功率网格：' grid_titles{k}]);
 savefig(grid_names{k});
end
newfig();plot(S.frequency_mhz,20*log10(abs(fftshift(f.channel_response))),'LineWidth',1.2);
xlabel('基带频率 / MHz');ylabel('信道幅度 20log_{10}|H| / dB');title('帧1：不同频率的幅度响应是否一致？');savefig('08_channel_magnitude.png');
newfig();plot(S.frequency_mhz,unwrap(angle(fftshift(f.channel_response))),'LineWidth',1.2);
xlabel('基带频率 / MHz');ylabel('展开的信道相位 / rad');title('帧1：不同频率的相位响应如何变化？');savefig('09_channel_phase.png');

inliers=logical(f.tracking.ml_inlier_mask);index=1:300;
newfig();h=plot(index(inliers),f.tracking.ml_phase_unwrapped_rad(inliers),'.','MarkerSize',10);hold on;
labels={'时延内点对应的相位'};
if any(~inliers)
 h(end+1)=plot(index(~inliers),f.tracking.ml_phase_unwrapped_rad(~inliers),'x');labels{end+1}='时延外点对应的相位';
end
h(end+1)=plot(index,f.tracking.phase_intercept_rad,'k-','LineWidth',1.8);labels{end+1}='整帧相位拟合';
xlabel('帧内数据符号编号 / 1～300');ylabel('待补偿相位 / rad');title('帧1：逐符号相位估计与整帧拟合');
legend(h,labels,'Location','best');savefig('10_phase_correction.png');
newfig();delay=f.tracking.ml_delay_samples/240e6*1e9;
h=plot(index(inliers),delay(inliers),'.','MarkerSize',10);hold on;labels={'RANSAC时延内点'};
if any(~inliers)
 h(end+1)=plot(index(~inliers),delay(~inliers),'x');labels{end+1}='RANSAC时延外点';
end
h(end+1)=plot(index,f.tracking.residual_delay_s*1e9,'k-','LineWidth',1.8);labels{end+1}='整帧时延拟合';
xlabel('帧内数据符号编号 / 1～300');ylabel('残余时延估计 / ns');title('帧1：逐符号时延估计与整帧拟合（非绝对传播时延）');
legend(h,labels,'Location','best');savefig('11_delay_correction.png');

newfig();bar(1:4,100*D(1).heldout_evm,'FaceColor',[.18 .46 .65]);
xticks(1:4);xticklabels({'粗CFO/FFT','CFO/SFO更新','信道均衡','最终ML同步'});
ylabel('8条留出导频的EVM / %');title('帧1：处理阶段是否真的改善了已知参考误差？');
for k=1:4,text(k,100*D(1).heldout_evm(k)+3,sprintf('%.2f%%',100*D(1).heldout_evm(k)),'HorizontalAlignment','center');end
ylim([0 max(100*D(1).heldout_evm)*1.18]);savefig('12_pilot_evm_stages.png');
newfig();plot(index,100*D(1).symbol_evm(3,:),'-','LineWidth',1);hold on;
plot(index,100*D(1).symbol_evm(4,:),'--','LineWidth',1.2);
xlabel('帧内数据符号编号 / 1～300');ylabel('单列留出导频EVM / %');title('帧1：整帧平均值是否掩盖某些符号变差？');
legend('信道均衡后','最终ML同步后','Location','best');savefig('13_pilot_evm_by_symbol.png');
newfig();set(gcf,'Position',[30 30 760 720]);U=S.derotated_pilots{4};plot(real(U(:)),imag(U(:)),'.','MarkerSize',6);hold on;plot(1,0,'rx','MarkerSize',14,'LineWidth',2);
radius=max(.65,max(abs(U(:)-1))*1.08);axis equal;axis([1-radius 1+radius -radius radius]);grid on;xlabel('Re(Z/P)');ylabel('Im(Z/P)');title('帧1：留出导频是否围绕(1,0)？');
legend('判决前的留出导频','理想参考(1,0)','Location','best');savefig('14_pilot_reference_cloud.png');
newfig();imagesc(index,1:8,S.heldout_error_magnitude);axis xy;colorbar;
yticks(1:8);yticklabels(string(S.reference_rows));xlabel('帧内数据符号编号 / 1～300');ylabel('留出导频的MATLAB子载波行号');
title('帧1：哪些导频、哪些符号的|Z-P|较大？');savefig('15_pilot_error_map.png');
newfig();phase=squeeze(D(1).heldout_phase_deg(4,:,:));plot(index,phase.','LineWidth',1);yline(0,':');
xlabel('帧内数据符号编号 / 1～300');ylabel('平均留出导频残余相位 / °');title('帧1：补偿后，正负频带是否仍有相位偏差？');
legend('正频率留出导频','负频率留出导频','零相位','Location','best');savefig('16_pilot_residual_phase.png');

newfig();plot(1:301,abs(S.cp_correlation_after),'LineWidth',1);hold on;
yline(median(abs(S.cp_correlation_after)),':','中位数','LineWidth',1.5);ylim([0 1]);
xlabel('OFDM网格列（1=SSS）');ylabel('CP与符号尾部的归一化相关幅度');title('帧1：循环前缀与其复制的尾部是否一致？');savefig('17_cp_magnitude.png');
newfig();plot(1:301,angle(S.cp_correlation_before)*180/pi,'LineWidth',1);hold on;
plot(1:301,angle(S.cp_correlation_after)*180/pi,'LineWidth',1);yline(0,':');
xlabel('OFDM网格列（1=SSS）');ylabel('CP相关相位 / °');title('帧1：补偿总CFO前后的CP相位');
legend('总CFO补偿前','总CFO补偿后','零相位','Location','best');savefig('18_cp_phase.png');

extent=max(1.6,max(abs(S.payload_points),[],'all')*1.05);
for k=1:numel(S.selected_grid_columns)
 column=S.selected_grid_columns(k);z=S.payload_points(:,k);positive=a.freq(S.payload_rows)>=0;
 newfig();set(gcf,'Position',[30 30 760 720]);plot(real(z(~positive)),imag(z(~positive)),'.','MarkerSize',7);hold on;
 plot(real(z(positive)),imag(z(positive)),'.','MarkerSize',7);axis equal;axis([-extent extent -extent extent]);
 xlabel('I：最终均衡/同步网格实部');ylabel('Q：最终均衡/同步网格虚部');
 title(sprintf('帧1：只看数据符号%d（网格列%d）的判决前载荷点',column-1,column));
 legend('负频率载荷','正频率载荷','Location','northeast');savefig(sprintf('19_constellation_symbol_%03d.png',column-1));
end

g=S.frame_guard;indices=[g.raw_preguard.sample_indices(:);g.raw_guard.sample_indices(:)];
samples=[g.raw_preguard.samples(:);g.raw_guard.samples(:)];time=(indices-g.guard_start_sample_capture)/250e6*1e6;
power=abs(samples).^2/g.raw_preguard.mean_power;
newfig();plot(time,10*log10(max(power,realmin)),'.','Color',[.76 .79 .81],'MarkerSize',4);hold on;
plot(time,10*log10(max(movmean(power,31),realmin)),'Color',[0 .447 .741],'LineWidth',1.6);
xline(0,'k--','模型占用末端');xline(g.mapped_guard_duration_s*1e6,'k:','预测保护窗末端');
plot([0 g.mapped_guard_duration_s*1e6],g.raw_guard_to_preguard_power_db*[1 1],'-','Color',[.85 .4 .15],'LineWidth',2);
xlabel('相对模型占用末端 / μs');ylabel('相对等长前窗平均功率 / dB');title('帧1：预测保护窗内的能量是否下降？');
legend('原始逐采样功率','31点滑动平均','模型占用末端','预测窗末端','保护窗均值','Location','best');savefig('20_guard_power.png');
newfig();guard=arrayfun(@(x)x.frame_guard.raw_guard_to_preguard_power_db,summary.estimates);
bar(1:numel(guard),guard,'FaceColor',[.18 .46 .65]);yline(0,':');
xlabel('按时间排序的接收帧编号');ylabel('预测保护窗 / 等长前窗平均功率 / dB');title('9帧：预测保护窗的功率下降是否一致？');savefig('21_guard_all_frames.png');
newfig();E=vertcat(D.heldout_evm);barplot=bar(1:numel(D),100*E(:,4),'FaceColor','flat');
colors=repmat([.16 .52 .48],numel(D),1);
for k=1:numel(D),if ~strcmp(evaluation.metrics(k).annotation_status,'matched'),colors(k,:)=[.83 .57 .22];end,end
barplot.CData=colors;ylim([0 max(100*E(:,4))*1.2]);xlabel('按时间排序的接收帧编号');ylabel('最终留出导频EVM / %');
title('9帧的最终参考误差：橙色为未匹配作者标注的额外候选');savefig('22_frame_evm_summary.png');

report=struct('status','created','version','readable-v1','frame_count',numel(D),'detailed_frame',1,...
 'files',{files},'source_diagnostics',pointer.output_dir,'receiver_results_modified',false,...
 'source_policy','Saved first-frame arrays and diagnostics; raw IQ read only for capture power and PSD',...
 'guard_endpoint_policy','Model predicted; no independent noise-edge detection');
fid=fopen(fullfile(out,'readable.json'),'w');fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true));fclose(fid);
fprintf('READABLE_DIAGNOSTICS_CREATED figures=%d\n',numel(files));

function newfig()
 figure('Visible','off','Position',[30 30 1300 540],'Color','w');grid on;box on;
end
function savefig(name)
 grid on;exportgraphics(gcf,fullfile(out,name),'Resolution',130);close(gcf);files{end+1}=name;
end
end
