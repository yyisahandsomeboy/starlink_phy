function d = minsum(llr,H,normalization,maxIterations)
%MINSUM L=log P(0)/P(1)，按边存储消息；不构造N×N矩阵。
llr=llr(:);assert(all(isfinite(llr))&&size(H,2)==numel(llr));
assert(isscalar(normalization)&&normalization>0&&normalization<=1&&maxIterations>=0);
[checks,variables]=find(H);M=size(H,1);N=size(H,2);E=numel(variables);
order=cell(M,1);for j=1:M,order{j}=find(checks==j);end
q=llr(variables);r=zeros(E,1);post=llr;before=llr<0;bits=before;
initial=nnz(mod(H*double(bits),2));iterations=0;
if initial>0
    for it=1:maxIterations
        for check=1:M
            edge=order{check};v=q(edge);signs=ones(size(v));signs(v<0)=-1;
            a=abs(v);[smallest,k]=min(a);a(k)=Inf;second=min(a);magnitudes=repmat(smallest,size(v));magnitudes(k)=second;
            r(edge)=normalization*prod(signs).*signs.*magnitudes;
        end
        post=llr+accumarray(variables,r,[N 1]);bits=post<0;iterations=it;
        if ~any(mod(H*double(bits),2)),break;end
        q=post(variables)-r;q=max(-50,min(50,q));
    end
end
d=struct('bits',bits,'posterior_llr',post,'initial_failed_checks',initial, ...
    'final_failed_checks',nnz(mod(H*double(bits),2)),'hard_changes',nnz(bits~=before),'iterations',iterations, ...
    'converged',~any(mod(H*double(bits),2)),'normalization',normalization);
end
