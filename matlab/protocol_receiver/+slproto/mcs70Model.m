function model = mcs70Model()
%MCS70MODEL 冻结的70接收等价QC512模型；不认证商业标准身份。
persistent saved
if ~isempty(saved),model=saved;return;end
base=fileparts(fileparts(mfilename('fullpath')));m=jsondecode(fileread(fullfile(base,'models','mcs70_qc512_utexas_v1.json')));
Z=m.Z;M=m.N-m.K;B=M/Z;seeds=cell(1,B);rr=cell(1,B);cc=cell(1,B);groups={};
for b=1:B
    if iscell(m.seed_supports_0based),seed=m.seed_supports_0based{b}(:).';else,seed=m.seed_supports_0based(b,:);end
    seeds{b}=seed;support=floor(seed/Z)*Z+mod(seed+(0:Z-1)',Z)+1;
    check=repmat(((b-1)*Z+(1:Z))',1,numel(seed));rr{b}=check(:);cc{b}=support(:);
end
H=sparse(vertcat(rr{:}),vertcat(cc{:}),1,M,m.N);degrees=full(sum(H,2));
for degree=unique(degrees).'
    which=find(degrees==degree);[row,col]=find(H(which,:));edges=sortrows([row col],[1 2]);
    groups{end+1}=reshape(edges(:,2),degree,[]).'; %#ok<AGROW>
end
inverse=zeros(Z,B,B);hp=zeros(Z,B,B);
for i=1:B
    raw=uint8(hex2dec(reshape(m.parity_inverse_first_rows_hex_little_endian{i},2,[]).'));
    bits=reshape(bsxfun(@bitget,raw,1:8).',[],1);inverse(:,i,:)=reshape(bits,Z,1,B);
    p=seeds{i}(seeds{i}>=m.K)-m.K;
    for v=p,hp(mod(v,Z)+1,i,floor(v/Z)+1)=1;end
end
F=fft(hp,[],1);V=fft(inverse,[],1);maximum=0;
for i=1:B
    for j=1:B
        product=zeros(Z,1);for k=1:B,product=product+F(:,i,k).*V(:,k,j);end
        value=real(ifft(product));maximum=max(maximum,max(abs(value-round(value))));
        expected=zeros(Z,1);expected(1)=i==j;assert(isequal(mod(round(value),2),expected),'slproto:MCS70Inverse','完整QC奇偶逆关系失败');
    end
end
assert(maximum<1e-7&&isequal(degrees,repelem(m.row_weights(:),Z)));
model=struct('version',m.version,'metadata',m,'N',m.N,'K',m.K,'Z',Z,'H',H,'Hu',H(:,1:m.K), ...
    'group_supports',{groups},'parity_inverse_fft',V,'rank_H',M,'rank_Hp',M, ...
    'inverse_verified_all_coordinates',true,'inverse_fft_rounding_error',maximum,'GH_orthogonal_implicit',true);
saved=model;
end
