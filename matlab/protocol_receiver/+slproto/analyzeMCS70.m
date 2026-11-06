function result = analyzeMCS70(stream,headers,calibration,opt)
%ANALYZEMCS70 对条件70分配进行独立软译码和重编码，不改变原始观测。
if nargin<4,opt=slproto.defaultOptions();end
result=struct('available',false,'reason','','id',70,'model','mcs70-qc512-utexas-v1','word_count',0,'words',struct([]), ...
    'application_plaintext_recovered',false,'commercial_identity_authenticated',false);
plan=slproto.planAllocations(headers);regions=plan.regions;
if ~plan.available||isempty(regions),result.reason=plan.reason;return;end
regions=regions([regions.id]==70);if isempty(regions),result.reason='本帧无已定位的编号70分配';return;end
assert(isfield(calibration,'gain_per_column'));gain=repelem(calibration.gain_per_column(:),1004);
model=slproto.mcs70Model();records=cell(1,sum([regions.quantity]));n=0;
for a=1:numel(regions)
    assert(regions(a).resources_per_unit==4096);
    for j=1:regions(a).quantity
        n=n+1;first=regions(a).start_r0+(j-1)*4096;ii=first+(1:4096);z=stream(ii)./gain(ii);
        % 70与66使用相同16QAM标签；行重不同，译码器按行重分组。
        d=slproto.minsumGrouped(slproto.mcs66LLR(z,opt.likelihood_scale),model.group_supports,opt.minsum_normalization,opt.max_iterations);
        coded=slproto.encodeMCS70(d.bits(1:model.K),model);bits=reshape(double(coded),4,[]).';
        prediction=((1-2*bits(:,1)).*(3-2*bits(:,3))+1j*(1-2*bits(:,2)).*(3-2*bits(:,4)))/sqrt(10);
        control=coded;control(model.K+1:end)=~control(model.K+1:end);b=reshape(double(control),4,[]).';
        flipped=((1-2*b(:,1)).*(3-2*b(:,3))+1j*(1-2*b(:,2)).*(3-2*b(:,4)))/sqrt(10);p=model.K/4+1:4096;
        records{n}=struct('ordinal',j,'start_r0',first,'end_r0',first+4095, ...
            'initial_failed_checks',d.initial_failed_checks,'final_failed_checks',d.final_failed_checks, ...
            'decoder_hard_changes',d.hard_changes,'iterations',d.iterations,'converged',d.converged, ...
            'reencode_matches_decoded_word',isequal(coded,d.bits), ...
            'parity_remodulation_nmse',sum(abs(z(p)-prediction(p)).^2)/sum(abs(z(p)).^2), ...
            'parity_flip_control_nmse',sum(abs(z(p)-flipped(p)).^2)/sum(abs(z(p)).^2), ...
            'information_bits',d.bits(1:model.K),'decoded_codeword',d.bits);
    end
end
result.available=true;result.reason='固定接收等价QC模型；其他未识别编号保持未知';result.words=[records{:}];result.word_count=n;
result.N=model.N;result.K=model.K;result.Z=model.Z;result.H_rank=model.rank_H;result.Hp_rank=model.rank_Hp;
result.GH_orthogonal=model.GH_orthogonal_implicit;result.rate_numerator=25;result.rate_denominator=32;
result.all_converged=all([result.words.converged]);result.all_reencode_matches=all([result.words.reencode_matches_decoded_word]);
result.likelihood_scale=opt.likelihood_scale;result.message_clip=50;result.calibration='FIT pilot gain only; no target-field phase/gain fitting';
end
