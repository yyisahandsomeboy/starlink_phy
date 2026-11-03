function model = recoverQC(words,developmentMask,K,Z)
%RECOVERQC 独立恢复系统P；QC展开不增加独立采集数量，留出字绝不进入消元。
assert(islogical(words)&&size(words,2)==2*K&&K<=1024&&mod(2*K,Z)==0);
developmentMask=logical(developmentMask(:));assert(numel(developmentMask)==size(words,1)&&any(developmentMask)&&any(~developmentMask));
fit=words(developmentMask,:);assert(size(fit,1)*Z<=8192,'slproto:MatrixBudget','QC拟合展开超出预算');
expanded=false(size(fit,1)*Z,2*K);
for shift=0:Z-1
    block=reshape(fit.',Z,2*K/Z,[]);block=circshift(block,shift,1);
    expanded(shift*size(fit,1)+(1:size(fit,1)),:)=reshape(block,2*K,[]).';
end
[P,info]=slproto.gf2Solve(expanded(:,1:K),expanded(:,K+1:end));
model=struct('fit',info,'P',P,'independent_development_words',nnz(developmentMask), ...
    'QC_augmented_rows',size(expanded,1),'verification_words',nnz(~developmentMask), ...
    'verification_parity_errors',[],'scope','QC-conditional, same capture; augmented shifts are not independent transmissions');
if info.unique
    reserved=words(~developmentMask,:);pred=mod(double(reserved(:,1:K))*double(P),2);
    model.verification_parity_errors=sum(pred~=reserved(:,K+1:end),2);
end
end
