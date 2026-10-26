function baseline_manifest(cfg)
root=cfg.root; code=[dir(fullfile(root,'matlab','baseline','*.m'));dir(fullfile(root,'matlab','evaluation','*.m'))];
paths={fullfile(root,'config','real_receiver.json'),fullfile(root,'config','evaluation.json'),fullfile(root,'config','evaluator_lock.json'),fullfile(root,'config','artifact_contract.json'),cfg.input_path};
paths{end+1}=fullfile(root,'config','author_receiver_v1.json');
if isfield(cfg,'truth_path'), paths{end+1}=cfg.truth_path; end
for j=1:numel(code), paths{end+1}=fullfile(code(j).folder,code(j).name); end
entries=struct([]);
for j=1:numel(paths)
 p=paths{j}; fid=fopen(p,'r'); if fid<0, continue; end
 md=java.security.MessageDigest.getInstance('SHA-256');
 while ~feof(fid), bytes=fread(fid,65536,'*uint8'); md.update(bytes); end; fclose(fid);
 digest=typecast(md.digest(),'uint8'); h=lower(reshape(dec2hex(digest,2).',1,[]));
 x=struct('path',strrep(p,[root filesep],''),'sha256',h);
 if isempty(entries), entries=x; else, entries(end+1)=x; end
end
manifest=struct('role','codex_baseline','timestamp_utc',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")),...
 'matlab_version',version,'matlab_release',version('-release'),'platform',computer,'configuration',cfg,'files',entries);
fid=fopen(fullfile(cfg.run_dir,'manifest.json'),'w'); fprintf(fid,'%s\n',jsonencode(manifest,'PrettyPrint',true)); fclose(fid);
end
