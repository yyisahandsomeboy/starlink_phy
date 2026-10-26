function result = validateRun(runDir)
%VALIDATERUN 独立回读学习结果，验证输入、尺寸、FFT/均衡和已运行步骤。
% 原始IQ和已保存变量回读；不以作者TOA帮助检测，也不修改旧评价器。
% 若只有前8步，只报告前端数值检查；不会把它记为完整接收成功。
% 单帧完整学习检查也不替代原评价器至少2帧的要求，没有业务BER。

saved = load(fullfile(runDir,'lesson_config.mat'),'frozenConfig');
cfg = saved.frozenConfig;
limits = jsondecode(fileread(fullfile(cfg.project_root,'config','learning_validation_v1.json')));
refs = slrx.references(cfg);
capture = readStep(runDir,'01_capture');
result = struct('status','partial','version',limits.version,'owner','codex_baseline', ...
    'single_frame_only',true,'original_evaluator_changed',false,'payload_bits_available',false);
% 原BIN中32个复采样的独立读取，确认没有把分量数当作复采样数。
fid = fopen(cfg.input_file,'r','ieee-le');assert(fid>=0);
fseek(fid,4*(cfg.first_complex_sample-1),'bof');parts=fread(fid,[2 32],'int16=>double');fclose(fid);
expected = complex(parts(1,:),parts(2,:)).'/32768;
assert(isequal(capture.iq(1:32),expected),'原始I/Q读取或一基偏移错误');
result.raw_readback_exact = true;
if exist(fullfile(runDir,'02_resampled.mat'),'file')
    sampled = readStep(runDir,'02_resampled');
    assert(sampled.fs_hz==cfg.model_fs_hz);
    result.nominal_sample_rate_hz = sampled.fs_hz;
end
if exist(fullfile(runDir,'03_sync.mat'),'file')
    sync = readStep(runDir,'03_sync');
    expectedCapture = cfg.first_complex_sample+(sync.selected.start_sample_nominal-1)*cfg.capture_fs_hz/cfg.model_fs_hz;
    assert(abs(sync.selected.start_sample_capture-expectedCapture)<1e-8,'同步坐标转换错误');
    result.independent_detection = ~sync.summary.annotations_used;
    result.start_sample_capture = sync.selected.start_sample_capture;
    result.model_and_capture_coordinate_identity = true;
end
if exist(fullfile(runDir,'06_fft_grid.mat'),'file')
    time = readStep(runDir,'05_without_cp');
    frequency = readStep(runDir,'06_fft_grid');
    independent = fft(time.without_cp,[],1)/sqrt(cfg.nfft);
    error = norm(frequency.values-independent,'fro')/norm(independent,'fro');
    assert(isequal(size(frequency.values),[1024 301]) && error<=limits.fft_relative_error_max);
    result.FFT_relative_error = error;
end
if exist(fullfile(runDir,'08_equalized.mat'),'file')
    channel = readStep(runDir,'07_channel');
    equalized = readStep(runDir,'08_equalized');
    error = norm(equalized.values-frequency.values./channel.H,'fro')/norm(equalized.values,'fro');
    assert(error<1e-12,'均衡除法与保存网格不一致');
    result.equalization_relative_error = error;
    result.first_equalized_heldout_pilot_evm = equalized.heldout_pilot_evm_after;
    result.front_end_checks = 'passed';
end
if exist(fullfile(runDir,'14_decisions.mat'),'file')
    tracked = readStep(runDir,'13h_tracking');
    decisions = readStep(runDir,'14_decisions');
    assert(isequal(size(tracked.values),[1024 301]) && isequal(size(decisions.hard_symbols),[1004 300]));
    assert(all(isnan(decisions.hard_symbols(~decisions.valid_mask))) && all(decisions.point_id_0based(~decisions.valid_mask)==-1));
    reference = refs.pilots(refs.eval_rows,2:301);
    evm = sqrt(sum(abs(tracked.values(refs.eval_rows,2:301)-reference).^2,'all')/sum(abs(reference).^2,'all'));
    improvement = 1-evm/equalized.heldout_pilot_evm_before;
    assert(evm<=limits.real_heldout_pilot_evm_max && improvement>=limits.real_pilot_relative_improvement_min, ...
        '留出导频没有达到沿用的真实数据数值规则；不降低门槛');
    assert(norm(tracked.values(refs.payload_rows,2:301),'fro')>1e-6,'载荷网格被清零');
    result.status = 'passed';
    result.complete_single_frame_pipeline = true;
    result.final_heldout_pilot_evm = evm;
    result.relative_improvement_vs_raw_fft = improvement;
    result.valid_hard_symbol_count = nnz(decisions.valid_mask);
    result.original_full_multiframe_acceptance = 'not_claimed_single_frame';
end
fid = fopen(fullfile(runDir,'learning_validation.json'),'w');assert(fid>=0);
fprintf(fid,'%s',jsonencode(result,'PrettyPrint',true));fclose(fid);
fprintf('LEARNING_INDEPENDENT_CHECK %s\n',result.status);
end

function data = readStep(runDir, key)
%READSTEP 从本学习目录的独立MAT回读data，不从旧接收结果补造输出。
saved = load(fullfile(runDir,[key '.mat']),'data');
data = saved.data;
end
