function coded = encodeMCS66(u,model)
%ENCODEMCS66 固定奇偶逆从输入重建校验位；不重复接收硬位。
if nargin<2,model=slproto.mcs66Model();end
u=logical(u(:));assert(numel(u)==model.K);Z=model.Z;B=(model.N-model.K)/Z;
rhs=mod(model.Hu*double(u),2);F=fft(reshape(rhs,Z,B),[],1);out=zeros(Z,B);
for i=1:B
    value=zeros(Z,1);
    for j=1:B,value=value+conj(model.parity_inverse_fft(:,i,j)).*F(:,j);end
    realValue=real(ifft(value));assert(max(abs(realValue-round(realValue)))<1e-7);
    out(:,i)=mod(round(realValue),2);
end
coded=[u;logical(out(:))];assert(~any(mod(model.H*double(coded),2)));
end
