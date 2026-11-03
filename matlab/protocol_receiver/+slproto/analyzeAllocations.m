function a = analyzeAllocations(stream,headers,calibrated,pilots)
%ANALYZEALLOCATIONS 按资源而非整列判决；保留观测，单独导出条件几何索引。
registry=slproto.allocationRegistry();plan=slproto.planAllocations(headers,registry,numel(stream));
a=struct('available',plan.available,'complete',plan.complete,'plan',plan,'profile',registry, ...
    'transmitter_bit_mapping_verified',false,'application_plaintext_recovered',false);
if ~plan.available,return;end
cal=slproto.resourceCalibration(calibrated,pilots);g=repelem(cal.gain_per_column(:),1004);v=repelem(cal.variance_per_column(:),1004);a.calibration=cal;
N=numel(stream);a.region_index=zeros(N,1,'uint8');a.symbol_index=zeros(N,1,'uint8');
a.decided_symbol=complex(nan(N,1));a.boundary_uncertain=false(N,1);a.regions=struct([]);
bank={'BPSK','QPSKaxes','QPSKdiag','16QAM','32cross','64QAM'};
for j=1:numel(plan.regions)
    r=plan.regions(j);ii=(r.start_r0+1:r.end_exclusive_r0)';C=slproto.alphabet(r.alphabet);
    [~,idx,residual]=slproto.symbolLikelihood(stream(ii),C,g(ii),v(ii));
    a.region_index(ii)=uint8(j);a.symbol_index(ii)=idx;a.decided_symbol(ii)=C(double(idx));
    % r0奇数为留出资源；FIT导频参数在看载荷前固定。
    test=ii(mod(ii-1,2)==1);if numel(test)>10000,test=test(round(linspace(1,numel(test),10000)));end
    scores=zeros(1,numel(bank));for b=1:numel(bank),scores(b)=mean(slproto.symbolLikelihood(stream(test),slproto.alphabet(bank{b}),g(test),v(test)));end
    [~,winner]=min(scores);r.EVAL_symbol_count=numel(test);r.alphabet_bank=bank;r.EVAL_mean_NLL=scores;
    r.EVAL_winner=bank{winner};r.expected_wins=strcmp(r.alphabet,r.EVAL_winner);
    r.decision_directed_NMSE=sum(residual)/sum(abs(stream(ii)).^2);r.symbol_errors_measured=false;
    if isempty(a.regions),a.regions=r;else,a.regions(end+1)=r;end %#ok<AGROW>
end
a.boundaries=slproto.fitAllocationBoundaries(stream,plan,g,v);
if a.boundaries.available
    for j=1:2
        bounds=sort([a.boundaries.predicted_r0(j) a.boundaries.signal_fit_r0(j)]);
        lo=max(0,bounds(1)-4);hi=min(N,bounds(2)+5);a.boundary_uncertain(lo+1:hi)=true;
    end
end
a.uncertain_resource_count=nnz(a.boundary_uncertain);
a.unresolved_resource_count=nnz(a.region_index==0);
% 只有跨越不同字母表的列才比较；基线在r0偶数上选一个整列模型，在同列奇数上评价。
a.mixed_columns=struct([]);
for col=2:301
    ii=((col-2)*1004+(1:1004))';ri=unique(a.region_index(ii));ri(ri==0)=[];
    if numel(ri)<2||numel(unique({plan.regions(double(ri)).alphabet}))<2,continue;end
    train=ii(mod(ii-1,2)==0);test=ii(mod(ii-1,2)==1);fit=zeros(size(bank));eval=fit;
    for b=1:numel(bank)
        C=slproto.alphabet(bank{b});fit(b)=mean(slproto.symbolLikelihood(stream(train),C,g(train),v(train)));
        eval(b)=mean(slproto.symbolLikelihood(stream(test),C,g(test),v(test)));
    end
    [~,b]=min(fit);nll=zeros(size(test));
    for k=double(ri(:).')
        jj=a.region_index(test)==k;nll(jj)=slproto.symbolLikelihood(stream(test(jj)),slproto.alphabet(plan.regions(k).alphabet),g(test(jj)),v(test(jj)));
    end
    item=struct('column',col,'region_indices',double(ri(:).'),'single_column_model_selected_on_FIT',bank{b}, ...
        'single_column_EVAL_NLL',eval(b),'resource_model_EVAL_NLL',mean(nll),'EVAL_NLL_improvement',eval(b)-mean(nll),'EVAL_count',numel(test));
    if isempty(a.mixed_columns),a.mixed_columns=item;else,a.mixed_columns(end+1)=item;end %#ok<AGROW>
end
a.symbol_indices_are_bit_mapping=false;
end
