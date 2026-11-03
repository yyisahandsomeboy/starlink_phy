function output = RUN_CODEX_RECEIVER(cfg)
%RUN_CODEX_RECEIVER 升级入口：原真实IQ接收机 + 共享PN/PDU/Code5后处理。
% cfg保留author_receiver接口；必须使用新目录。已有结果用RUN_PROTOCOL_ANALYSIS。
assert(isstruct(cfg)&&isfield(cfg,'root')&&isfield(cfg,'run_dir')&&isfield(cfg,'input_path'));
assert(~isfolder(cfg.run_dir),'slproto:FreshRun','完整接收请使用新目录；已有MAT可只读升级');
if ~isfield(cfg,'workers'),cfg.workers=0;end
addpath(fullfile(cfg.root,'matlab','baseline'),fullfile(cfg.root,'matlab','protocol_receiver'));
physical=author_receiver(cfg);count=numel(physical.frames);clear physical;
assert(count>=1,'slproto:NoFrame','原接收机未输出可处理帧');
frames=1:count;if isfield(cfg,'protocol_frames'),frames=cfg.protocol_frames;end
protocol=RUN_PROTOCOL_ANALYSIS(cfg.run_dir,'Frames',frames);
output=struct('owner','codex_baseline','upgrade_version','pdu-receiver-v1', ...
    'physical_run_dir',cfg.run_dir,'physical_receiver_version','author-ml-v1','protocol',protocol, ...
    'payload_plaintext_recovered',false,'original_evaluator_changed',false);
end
