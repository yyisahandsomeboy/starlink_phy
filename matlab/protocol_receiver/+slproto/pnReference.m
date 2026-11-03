function [R,info] = pnReference(model)
%PNREFERENCE 固定模型，不从待译头部重新拟合参考或逐区旋转。
if nargin<1,model='utexas_verified_pairclock';end
c=slproto.coordinates();[a,s]=ndgrid(0:1019,1:301);
switch model
    case 'utexas_verified_pairclock'
        % 旧实验已经由FIT及未参与拟合的导频核验的等效状态。
        state=false(1,15);state(2)=true;seed=state;bits=false(32767,1);
        for j=1:32767
            bits(j)=state(15);state=[xor(state(14),state(15)) state(1:14)];
        end
        assert(isequal(seed,state));clock=2*(1020*(s-1)+a);
        labels=2*double(bits(mod(clock,32767)+1))+double(bits(mod(clock+1,32767)+1));
        anchor='Before nominal SSS column at first loaded carrier; equivalent state, not physical burst-reset seed';
    case 'paper_v2_480MHz_capture'
        % 论文式(7)-(8)；该对齐只被论文自己的采集支持，不能自动移植。
        bits=false(32767,1);bits(1:15)=('000000100000010'=='1');
        for j=16:32767,bits(j)=xor(bits(j-14),bits(j-15));end
        d=1020*(s-17)+a;h=bits(mod(d+16327,32767)+1);l=~bits(mod(d+16320,32767)+1);
        labels=mod(2*double(h)+double(l)+1,4);anchor='Paper v2 slot17 loaded-carrier0, indices16327/16320';
    otherwise,error('slproto:PNModel','未声明的PN模型');
end
R=ones(1024,301);R(c.loaded_rows,:)=exp(1j*pi/2*labels);
info=struct('model',model,'state_anchor',anchor,'unit_modulus_error',max(abs(abs(R(:))-1)), ...
    'loaded_carriers_per_slot',1020,'payload_carriers_per_slot',1004, ...
    'physical_burst_reset_seed','unknown','fit_to_current_header',false);
end
