function result=author_receiver(cfg)
% Real raw-IQ implementation of published author pipeline, no annotations.
root=cfg.root;addpath(fullfile(root,'matlab','visualization'));
opt=jsondecode(fileread(fullfile(root,'config','author_receiver_v1.json')));a=author_sequences(root);
if isfield(cfg,'max_candidates'),opt.max_candidates=cfg.max_candidates;end
if ~exist(cfg.run_dir,'dir'),mkdir(cfg.run_dir);end
tic;fid=fopen(cfg.input_path,'r','ieee-le');assert(fid>=0,'author:Input');
components=fread(fid,[2 Inf],'int16=>double');fclose(fid);y=complex(components(1,:),components(2,:)).'/32768;clear components;
Fs=opt.capture_fs_hz;F=240e6;quality=struct('sample_count',numel(y),'Fs',Fs,...
 'rms',sqrt(mean(abs(y).^2)),'dc',[real(mean(y)) imag(mean(y))],...
 'clipped_fraction',mean(abs(real(y))>=32767/32768 | abs(imag(y))>=32767/32768));
[v,fir]=resample(y,24,25,50);removed_dc=mean(v);v=v-removed_dc;
[P,ff]=pwelch(y(1:min(end,1000000)),hann(4096),2048,8192,Fs,'centered');
input_diagnostics=struct('resample_fir',fir,'resample_ratio',[24 25],'removed_dc',removed_dc,...
 'psd_linear',P,'psd_frequency_hz',ff,'time_origin','Raw complex sample1=t0');
[candidates,rejected,scan]=acquire(v,a,opt);
[shared_channel,shared_diagnostics]=shared_sss_channel(v,candidates,a,opt);
frames=struct([]);candidate_diagnostics=cell(1,numel(candidates));
completed=cell(1,numel(candidates));failed=cell(1,numel(candidates));
workers=opt.workers;if isfield(cfg,'workers'),workers=cfg.workers;end
if workers>0 && isempty(gcp('nocreate')),parpool('Processes',workers);end
selected=1:numel(candidates);if isfield(cfg,'candidate_indices'),selected=cfg.candidate_indices;end
parfor (index=1:numel(candidates),workers)
 if ~ismember(index,selected),continue;end
 maxNumCompThreads(4);
 if candidates(index).sss_metric<opt.processing_sss_min_correlation
  failed{index}=add_rejected(struct([]),candidates(index),NaN,'sss_processing_quality_gate');continue;
 end
 try
  [one_frame,failed{index},candidate_diagnostics{index}]=process_candidate(candidates(index),index,v,a,opt,cfg,shared_channel);
  if ~isempty(one_frame),completed{index}=fullfile(cfg.run_dir,sprintf('frame_candidate_%02d.mat',index));end
 catch ME
  failed{index}=add_rejected(struct([]),candidates(index),NaN,['candidate_exception:' ME.identifier]);
  candidate_diagnostics{index}=struct('error_identifier',ME.identifier,'error_message',ME.message,'error_stack',ME.stack);
 end
end
% Release process workers before collecting the large saved intermediate arrays.
pool=gcp('nocreate');if workers>0 && ~isempty(pool),delete(pool);end
for index=1:numel(candidates)
 if ~isempty(completed{index})
  checkpoint=load(completed{index},'completed_frame');
  if isempty(frames),frames=checkpoint.completed_frame;else,frames(end+1)=checkpoint.completed_frame;end
  clear checkpoint;
 end
 if ~isempty(failed{index})
  if isempty(rejected),rejected=failed{index};else,rejected(end+1)=failed{index};end
 end
end
if ~isempty(frames),[~,order]=sort([frames.start_sample_capture]);frames=frames(order);end
frames=frame_guard_metrics(frames,Fs,F,y,v);
result=struct('role','codex_baseline','receiver_version','author-ml-v1','frames',frames,'quality',quality,...
 'rejected',rejected,'elapsed_seconds',toc,'input_diagnostics',input_diagnostics,'acquisition_scan',scan,...
 'candidate_diagnostics',{candidate_diagnostics},'shared_channel_diagnostics',shared_diagnostics,...
 'parameter_file','config/author_receiver_v1.json',...
 'algorithm_source','Qin journal VI-A-D and Qin PLANS2025 V-B-F; numerical implementation choices documented',...
 'author_results_used_as_receiver_inputs',false);
