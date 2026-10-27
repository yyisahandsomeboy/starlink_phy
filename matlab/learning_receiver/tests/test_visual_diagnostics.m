function report = test_visual_diagnostics(root, sourceRun, out)
%TEST_VISUAL_DIAGNOSTICS 合成关系单测+实际检查点资源/坐标测试，绝不冒充真实DSP恢复。
if ~exist(out,'dir'),mkdir(out);end
addpath(fullfile(root,'matlab','learning_receiver'));
cfg=slrx.defaultConfig(root);refs=slrx.references(cfg);
shifted=cfg;shifted.first_complex_sample=201;
p=[1 2 25 1234.125];raw=slrx.diag.coordinates('model_to_capture',p,shifted);
assert(raw(1)==201&&raw(3)==226);
assert(abs(raw(2)-round(raw(2)))>1e-5);
assert(max(abs(slrx.diag.coordinates('capture_to_model',raw,shifted)-p))<1e-9);
assert(max(abs(slrx.diag.coordinates('capture_to_ms',raw,shifted)-(raw-1)/cfg.capture_fs_hz*1e3))<1e-12);
assert(abs(slrx.diag.coordinates('bin_to_mhz',-512,cfg)+cfg.model_fs_hz/2/1e6)<1e-10);

context=slrx.diag.loadLesson(sourceRun,root);
assert(context.raw_bin_reads==0&&context.checkpoint_read_count==22);
baseOptions=struct('symbols',50,'carrier_mode','payload','frequency_band_mhz',[-120 120], ...
    'geometry_id',[],'normalization','none','grid_columns',1:301,'selected_row',65, ...
    'max_points',6000,'low_channel_fraction',.1,'show_figures',false);
[fig,captureInfo]=slrx.viz.plotCapture(context,baseOptions);
axesHandles=findall(fig,'Type','axes');titles=arrayfun(@(a)string(a.Title.String),axesHandles);
assert(any(contains(titles,'原始时域IQ散点图（非子载波调制星座）'))&&~captureInfo.raw_scatter_is_modulation_constellation);close(fig);
view=slrx.diag.constellationData(context,baseOptions);
assert(numel(view.rows)==numel(refs.payload_rows)&&isempty(intersect(view.rows,refs.pilot_rows)));
assert(isequal(view.grid_columns,51));
assert(isequal(view.stages(1).raw_values,context.fft1.values(view.rows,51)));
assert(isequal(view.stages(6).raw_values,context.track2.values(view.rows,51)));
opts=baseOptions;opts.symbols=49:51;opts.normalization='common_rms';multi=slrx.diag.constellationData(context,opts);
assert(multi.total_selected_points==3*numel(refs.payload_rows));
for pass=1:2
    indices=(pass-1)*3+(1:3);assert(numel(unique([multi.stages(indices).display_divisor]))==1);
end
for mode={'positive','negative','fit_pilots','eval_pilots'}
    opts=baseOptions;opts.carrier_mode=mode{1};selected=slrx.diag.constellationData(context,opts);
    bins=refs.frequency_bins(selected.rows);
    if strcmp(mode{1},'positive'),assert(all(bins>0));elseif strcmp(mode{1},'negative'),assert(all(bins<0));
    elseif strcmp(mode{1},'fit_pilots'),assert(isequal(sort(selected.rows),sort(refs.fit_rows(:))));
    else,assert(isequal(sort(selected.rows),sort(refs.eval_rows(:))));end
end
opts=baseOptions;opts.carrier_mode='band';opts.frequency_band_mhz=[-10 10];selected=slrx.diag.constellationData(context,opts);
frequencies=slrx.diag.coordinates('bin_to_mhz',refs.frequency_bins(selected.rows),cfg);assert(all(abs(frequencies)<=10));

% 精确检查非零窗口起点和小数原采样坐标，不依赖历史帧头125001。
sync=context.sync;delta=shifted.first_complex_sample-context.cfg.first_complex_sample;
sync.selected.start_sample_capture=sync.selected.start_sample_capture+delta;
for k=1:numel(sync.candidates),sync.candidates(k).start_sample_capture=sync.candidates(k).start_sample_capture+delta;end
[fig,s]=slrx.viz.plotGlobalSync(sync,shifted,false);
menu=findall(fig,'Tag','slrx-global-coordinate');
for k=1:3
    menu.Value=k;feval(menu.Callback,menu,[]);assert(fig.UserData.coordinate_mode==k);
end
assert(abs(s.selected.raw_sample-context.sync.selected.start_sample_capture-delta)<1e-8);close(fig);
[fig,s]=slrx.viz.plotLocalSync(sync,shifted,false);assert(s.trace_max_is_not_true_global_max);close(fig);
trace=slrx.diag.tracePoint(context,2,50,65);
indices=51*(cfg.nfft+cfg.cp_length)+cfg.cp_length+(1:cfg.nfft);
expected=slrx.diag.coordinates('model_to_capture',context.time2.sample_positions_nominal(indices),context.cfg);
assert(isequal(trace.capture_positions,expected)&&~trace.unique_raw_sample);

