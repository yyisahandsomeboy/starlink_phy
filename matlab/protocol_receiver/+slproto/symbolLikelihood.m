function [nll,index,residual] = symbolLikelihood(z,C,g,v)
%SYMBOLLIKELIHOOD 稳定等概率高斯混合；分块避免N×64整帧矩阵。
z=z(:);g=g(:);v=v(:);assert(isscalar(g)||numel(g)==numel(z));assert(isscalar(v)||numel(v)==numel(z));
assert(all(g>0)&all(v>0));nll=zeros(size(z));index=zeros(size(z),'uint8');residual=zeros(size(z));
for a=1:4096:numel(z)
    ii=a:min(a+4095,numel(z));gg=g;if ~isscalar(g),gg=g(ii);end;vv=v;if ~isscalar(v),vv=v(ii);end
    d=abs(z(ii)-gg.*C(:).').^2;[r,k]=min(d,[],2);D=d./vv;m=r./vv;
    nll(ii)=m-log(mean(exp(m-D),2));index(ii)=uint8(k);residual(ii)=r;
end
end
