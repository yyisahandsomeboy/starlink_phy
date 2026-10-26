function d=payload_hard_decision(s,minimum_posterior)
% Export nearest-point candidates as conditional hard symbols with erasures.
% The input point order is geometric, not a commercial bit mapping.
if nargin<2,minimum_posterior=.90;end
assert(isscalar(minimum_posterior) && isfinite(minimum_posterior) && minimum_posterior>=0 && minimum_posterior<=1);
shape=size(s.geometry_id);rows=s.payload_matlab_rows(:);cols=s.source_grid_columns(:).';
assert(isequal(size(s.geometric_point_id_0based),shape) && isequal(size(s.erasure_mask),shape));
assert(isequal(size(s.candidate_point),shape) && isequal(size(s.conditional_model_posterior),shape));
assert(shape(1)==numel(rows) && shape(2)==numel(cols));
assert(numel(unique(rows))==numel(rows) && all(rows>=1 & rows<=1024));
assert(numel(unique(cols))==numel(cols) && all(cols>=2 & cols<=301));
assert(all(ismember(s.geometry_id(:),0:4)) && numel(s.candidate_geometries)==4);
known=s.geometry_id>0;posterior=s.conditional_model_posterior;
assert(all(isfinite(posterior(:))) && all(posterior(:)>=0 & posterior(:)<=1));
assert(all(isfinite(s.candidate_point(known))),'payload:DecisionPoint','Known candidate points must be finite');
valid=known & ~s.erasure_mask & posterior>=minimum_posterior;
hard=complex(nan(shape),nan(shape));observed=hard;ids=-ones(shape,'int16');
for m=1:4
 c=s.candidate_geometries{m};mask=s.geometry_id==m;
 index=double(s.geometric_point_id_0based(mask));
 assert(all(index>=0 & index<numel(c) & index==floor(index)),...
  'payload:DecisionIndex','Geometric point index outside selected constellation');
 mask=mask & valid;index=double(s.geometric_point_id_0based(mask))+1;
 hard(mask)=c(index);observed(mask)=s.candidate_point(mask);
 ids(mask)=s.geometric_point_id_0based(mask);
end
grid=complex(nan(1024,301),nan(1024,301));grid(rows,cols)=hard;
observed_grid=grid;observed_grid(rows,cols)=observed;
payload=false(1024,301);payload(rows,cols)=true;
valid_grid=false(1024,301);valid_grid(rows,cols)=valid;
d=struct('version','payload-hard-decision-v1','owner','codex_baseline',...
 'hard_symbols',hard,'hard_symbols_observed_scale',observed,'point_id_0based',ids,...
 'valid_mask',valid,'erasure_mask',~valid,'geometry_id',s.geometry_id,...
 'conditional_model_posterior',posterior,...
 'hard_grid',grid,'hard_grid_observed_scale',observed_grid,'payload_mask',payload,...
 'valid_grid_mask',valid_grid,'payload_erasure_mask',payload & ~valid_grid,...
 'payload_matlab_rows',rows,'source_grid_columns',cols,'minimum_model_posterior',minimum_posterior,...
 'total_count',numel(valid),'valid_count',nnz(valid),'erased_count',nnz(~valid),...
 'unknown_geometry_count',nnz(~known),'low_reliability_count',nnz(known & ~valid),...
 'conditional_on_estimated_geometry',true,'business_bits_available',false,...
 'real_payload_SER_available',false,'real_payload_BER_available',false,...
 'scope','Conditional geometric symbol decisions; erased resources are NaN/-1; no payload bit mapping');
end
