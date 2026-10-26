function summary=export_author_payload(cfg,f)
% Export the receiver's author-method classification and nearest hard symbols.
% Display quarters inherit whole-symbol labels; they are not new classifiers.
root=cfg.root;out=cfg.out;started=tic;
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
if nargin<2
 f=load_payload_frame(cfg.run_dir,cfg.frame_index);
end
assert(strcmp(f.modulation.method_version,'author-ml-v1'));
assert(isequal(size(f.grid_after),[1024 301]));
a=author_sequences(root);rows=setdiff(a.active,a.rows);[~,order]=sort(a.freq(rows));rows=rows(order);
Z=f.grid_after(rows,2:301);assert(isequal(size(Z),[1004 300]) && all(isfinite(Z),'all'));
types=double(f.modulation.geometry_id_per_data_symbol(:).');
gains=f.modulation.gain_per_data_symbol(:).';
assert(numel(types)==300 && all(ismember(types,0:4)) && numel(gains)==300);
assert(all(isfinite(gains(types>0))) && all(gains(types>0)>0));
assert(isequal(size(f.modulation.cardinality_scores),[4 300]) && numel(f.modulation.records)==300);
noise=f.intermediates.channel_final.noise_variance_equalized(rows);
assert(numel(noise)==1004 && all(isfinite(noise)) && all(noise>=0));noise=max(noise(:),eps);
opt=jsondecode(fileread(fullfile(root,'config','payload_analysis_v1.json')));
opt.legacy_geometry_config_version=opt.version;opt.version='author-ml-v1';
opt.minimum_point_posterior=0;
opt.classification_method='Receiver k-means cardinality and marginalized ML; no export-time refit';
opt.region_classification_source='whole_author_symbol';
opt.notes='Whole-symbol author classifications inherited by display quarters; posterior is diagnostic and never erases a known column.';
C=payload_models();names=opt.candidate_names;
count=numel(rows);bounds=round(linspace(0,count,5));groups={1:count};
for region=1:4,groups{region+1}=bounds(region)+1:bounds(region+1);end
map=repmat(types,5,1);records=cell(5,300);
geometry_id=repmat(uint8(types),count,1);point_id=-ones(size(Z),'int16');
posterior=zeros(size(Z));candidate_point=complex(nan(size(Z)),nan(size(Z)));
erasure=repmat(types==0,count,1);
for symbol=1:300
 id=types(symbol);minimum=nan(count,1);assigned=zeros(count,1);
 if id>0
  c=C{id};distance=abs(Z(:,symbol)-gains(symbol)*c.').^2;
  [minimum,assigned]=min(distance,[],2);
  weights=exp(-(distance-minimum)./noise);weights=weights./sum(weights,2);
  posterior(:,symbol)=max(weights,[],2);
  point_id(:,symbol)=int16(assigned-1);candidate_point(:,symbol)=gains(symbol)*c(assigned);
 end
 for region=1:5
  rr=groups{region};r=display_record(id,numel(rr),gains(symbol),mean(noise(rr)),names);
  r.source_record_index=symbol;r.cardinality_scores=f.modulation.cardinality_scores(:,symbol).';
  if isstruct(f.modulation.records{symbol}) && isfield(f.modulation.records{symbol},'cardinality')
   r.cardinality=f.modulation.records{symbol}.cardinality;
  end
  if id>0
   r.decision_evm=sqrt(mean(minimum(rr)))/gains(symbol);
   r.occupied_fraction=numel(unique(assigned(rr)))/numel(C{id});
   r.mean_conditional_model_posterior=mean(posterior(rr,symbol));
  end
  records{region,symbol}=r;
 end
end
symbols=struct('payload_matlab_rows',rows,'data_symbol_indices',1:300,'geometry_id',geometry_id,...
 'frame_index',cfg.frame_index,'source_start_sample_capture',f.start_sample_capture,...
 'source_grid_columns',2:301,'frequency_bins_signed',a.freq(rows),'model_fs_hz',240e6,...
 'geometric_point_id_0based',point_id,'candidate_point',candidate_point,'erasure_mask',erasure,...
 'conditional_model_posterior',posterior,'candidate_geometries',{C},...
 'method_version','author-ml-v1','gain_per_data_symbol',gains,...
 'point_order_status','Internal geometric order only; NOT Starlink bits/Gray order',...
 'posterior_role','Diagnostic under the selected geometry; no posterior erasures',...
 'business_bits_available',false,'real_SER_available',false,'real_BER_available',false);
save(fullfile(out,'symbol_candidates.mat'),'symbols','-v7');
decisions=payload_hard_decision(symbols,0);
decisions.version='author-nearest-symbol-v1';
decisions.method_version='author-ml-v1';decisions.frame_index=cfg.frame_index;
decisions.source_start_sample_capture=f.start_sample_capture;
decisions.frequency_bins_signed=a.freq(rows);decisions.model_fs_hz=240e6;
decisions.gain_per_data_symbol=gains;decisions.region_classification_source='whole_author_symbol';
decisions.posterior_role=symbols.posterior_role;
% These received heldout pilots are evaluated after reception, without fitting.
received=f.grid_after(a.eval,2:301);reference=a.pilots(a.eval,2:301);c=C{2};
[~,predicted]=min(abs(received(:)-c.').^2,[],2);
[reference_distance,truth]=min(abs(reference(:)-c.').^2,[],2);
assert(max(reference_distance)<1e-20,'payload:PilotReference','Pilot reference differs from 4QAM geometry');
pilot_error=reshape(predicted~=truth,size(reference));
decisions.heldout_pilot=struct('matlab_rows',a.eval,'source_grid_columns',2:301,...
 'received',received,'reference',reference,'hard_symbols',reshape(c(predicted),size(reference)),...
 'error_mask',pilot_error,'error_count',nnz(pilot_error),'symbol_count',numel(pilot_error),...
 'SER',mean(pilot_error,'all'),'scope','Known eight heldout pilots only; not payload SER');
save(fullfile(out,'symbol_decisions.mat'),'decisions','-v7');
decision_summary=struct('version',decisions.version,'method_version','author-ml-v1','frame_index',cfg.frame_index,...
 'payload_resource_count',decisions.total_count,'valid_decision_count',decisions.valid_count,...
 'erased_count',decisions.erased_count,'unknown_geometry_count',decisions.unknown_geometry_count,...
 'low_model_reliability_count',decisions.low_reliability_count,'minimum_conditional_model_posterior',0,...
 'unknown_data_symbol_indices',find(types==0),'posterior_role',symbols.posterior_role,...
 'heldout_pilot_error_count',nnz(pilot_error),'heldout_pilot_symbol_count',numel(pilot_error),...
 'heldout_pilot_SER',mean(pilot_error,'all'),...
 'scope','Author nearest geometric symbols; unknown/composite columns erased; known-pilot SER is not payload SER',...
 'business_bits_available',false,'real_payload_SER_available',false,'real_payload_BER_available',false,...
 'FEC_H_status','unknown','codeblock_boundaries_status','unknown','bit_map_status','unknown','scrambler_status','unknown');
writejson(fullfile(out,'decisions.json'),decision_summary);
author_records=f.modulation.records;cardinality_scores=f.modulation.cardinality_scores;
save(fullfile(out,'analysis_data.mat'),'records','map','Z','rows','groups','opt','author_records','cardinality_scores','-v7');
band_frequency_mhz=cell(1,5);
for region=1:5
 bins=a.freq(rows(groups{region}));band_frequency_mhz{region}=[min(bins) max(bins)]*240e6/1024/1e6;
end
browser=struct('version','author-ml-v1','method_version','author-ml-v1','frame_index',cfg.frame_index,...
 'map',map,'records',{records},'I',round(real(Z),5),'Q',round(imag(Z),5),...
 'groups0',{cellfun(@(rr)rr-1,groups,'UniformOutput',false)},...
 'band_frequency_mhz',{band_frequency_mhz},'candidate_names',{names},...
 'model_real',{cellfun(@real,C,'UniformOutput',false)},'model_imag',{cellfun(@imag,C,'UniformOutput',false)},...
 'hard_I',round(real(decisions.hard_symbols),5),'hard_Q',round(imag(decisions.hard_symbols),5),...
 'decision_valid',decisions.valid_mask,'decision_summary',decision_summary,...
 'region_classification_source','whole_author_symbol',...
 'scope','Receiver author-method whole-symbol labels; display quarters inherit labels; no extra sample-split validation or payload bit truth');
writejson(fullfile(out,'explorer_data.json'),browser);
counts=arrayfun(@(id)nnz(types==id),0:4);
summary=struct('status','created','version','author-ml-v1','method_version','author-ml-v1',...
 'frame_index',cfg.frame_index,'analyzed_data_symbols',300,'region_count',5,...
 'symbol_counts_unknown_qpsk_4qam_16qam_cross32',counts,'frequency_inconsistency_symbols',[],...
 'region_classification_source','whole_author_symbol','classified_resource_fraction',mean(geometry_id>0,'all'),...
 'internally_supported_resource_fraction',mean(geometry_id>0,'all'),'not_erased_resource_fraction',mean(~erasure,'all'),...
 'scope','Author whole-symbol classification and nearest decisions; regional labels inherited, no separate regional model validation',...
 'FEC_status','unknown','bit_map_status','unknown','scrambler_status','unknown',...
 'codeblock_boundary_status','unknown','resource_bit_order_status','unknown','fec_parity_check_H_status','unknown',...
 'hard_decision_summary',decision_summary,'real_payload_bits_available',false,'SER_available',false,'BER_available',false);
if ~isfield(cfg,'make_plots') || cfg.make_plots,render(out,cfg.frame_index,Z,map,records,C,decisions);end
summary.elapsed_s=toc(started);writejson(fullfile(out,'analysis.json'),summary);
fprintf('AUTHOR_PAYLOAD_EXPORTED counts=%s valid=%d erased=%d\n',mat2str(counts),decisions.valid_count,decisions.erased_count);
end

function r=display_record(id,count,gain,variance,names)
r=struct('label_id',id,'best_id',id,'label','unknown','status','author_unknown_or_composite',...
 'sample_count',count,'scores_validation',nan(1,4),'scores_test',nan(1,4),...
 'score_gap',NaN,'test_score_gap',NaN,'decision_evm',NaN,'occupied_fraction',NaN,...
 'mean_validation_posterior',NaN,'mean_conditional_model_posterior',NaN,...
 'gain',gain,'phase_deg',0,'noise_power',variance,'candidate_parameters',nan(4,3),...
 'region_classification_source','whole_author_symbol','classification_method','author-ml-v1',...
 'diagnostic_metrics_only',true,'cardinality',NaN);
if id>0
 r.label=names{id};r.status='author_whole_symbol_classification';
 r.candidate_parameters(id,:)=[gain 0 variance];
end
end

function render(out,frame,Z,map,records,C,decisions)
fig=figure('Visible','off','Position',[20 20 1600 600],'Color','w');
imagesc(1:300,1:5,map,[0 4]);colormap(fig,[.75 .77 .8;.13 .65 .38;.63 .38 .79;.17 .45 .86;.96 .55 .14]);
yticks(1:5);yticklabels({'Whole symbol','Low negative band','High negative band','Low positive band','High positive band'});
xlabel('Data symbol index, excluding SSS');title(sprintf('Frame %d: author whole-symbol labels inherited by frequency regions',frame));
cb=colorbar;cb.Ticks=0:4;cb.TickLabels={'Unknown/composite','QPSK','4QAM','16QAM','cross32QAM'};
exportgraphics(fig,fullfile(out,'modulation_candidates_map.png'),'Resolution',140);close(fig);
for symbol=[1 50 100 150 200 250]
 r=records{1,symbol};z=Z(:,symbol);fig=figure('Visible','off','Position',[20 20 1100 950],'Color','w');
 plot(real(z),imag(z),'.','MarkerSize',8,'Color',[.15 .45 .82]);hold on;grid on;axis equal;
 if r.label_id>0
  c=r.gain*C{r.label_id};plot(real(c),imag(c),'ro','MarkerSize',13,'LineWidth',2);
  legend('Received points, unchanged','Selected geometry at receiver gain','Location','northoutside');
 end
 extent=max(1.7,max(abs(z))*1.05);axis([-extent extent -extent extent]);xlabel('I');ylabel('Q');
 title({sprintf('Data symbol %d: %s, %d received points',symbol,r.label,numel(z)),...
  'Author whole-symbol classification; nearest-point distance is not payload truth'},'Interpreter','none');
 exportgraphics(fig,fullfile(out,sprintf('constellation_symbol_%03d.png',symbol)),'Resolution',140);close(fig);
end
symbol=50;valid=decisions.valid_mask(:,symbol);z=Z(:,symbol);hard=decisions.hard_symbols(:,symbol);
fig=figure('Visible','off','Position',[20 20 1700 800],'Color','w');tiledlayout(1,2,'TileSpacing','compact');
nexttile;plot(real(z),imag(z),'.','Color',[.15 .45 .82]);grid on;axis equal;xlabel('I');ylabel('Q');
title(sprintf('Symbol %d: %d original received points',symbol,numel(z)));
nexttile;plot(real(hard(valid)),imag(hard(valid)),'o','Color',[.1 .6 .35],'MarkerSize',8,'LineWidth',1.5);
grid on;axis equal;xlabel('I');ylabel('Q');title({sprintf('Nearest decisions: %d valid, %d erased',nnz(valid),nnz(~valid)),...
 'Canonical unit mean energy; orderly points do not imply correctness'});
exportgraphics(fig,fullfile(out,'symbol_decision_comparison.png'),'Resolution',140);close(fig);
end

function writejson(path,obj)
fid=fopen(path,'w');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(obj));clear cleanup;
end
