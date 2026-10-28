function result = test_discrete_visualization(root, sourceRun, out)
%TEST_DISCRETE_VISUALIZATION 原采样、CP、FFT和类别图的独立坐标/值检查。
assert(~isfolder(out),'请使用新的测试目录');mkdir(out);
addpath(fullfile(root,'matlab','learning_receiver'));
context=slrx.diag.loadLesson(sourceRun,root);cfg=context.cfg;cfg.show_figures=false;
opts=struct('symbols',50,'carrier_mode','payload','frequency_band_mhz',[-120 120], ...
    'geometry_id',[],'normalization','none','grid_columns',1:301,'selected_row',65, ...
    'max_points',6000,'low_channel_fraction',.1,'show_figures',false);

% 非零起点和同一时间窗；用已知序列独立计算，不依赖真实帧头数值。
shifted=cfg;shifted.first_complex_sample=201;
fixture=struct('cfg',shifted,'capture',struct('iq',complex((1:80)',-(1:80)'), ...
    'first_complex_sample',201),'sampled',struct('iq',complex((1:77)',2*(1:77)')));
v=slrx.diag.sampleView(fixture,1,32);
assert(isequal(v.raw_positions,(201:232)')&&isequal(v.model_indices,(1:30)'));
assert(max(abs(v.raw_time_ns-(0:31)'*4))<1e-10);
assert(max(abs(v.model_time_ns-(0:29)'*(1e9/cfg.model_fs_hz)))<1e-9);
assert(isequal(v.model_values,fixture.sampled.iq(1:30)));
v=slrx.diag.sampleView(fixture,2,32);assert(all(v.model_time_ns>=0)&&all(v.model_time_ns<=124+1e-9));
fixture=rmfield(fixture,'sampled');v=slrx.diag.sampleView(fixture,79,32);
assert(numel(v.raw_indices)==2&&~v.model_available&&isempty(v.model_values));

[fig,capture]=slrx.viz.plotCapture(context,opts);h=findall(fig,'Tag','slrx-capture-I');
assert(isequal(h.YData(:),real(capture.sample_view.raw_values)));
assert(numel(h.XData)==32);close(fig);
fig=slrx.viz.plotSampleWindow(context.capture.iq,cfg.capture_fs_hz,'原采样',false);
h=findall(fig,'Tag','slrx-window-Q');assert(isequal(h.YData(:),imag(context.capture.iq(1:32))));close(fig);

[fig,cp]=slrx.viz.plotCP(context,opts);
assert(isequal(cp.cp_symbol_indices_0based,0:31)&&isequal(cp.tail_symbol_indices_0based,1024:1055));
h=findall(fig,'Tag','slrx-cp-I');assert(isequal(h.YData(:),real(cp.cp)));assert(numel(h.XData)==32);close(fig);
[fig,ofdm]=slrx.viz.plotOFDM(context,opts);
assert(isequal(ofdm.cp_boundary.indices_0based,0:63));
assert(isequal(ofdm.cp_boundary.values(33:64),context.ofdm2.without_cp(1:32,51)));
assert(isequal(ofdm.valid_local.values,context.ofdm2.without_cp(1:32,51)));
assert(isequal(ofdm.local_fft.values,context.fft2.values(ofdm.local_fft.matlab_rows,51)));
assert(numel(ofdm.local_fft.signed_bins)==32&&all(diff(ofdm.local_fft.signed_bins)==1));
h=findall(fig,'Tag','slrx-local-fft');assert(isequal(h.YData(:),abs(ofdm.local_fft.values(:))));close(fig);
edgeOptions=opts;edgeOptions.selected_row=513;[fig,edge]=slrx.viz.plotOFDM(context,edgeOptions);
assert(edge.local_fft.signed_bins(1)==-512&&edge.local_fft.matlab_rows(1)==513);close(fig);
edgeOptions.selected_row=512;[fig,edge]=slrx.viz.plotOFDM(context,edgeOptions);
assert(edge.local_fft.signed_bins(end)==511&&edge.local_fft.matlab_rows(end)==512);close(fig);

fig=slrx.viz.plotLocalSync(context.sync,cfg,false);h=findall(fig,'Tag','slrx-local-pss');
assert(isequal(h.XData(:),context.sync.selected.sync_local_curve.lag_model_samples(:)));
assert(isequal(h.YData(:),context.sync.selected.sync_local_curve.pss(:)));close(fig);
fig=slrx.viz.plotCardinality(context.classes1,cfg);h=findall(fig,'Tag','slrx-cardinality-scores');
assert(isequal(h.YData(:),context.classes1.scores(:,cfg.display_data_column)));
h=findall(fig,'Tag','slrx-cardinality-steps');assert(isequal(h.YData(1:300),context.classes1.selected_cardinality));close(fig);
pilots=slrx.diag.pilotMetrics(context);figs=slrx.viz.plotPilots(context,opts,pilots);
for k=[1 3]
    if k==1,tag='slrx-symbol-evm';else,tag='slrx-pilot-phase';end
    handles=findall(figs(k),'Tag',tag);assert(~isempty(handles));
    assert(all(arrayfun(@(h)strcmp(h.LineStyle,'none'),handles)));
end
close(figs);

% 主线仍按原文件名导出，实际执行已修改的各个绘图分支。
cfg.run_dir=fullfile(out,'main_flow');mkdir(cfg.run_dir);
slrx.drawStep(cfg,'01_capture',1,context.capture);
slrx.drawStep(cfg,'02_resampled',2,context.sampled);
slrx.drawStep(cfg,'05_without_cp',5,context.ofdm1);
slrx.drawStep(cfg,'09_pilot_observations',9,context.pilots1);
slrx.drawStep(cfg,'10_cardinality',10,context.classes1);
report=slrx.diag.exportDiagnostics(context,opts,fullfile(out,'report'));
assert(numel(report.figures)==15&&report.raw_bin_reads==0&&report.source_checkpoint_hashes_unchanged);
reference=jsondecode(fileread(fullfile(sourceRun,'learning_validation.json')));
assert(report.pilots.records(6).calibrated_evm==reference.final_heldout_pilot_evm);
result=struct('status','passed','same_time_sampling_grids',true,'truncated_and_missing_samples',true, ...
    'CP_pair_indices_and_values',true,'local_FFT_rows_bins_values',true,'negative_and_positive_FFT_edges',true, ...
    'local_sync_scores_unchanged',true,'category_scores_unchanged',true,'observations_are_unconnected_points',true, ...
    'main_flow_exports',true,'report_png_count',15,'raw_bin_reads',0,'source_checkpoints_unchanged',true, ...
    'final_EVAL_evm_unchanged',report.pilots.records(6).calibrated_evm);
slrx.diag.writeJSON(fullfile(out,'discrete_visualization_tests.json'),result);
fprintf('DISCRETE_VISUALIZATION_TESTS_PASSED\n');
end
