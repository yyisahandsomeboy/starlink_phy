function report = exportDiagnostics(context, options, out)
%EXPORTDIAGNOSTICS 只读MAT的独立诊断；一步加载、多图复用、不启动接收DSP。
assert(~exist(out,'dir'),'slrx:DiagnosticImmutable','请使用新的诊断输出目录：%s',out);
mkdir(out);figFolder=fullfile(out,'figures');mkdir(figFolder);
cfg=context.cfg;refs=context.refs;context.diagnostic_pilots=slrx.diag.pilotMetrics(context);
if isempty(options.frequency_band_mhz)
    options.frequency_band_mhz=[min(refs.frequency_bins) max(refs.frequency_bins)]*cfg.model_fs_hz/cfg.nfft/1e6;
end
if isempty(options.grid_columns),options.grid_columns=1:cfg.data_column_count+1;end
if ~isempty(options.selected_row),validateattributes(options.selected_row,{'numeric'},{'scalar','integer','>=',1,'<=',cfg.nfft});end
validateattributes(options.grid_columns,{'numeric'},{'integer','>=',1,'<=',cfg.data_column_count+1});
catalog=struct([]);sync=struct();details=struct();
[fig,details.capture]=slrx.viz.plotCapture(context,options);keep(fig,'capture','00_capture.png');
[fig,details.resampling]=slrx.viz.plotResampling(context,options);keep(fig,'resampling','00b_resampling.png');
if isfield(context,'sync')
    [fig,sync]=slrx.viz.plotGlobalSync(context.sync,cfg,options.show_figures);keep(fig,'global_sync','01_sync_global.png');
    fig=slrx.viz.plotLocalSync(context.sync,cfg,options.show_figures);keep(fig,'local_sync','02_sync_local.png');
    writetable(struct2table(sync.candidates),fullfile(out,'sync_candidates.csv'),'Encoding','UTF-8');
end
view=slrx.diag.constellationData(context,options);
options.symbols=view.symbols;
if isempty(options.selected_row)
    [~,i]=min(abs(refs.frequency_bins(view.rows)-64));options.selected_row=view.rows(i);
else,assert(ismember(options.selected_row,view.rows),'slrx:DiagnosticSelection','SelectedRow必须属于当前资源选择');end
[fig,view]=slrx.viz.plotConstellationStages(context,options);keep(fig,'constellations','03_constellation_stages.png');
fig=slrx.viz.plotConditionalModels(context,options,view);keep(fig,'models','04_conditional_models.png');
[fig,details.cfo]=slrx.viz.plotCFO(context,options);keep(fig,'cfo','05_cfo.png');
[fig,details.sfo]=slrx.viz.plotSFO(context,options);keep(fig,'sfo','06_sfo.png');
[fig,details.ofdm]=slrx.viz.plotOFDM(context,options);keep(fig,'ofdm','07_ofdm_symbol.png');
[fig,details.cp]=slrx.viz.plotCP(context,options);keep(fig,'cp','08_cp_copy.png');
fig=slrx.viz.plotFFTGrid(context,options);keep(fig,'fft','09_fft_grid.png');
[fig,details.channel]=slrx.viz.plotChannel(context,options);keep(fig,'channel','10_channel.png');
pilots=context.diagnostic_pilots;
figs=slrx.viz.plotPilots(context,options,pilots);
keep(figs(1),'evm','11_pilot_evm.png');keep(figs(2),'pilot_cloud','12_pilot_cloud.png');keep(figs(3),'pilot_errors','13_pilot_errors.png');
[fig,details.tracking]=slrx.viz.plotTracking(context,options);keep(fig,'tracking','11b_tracking.png');
fig=slrx.viz.plotGuard(context,options);keep(fig,'guard','14_guard.png');
debugFiles=slrx.viz.debugPlots(context,options,out);

% 逐点资源CSV中的区间是直接FFT有效区时间支持，不把一点说成一个IQ样本。
pointRows=struct('round',{},'stage',{},'data_symbol',{},'grid_column',{},'matlab_row',{}, ...
    'signed_bin',{},'frequency_mhz',{},'raw_I',{},'raw_Q',{},'display_divisor',{}, ...
    'capture_start',{},'capture_end',{});
rangeCache=cell(2,cfg.data_column_count);
for pass=1:2
    for symbol=view.symbols
        t=slrx.diag.tracePoint(context,pass,symbol,options.selected_row);
        range=[NaN NaN];if t.available,range=t.raw_interval;end
        rangeCache{pass,symbol}=range;
    end
