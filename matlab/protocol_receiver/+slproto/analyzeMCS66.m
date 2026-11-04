function result = analyzeMCS66(stream,headers,calibration,opt)
%ANALYZEMCS66 条件资源分配上的固定FEC模型；原观测只读，结果独立存储。
if nargin<4,opt=slproto.defaultOptions();end
result=struct('available',false,'reason','','id',66,'model','mcs66-qc512-utexas-v1','word_count',0,'words',struct([]), ...
    'application_plaintext_recovered',false,'commercial_identity_authenticated',false);
plan=slproto.planAllocations(headers);r=plan.regions;
if ~plan.available||isempty(r),result.reason=plan.reason;return;end
r=r([r.id]==66);if isempty(r),result.reason='本帧无已定位的编号66分配';return;end
assert(isfield(calibration,'gain_per_column'));gain=repelem(calibration.gain_per_column(:),1004);
model=slproto.mcs66Model();records=cell(1,sum([r.quantity]));n=0;
for a=1:numel(r)
    assert(r(a).resources_per_unit==4096);
    for j=1:r(a).quantity
        n=n+1;first=r(a).start_r0+(j-1)*4096;ii=first+(1:4096);z=stream(ii)./gain(ii);
        llr=slproto.mcs66LLR(z,opt.likelihood_scale);d=slproto.minsumRegular(llr,model.supports,opt.minsum_normalization,opt.max_iterations);
        usedScale=opt.likelihood_scale;initialAttempt=d.final_failed_checks;
        attempts=struct('scale',usedScale,'converged',d.converged,'final_failed_checks',d.final_failed_checks,'iterations',d.iterations);
        if ~d.converged&&isfield(opt,'mcs66_retry_scale')&&opt.mcs66_retry_scale>0&&opt.mcs66_retry_scale~=usedScale
            retry=slproto.minsumRegular(slproto.mcs66LLR(z,opt.mcs66_retry_scale),model.supports,opt.minsum_normalization,opt.max_iterations);
            attempts(2)=struct('scale',opt.mcs66_retry_scale,'converged',retry.converged,'final_failed_checks',retry.final_failed_checks,'iterations',retry.iterations);
            if retry.converged,d=retry;usedScale=opt.mcs66_retry_scale;end
        end
        coded=slproto.encodeMCS66(d.bits(1:model.K),model);bits=reshape(double(coded),4,[]).';
        prediction=((1-2*bits(:,1)).*(3-2*bits(:,3))+1j*(1-2*bits(:,2)).*(3-2*bits(:,4)))/sqrt(10);
        control=coded;control(model.K+1:end)=~control(model.K+1:end);b=reshape(double(control),4,[]).';
        flipped=((1-2*b(:,1)).*(3-2*b(:,3))+1j*(1-2*b(:,2)).*(3-2*b(:,4)))/sqrt(10);p=model.K/4+1:4096;
        records{n}=struct('ordinal',j,'start_r0',first,'end_r0',first+4095, ...
            'initial_failed_checks',d.initial_failed_checks,'final_failed_checks',d.final_failed_checks, ...
            'decoder_hard_changes',d.hard_changes,'iterations',d.iterations,'converged',d.converged, ...
            'initial_attempt_final_failed_checks',initialAttempt,'used_likelihood_scale',usedScale,'attempts',attempts, ...
            'reencode_matches_decoded_word',isequal(coded,d.bits), ...
            'parity_remodulation_nmse',sum(abs(z(p)-prediction(p)).^2)/sum(abs(z(p)).^2), ...
            'parity_flip_control_nmse',sum(abs(z(p)-flipped(p)).^2)/sum(abs(z(p)).^2), ...
            'information_bits',d.bits(1:model.K),'decoded_codeword',d.bits);
    end
end
result.available=true;result.reason='固定接收等价QC模型；非官方身份认证；高阶其他编号不套用此模型';
result.word_count=n;result.words=[records{:}];result.N=model.N;result.K=model.K;result.Z=model.Z;
result.H_rank=model.rank_H;result.Hp_rank=model.rank_Hp;result.GH_orthogonal=model.GH_orthogonal_implicit;
result.rate_numerator=3;result.rate_denominator=4;result.all_converged=all([result.words.converged]);
result.all_reencode_matches=all([result.words.reencode_matches_decoded_word]);result.likelihood_scale=opt.likelihood_scale;
result.message_clip=50;result.retried_words=nnz(arrayfun(@(w)numel(w.attempts)>1,result.words));
if isfield(opt,'mcs66_retry_scale'),result.retry_likelihood_scale=opt.mcs66_retry_scale;end
result.calibration='FIT pilot gain only; no target-field phase/gain fitting';
end
