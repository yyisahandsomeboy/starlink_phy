function model = mcs66Model()
%MCS66MODEL 冻结的接收等价模型；不声称商业标准身份。
persistent saved
if ~isempty(saved),model=saved;return;end
base=fileparts(fileparts(mfilename('fullpath')));m=jsondecode(fileread(fullfile(base,'models','mcs66_qc512_utexas_v1.json')));
Z=m.Z;M=m.N-m.K;B=M/Z;seed=m.seed_supports_0based;supports=zeros(M,size(seed,2));
for b=1:B
    for s=0:Z-1,supports((b-1)*Z+s+1,:)=floor(seed(b,:)/Z)*Z+mod(seed(b,:)+s,Z)+1;end
end
checks=repmat((1:M)',1,size(supports,2));H=sparse(checks(:),supports(:),1,M,m.N);
inverse=zeros(Z,B,B);hp=zeros(Z,B,B);
for i=1:B
    raw=uint8(hex2dec(reshape(m.parity_inverse_first_rows_hex_little_endian{i},2,[]).'));
    bits=reshape(bsxfun(@bitget,raw,1:8).',[],1);inverse(:,i,:)=reshape(bits,Z,1,B);
    p=seed(i,seed(i,:)>=m.K)-m.K;
    for v=p,hp(mod(v,Z)+1,i,floor(v/Z)+1)=1;end
end
F=fft(hp,[],1);V=fft(inverse,[],1);maximum=0;
for i=1:B
    for j=1:B
        product=zeros(Z,1);
        for k=1:B,product=product+F(:,i,k).*V(:,k,j);end
        realProduct=real(ifft(product));maximum=max(maximum,max(abs(realProduct-round(realProduct))));
        check=mod(round(realProduct),2);expected=zeros(Z,1);expected(1)=i==j;
        assert(isequal(check,expected),'slproto:MCS66Inverse','完整QC奇偶逆关系失败');
    end
end
assert(maximum<1e-7&&all(full(sum(H,2))==14));
model=struct('version',m.version,'metadata',m,'N',m.N,'K',m.K,'Z',Z,'H',H, ...
    'supports',supports,'Hu',H(:,1:m.K),'parity_inverse_fft',V,'rank_H',M, ...
    'rank_Hp',M,'inverse_verified_all_coordinates',true,'inverse_fft_rounding_error',maximum, ...
    'GH_orthogonal_implicit',true);saved=model;
end
