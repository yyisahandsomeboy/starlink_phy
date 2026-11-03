function manifest = sourceManifest()
%SOURCEMANIFEST 固定协议模块与模型的逐文件身份，避免只记录旧学习源码。
base=fileparts(fileparts(mfilename('fullpath')));root=fileparts(fileparts(base));
files=[dir(fullfile(base,'**','*.m'));dir(fullfile(base,'models','*.json'))];
extra={'matlab/learning_receiver/CONTINUE_TO_PDU.m','matlab/learning_receiver/START_HERE.m', ...
    'matlab/learning_receiver/+slrx/defaultConfig.m','matlab/baseline/RUN_CODEX_RECEIVER.m'};
records=struct('path',{},'sha256',{});
for j=1:numel(files)
    p=fullfile(files(j).folder,files(j).name);rel=erase(p,[root filesep]);
    records(end+1)=struct('path',strrep(rel,filesep,'/'),'sha256',slrx.sha256(p)); %#ok<AGROW>
end
for j=1:numel(extra),records(end+1)=struct('path',extra{j},'sha256',slrx.sha256(fullfile(root,extra{j})));end %#ok<AGROW>
manifest=struct('version','pdu-receiver-source-v2','owner','codex_baseline','files',records);
end