end
for k=1:6
    stage=view.stages(k);if ~stage.available,continue;end
    for j=1:numel(view.display_flat_indices)
        row=view.display_rows(j);column=view.display_columns(j);z=stage.raw_values(view.display_flat_indices(j));
        range=rangeCache{stage.round,column-1};
        pointRows(end+1)=struct('round',stage.round,'stage',stage.source,'data_symbol',column-1, ...
            'grid_column',column,'matlab_row',row,'signed_bin',refs.frequency_bins(row), ...
            'frequency_mhz',slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(row),cfg), ...
            'raw_I',real(z),'raw_Q',imag(z),'display_divisor',stage.display_divisor, ...
            'capture_start',range(1),'capture_end',range(2)); %#ok<AGROW>
    end
end
writetable(struct2table(pointRows),fullfile(out,'point_resources.csv'),'Encoding','UTF-8');
trace1=slrx.diag.tracePoint(context,1,options.symbols(1),options.selected_row);
trace2=slrx.diag.tracePoint(context,2,options.symbols(1),options.selected_row);
save(fullfile(out,'diagnostics_data.mat'),'view','pilots','sync','details','trace1','trace2','-v7.3');

% 建立统一摘要时只读已加载结构。输出写在新诊断目录，不覆盖历史记录。
summaryCfg=cfg;summaryCfg.run_dir=out;
for k=1:numel(context.sources)
    source=context.sources(k);
    names=slrx.diag.stepFigures(source.key);
    names=names(cellfun(@(name)isfile(fullfile(figFolder,name)),names));
    slrx.diag.summarizeStep(summaryCfg,source.key,context.(source.field),context.run_dir,names);
end
stepFile=fullfile(out,'diagnostics_summary.json');
report=jsondecode(fileread(stepFile));
report.status='generated_for_available_checkpoints';
report.frame_rank=cfg.frame_rank;
report.generated_at=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
report.source_run=context.run_dir;report.source_checkpoints=context.sources;
report.missing_checkpoints=context.missing;
report.all_22_checkpoints_present=isempty(context.missing);
report.source_validation=struct('available',false,'scope','not rerun by visualization');
validationFile=fullfile(context.run_dir,'learning_validation.json');
if exist(validationFile,'file')
    report.source_validation=struct('available',true,'scope','existing saved validation; visualization does not rerun DSP', ...
        'file',validationFile,'data',jsondecode(fileread(validationFile)));
end
report.figures=catalog;report.options=options;report.sync=sync;report.debug_files=debugFiles;
report.constellations=rmfield(view,{'row_map','column_map','display_rows','display_columns'});
report.constellations.stages=rmfield(view.stages,{'raw_values','display_values'});
report.pilots=pilots;report.pilots.records=rmfield(pilots.records,{'derotated','error','phase_deg'});
report.details=details;
% 完整1024点坐标序列留MAT，小JSON只放区间。
if isfield(report.details,'ofdm')&&isfield(report.details.ofdm,'trace')
    t=report.details.ofdm.trace;
    if t.available,t=rmfield(t,{'model_positions','capture_positions'});end
    report.details.ofdm.trace=t;
end
report.receiver_results_modified=false;report.raw_bin_reads=context.raw_bin_reads;
report.checkpoint_read_count=context.checkpoint_read_count;
report.source_checkpoint_hashes_unchanged=true;
for k=1:numel(context.sources)
    assert(strcmp(slrx.sha256(context.sources(k).path),context.sources(k).sha256), ...
        'slrx:DiagnosticMutation','诊断期间源检查点发生改变：%s',context.sources(k).path);
