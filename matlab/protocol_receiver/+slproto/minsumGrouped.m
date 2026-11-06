function d = minsumGrouped(llr,groups,normalization,maxIterations)
%MINSUMGROUPED 按行重分组的稀疏normalized-min-sum，不建立N×N矩阵。
llr=llr(:);N=numel(llr);assert(all(isfinite(llr))&&normalization>0&&normalization<=1&&maxIterations>=0);
q=cell(size(groups));messages=cell(size(groups));before=llr<0;bits=before;post=llr;initial=0;
for g=1:numel(groups)
    idx=groups{g};assert(size(idx,2)>=2&&all(idx>=1&idx<=N,'all'));
    q{g}=llr(idx);initial=initial+nnz(mod(sum(bits(idx),2),2));
end
failed=initial;iterations=0;
for it=1:maxIterations
    if failed==0,break;end
    post=llr;
    for g=1:numel(groups)
        idx=groups{g};v=q{g};signs=ones(size(v));signs(v<0)=-1;a=abs(v);[~,k]=min(a,[],2);mins=mink(a,2,2);
        magnitude=repmat(mins(:,1),1,size(idx,2));magnitude(sub2ind(size(v),(1:size(v,1))',k))=mins(:,2);
        messages{g}=normalization*prod(signs,2).*signs.*magnitude;
        post=post+accumarray(idx(:),messages{g}(:),[N 1]);
    end
    bits=post<0;failed=0;iterations=it;
    for g=1:numel(groups)
        idx=groups{g};failed=failed+nnz(mod(sum(bits(idx),2),2));q{g}=max(-50,min(50,post(idx)-messages{g}));
    end
end
d=struct('bits',bits,'posterior_llr',post,'initial_failed_checks',initial,'final_failed_checks',failed, ...
    'hard_changes',nnz(bits~=before),'iterations',iterations,'converged',failed==0);
end