save(fullfile(cfg.run_dir,'result.mat'),'result','-v7.3');
summary=struct('role',result.role,'receiver_version',result.receiver_version,'quality',quality,'rejected',rejected,...
 'frame_count',numel(frames),'elapsed_seconds',result.elapsed_seconds,'estimates',[]);
if ~isempty(frames)
 fields={'grid_before','grid_resampled','grid_equalized','grid_after','channel_response','tracking','modulation','intermediates','sync_window_raw','sync_window_compensated','sync_local_curve'};
 summary.estimates=rmfield(frames,fields);
 for j=1:numel(summary.estimates)
  for name={'raw_guard','raw_preguard','nominal_guard','nominal_preguard'}
   summary.estimates(j).frame_guard.(name{1})=rmfield(summary.estimates(j).frame_guard.(name{1}),{'samples','sample_indices'});
  end
 end
end
write_json(fullfile(cfg.run_dir,'result.json'),summary);
figure('Visible','off');plot(ff/1e6,10*log10(P));grid on;xlabel('MHz');ylabel('PSD dB/Hz');exportgraphics(gcf,fullfile(cfg.run_dir,'iq_psd.png'));close(gcf);
end

function [f,bad,diagnostic]=process_candidate(f,index,v,a,opt,cfg,shared_channel)
F=240e6;bad=struct([]);diagnostic=[];
 fprintf('AUTHOR_FRAME candidate=%d start=%g\n',index,f.start_sample_nominal);
 sfo0=f.coarse_cfo_hz/opt.center_frequency_hz*1e6;
 [before,time_before]=author_receiver_dsp('extract_grid',v,f.start_sample_nominal,f.coarse_cfo_hz,0);
 [initial,time_initial]=author_receiver_dsp('extract_grid',v,f.start_sample_nominal,f.coarse_cfo_hz,sfo0);
 [Hfirst,chfirst]=author_receiver_dsp('channel',initial(:,1),a.sss_grid,a.freq,opt.smoothing_window,opt.smoothing_degree,shared_channel);
 first_eq=initial./Hfirst;[quick,seed_tracking]=pilot_seed(first_eq,a);
 quick_error=sqrt(mean(abs(quick(a.fit,2:301)-a.pilots(a.fit,2:301)).^2,'all'));
 diagnostic=struct('start_sample_nominal',f.start_sample_nominal,'coarse_sfo_ppm',sfo0,...
  'initial_pilot_fit_evm',quick_error,'pilot_seed_tracking',seed_tracking,'sync',f);
 if ~isfinite(quick_error) || quick_error>cfg.pilot_fit_evm_max
  bad=add_rejected(struct([]),f,quick_error,'initial_known_pilot_quality');f=[];return;
 end
 [~,first_tracking,first_mod]=author_receiver_dsp('frame_ml',first_eq,a,chfirst,opt,opt.seed+index*1000);
 beta_residual=first_tracking.delay_line_coefficients(1)/1056;
 sfo=((1+sfo0*1e-6)*(1-beta_residual)-1)*1e6;
 residual_cfo=first_tracking.phase_line_coefficients(1)*F*(1+sfo0*1e-6)/(2*pi*1056);
 cfo=f.coarse_cfo_hz+residual_cfo;
 assert(isfinite(sfo) && abs(sfo)<100,'author:SFO','Residual sample estimate outside model');
 [resampled,time_final]=author_receiver_dsp('extract_grid',v,f.start_sample_nominal,cfo,sfo);
 [H,ch]=author_receiver_dsp('channel',resampled(:,1),a.sss_grid,a.freq,opt.smoothing_window,opt.smoothing_degree,shared_channel);
 eq=resampled./H;
 [after,tracking,modulation]=author_receiver_dsp('frame_ml',eq,a,ch,opt,opt.seed+index*1000+500);
 fit_error=sqrt(mean(abs(after(a.fit,2:301)-a.pilots(a.fit,2:301)).^2,'all'));
 diagnostic.final_pilot_fit_evm=fit_error;
 if ~isfinite(fit_error) || fit_error>cfg.pilot_fit_evm_max
  bad=add_rejected(struct([]),f,fit_error,'author_ml_pilot_quality');f=[];return;
 end
 f.grid_before=before;f.grid_resampled=resampled;f.grid_equalized=eq;f.grid_after=after;
 f.channel_response=H;f.tracking=tracking;f.coarse_sfo_ppm=sfo0;f.sfo_ppm=sfo;
 f.residual_cfo_hz=residual_cfo;f.cfo_hz=cfo;f.pilot_fit_evm=fit_error;
 f.pilot_fit_rows=a.fit;f.pilot_eval_rows=a.eval;f.modulation=modulation;
 f.intermediates=struct('time_before',time_before,'time_initial_doppler',time_initial,...
  'time_final',time_final,'grid_initial_doppler',initial,'first_channel_response',Hfirst,...
  'grid_first_equalized',first_eq,'channel_first',chfirst,'channel_final',ch,...
  'first_ml_tracking',first_tracking,'first_modulation',first_mod,'pilot_seed_tracking',seed_tracking);
 % Preserve each completed candidate before proceeding to next costly frame.
 completed_frame=f;save(fullfile(cfg.run_dir,sprintf('frame_candidate_%02d.mat',index)),'completed_frame','-v7.3');
 fprintf('AUTHOR_FRAME_COMPLETED candidate=%d CFO=%.3f SFO=%.6f fitEVM=%.6f\n',index,cfo,sfo,fit_error);
