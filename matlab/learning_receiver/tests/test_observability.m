function result = test_observability(root,sourceRun,out)
%TEST_OBSERVABILITY 合成CFO/SFO与真实只读诊断；不冒充业务真值。
assert(~isfolder(out));mkdir(out);addpath(fullfile(root,'matlab','learning_receiver'));
cfg=slrx.defaultConfig(root);cfg.show_figures=false;refs=slrx.references(cfg);
N=cfg.frame_symbol_count*(cfg.nfft+cfg.cp_length);start=123.375;ppm=23.7;
t=(0:N-1)'/(1+ppm*1e-6)/cfg.model_fs_hz;p=[refs.pss;refs.sss;zeros(N-numel(refs.pss)-numel(refs.sss),1)];
L=cfg.nfft+cfg.cp_length;p(1:L)=p(1:L)*exp(.8j);p(L+1:2*L)=p(L+1:2*L)*exp(-1.1j);
trueCFO=12000;applied=10000;
d=struct('time_raw',.7*p.*exp(1j*2*pi*trueCFO*t),'time_cfo_compensated',[], ...
    'sample_positions_nominal',start+t*cfg.model_fs_hz,'sample_position_start',start,'cfo_hz',applied,'sfo_ppm',ppm);
d.time_cfo_compensated=d.time_raw.*exp(-1j*2*pi*applied*t);
fixture=struct('cfg',cfg,'refs',refs,'time1',d);info=slrx.diag.cfoMetrics(fixture);a=info.rounds(1);
assert(a.magnitude_relative_error<1e-12&&a.operation_relative_error<1e-10);
assert(max(abs(a.first_last_phase_rad+2*pi*applied*t([1 end])))<1e-9);
assert(abs(a.phase_increment_rad+2*pi*applied/(cfg.model_fs_hz*(1+ppm*1e-6)))<1e-10);
assert(strcmp(a.rotation_direction,'顺时针'));
for k=1:2
    g=a.reference_groups(k);
    assert(abs(g.before.frequency_hz-trueCFO)<2&&abs(g.after.frequency_hz-(trueCFO-applied))<2);
    assert(g.before.proxy_available&&g.after.proxy_available);
    assert(isequal(g.before.accepted_blocks,g.after.accepted_blocks),'前后拟合必须采用同一有效参考块');
    assert(all(g.block_first_indices>=(k-1)*L+cfg.cp_length+1)&&all(g.block_last_indices<=k*L));
end
for k=1:numel(a.points)
    x=a.points(k);theta=x.error_angle_rad;expected=complex(real(x.before)*cos(theta)+imag(x.before)*sin(theta), ...
        imag(x.before)*cos(theta)-real(x.before)*sin(theta));
    assert(abs(x.after-expected)<1e-12);
end
assert(~info.reference_is_independent&&~info.cfo_only_EVM_available);
% 负CFO完整补偿；两结构具有不同固定相位，仍独立分析。
d.cfo_hz=-trueCFO;d.time_raw=.7*p.*exp(-1j*2*pi*trueCFO*t);d.time_cfo_compensated=.7*p;
fixture.time2=d;info=slrx.diag.cfoMetrics(fixture);
assert(strcmp(info.rounds(2).rotation_direction,'逆时针'));
assert(abs(info.rounds(2).reference_groups(1).after.frequency_hz)<1e-6);
options=slrx.diag.plotOptions(cfg);[fig,info]=slrx.viz.plotCFO(fixture,options);
menu=findall(fig,'Tag','slrx-cfo-round');assert(fig.UserData.selected_round==2);
menu.Value=1;feval(menu.Callback,menu,[]);assert(fig.UserData.selected_round==1);close(fig);
fixture.time1.time_raw(:)=0;fixture.time1.time_cfo_compensated(:)=0;
info=slrx.diag.cfoMetrics(fixture);assert(~info.rounds(1).reference_groups(1).after.proxy_available);

context=slrx.diag.loadLesson(sourceRun,root);cfg=context.cfg;cfg.show_figures=false;options=slrx.diag.plotOptions(cfg);
resample=slrx.diag.resampleMetrics(context);
assert(resample.input_count==1000000&&resample.output_count==960000);
assert(abs(resample.input_duration_s-resample.output_duration_s)<1e-12);
assert(abs(resample.after_dc_removal)<1e-12);
realCFO=slrx.diag.cfoMetrics(context);
assert(all([realCFO.rounds.magnitude_relative_error]<1e-12)&&all([realCFO.rounds.operation_relative_error]<1e-8));
report=slrx.diag.exportDiagnostics(context,options,fullfile(out,'report'));
assert(numel(report.figures)==17&&report.raw_bin_reads==0&&report.source_checkpoint_hashes_unchanged);
assert(~isfolder(fullfile(out,'report','debug')));
% 新默认主线无需打开密集I波形；全部分支使用旧MAT执行绘图。
cfg.run_dir=fullfile(out,'main');mkdir(cfg.run_dir);
mapping={'01_capture',1,'capture';'02_resampled',2,'sampled';'03_sync',3,'sync'; ...
    '04_frame_time',4,'time1';'05_without_cp',5,'ofdm1';'06_fft_grid',6,'fft1';'07_channel',7,'channel1'; ...
    '08_equalized',8,'eq1';'09_pilot_observations',9,'pilots1';'10_cardinality',10,'classes1';'11_tracking',11,'track1'; ...
    '13a_frame_time',4,'time2';'13b_without_cp',5,'ofdm2';'13c_fft_grid',6,'fft2';'13d_channel',7,'channel2'; ...
    '13e_equalized',8,'eq2';'13f_pilots',9,'pilots2';'13g_cardinality',10,'classes2';'13h_tracking',11,'track2'; ...
    '14_decisions',14,'decisions';'15_guard',15,'guard'};
for k=1:size(mapping,1)
    stepContext=context;
    % 模拟实时步骤：当前CFO步骤不偷看后续FFT、EVAL、另一轮或ML结果。
    if mapping{k,2}==4,stepContext=struct('refs',context.refs);end
    slrx.drawStep(cfg,mapping{k,1},mapping{k,2},context.(mapping{k,3}),stepContext);
end
assert(numel(dir(fullfile(cfg.run_dir,'figures','*.png')))==22);
slrx.drawStep(cfg,'12_refined_offsets',12,context.offsets,context);
assert(numel(dir(fullfile(cfg.run_dir,'figures','*.png')))==22,'第12步仅数值更新，不额外生成图片');
assert(~isfolder(fullfile(cfg.run_dir,'figures','debug')));
debugOptions=options;debugOptions.debug_plots=true;
debugFiles=slrx.viz.debugPlots(context,debugOptions,fullfile(out,'advanced'));
assert(numel(debugFiles)==3&&isfile(fullfile(out,'advanced','debug','cfo_dense_round1.png')));
result=struct('status','passed','synthetic_CFO_sign_and_SFO_time',true,'different_PSS_SSS_intercepts',true, ...
    'block_boundaries',true,'zero_signal_rejects_proxy',true,'rotation_component_identity',true, ...
    'resample_counts_duration_DC',true,'real_rotation_invariance',true,'same_reference_not_independent',true, ...
    'main_default_pngs',22,'report_default_pngs',17,'debug_only_explicit',true, ...
    'source_MAT_hashes_unchanged',true,'raw_bin_reads_by_report',0,'real_cfo',realCFO,'resampling',resample);
slrx.diag.writeJSON(fullfile(out,'observability_tests.json'),result);
fprintf('OBSERVABILITY_TESTS_PASSED\n');
end
