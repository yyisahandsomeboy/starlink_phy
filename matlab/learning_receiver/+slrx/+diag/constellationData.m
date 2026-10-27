function view = constellationData(context, options)
%CONSTELLATIONDATA 两轮严格分开；每轮三阶段使用同一行、列及共同显示因子。
cfg=context.cfg; refs=context.refs;
symbols=options.symbols(:).';
validateattributes(symbols,{'numeric'},{'integer','>=',1,'<=',cfg.data_column_count});
assert(isscalar(symbols)||all(diff(symbols)==1),'slrx:DiagnosticSelection','多符号模式必须连续');
switch options.carrier_mode
    case {'payload','positive','negative','band'}
        rows=refs.payload_rows;
    case 'fit_pilots', rows=refs.fit_rows(:);
    case 'eval_pilots', rows=refs.eval_rows(:);
    otherwise, error('slrx:DiagnosticSelection','未知子载波模式');
end
frequency=slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(rows),cfg);
if strcmp(options.carrier_mode,'positive'), rows=rows(frequency>0);
elseif strcmp(options.carrier_mode,'negative'), rows=rows(frequency<0); end
frequency=slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(rows),cfg);
rows=rows(frequency>=options.frequency_band_mhz(1) & frequency<=options.frequency_band_mhz(2));
assert(~isempty(rows),'slrx:DiagnosticSelection','所选频段内没有请求的子载波');
if ~isempty(options.geometry_id)
    assert(isfield(context,'track2'),'slrx:DiagnosticSelection','按候选几何筛选需要最终跟踪结果');
    symbols=symbols(ismember(context.track2.geometry_id(symbols),options.geometry_id));
    assert(~isempty(symbols),'slrx:DiagnosticSelection','所选符号没有匹配的候选几何');
end
columns=symbols+1;
[rowMap,columnMap]=ndgrid(rows,columns);
flat=unique(round(linspace(1,numel(rowMap),min(options.max_points,numel(rowMap)))));
view=struct('rows',rows(:),'symbols',symbols,'grid_columns',columns, ...
    'row_map',rowMap,'column_map',columnMap,'display_flat_indices',flat, ...
    'display_rows',rowMap(flat),'display_columns',columnMap(flat), ...
    'total_selected_points',numel(rowMap),'normalization',options.normalization, ...
    'display_transform_only',true,'carrier_mode',options.carrier_mode, ...
    'frequency_band_mhz',options.frequency_band_mhz,'candidate_geometry_filter',options.geometry_id, ...
    'mixed_symbol_warning','多列可能有不同几何/增益；合并点云不能证实一种商业调制');
fields={'fft1','eq1','track1';'fft2','eq2','track2'};
names={'FFT后/均衡前','信道均衡后','ML残余跟踪后'};
stages=struct('round',{},'name',{},'source',{},'available',{},'raw_values',{}, ...
    'display_values',{},'display_divisor',{},'raw_rms',{},'raw_max_abs',{});
for pass=1:2
    factor=1;
    if strcmp(options.normalization,'common_rms')
        for j=3:-1:1
            field=fields{pass,j};
            if isfield(context,field)
                data=context.(field).values(rows,columns);factor=max(sqrt(mean(abs(data(:)).^2)),eps);break;
            end
        end
    end
    for j=1:3
        field=fields{pass,j}; available=isfield(context,field);
        z=[];rmsValue=NaN;maximum=NaN;
        if available
            z=context.(field).values(rows,columns);
            rmsValue=sqrt(mean(abs(z(:)).^2));maximum=max(abs(z(:)));
        end
        stages(end+1)=struct('round',pass,'name',names{j},'source',field, ...
            'available',available,'raw_values',z,'display_values',z/factor, ...
            'display_divisor',factor,'raw_rms',rmsValue,'raw_max_abs',maximum); %#ok<AGROW>
    end
end
view.stages=stages;
view.observed_stage_count=sum([stages.available]);
view.resource_count_meaning='total_selected_points是请求的资源位置数；缺失阶段没有观测点，不将请求数当已恢复点数';
end
