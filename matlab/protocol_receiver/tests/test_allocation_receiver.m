function result = test_allocation_receiver(root)
%TEST_ALLOCATION_RECEIVER 边界跨列、单字装箱、未知ID、似然和合成混合列反例。
addpath(fullfile(root,'matlab','protocol_receiver'),fullfile(root,'matlab','learning_receiver'));
registry=slproto.allocationRegistry();p=registry.profiles([registry.profiles.id]==85);
assert(28*p.resources_per_unit==91756&&ceil(28*p.coded_bits_hypothesis/5)==91751);
h=struct('first',struct('accepted',true,'end_r0',227,'fields',struct('entries',struct('index8',5,'quantity',4))), ...
    'second_unique',true,'first_body_length_agrees',true,'second_candidates',struct('start_r0',8420,'end_r0',8875,'fields',struct('entries',struct('index8',85,'quantity',2))));
plan=slproto.planAllocations(h);assert(plan.complete&&plan.regions(4).start_column==10&&plan.regions(4).start_q0==844);
assert(plan.predicted_tail_start_r0==8876+2*3277);
h.second_candidates.fields.entries(2)=struct('index8',250,'quantity',1);
plan=slproto.planAllocations(h);assert(~plan.complete&&plan.unknown_id==250&&isnan(plan.predicted_tail_start_r0)&&numel(plan.regions)==4);
C=slproto.alphabet('32cross');assert(numel(C)==32&&abs(mean(abs(C).^2)-1)<1e-14);
z=[.2+.7j;-.8-.2j];g=[.9;1.1];v=[.03;.05];[nll,k,res]=slproto.symbolLikelihood(z,C,g,v);
for j=1:2
    d=abs(z(j)-g(j)*C).^2;assert(abs(nll(j)+log(mean(exp(-d/v(j)))))<1e-12);[r,m]=min(d);assert(k(j)==m&&abs(res(j)-r)<1e-12);
end
% 固定导频尺度下的混合资源；不为任一候选拟合额外旋转或幅度。
rng(20261103);C16=slproto.alphabet('16QAM');C32=slproto.alphabet('32cross');
z=[C16(randi(16,500,1));C32(randi(32,504,1))]+.025*(randn(1004,1)+1j*randn(1004,1));
test=(2:2:1004)';n16=slproto.symbolLikelihood(z(test),C16,1,.01);n32=slproto.symbolLikelihood(z(test),C32,1,.01);
mixed=[n16(1:250);n32(251:end)];assert(mean(mixed)<min(mean(n16),mean(n32)));
% 负对照：纯16QAM强行一半换32，留出似然应变差。
pure=C16(randi(16,1004,1));a=slproto.symbolLikelihood(pure(test),C16,1,.01);b=slproto.symbolLikelihood(pure(test),C32,1,.01);
assert(mean([a(1:250);b(251:end)])>mean(a));
result=struct('status','passed','per_unit_rounding_differs_from_joint_packing',true, ...
    'inside_column_mapping',true,'unknown_ID_stops_plan',true,'scalar_likelihood_check',true, ...
    'synthetic_mixed_and_pure_negative_control',true,'transmitter_bit_mapping_claimed',false);
fprintf('ALLOCATION_UNIT_TESTS_PASSED\n');
end
