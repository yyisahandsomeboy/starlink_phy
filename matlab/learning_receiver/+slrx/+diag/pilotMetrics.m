function metrics = pilotMetrics(context)
%PILOTMETRICS 相同EVAL资源；SSS标量标定另存参数，绝不以EVAL拟合增益。
cfg=context.cfg; refs=context.refs;
fields={'fft1','eq1','track1','fft2','eq2','track2'};
P=refs.pilots(refs.eval_rows,2:cfg.data_column_count+1);
records=struct('stage',{},'round',{},'available',{},'raw_evm',{},'calibrated_evm',{}, ...
    'calibration_divisor',{},'calibration_source',{},'per_symbol_evm',{},'derotated',{},'error',{},'phase_deg',{});
for k=1:numel(fields)
    field=fields{k}; available=isfield(context,field); rawEvm=NaN; evm=NaN; alpha=1;
    per=[];ratio=[];errorValue=[];phase=[];calibration='none; already in receiver output units';
    if available
        G=context.(field).values;
        Z=G(refs.eval_rows,2:cfg.data_column_count+1);
        rawEvm=sqrt(sum(abs(Z-P).^2,'all')/sum(abs(P).^2,'all'));
        if startsWith(field,'fft')
            active=find(abs(refs.sss_grid)>eps);
            alpha=sum(conj(refs.sss_grid(active)).*G(active,1))/sum(abs(refs.sss_grid(active)).^2);
            assert(isfinite(alpha)&&abs(alpha)>eps,'slrx:DiagnosticCalibration','SSS整体增益不可用');
            calibration='SSS-only scalar; diagnostic reference calibration, not receiver output';
        end
        calibrated=Z/alpha;
        evm=sqrt(sum(abs(calibrated-P).^2,'all')/sum(abs(P).^2,'all'));
        per=sqrt(sum(abs(calibrated-P).^2,1)./sum(abs(P).^2,1));
        ratio=calibrated./P;errorValue=abs(calibrated-P);
        phase=angle(ratio)*180/pi;
    end
    records(end+1)=struct('stage',field,'round',1+(k>3),'available',available, ...
        'raw_evm',rawEvm,'calibrated_evm',evm,'calibration_divisor',alpha, ...
        'calibration_source',calibration,'per_symbol_evm',per,'derotated',ratio, ...
        'error',errorValue,'phase_deg',phase); %#ok<AGROW>
end
metrics=struct('eval_rows',refs.eval_rows,'fit_rows',refs.fit_rows, ...
    'grid_columns',2:cfg.data_column_count+1,'records',records, ...
    'formula','sqrt(sum(abs(Z-P).^2)/sum(abs(P).^2))', ...
    'policy','EVAL从不参与标定或拟合；FFT阶段的SSS标量除法仅用于诊断参考标定；同时保留未标定EVM', ...
    'business_BER_available',false,'business_SER_available',false);
end
