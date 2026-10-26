function evaluation = evaluate_receiver(cfg)
% Independent scorer: reads computed arrays and private truth, never trusts result.json.
root=cfg.root; th=jsondecode(fileread(fullfile(root,'config','evaluation.json')));
addpath(fullfile(root,'matlab','baseline')); a=author_sequences(root);
if isfield(cfg,'result_path'), rp=cfg.result_path; else, rp=fullfile(cfg.run_dir,'result.mat'); end
D=load(rp); if isfield(D,'result'), R=D.result; else, R=D; end
if isfield(R,'frames'), frames=R.frames;
else
 if isfield(R,'grids'), G=R.grids; else, G=R.Z; end
 starts=R.starts0+1; frames=struct([]);
 for j=1:size(G,3)
  f=struct('grid_after',G(:,:,j),'start_sample_capture',starts(j),'cfo_hz',R.cfo_hz(min(j,end)),...
    'sfo_ppm',NaN,'pss_metric',NaN,'sss_metric',NaN,'pilot_fit_rows',[],'pilot_eval_rows',a.eval);
  if isfield(R,'grid_before'), f.grid_before=R.grid_before(:,:,j); end
  if isfield(R,'sfo_ppm'), f.sfo_ppm=R.sfo_ppm(min(j,end)); end
  if isempty(frames), frames=f; else, frames(end+1)=f; end
 end
end
mode=cfg.data_type; isreal=strcmp(mode,'real_iq');
if ~isreal
 if isfield(cfg,'truth_path'), tp=cfg.truth_path; else, tp=fullfile(root,'matlab','evaluation','private','synthetic_holdout_truth.mat'); end
 T=load(tp,'truth'); T=T.truth;
else
 % This privileged reader is deliberately absent from demo_receiver.
 info=jsondecode(fileread(fullfile(root,'data','raw','exemplar250-257','sliceInfo.json')));
 T=struct();
