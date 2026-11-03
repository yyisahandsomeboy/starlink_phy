function result = analyzeCode5(stream,headers,opt)
%ANALYZECODE5 只处理CRC支持的第一组code5分配；未识别的格式不套用此H。
result=struct('available',false,'reason','第一组头部未通过或不是已支持的格式5', ...
    'model','code5-qc128-utexas-v1','word_count',0,'words',struct([]), ...
    'business_payload_decoded',false,'format_identity','receiver-conditional code5; not authenticated standard');
h=headers.first;if ~opt.enable_code5||~h.accepted,return;end
entries=h.fields.entries;if numel(entries)~=1||entries.index8~=5,return;end
count=entries.quantity;if count<1||228+count*2048>numel(stream),result.reason='分配长度越界或为空';return;end
model=slproto.code5Model();result.available=true;result.reason='CRC支持的条件分配；固定H/P模型，不从当前字拟合';result.word_count=count;
records=cell(1,count);
for j=1:count
    first=228+(j-1)*2048;x=stream(first+(1:2048));llr=4*real(x)/opt.likelihood_scale;
    d=slproto.minsum(llr,model.H,opt.minsum_normalization,opt.max_iterations);
    observed=real(x)<0;predictedParity=mod(double(observed(1:1024)).'*double(model.P),2).';
    u=d.bits(1:1024);predicted=logical(mod(double(u).'*double(model.P),2).');coded=[u;predicted];
    reference=1-2*double(coded);control=coded;control(1025:end)=~control(1025:end);
    % 只在奇偶资源比较，输入信息位置固定；同一观测、幅度单位和支持集。
    p=1025:2048;nmse=sum(abs(x(p)-reference(p)).^2)/sum(abs(x(p)).^2);
    flipped=1-2*double(control);bad=sum(abs(x(p)-flipped(p)).^2)/sum(abs(x(p)).^2);
    records{j}=struct('ordinal',j,'start_r0',first,'end_r0',first+2047, ...
        'raw_parity_prediction_errors',nnz(predictedParity~=observed(1025:end)), ...
        'initial_failed_checks',d.initial_failed_checks,'final_failed_checks',d.final_failed_checks, ...
        'decoder_hard_changes',d.hard_changes,'iterations',d.iterations,'converged',d.converged, ...
        'reencode_matches_decoded_word',isequal(coded,d.bits),'parity_remodulation_nmse',nmse, ...
        'parity_flip_control_nmse',bad,'information_bits',u,'decoded_codeword',d.bits, ...
        'likelihood_scale',opt.likelihood_scale,'llr_convention','log P(0)/P(1); positive means bit0');
end
result.words=[records{:}];result.H_rank=model.rank_H;result.GH_orthogonal=model.generator_check_orthogonal;
result.same_capture_model_development_frames=model.metadata.training_frame_indices;
end
