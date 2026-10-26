function check=test_author_payload_artifacts(root,run_dir,out)
% Check author decisions against received grids; no modulation/bit truth used.
% A root-only call exercises an independent small fixture before a real run.
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
if nargin<2
 [run_dir,out]=fixture(root);
 cfg=struct('root',root,'run_dir',run_dir,'out',out,'frame_index',1,'make_plots',false);
 export_author_payload(cfg);
end
A=load(fullfile(out,'analysis_data.mat'));
S=load(fullfile(out,'symbol_candidates.mat'),'symbols');S=S.symbols;
H=load(fullfile(out,'symbol_decisions.mat'),'decisions');H=H.decisions;
F=load_payload_frame(run_dir,S.frame_index);
a=author_sequences(root);rows=setdiff(a.active,a.rows);[~,order]=sort(a.freq(rows));rows=rows(order);
models=payload_models();column_ids=double(F.modulation.geometry_id_per_data_symbol(:).');
gain=F.modulation.gain_per_data_symbol(:).';noise=F.intermediates.channel_final.noise_variance_equalized(rows);
assert(isequal(size(A.Z),[1004 300]) && isequal(size(A.map),[5 300]));
assert(isequal(A.rows,rows) && isequal(A.Z,F.grid_after(rows,2:301)),...
 'payload:AuthorSource','Exported samples differ from source grid');
assert(isequal(S.payload_matlab_rows,rows) && isequal(S.source_grid_columns,2:301));
assert(isequal(S.frequency_bins_signed,a.freq(rows)) && issorted(S.frequency_bins_signed));
assert(isequal(S.candidate_geometries,models) && all(cellfun(@(c)abs(mean(abs(c).^2)-1)<1e-12,models)));
assert(isequal(A.author_records,F.modulation.records));
assert(isequal(A.cardinality_scores,F.modulation.cardinality_scores));
assert(isequal(A.map,repmat(column_ids,5,1)),...
 'payload:AuthorRegions','Display regions must inherit whole-symbol classification');
assert(isequal(sort([A.groups{2:5}]),1:numel(rows)) && isequal(A.groups{1},1:numel(rows)));
for symbol=1:300
 id=column_ids(symbol);
 assert(all(S.geometry_id(:,symbol)==id));
 for region=1:5
  r=A.records{region,symbol};
  assert(r.label_id==id && r.best_id==id && r.phase_deg==0);
  assert(r.sample_count==numel(A.groups{region}));
  assert(strcmp(r.region_classification_source,'whole_author_symbol'));
 end
 if id==0
  assert(all(S.erasure_mask(:,symbol)) && all(S.geometric_point_id_0based(:,symbol)==-1));
  assert(all(~H.valid_mask(:,symbol)) && all(isnan(H.hard_symbols(:,symbol))));
  assert(all(H.point_id_0based(:,symbol)==-1) && all(S.conditional_model_posterior(:,symbol)==0));
  continue;
 end
 z=A.Z(:,symbol);c=models{id};distance=abs(z-gain(symbol)*c.').^2;
 [closest,ids]=min(distance,[],2);
 weight=exp(-(distance-closest)./max(noise,eps));probability=max(weight./sum(weight,2),[],2);
 assert(isequal(S.geometric_point_id_0based(:,symbol),int16(ids-1)));
 assert(max(abs(S.conditional_model_posterior(:,symbol)-probability))<1e-12);
 assert(all(~S.erasure_mask(:,symbol)) && all(H.valid_mask(:,symbol)),...
  'payload:AuthorPosterior','Author nearest decisions must not be erased by posterior');
 assert(isequal(H.point_id_0based(:,symbol),int16(ids-1)));
 assert(max(abs(H.hard_symbols(:,symbol)-c(ids)))<1e-12);
 assert(max(abs(H.hard_symbols_observed_scale(:,symbol)-gain(symbol)*c(ids)))<1e-12);
 assert(max(abs(S.candidate_point(:,symbol)-gain(symbol)*c(ids)))<1e-12);
end
expected_payload=false(1024,301);expected_payload(rows,2:301)=true;
expected_valid=false(1024,301);expected_valid(rows,2:301)=repmat(column_ids>0,1004,1);
assert(isequal(H.payload_mask,expected_payload) && isequal(H.valid_grid_mask,expected_valid));
assert(isequaln(H.hard_grid(rows,2:301),H.hard_symbols));
assert(isequaln(H.hard_grid_observed_scale(rows,2:301),H.hard_symbols_observed_scale));
assert(all(isnan(H.hard_grid(~expected_valid))) && all(~H.valid_grid_mask(~expected_payload)));
assert(H.minimum_model_posterior==0 && H.valid_count==nnz(expected_valid));
assert(H.erased_count==1004*nnz(column_ids==0) && H.unknown_geometry_count==H.erased_count);
assert(H.low_reliability_count==0 && H.total_count==301200);
assert(H.frame_index==S.frame_index && H.source_start_sample_capture==F.start_sample_capture);
p=F.grid_after(a.eval,2:301);reference=a.pilots(a.eval,2:301);c=models{2};
[~,predicted]=min(abs(p(:)-c.').^2,[],2);[~,truth]=min(abs(reference(:)-c.').^2,[],2);
errors=reshape(predicted~=truth,size(reference));
assert(isequal(H.heldout_pilot.matlab_rows,a.eval) && H.heldout_pilot.symbol_count==2400);
assert(~any(H.payload_mask(a.eval,:),'all') && ~any(H.payload_mask(a.fit,:),'all'));
assert(isequal(H.heldout_pilot.received,p) && isequal(H.heldout_pilot.reference,reference));
assert(isequal(H.heldout_pilot.error_mask,errors) && H.heldout_pilot.error_count==nnz(errors));
assert(abs(H.heldout_pilot.SER-mean(errors,'all'))<eps);
assert(isequal(H.heldout_pilot.hard_symbols,reshape(c(predicted),size(reference))));
B=jsondecode(fileread(fullfile(out,'explorer_data.json')));
assert(isequal(B.map,A.map) && isequal(size(B.I),size(A.Z)) && isequal(B.decision_valid,H.valid_mask));
assert(max(abs(B.I-real(A.Z)),[],'all')<=5.1e-6 && max(abs(B.Q-imag(A.Z)),[],'all')<=5.1e-6);
J=jsondecode(fileread(fullfile(out,'decisions.json')));
assert(J.valid_decision_count==H.valid_count && J.erased_count==H.erased_count);
assert(J.heldout_pilot_symbol_count==2400 && J.heldout_pilot_error_count==nnz(errors));
check=struct('status','passed','method_version','author-ml-v1',...
 'scope','Author geometric decisions checked against original samples; no payload bit truth',...
 'regions_checked',1500,'symbol_array_entries_checked',numel(A.Z),...
 'whole_symbol_label_counts',arrayfun(@(id)nnz(column_ids==id),0:4),...
 'source_grid_preserved',true,'whole_symbol_regions_inherited',true,...
 'geometric_decisions_consistent',true,'hard_symbols_and_erasures_consistent',true,...
 'valid_hard_symbol_count',H.valid_count,'unknown_columns',find(column_ids==0),...
 'heldout_pilot_symbol_count',2400,'heldout_pilot_SER_independently_recomputed',true,...
 'real_modulation_truth_available',false,'business_bits_verified',false);
fid=fopen(fullfile(out,'artifact_check.json'),'w');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(check));clear cleanup;
fprintf('AUTHOR_PAYLOAD_ARTIFACT_CHECK_PASSED regions=1500 entries=%d\n',numel(A.Z));
end

function [run_dir,out]=fixture(root)
a=author_sequences(root);C=payload_models();rows=setdiff(a.active,a.rows);
ids=repmat(1:4,1,75);ids([5 77 300])=0;gains=.7+.6*(0:299)/299;
grid=complex(zeros(1024,301));grid(:,1)=a.sss_grid;
for symbol=1:300
 if ids(symbol)==0,grid(rows,symbol+1)=.2+.1j;continue;end
 c=C{ids(symbol)};index=mod((0:numel(rows)-1)',numel(c))+1;
 grid(rows,symbol+1)=gains(symbol)*c(index)+.003*(1+1j);
end
% A QPSK point at the origin has posterior 1/4 yet is a valid nearest decision.
grid(rows(1),2)=0;grid(a.rows,2:301)=a.pilots(a.rows,2:301);
grid(a.eval(1),2)=-grid(a.eval(1),2);
records=cell(1,300);
for symbol=1:300,records{symbol}=struct('cardinality',numel(C{max(ids(symbol),1)}),'symbol_index',symbol);end
f=struct('grid_after',grid,'start_sample_capture',12345,...
 'modulation',struct('method_version','author-ml-v1','geometry_id_per_data_symbol',ids,...
 'gain_per_data_symbol',gains,'cardinality_scores',repmat([.8;.2;.4;.3],1,300),'records',{records}),...
 'intermediates',struct('channel_final',struct('noise_variance_equalized',linspace(.01,.2,1024)')));
result=struct('frames',f);run_dir=tempname;mkdir(run_dir);out=fullfile(run_dir,'payload');mkdir(out);
save(fullfile(run_dir,'result.mat'),'result','-v7');
end
