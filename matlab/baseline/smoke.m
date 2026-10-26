root=getenv('STARLINK_DEMO_ROOT');out=fullfile(root,'reports');
rng(1);x=randn(128,1)+1i*randn(128,1);err=norm(ifft(fft(x))-x)/norm(x);assert(err<1e-12);
s=struct('release',version('-release'),'version',version,'matlabroot',matlabroot,'arch',computer('arch'),'fft_roundtrip',err,'toolboxes',{ver});
s.functions=struct;names={'resample','jsonencode','jsondecode','exportgraphics','qammod','kmeans'};
for i=1:numel(names);s.functions.(names{i})=which(names{i});end
if ~isempty(which('resample')); y=resample(x,24,25);s.resample_length=numel(y);end
assert(jsondecode(jsonencode(struct('a',1))).a==1);
save(fullfile(out,'matlab_smoke.mat'),'x','s');
f=figure('Visible','off');plot(abs(x));exportgraphics(f,fullfile(out,'matlab_smoke.png'));close(f);
fid=fopen(fullfile(out,'matlab_smoke.json'),'w');fprintf(fid,'%s',jsonencode(s));fclose(fid);disp(jsonencode(s));