end
metrics=struct([]); allpass=true; used=[];
for j=1:numel(frames)
 f=frames(j); failures={}; shapeok=isequal(size(f.grid_after),[1024 301]);
 if ~shapeok, failures{end+1}='grid_shape'; end
 splitok=isfield(f,'pilot_fit_rows') && ~isempty(f.pilot_fit_rows) && isempty(intersect(f.pilot_fit_rows,a.eval));
 if ~splitok, failures{end+1}='heldout_pilot_leakage_or_missing_fit_declaration'; end
 [pm,sm]=independent_sync(cfg,f,a); 
 if ~isfinite(pm)||pm<th.pss_correlation_min, failures{end+1}='pss_proof'; end
 if ~isfinite(sm)||sm<th.sss_correlation_min, failures{end+1}='sss_proof'; end
 m=struct('frame',j,'start_sample_capture',f.start_sample_capture,'shape_ok',shapeok,'pilot_split_ok',splitok,...
 'pss_correlation',pm,'sss_correlation',sm,'cfo_hz',getnum(f,'cfo_hz'),'sfo_ppm',getnum(f,'sfo_ppm'));
 if shapeok
  if any(~isfinite(f.grid_after),'all'), failures{end+1}='nonfinite_grid'; end
  target=a.pilots(a.eval,2:end); Z=f.grid_after(a.eval,2:end);
  m.heldout_pilot_evm_after=sqrt(mean(abs(Z-target).^2,'all')/mean(abs(target).^2,'all'));
  if norm(Z,'fro')<=eps*norm(target,'fro'), failures{end+1}='degenerate_zero_pilot_grid'; end
  m.heldout_pilot_evm_before=NaN;
  if isfield(f,'grid_before') && isequal(size(f.grid_before),[1024 301])
   B=f.grid_before; active=3:1022;
   gain=sum(conj(a.sss_grid(active)).*B(active,1))/sum(abs(a.sss_grid(active)).^2);
   if abs(gain)>1e-6, m.heldout_pilot_evm_before=sqrt(mean(abs(B(a.eval,2:end)/gain-target).^2,'all')); end
  end
  m.relative_pilot_evm_improvement=1-m.heldout_pilot_evm_after/m.heldout_pilot_evm_before;
  if ~isfinite(m.heldout_pilot_evm_after), failures{end+1}='nonfinite_evm'; end
  if isreal
   capture_samples=12500000;
   required_capture_samples=ceil(302*1056*250e6/240e6);
   if ~isfinite(f.start_sample_capture) || f.start_sample_capture<1 || f.start_sample_capture-1+required_capture_samples>capture_samples
    failures{end+1}='incomplete_real_frame';
   end
   if m.heldout_pilot_evm_after>th.real_iq.heldout_pilot_evm_max, failures{end+1}='real_pilot_evm'; end
   if ~isfinite(m.relative_pilot_evm_improvement)||m.relative_pilot_evm_improvement<th.real_iq.relative_pilot_evm_improvement_min
    failures{end+1}='real_pilot_improvement';
   end
  else
   [terr,idx]=min(abs(T.starts_capture-f.start_sample_capture));
   if ismember(idx,used), failures{end+1}='duplicate_truth_frame'; end; used(end+1)=idx;
   ref=T.grid(:,:,idx); idxactive=3:1022;
   m.grid_evm=sqrt(mean(abs(f.grid_after(idxactive,:)-ref(idxactive,:)).^2,'all')/mean(abs(ref(idxactive,:)).^2,'all'));
   m.timing_error_samples=terr; m.cfo_error_hz=abs(m.cfo_hz-T.cfo_hz); m.sfo_error_ppm=abs(m.sfo_ppm-T.sfo_ppm);
   if isinf(T.snr_db), lim=th.synthetic.noiseless_grid_evm_max; else, lim=th.synthetic.impaired_grid_evm_max; end
   if ~isfinite(m.grid_evm)||m.grid_evm>lim, failures{end+1}='synthetic_grid_evm'; end
   if m.heldout_pilot_evm_after>th.synthetic.pilot_evm_max, failures{end+1}='synthetic_pilot_evm'; end
   if terr>th.synthetic.timing_error_samples_max, failures{end+1}='synthetic_timing'; end
   if ~isfinite(m.cfo_error_hz)||m.cfo_error_hz>th.synthetic.cfo_error_hz_max, failures{end+1}='synthetic_cfo'; end
   if ~isfinite(m.sfo_error_ppm)||m.sfo_error_ppm>th.synthetic.sfo_error_ppm_max, failures{end+1}='synthetic_sfo'; end
  end
  if ~isfield(cfg,'make_plots') || cfg.make_plots
  figure('Visible','off'); tiledlayout(1,2);
  nexttile; if isfield(f,'grid_before'), before=f.grid_before(a.eval,2:end); plot(real(before(:)),imag(before(:)),'.'); end
  title('Before: heldout pilot rows'); axis equal; grid on;
  nexttile; plot(real(Z(:)),imag(Z(:)),'.'); hold on; plot(real(target(:)),imag(target(:)),'ko');
  title(sprintf('After: EVM %.3f',m.heldout_pilot_evm_after)); axis equal; grid on;
  exportgraphics(gcf,fullfile(cfg.run_dir,sprintf('pilot_evm_frame_%d.png',j))); close(gcf);
  end
 end
 m.failures=failures; m.accepted=isempty(failures); allpass=allpass && m.accepted; if isempty(metrics), metrics=m; else, metrics(end+1)=m; end
end
countok=numel(frames)>=th.minimum_frames;
evaluation=struct('schema_version',1,'evaluator','independent_array_recomputation','mode',mode,...
 'role',field_or(R,'role','agent'),'frame_count',numel(frames),'minimum_frame_count_pass',countok,...
 'accepted',allpass&&countok,'metrics',metrics,'threshold_file','config/evaluation.json',...
 'evaluation_version',th.evaluation_version);
