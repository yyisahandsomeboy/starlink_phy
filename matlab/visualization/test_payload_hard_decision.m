function test_payload_hard_decision(root)
% Small known geometric fixtures, not a claim of real payload bit truth.
addpath(fullfile(root,'matlab','visualization'));C=payload_models();
for m=1:4
 ids=int16((0:numel(C{m})-1).');h=1.12*exp(1j*.04);
 s=struct('geometry_id',uint8(m*ones(size(ids))),'geometric_point_id_0based',ids,...
  'candidate_point',h*C{m},'erasure_mask',false(size(ids)),...
  'conditional_model_posterior',ones(size(ids)),'candidate_geometries',{C},...
  'payload_matlab_rows',(3:numel(ids)+2).','source_grid_columns',2);
 d=payload_hard_decision(s);
 assert(max(abs(d.hard_symbols-C{m}))<1e-12);
 assert(max(abs(d.hard_symbols_observed_scale-h*C{m}))<1e-12);
 assert(isequal(d.point_id_0based,ids));assert(all(d.valid_mask));
 assert(isequal(d.conditional_model_posterior,s.conditional_model_posterior));
 assert(isequal(size(d.hard_grid),[1024 301]));
 assert(isequal(d.hard_grid(s.payload_matlab_rows,2),C{m}));
 assert(all(isnan(d.hard_grid(:,1))));assert(all(~d.payload_mask(:,1)));
 s.erasure_mask(1)=true;s.geometry_id(2)=0;s.geometric_point_id_0based(2)=-1;
 s.conditional_model_posterior(4)=.1;
 d=payload_hard_decision(s);
 assert(all(isnan(d.hard_symbols(1:2))) && all(d.point_id_0based(1:2)==-1));
 assert(all(~d.valid_mask(1:2)) && all(d.payload_erasure_mask(s.payload_matlab_rows(1:2),2)));
 assert(isnan(d.hard_symbols(4)) && d.point_id_0based(4)==-1);
 assert(d.total_count==numel(ids) && d.valid_count==numel(ids)-3 && d.erased_count==3);
 assert(d.unknown_geometry_count==1 && d.low_reliability_count==2);
 s.geometric_point_id_0based(3)=int16(numel(C{m}));
 caught=false;try,payload_hard_decision(s);catch ME,caught=strcmp(ME.identifier,'payload:DecisionIndex');end
 assert(caught,'Out-of-range geometric index must be rejected');
end
fprintf('PAYLOAD_HARD_DECISION_TEST_PASSED\n');
end
