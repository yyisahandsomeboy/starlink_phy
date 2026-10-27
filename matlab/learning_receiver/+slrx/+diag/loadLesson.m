function context = loadLesson(runDir, projectRoot)
%LOADLESSON 每个检查点只读取一次；不运行DSP，也不重读原始50ms BIN。
if nargin<2
    here=fileparts(mfilename('fullpath'));
    projectRoot=fileparts(fileparts(fileparts(fileparts(here))));
end
saved=load(fullfile(runDir,'lesson_config.mat'),'frozenConfig');
context.cfg=saved.frozenConfig;
context.cfg.project_root=projectRoot; % 仅资源/源码路径重定位，物理参数仍取运行快照。
context.cfg.run_dir=runDir;
context.run_dir=runDir;
context.refs=slrx.references(context.cfg);
mapping={
 'capture','01_capture'; 'sampled','02_resampled'; 'sync','03_sync';
 'time1','04_frame_time'; 'ofdm1','05_without_cp'; 'fft1','06_fft_grid';
 'channel1','07_channel'; 'eq1','08_equalized'; 'pilots1','09_pilot_observations';
 'classes1','10_cardinality'; 'track1','11_tracking'; 'offsets','12_refined_offsets';
 'time2','13a_frame_time'; 'ofdm2','13b_without_cp'; 'fft2','13c_fft_grid';
 'channel2','13d_channel'; 'eq2','13e_equalized'; 'pilots2','13f_pilots';
 'classes2','13g_cardinality'; 'track2','13h_tracking';
 'decisions','14_decisions'; 'guard','15_guard'};
context.sources=struct('key',{},'field',{},'path',{},'sha256',{});
context.missing={};
for k=1:size(mapping,1)
    file=fullfile(runDir,[mapping{k,2} '.mat']);
    if exist(file,'file')
        saved=load(file,'data');
        assert(isfield(saved,'data'),'slrx:DiagnosticCheckpoint','MAT缺少data：%s',file);
        context.(mapping{k,1})=saved.data;
        context.sources(end+1)=struct('key',mapping{k,2},'field',mapping{k,1}, ...
            'path',file,'sha256',slrx.sha256(file)); %#ok<AGROW>
    else
        context.missing{end+1}=mapping{k,2}; %#ok<AGROW>
    end
end
context.raw_bin_reads=0;
context.checkpoint_read_count=numel(context.sources);
context.mapping_convention='resample nominal delay compensated; first_complex_sample anchors continuous 1-based model time';
end
