function [X,info] = gf2Solve(A,B)
%GF2SOLVE 小型逻辑矩阵消元；检查一致性与满列秩，不以自由变量任意补全。
A=logical(full(A));B=logical(full(B));assert(size(A,1)==size(B,1));
[m,n]=size(A);assert(n<=2048&&m<=8192,'slproto:MatrixBudget','超过本版GF(2)矩阵预算');
aug=[A B];pivot=zeros(1,min(m,n));r=0;
for col=1:n
    k=find(aug(r+1:end,col),1);if isempty(k),continue;end
    r=r+1;k=k+r-1;aug([r k],:)=aug([k r],:);pivot(r)=col;
    other=find(aug(:,col));other(other==r)=[];
    if ~isempty(other),aug(other,:)=xor(aug(other,:),aug(r,:));end
    if r==m,break;end
end
inconsistent=any(~any(aug(:,1:n),2)&any(aug(:,n+1:end),2));
info=struct('rank',r,'columns',n,'consistent',~inconsistent,'unique',r==n&&~inconsistent);
X=[];if info.unique,X=aug(1:n,n+1:end);end
end
