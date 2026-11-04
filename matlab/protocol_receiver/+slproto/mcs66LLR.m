function llr = mcs66LLR(z,scale)
%MCS66LLR 固定16QAM位标签：负I、负Q、内幅I、内幅Q；LLR正值偏向0。
if nargin<2,scale=.04;end
C=slproto.alphabet('16QAM');labels=[real(C)<0 imag(C)<0 abs(real(C))<2/sqrt(10) abs(imag(C))<2/sqrt(10)];
d=abs(z(:)-C.').^2/scale;L=zeros(numel(z),4);
for b=1:4
    a=d(:,~labels(:,b));v=d(:,labels(:,b));ma=min(a,[],2);mv=min(v,[],2);
    L(:,b)=mv-ma+log(sum(exp(ma-a),2))-log(sum(exp(mv-v),2));
end
llr=reshape(L.',[],1);
end
