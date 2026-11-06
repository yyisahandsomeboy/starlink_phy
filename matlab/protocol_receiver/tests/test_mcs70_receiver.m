function result = test_mcs70_receiver(root)
addpath(fullfile(root,'matlab','protocol_receiver'));m=slproto.mcs70Model();assert(m.rank_H==3584&&m.rank_Hp==3584&&m.GH_orthogonal_implicit);
rng(20261104);u=rand(m.K,1)>.5;c=slproto.encodeMCS70(u,m);assert(~any(mod(m.H*double(c),2)));
llr=8*(1-2*double(c));llr([21 15001])=-.25*llr([21 15001]);d=slproto.minsumGrouped(llr,m.group_supports,.8,60);
assert(d.converged&&isequal(d.bits,c)&&d.hard_changes==2);reference=slproto.minsum(llr,m.H,.8,60);assert(isequal(d.bits,reference.bits));
b=reshape(double(c),4,[]).';z=((1-2*b(:,1)).*(3-2*b(:,3))+1j*(1-2*b(:,2)).*(3-2*b(:,4)))/sqrt(10);assert(isequal(slproto.mcs66LLR(z,.04)<0,c));
result=struct('status','passed','full_Hp_inverse',m.inverse_verified_all_coordinates,'implicit_GH',true,'synthetic_two_bit_correction',true,'original_minsum_agreement',true,'mapping_exact_inverse',true);
fprintf('MCS70_UNIT_PASSED\n');
end
