function result = test_protocol_receiver(root)
%TEST_PROTOCOL_RECEIVER 论文CRC例、独立编码约定、纠错、秩失败与资源坐标。
addpath(fullfile(root,'matlab','protocol_receiver'));opt=slproto.defaultOptions();
toBits=@(hex)reshape(dec2bin(hex2dec(reshape(hex,8,[]).'),32).'-'0',[],1);
bits=toBits('3048A0A0000000E8');assert(slproto.crc8(bits(1:end-8))==232);
bits4=toBits('342250800384C0A48002280000000089');assert(slproto.crc8(bits4(1:end-8))==137);
f=slproto.parseFields(bits);assert(f.block_count_field==2&&f.entry_count==1&&f.entries.index8==5&&f.entries.quantity==5&&f.packing_ok);
u=[bits(1:32);zeros(6,1)];[coded,state]=slproto.bccEncode(u);assert(state==0);
b=slproto.bccDecode(1-2*double(coded),0);assert(isequal(b.inputs,logical(u))&&b.hard_changes==0&&b.zero_tail);
x=1-2*double(coded);x(23)=-0.2*x(23);b=slproto.bccDecode(x,0);assert(isequal(b.inputs,logical(u))&&b.hard_changes==1);
wrong=slproto.bccDecode(1-2*double(coded),1);assert(wrong.hard_changes>0);
c=slproto.coordinates();assert(c.payload_bins(1)==-512&&c.payload_bins(228)==-277&&c.payload_bins(1004)==511);
assert(c.slot(1005)==3&&c.q(1005)==0&&c.grid_column(1005)==3&&~any(ismember(c.payload_rows,c.pilot_rows)));
[R,pn]=slproto.pnReference();assert(pn.unit_modulus_error<1e-14&&isequal(size(R),[1024 301]));
model=slproto.code5Model();assert(model.rank_H==1024&&model.generator_check_orthogonal);
assert(all(full(sum(model.H,2))==6)&&all(ismember(full(sum(model.H,1)),[2 3 4])));
rng(20261103);u=rand(1024,1)>.5;parity=logical(mod(double(u).'*double(model.P),2).');word=[u;parity];
assert(~any(mod(model.H*double(word),2)));llr=6*(1-2*double(word));llr([55 1200])=-.25*llr([55 1200]);
d=slproto.minsum(llr,model.H,.8,60);assert(d.converged&&isequal(d.bits,word)&&d.hard_changes==2);
% 小型已知QC线性关系，验证满秩、留出错误和欠定/不一致拒绝。
P=logical(blkdiag(circshift(eye(4),1,2),circshift(eye(4),2,2)));U=[logical(eye(8));true(1,8)];W=[U logical(mod(double(U)*double(P),2))];
fit=[true(8,1);false];m=slproto.recoverQC(W,fit,8,4);assert(m.fit.unique&&isequal(m.P,P)&&all(m.verification_parity_errors==0));
W(end,end)=~W(end,end);m=slproto.recoverQC(W,fit,8,4);assert(m.fit.unique&&m.verification_parity_errors==1);
[X,check]=slproto.gf2Solve(false(2,3),false(2,1));assert(isempty(X)&&~check.unique);
[X,check]=slproto.gf2Solve([1;1],[0;1]);assert(isempty(X)&&~check.consistent);
result=struct('status','passed','published_CRC_examples',2,'soft_BCC_and_error_correction',true, ...
    'coordinate_cases',true,'code5_H_rank',1024,'code5_GH_orthogonal',true,'synthetic_minsum_changes',2, ...
    'QC_full_rank_and_reserved_error',true,'rank_deficient_and_inconsistent_rejected',true);
fprintf('PROTOCOL_UNIT_TESTS_PASSED\n');
end