end

function [frames,rejected,trace]=acquire(v,a,opt)
M=numel(v);F=240e6;seg=a.pss(161:288);score=zeros(M-1055,1);block=1000000;
for first=1:block:numel(score)
 last=min(numel(score),first+block-1);chunk=v(first:last+1055);nfft=2^nextpow2(numel(chunk)+127);
 c=ifft(fft(chunk,nfft).*fft(conj(flipud(seg)),nfft));c=c(128:numel(chunk));local=zeros(last-first+1,1);
 for j=0:7,local=local+abs(c(33+j*128+(0:numel(local)-1)));end
 energy=sqrt(movsum(abs(chunk).^2,[0 1055]));score(first:last)=local./max(energy(1:numel(local))*sqrt(128)*8,eps);
end
trace=struct('score_sample_nominal',(1:100:numel(score))','score_decimated',score(1:100:end),...
 'trace_decimation',100,'coarse_method','PSS repeat-magnitude proposals; acceptance uses coherent PSS+SSS CAF');
frames=struct([]);rejected=struct([]);reference=[a.pss;a.sss];
for attempt=1:36
 [coarse,b]=max(score);if coarse<.07,break;end
 score(max(1,b-1100):min(numel(score),b+1100))=0;
 if ~isempty(frames) && any(abs([frames.start_sample_nominal]-b)<200000),continue;end
 best=-Inf;bs=NaN;bf=NaN;
 for offset=-1024:128:1024
  s=b+offset;if s<1 || s+2111>M,continue;end
  zz=reshape(v(s+32+(0:1023)),128,8);zz(:,1)=-zz(:,1);
  repetition=sum(zz(:,2:end).*conj(zz(:,1:end-1)),'all');f0=angle(repetition)*F/(2*pi*128);
  for alias=-2:2
   cf=f0+alias*F/128;
   for dt=-4:4
    st=s+dt;if st<1 || st+2111>M,continue;end
    w=v(st+(0:2111)).*exp(-1j*2*pi*cf*(0:2111)'/F);
    val=abs(reference'*w)/(norm(reference)*norm(w)+eps);
    if val>best,best=val;bs=st;bf=cf;end
   end
  end
 end
 if ~isfinite(bs),continue;end
 raw=v(bs+(0:2111));n=(0:2111)'/F;
 bf=fminbnd(@(f)-abs(reference'*(raw.*exp(-1j*2*pi*f*n)))^2,bf-10000,bf+10000,optimset('TolX',.001,'Display','off'));
 w=raw.*exp(-1j*2*pi*bf*n);
 pm=abs(a.pss'*w(1:1056))/(norm(a.pss)*norm(w(1:1056))+eps);
 sm=abs(a.sss'*w(1057:2112))/(norm(a.sss)*norm(w(1057:2112))+eps);
 f=struct('start_sample_nominal',bs,'start_sample_capture',(bs-1)*250/240+1,...
  'coarse_cfo_hz',bf,'pss_metric',pm,'sss_metric',sm,'coarse_metric',coarse,...
  'coherent_pss_sss_metric',abs(reference'*w)/(norm(reference)*norm(w)+eps));
 if pm<.08 || sm<.05 || bs+302*1056+64>M
  rejected=add_rejected(rejected,f,NaN,'sync_or_incomplete_window');continue;
 end
 lags=-8:8;pc=zeros(size(lags));sc=pc;combined=pc;
 for j=1:numel(lags)
  if bs+lags(j)<1 || bs+lags(j)+2111>M,continue;end
  z=v(bs+lags(j)+(0:2111)).*exp(-1j*2*pi*bf*n);
  pc(j)=abs(a.pss'*z(1:1056))/(norm(a.pss)*norm(z(1:1056))+eps);
  sc(j)=abs(a.sss'*z(1057:2112))/(norm(a.sss)*norm(z(1057:2112))+eps);
  combined(j)=abs(reference'*z)/(norm(reference)*norm(z)+eps);
 end
 f.sync_window_raw=raw;f.sync_window_compensated=w;
 f.sync_local_curve=struct('lag_model_samples',lags,'pss',pc,'sss',sc,'coherent_pss_sss',combined,'cfo_hz',bf);
 if isempty(frames),frames=f;else,frames(end+1)=f;end
 if numel(frames)>=opt.max_candidates,break;end
end
end
function [corrected,t]=pilot_seed(grid,a)
q=grid(a.fit,2:301)./a.pilots(a.fit,2:301);l=unwrap(angle(mean(q(1:4,:),1)));r=unwrap(angle(mean(q(5:8,:),1)));
x=1:300;lf=polyval(polyfit(x,l,1),x);rf=polyval(polyfit(x,r,1),x);
kl=mean(a.freq(a.fit(1:4)));kr=mean(a.freq(a.fit(5:8)));slope=(rf-lf)/(kr-kl);phase=(lf*kr-rf*kl)/(kr-kl);
corrected=grid;corrected(:,2:301)=grid(:,2:301).*exp(-1j*(a.freq*slope+ones(1024,1)*phase));
t=struct('raw_left_phase_rad',l,'raw_right_phase_rad',r,'phase_line_rad',phase,'delay_line_samples',-slope*1024/(2*pi),...
 'role','initialization and candidate quality only; final correction is unknown-data ML','fit_rows',a.fit,'heldout_excluded',a.eval);
end
function [shared,d]=shared_sss_channel(v,frames,a,opt)
% Journal VI-B permits refining receiver/satellite/band H with successive SSS.
% Only independently acquired, high-correlation SSS windows enter this fit.
rows=a.active(:);sum_h=zeros(1024,1);weight=0;indices=[];individual=cell(1,numel(frames));weights=[];
for j=1:numel(frames)
 f=frames(j);if f.sss_metric<opt.shared_sss_channel_min_correlation,continue;end
 sfo=f.coarse_cfo_hz/opt.center_frequency_hz*1e6;offset=(1056:2111)'/(1+sfo*1e-6);
 w=bandlimited_sample(v,f.start_sample_nominal+offset).*exp(-1j*2*pi*f.coarse_cfo_hz*offset/240e6);
 Y=fft(w(33:end))/32;
 [~,ch]=author_receiver_dsp('channel',Y,a.sss_grid,a.freq,opt.smoothing_window,opt.smoothing_degree);
 wgt=f.sss_metric^2;sum_h=sum_h+wgt*ch.channel_normalized;weight=weight+wgt;
 indices(end+1)=j;individual{j}=ch;weights(end+1)=wgt;
end
if weight==0,shared=[];else,shared=sum_h/weight;end
d=struct('source','Journal VI-B repeated-SSS channel refinement','candidate_indices',indices,...
 'correlation_weights',weights,'normalized_shared_channel',shared,'individual_sss_estimates',{individual},...
 'minimum_sss_correlation',opt.shared_sss_channel_min_correlation,'reference_only','Known SSS; no data-pilot heldout or author decisions used',...
 'assumption','Normalized response stable across selected short-capture candidates; satellite/beam identity not independently established');
end
function rejected=add_rejected(rejected,f,evm,reason)
bad=struct('start_sample_nominal',f.start_sample_nominal,'start_sample_capture',f.start_sample_capture,...
 'pss_metric',f.pss_metric,'sss_metric',f.sss_metric,'pilot_fit_evm',evm,'reason',reason);
if isempty(rejected),rejected=bad;else,rejected(end+1)=bad;end
end
function write_json(path,value)
fid=fopen(path,'w');assert(fid>=0);fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));fclose(fid);
end
