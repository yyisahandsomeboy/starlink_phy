function report = RUN_MCS70_ANALYSIS(protocolMat,out)
%RUN_MCS70_ANALYSIS 对已有协议MAT只读补算70；仅输出数值，不修改交互页面。
here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(here));addpath(here,fullfile(root,'matlab','learning_receiver'));
assert(isfile(protocolMat)&&~isfolder(out));digest=slrx.sha256(protocolMat);loaded=load(protocolMat,'result');r=loaded.result;
assert(isfield(r,'allocations')&&r.allocations.available);
coding=slproto.analyzeMCS70(r.payload_stream,r.headers,r.allocations.calibration,slproto.defaultOptions());
mkdir(out);save(fullfile(out,'mcs70.mat'),'coding','-v7.3');report=coding;
if report.available,report.words=rmfield(report.words,{'information_bits','decoded_codeword'});end
report.source=struct('protocol_mat',protocolMat,'protocol_mat_sha256',digest);assert(strcmp(digest,slrx.sha256(protocolMat)));
slproto.writeJSON(fullfile(out,'mcs70_summary.json'),report);fprintf('MCS70_RESULT available=%d words=%d\n',report.available,report.word_count);
end
