function [coded,finalState] = bccEncode(inputs)
%BCCENCODE K=7、1/3、(155,123,137)八进制；g的bit0表示当前输入。
inputs=inputs(:);assert(all(inputs==0|inputs==1));g=uint16([109 83 95]);state=uint16(0);coded=false(3*numel(inputs),1);
for n=1:numel(inputs)
    v=bitor(bitshift(state,1),uint16(inputs(n)));
    for a=1:3,coded(3*n-3+a)=mod(sum(bitget(bitand(v,g(a)),1:7)),2);end
    state=bitand(v,63);
end
finalState=double(state);
end