% 合成CFO：只检验显示数学关系，不计作真实Starlink恢复。
reference=[refs.pss;refs.sss];n=(0:numel(reference)-1)';f=12000;
synthetic=struct('cfg',cfg,'refs',refs);
synthetic.time1=struct('time_raw',reference.*exp(1j*2*pi*f*n/cfg.model_fs_hz), ...
    'time_cfo_compensated',reference,'sample_positions_nominal',1+n,'sample_position_start',1,'cfo_hz',f,'sfo_ppm',0);
[fig,cfo]=slrx.viz.plotCFO(synthetic,baseOptions);assert(max(abs(cfo.rounds(1).phase_after_rad))<1e-12);close(fig);

% 合成QPSK/CP/FFT：已知复制关系和缩放，检查绘图是否保持这些关系。
rng(9);C=refs.constellations{1};grid=reshape(C(randi(numel(C),cfg.nfft*(cfg.data_column_count+1),1)),cfg.nfft,[]);
time=ifft(grid,[],1)*sqrt(cfg.nfft);blocks=[time(end-cfg.cp_length+1:end,:);time];
frame=[refs.pss;blocks(:)];
synthetic.time1=struct('time_raw',frame,'time_cfo_compensated',frame, ...
    'sample_positions_nominal',(1:numel(frame))','sample_position_start',1,'cfo_hz',0,'sfo_ppm',0);
synthetic.ofdm1=struct('without_cp',time);synthetic.fft1=struct('values',grid);
synthetic.eq1=struct('values',grid);synthetic.track1=struct('values',grid);
[fig,qpskView]=slrx.viz.plotConstellationStages(synthetic,baseOptions);
assert(all(ismember(qpskView.stages(1).raw_values(:),C)));
assert(isequal(qpskView.stages(1).raw_values,qpskView.stages(2).raw_values));
assert(isequal(qpskView.stages(2).raw_values,qpskView.stages(3).raw_values));
assert(~qpskView.stages(4).available);close(fig);
[fig,cp]=slrx.viz.plotCP(synthetic,baseOptions);assert(abs(cp.correlation_after-1)<1e-12&&isequal(cp.cp,cp.tail));close(fig);
[fig,ofdm]=slrx.viz.plotOFDM(synthetic,baseOptions);assert(ofdm.symbol_length==1056&&ofdm.cp_length==32);close(fig);
fig=slrx.viz.plotFFTGrid(synthetic,baseOptions);menu=findall(fig,'Tag','slrx-grid-coordinate');menu.Value=2;feval(menu.Callback,menu,[]);
assert(fig.UserData.coordinate_mode==2&&isequal(fig.UserData.signed_bins,sort(refs.frequency_bins)));close(fig);

% SSS标定不使用EVAL：改变EVAL也不能改变估计的整体标定除数。
alpha=2+3j;synthetic.fft1.values=refs.pilots*alpha;synthetic.fft1.values(:,1)=refs.sss_grid*alpha;
synthetic.eq1.values=refs.pilots;synthetic.track1.values=refs.pilots;
metrics=slrx.diag.pilotMetrics(synthetic);assert(metrics.records(1).calibrated_evm<1e-12);
savedAlpha=metrics.records(1).calibration_divisor;
synthetic.fft1.values(refs.eval_rows,2:end)=17*synthetic.fft1.values(refs.eval_rows,2:end);
changed=slrx.diag.pilotMetrics(synthetic);assert(isequal(savedAlpha,changed.records(1).calibration_divisor));

% 原生浏览器：控件真实回调，符号与阶段切换；不打开用户其他图。
browser=BROWSE_DIAGNOSTICS(sourceRun,'Visible',false);controls=browser.UserData;
controls.first.String='51';controls.last.String='51';controls.stage.Value=4;controls.refresh();
comparison=browser.UserData.comparison;assert(comparison.UserData.view.symbols==51);close(comparison);close(browser);

% 真实读IQ检查点的部分运行：缺失21个后续步骤，不得报告完整成功。
partial=fullfile(out,'only_capture');mkdir(partial);frozenConfig=context.cfg;frozenConfig.run_dir=partial;
save(fullfile(partial,'lesson_config.mat'),'frozenConfig');
copyfile(fullfile(sourceRun,'01_capture.mat'),fullfile(partial,'01_capture.mat'));
partialReport=RUN_DIAGNOSTICS(partial,'OutputDir',fullfile(out,'partial_report'),'ShowFigures',false);
assert(~partialReport.all_22_checkpoints_present&&numel(partialReport.missing_checkpoints)==21);
assert(~any([partialReport.pilots.records.available])&&partialReport.constellations.observed_stage_count==0);
assert(~partialReport.source_validation.available&&~partialReport.business_BER_available);

report=struct('status','passed','synthetic_tests_are_not_real_recovery',true,'nonzero_window_coordinates',true, ...
    'fractional_coordinates',true,'local_zero_mapping',true,'same_rows_and_columns',true, ...
    'normalization_factors_preserved',true,'frequency_selection',true,'raw_iq_label_policy',true, ...
    'known_reference_CFO_display',true,'synthetic_QPSK_stage_display',true,'CP_copy',true,'FFT_row_bin_axes',true, ...
    'SSS_calibration_no_eval_leakage',true,'point_trace_is_interval_not_unique_sample',true,'native_browser_callbacks',true,'partial_run_not_success',true);
slrx.diag.writeJSON(fullfile(out,'visual_unit_tests.json'),report);
fprintf('VISUAL_DIAGNOSTIC_UNIT_TESTS_PASSED\n');
end