if isreal
 evaluation.reference_metadata_fields=fieldnames(info); evaluation.reference_metadata_used_for_detection=false;
 % TOA conventions in slice metadata are checked when explicit sample positions exist.
 evaluation.real_payload_ber_available=false;
 evaluation.annotation_toa_s=info.frameSet.toa_s;
 used_annotations=[]; matched_count=0;
 for j=1:numel(metrics)
  errs=abs(metrics(j).start_sample_capture-1-info.frameSet.toa_s*250e6);
  [evaluation.metrics(j).annotation_timing_error_samples,ix]=min(errs);
  matched=isfinite(evaluation.metrics(j).annotation_timing_error_samples) && evaluation.metrics(j).annotation_timing_error_samples<=th.real_iq.timing_reference_tolerance_samples;
  evaluation.metrics(j).nearest_annotation_frame_index=info.frameSet.index(ix);
  evaluation.metrics(j).annotation_frame_index=NaN;
  evaluation.metrics(j).annotation_status='unmatched_candidate';
  evaluation.metrics(j).evaluation_holdout=false;
  if ~matched, continue; end
  evaluation.metrics(j).annotation_frame_index=info.frameSet.index(ix);
  evaluation.metrics(j).annotation_status='matched';
  if ismember(ix,used_annotations)
   evaluation.metrics(j).failures{end+1}='duplicate_real_frame';
   evaluation.metrics(j).accepted=false;
   evaluation.accepted=false;
  elseif evaluation.metrics(j).accepted
   used_annotations(end+1)=ix; matched_count=matched_count+1;
  end
  % Split by chronological annotation ordinal, independent of detection order.
  evaluation.metrics(j).evaluation_holdout=ix>2 && ix<numel(info.frameSet.index);
 end
 evaluation.matched_annotation_count=matched_count;
 evaluation.unmatched_candidate_count=sum(strcmp({evaluation.metrics.annotation_status},'unmatched_candidate'));
 evaluation.minimum_frame_count_pass=matched_count>=th.minimum_frames;
 evaluation.holdout_matched_count=sum([evaluation.metrics.evaluation_holdout] & [evaluation.metrics.accepted]);
 evaluation.accepted=evaluation.accepted && evaluation.minimum_frame_count_pass && evaluation.holdout_matched_count>=1;
 evaluation.annotation_policy='Only tolerance-matched valid frames count toward annotated acceptance. Unlisted candidates remain separately reported; no forced assignment.';
end
if evaluation.accepted, evaluation.status='passed'; else, evaluation.status='failed'; end
fid=fopen(fullfile(cfg.run_dir,'evaluation.json'),'w'); fprintf(fid,'%s\n',jsonencode(evaluation,'PrettyPrint',true)); fclose(fid);
save(fullfile(cfg.run_dir,'evaluation.mat'),'evaluation');
fprintf('INDEPENDENT EVALUATION accepted=%d frames=%d\n',evaluation.accepted,numel(frames));
end
function n=getnum(s,k)
if isfield(s,k), n=s.(k); else, n=NaN; end
end
function v=field_or(s,k,default)
if isfield(s,k), v=s.(k); else, v=default; end
end

function [pm,sm]=independent_sync(cfg,f,a)
pm=NaN; sm=NaN;
if ~isfield(cfg,'input_path'), cfg.input_path=cfg.input_mat; end
ip=cfg.input_path; if ~startsWith(ip,'/'), ip=fullfile(cfg.root,ip); end
if strcmp(cfg.data_type,'synthetic')
 D=load(ip,'y','Fs'); Fs=D.Fs; source=D.y;
 start=floor(f.start_sample_capture)-128; start=max(1,start); stop=min(numel(source),start+2500);
 y=source(start:stop);
else
 Fs=250e6; start=max(1,floor(f.start_sample_capture)-128); fid=fopen(ip,'r','ieee-le');
 fseek(fid,4*(start-1),'bof'); z=fread(fid,[2 2501],'int16=>double'); fclose(fid); y=complex(z(1,:),z(2,:)).'/32768;
end
[p,q]=rat(240e6/Fs); y=resample(y,p,q,50);
position=(f.start_sample_capture-start)*240e6/Fs+1; n=(0:2111)';
if position+2111>numel(y), return; end
w=bandlimited_sample(y,position+n).*exp(-1j*2*pi*f.cfo_hz*n/240e6);
pm=abs(a.pss'*w(1:1056))/(norm(a.pss)*norm(w(1:1056))+eps);
sm=abs(a.sss'*w(1057:2112))/(norm(a.sss)*norm(w(1057:2112))+eps);
end
