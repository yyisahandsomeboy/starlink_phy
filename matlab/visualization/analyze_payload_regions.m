function summary=analyze_payload_regions(cfg)
% Export the current author-method receiver's saved classification and decisions.
addpath(fullfile(cfg.root,'matlab','baseline'),fullfile(cfg.root,'matlab','visualization'));
f=load_payload_frame(cfg.run_dir,cfg.frame_index);
assert(isfield(f,'modulation') && strcmp(f.modulation.method_version,'author-ml-v1'),...
 'payload:ReceiverVersion','Only author-ml-v1 receiver outputs are supported');
summary=export_author_payload(cfg,f);
end
