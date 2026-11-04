function d = minsumRegular(llr,supports,normalization,maxIterations)
%MINSUMREGULAR 等行重稀疏H的向量化normalized-min-sum；不分配N×N矩阵。
llr=llr(:);M=size(supports,1);degree=size(supports,2);N=numel(llr);
assert(all(isfinite(llr))&&all(supports>=1&supports<=N,'all'));
q=llr(supports);bits=llr<0;post=llr;initial=nnz(mod(sum(bits(supports),2),2));failed=initial;iterations=0;
for it=1:maxIterations
    if failed==0,break;end
    signs=ones(size(q));signs(q<0)=-1;a=abs(q);[~,k]=min(a,[],2);mins=mink(a,2,2);
    magnitude=repmat(mins(:,1),1,degree);magnitude(sub2ind(size(q),(1:M)',k))=mins(:,2);
    messages=normalization*prod(signs,2).*signs.*magnitude;
    post=llr+accumarray(supports(:),messages(:),[N 1]);bits=post<0;iterations=it;
    failed=nnz(mod(sum(bits(supports),2),2));q=max(-50,min(50,post(supports)-messages));
end
d=struct('bits',bits,'posterior_llr',post,'initial_failed_checks',initial,'final_failed_checks',failed, ...
    'hard_changes',nnz(bits~=(llr<0)),'iterations',iterations,'converged',failed==0);
end
