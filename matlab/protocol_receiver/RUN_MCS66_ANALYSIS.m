function report = RUN_MCS66_ANALYSIS(protocolMat,out)
%RUN_MCS66_ANALYSIS 从既有协议检查点只读补算66，无需重复物理DSP。
here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(here));
addpath(here,fullfile(root,'matlab','learning_receiver'));
assert(isfile(protocolMat)&&~isfolder(out));digest=slrx.sha256(protocolMat);
d=load(protocolMat,'result');r=d.result;assert(isfield(r,'allocations')&&r.allocations.available);
coding=slproto.analyzeMCS66(r.payload_stream,r.headers,r.allocations.calibration,slproto.defaultOptions());
mkdir(out);save(fullfile(out,'mcs66.mat'),'coding','-v7.3');report=coding;
if report.available,report.words=rmfield(report.words,{'information_bits','decoded_codeword'});end
report.source=struct('protocol_mat',protocolMat,'protocol_mat_sha256',digest);
assert(strcmp(digest,slrx.sha256(protocolMat)));slproto.writeJSON(fullfile(out,'mcs66_summary.json'),report);
fprintf('MCS66_RESULT available=%d words=%d\n',report.available,report.word_count);
end
