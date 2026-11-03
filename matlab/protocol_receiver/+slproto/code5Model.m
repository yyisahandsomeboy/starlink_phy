function model = code5Model()
%CODE5MODEL 从独立恢复的8条QC种子展开；完整H与系统生成器互证后缓存。
persistent saved
if ~isempty(saved),model=saved;return;end
base=fileparts(fileparts(mfilename('fullpath')));source=fullfile(base,'models','code5_qc128_utexas_v1.json');
m=jsondecode(fileread(source));seeds=m.seed_supports_0based;supports=zeros(1024,6);r=0;
for j=1:size(seeds,1)
    for shift=0:127
        r=r+1;supports(r,:)=floor(seeds(j,:)/128)*128+mod(seeds(j,:)+shift,128)+1;
    end
end
checkIndex=repmat((1:1024)',1,6);H=sparse(checkIndex(:),supports(:),ones(numel(supports),1),1024,2048);
[transposeP,check]=slproto.gf2Solve(H(:,1025:end),H(:,1:1024));
assert(check.unique,'slproto:Code5Rank','奇偶分区必须满秩');P=transposeP.';
G=[logical(eye(1024)) P];orthogonal=~any(mod(double(G)*H.',2),'all');
assert(orthogonal&&all(full(sum(H,2))==6));
model=struct('version',m.version,'H',H,'P',P,'supports',supports,'N',2048,'K',1024,'Z',128, ...
    'rank_H',check.rank,'generator_check_orthogonal',orthogonal,'source',m.source,'metadata',m);
saved=model;
end
