function b = bccDecode(observations,polarity)
%BCCDECODE 38输入/114编码资源；完整64状态软Viterbi，从0开始并要求回到0。
if nargin<2,polarity=0;end
assert(isscalar(polarity)&&ismember(polarity,[0 1]));x=real(observations(:));assert(numel(x)==114&&all(isfinite(x)));
persistent nextState expected predecessors
if isempty(nextState)
    nextState=zeros(64,2);expected=zeros(64,2,3);predecessors=zeros(64,2);
    for s=0:63
        for u=0:1
            v=bitor(bitshift(uint16(s),1),uint16(u));ns=double(bitand(v,63));nextState(s+1,u+1)=ns+1;
            predecessors(ns+1,floor(s/32)+1)=s+1;
            for a=1:3,g=[109 83 95];expected(s+1,u+1,a)=1-2*mod(sum(bitget(bitand(v,uint16(g(a))),1:7)),2);end
        end
    end
end
x=reshape(x*(1-2*polarity),3,38);metric=inf(64,1);metric(1)=0;trace=zeros(64,38,'uint8');
for n=1:38
    branch=sum((expected-reshape(x(:,n),1,1,3)).^2,3);new=inf(64,1);
    for ns=1:64
        u=mod(ns-1,2)+1;p=predecessors(ns,:);[new(ns),which]=min(metric(p)+branch(sub2ind([64 2],p,[u u])).');
        trace(ns,n)=uint8(p(which)-1);
    end
    metric=new;
end
state=0;inputs=false(38,1);
for n=38:-1:1,inputs(n)=mod(state,2);state=double(trace(state+1,n));end
[coded,finalState]=slproto.bccEncode(inputs);coded=xor(coded,logical(polarity));observed=real(observations(:))<0;
b=struct('inputs',inputs,'word_bits',inputs(1:32),'tail_bits',inputs(33:38), ...
    'zero_initial_state',state==0,'zero_final_state',finalState==0,'zero_tail',~any(inputs(33:38)), ...
    'reencoded',coded,'hard_observed',observed,'hard_changes',nnz(coded~=observed), ...
    'soft_path_metric',metric(1),'polarity',polarity,'word_hex',upper(dec2hex(sum(double(inputs(1:32)).*2.^(31:-1:0)'),8)));
end
