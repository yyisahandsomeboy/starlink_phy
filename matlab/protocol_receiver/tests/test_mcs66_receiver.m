function result = test_mcs66_receiver(root)
addpath(fullfile(root,'matlab','protocol_receiver'));m=slproto.mcs66Model();
assert(m.rank_H==4096&&m.inverse_verified_all_coordinates&&m.GH_orthogonal_implicit);
rng(20261104);u=rand(12288,1)>.5;c=slproto.encodeMCS66(u,m);assert(~any(mod(m.H*double(c),2)));
llr=8*(1-2*double(c));llr([19 14000])=-.25*llr([19 14000]);
d=slproto.minsumRegular(llr,m.supports,.8,60);assert(d.converged&&isequal(d.bits,c)&&d.hard_changes==2);
% 与原逐节点实现独立比较，防止向量化消息或边索引错误。
reference=slproto.minsum(llr,m.H,.8,60);assert(isequal(d.bits,reference.bits));
b=reshape(double(c),4,[]).';z=((1-2*b(:,1)).*(3-2*b(:,3))+1j*(1-2*b(:,2)).*(3-2*b(:,4)))/sqrt(10);
soft=slproto.mcs66LLR(z,.04);assert(isequal(soft<0,c));
result=struct('status','passed','Hp_inverse_all_coordinates',true,'implicit_GH_orthogonal',true, ...
    'synthetic_2bit_correction',true,'original_minsum_agreement',true,'mapper_exact_inverse',true);
fprintf('MCS66_UNIT_PASSED\n');
end
