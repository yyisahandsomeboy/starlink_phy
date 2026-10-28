function info = cfoMetrics(context)
%CFOMETRICS 只读实际取样时间、已施加旋转及分结构参考诊断；不反馈CFO。
cfg=context.cfg;refs=context.refs;L=cfg.nfft+cfg.cp_length;
assert(numel(refs.pss)==L&&numel(refs.sss)==L,'slrx:CFOReference','参考必须分别覆盖完整PSS/SSS时隙');
reference=[refs.pss(:);refs.sss(:)];rounds=cell(1,2);
for pass=1:2
    field=sprintf('time%d',pass);
    item=struct('available',isfield(context,field),'round',pass,'cfo_hz',NaN,'time_us',[], ...
        'applied_phase_rad',[],'first_last_phase_rad',[],'phase_increment_rad',NaN,'rotation_direction','不可用', ...
        'points',struct([]),'reference_groups',struct([]),'phase_before_rad',[],'phase_after_rad',[], ...
        'magnitude_relative_error',NaN,'operation_relative_error',NaN,'raw_bin_reads',0);
    if ~item.available,rounds{pass}=item;continue;end
    d=context.(field);positions=d.sample_positions_nominal(:);
    t=(positions-d.sample_position_start)/cfg.model_fs_hz;
    assert(numel(t)==numel(d.time_raw)&&numel(t)==numel(d.time_cfo_compensated)&&numel(t)>=2*L);
    applied=-2*pi*d.cfo_hz*t;selected=unique(round(linspace(1,numel(t),min(1000,numel(t)))));
    item.cfo_hz=d.cfo_hz;item.time_us=t(selected)*1e6;item.applied_phase_rad=applied(selected);
    item.first_last_phase_rad=applied([1 end]);item.phase_increment_rad=median(diff(applied));
    if item.phase_increment_rad>0,item.rotation_direction='逆时针';elseif item.phase_increment_rad<0,item.rotation_direction='顺时针';else,item.rotation_direction='不旋转';end
    before=d.time_raw(:);after=d.time_cfo_compensated(:);
    item.magnitude_relative_error=max(abs(abs(after)-abs(before)))/max(max(abs(before)),eps);
    item.operation_relative_error=norm(after-before.*exp(1j*applied))/max(norm(after),eps);
    % 固定选PSS/SSS有效区中点附近非零样本，不根据“漂亮程度”选点。
    points=struct([]);
    for g=1:2
        bounds=(g-1)*L+cfg.cp_length+(1:cfg.nfft);target=bounds(round(numel(bounds)/2));
        valid=bounds(abs(before(bounds))>max(abs(before(bounds)))*1e-8&abs(before(bounds))>eps);
        if isempty(valid),continue;end
        [~,k]=min(abs(valid-target));n=valid(k);
        point=struct('frame_index_1based',n,'model_position',positions(n),'time_us',t(n)*1e6, ...
            'before',before(n),'after',after(n),'magnitude_before',abs(before(n)),'magnitude_after',abs(after(n)), ...
            'error_angle_rad',-applied(n),'applied_phase_rad',applied(n),'principal_applied_phase_rad',angle(exp(1j*applied(n))), ...
            'measured_rotation_rad',angle(after(n)*conj(before(n))));
        if isempty(points),points=point;else,points(end+1)=point;end %#ok<AGROW>
    end
    item.points=points;
    groups=struct([]);names={'PSS','SSS'};
    for g=1:2
        % 每段各自去CP；64点块不跨CP/PSS/SSS边界。
        first=(g-1)*L+cfg.cp_length+1;last=g*L;block=64;
        nblocks=floor((last-first+1)/block);indices=reshape(first:first+nblocks*block-1,block,[]);
        p=reference(indices);a=before(indices);b=after(indices);energy=sum(abs(p).^2,1);
        times=sum(t(indices).*abs(p).^2,1)./max(energy,eps);
        ca=sum(a.*conj(p),1);cb=sum(b.*conj(p),1);
        coherenceA=abs(ca)./max(sqrt(sum(abs(a).^2,1).*energy),eps);
        coherenceB=abs(cb)./max(sqrt(sum(abs(b).^2,1).*energy),eps);
        family=ones(1,nblocks);if g==1,family=1+mod(0:nblocks-1,2);end
        % 前后使用共同有效块与相同权重，避免因筛选不同而制造改善。
        pairedCoherence=min(coherenceA,coherenceB);
        fa=phaseFit(times,ca,pairedCoherence,energy,family);
        fb=phaseFit(times,cb,pairedCoherence,energy,family);
        group=struct('name',names{g},'block_samples',block,'block_first_indices',indices(1,:), ...
            'block_last_indices',indices(end,:),'time_us',times*1e6,'family',family, ...
            'coherence_before',coherenceA,'coherence_after',coherenceB,'before',fa,'after',fb, ...
            'correlation_before',abs(reference(first:last)'*before(first:last))/max(norm(reference(first:last))*norm(before(first:last)),eps), ...
            'correlation_after',abs(reference(first:last)'*after(first:last))/max(norm(reference(first:last))*norm(after(first:last)),eps));
        if isempty(groups),groups=group;else,groups(end+1)=group;end %#ok<AGROW>
        item.phase_before_rad=[item.phase_before_rad fa.phase_rad];
        item.phase_after_rad=[item.phase_after_rad fb.phase_rad];
    end
    item.reference_groups=groups;rounds{pass}=item;
end
if isfield(context,'diagnostic_pilots'),pilots=context.diagnostic_pilots;else,pilots=slrx.diag.pilotMetrics(context);end
info=struct('rounds',[rounds{:}],'block_samples',64,'reference','PSS与SSS有效区分别分析，剔除CP', ...
    'applied_formula','a=-2*pi*f*t; z_after=z_before*exp(1j*a)', ...
    'component_formula','theta=2*pi*f*t; I_after=I*cos(theta)+Q*sin(theta); Q_after=Q*cos(theta)-I*sin(theta)', ...
    'reference_is_independent',false,'cfo_only_EVM_available',false, ...
    'reference_limit','同步参考参与原CFO估计；分块相位含信道/噪声，斜率只是受模型条件限制的代理，拟合残差不必随补偿减小', ...
    'fit_policy','诊断门限：块相干度>=0.2、至少6块、每族至少3块、加权相位残差RMS<=0.35rad；不改变接收门限', ...
    'heldout',rmfield(pilots,{'eval_rows','fit_rows','grid_columns','formula','policy'}));
info.heldout.records=rmfield(pilots.records,{'per_symbol_evm','derotated','error','phase_deg'});
info.heldout_interpretation='EVAL未参与同步/ML拟合；所列各阶段均已补偿CFO，FFT/均衡/跟踪还含其他处理，不能作为仅CFO的因果对照';
end

function fit = phaseFit(t,c,coherence,energy,family)
fit=struct('phase_rad',nan(size(t)),'fitted_phase_rad',nan(size(t)),'accepted_blocks',false(size(t)), ...
    'frequency_hz',NaN,'residual_rms_rad',NaN,'proxy_available',false,'reason','块不足、低相干或相位模型不适用', ...
    'unambiguous_frequency_hz',NaN,'interpretation','共享斜率、分族截距；非真实CFO真值或独立证据');
valid=isfinite(c)&isfinite(coherence)&coherence>=.2&energy>eps;
families=unique(family);X=zeros(numel(t),1+numel(families));X(:,1)=(t(:)-mean(t))*1e6;enough=true;
for j=1:numel(families)
    index=find(valid&family==families(j));X(:,j+1)=family(:)==families(j);
    if numel(index)<3||any(diff(index)>numel(families)),enough=false;end
    if ~isempty(index),fit.phase_rad(index)=unwrap(angle(c(index)));end
    if numel(index)>1,fit.unambiguous_frequency_hz=1/(2*max(diff(t(index))));end
end
if nnz(valid)<6||~enough,return;end
w=coherence(valid).^2;A=X(valid,:).*sqrt(w(:));y=fit.phase_rad(valid).'.*sqrt(w(:));
if rank(A)<size(A,2),return;end
coeff=A\y;pred=X*coeff;res=fit.phase_rad(valid).'-pred(valid);
fit.frequency_hz=coeff(1)*1e6/(2*pi);fit.residual_rms_rad=sqrt(sum(w(:).*res.^2)/sum(w));
fit.fitted_phase_rad=pred.';fit.accepted_blocks=valid;
fit.proxy_available=fit.residual_rms_rad<=.35;
if fit.proxy_available,fit.reason='满足显示模型条件；仍须近似稳定参考信道、相位无混叠等假设';end
end