end
slrx.diag.writeJSON(stepFile,report);
slrx.diag.writeReport(out,report);
fprintf('DIAGNOSTICS_CREATED %s\nPNG=%d；原BIN读取次数=%d；已加载检查点=%d\n',out,numel(catalog),context.raw_bin_reads,context.checkpoint_read_count);
    function keep(fig,key,name)
        item=slrx.diag.chartCatalog(key,['figures/' name]);
        switch key
            case 'capture',item.available=isfield(context,'capture');
            case 'resampling',item.available=isfield(context,'sampled');
            case 'tracking',item.available=isfield(context,'track1')||isfield(context,'track2');
            case {'global_sync','local_sync'},item.available=isfield(context,'sync');
            case {'constellations','evm','pilot_cloud','pilot_errors'},item.available=any([viewAvailable()]);
            case 'models',item.available=isfield(context,'track1')||isfield(context,'track2');
            case {'cfo','sfo','ofdm','cp'},item.available=isfield(context,'time1')||isfield(context,'time2');
            case 'fft',item.available=isfield(context,'fft1')||isfield(context,'fft2');
            case 'channel',item.available=isfield(context,'channel1')||isfield(context,'channel2');
            case 'guard',item.available=isfield(context,'guard');
        end
        item.current_fact='尚无对应检查点；空面板不表示该步骤成功。';
        if item.available
            switch key
                case 'capture'
                    item.current_fact=sprintf('实际输入RMS=%.8g；截幅比例=%.8g；局部%d点，原/模型采样间隔 %.6g / %.6g ns；本页未重读BIN。',context.capture.rms,context.capture.clipped_fraction,numel(details.capture.sample_view.raw_indices),details.capture.sample_view.raw_spacing_ns,details.capture.sample_view.model_spacing_ns);
                case 'resampling'
                    item.current_fact=sprintf('N %.0f→%.0f；Fs %.9g→%.9gHz；N/Fs %.8g→%.8gs；去DC前/后|均值| %.5g→%.5g。',details.resampling.input_count,details.resampling.output_count,details.resampling.input_fs_hz,details.resampling.output_fs_hz,details.resampling.input_duration_s,details.resampling.output_duration_s,abs(details.resampling.before_dc_removal),abs(details.resampling.after_dc_removal));
                case 'tracking'
                    item.current_fact=sprintf('已保存ML轮数=%d；逐列残差和内点均直接读取，不重新拟合。',numel(details.tracking.rounds));
                case {'global_sync','local_sync'}
                    s=sync.selected;
                    item.current_fact=sprintf('选中%s；raw=%.12g；model=%.12g；%.9fms；PSS=%.6f；SSS=%.6f。',s.candidate_id,s.raw_sample,s.model_sample,s.time_ms,s.pss_score,s.sss_score);
                case {'constellations','models'}
                    item.current_fact=sprintf('实际选中%d列×%d子载波，显示%d/%d点；归一化=%s，变换参数保留在MAT。',numel(view.symbols),numel(view.rows),numel(view.display_flat_indices),view.total_selected_points,options.normalization);
                case 'cfo'
                    item.current_fact=sprintf('实际已生成的取帧轮次CFO/Hz：%s；参考相位只作诊断，不反馈算法。',mat2str([details.cfo.rounds.cfo_hz],10));
                case 'sfo'
                    item.current_fact=sprintf('实际取帧轮次SFO/ppm：%s；帧末漂移/ns：%s。',mat2str([details.sfo.rounds.sfo_ppm],9),mat2str([details.sfo.rounds.last_drift_ns],9));
                case 'ofdm'
                    item.current_fact=sprintf('第%d轮数据符号%d：%d=%d+%d；去CP部分与保存的without_cp逐值核对。',details.ofdm.round,details.ofdm.data_symbol,details.ofdm.symbol_length,cfg.cp_length,cfg.nfft);
                case 'cp'
                    item.current_fact=sprintf('本轮CFO补偿前/后|rho|：%.7f / %.7f。复相关值另存MAT/JSON。',abs(details.cp.correlation_before),abs(details.cp.correlation_after));
                case 'fft'
                    item.current_fact=sprintf('FFT列范围%s；纵轴频段%sMHz。MATLAB原行号映射保留，未更改矩阵。',mat2str([options.grid_columns(1) options.grid_columns(end)]),mat2str(options.frequency_band_mhz));
                case 'channel'
                    item.current_fact=sprintf('第%d轮：低H诊断线=%.8g，共%d个有效行低于该线；这不是新增通过门限。',details.channel.round,details.channel.low_threshold,numel(details.channel.low_rows));
                case {'evm','pilot_cloud','pilot_errors'}
                    item.current_fact=sprintf('六阶段SSS约定EVAL导频EVM：%s；NaN是阶段缺失，不是0误差。',mat2str([pilots.records.calibrated_evm],8));
                case 'guard'
                    item.current_fact=sprintf('模型保护窗/前窗平均功率=%.8g；窗口完整=%d。',context.guard.power_ratio,context.guard.in_capture);
            end
        end
        note=struct('purpose',item.purpose,'data_source',item.data_source,'calculation',item.calculation, ...
            'focus',item.normal_or_diagnostic_pattern,'current_result',item.current_fact,'limitations',item.limitations);
        slrx.viz.teachingNotes(fig,note);slrx.viz.saveFigure(fig,figFolder,name,options.show_figures);
        if isempty(catalog),catalog=item;else,catalog(end+1)=item;end
    end
    function available=viewAvailable()
        available=cellfun(@(name)isfield(context,name),{'fft1','eq1','track1','fft2','eq2','track2'});
    end
end
