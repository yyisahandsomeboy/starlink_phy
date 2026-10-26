function cfg = defaultConfig(projectRoot)
%DEFAULTCONFIG 建立学习版参数；不修改旧接收机的配置文件。
% 输入 projectRoot：工程根目录。省略时从本函数路径自动定位。
% 输出 cfg：小型配置结构，单位写在字段名或注释中。
% 学习建议：先保持默认参数，运行 START_HERE.m 的前8节；看清网格后
% 再运行耗时较长的星座识别/ML。修改DSP参数时请创建新的学习目录。

if nargin < 1
    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(fileparts(fileparts(here)));
end
reference = jsondecode(fileread(fullfile(projectRoot, 'config', 'author_receiver_v1.json')));
cfg.project_root = projectRoot;
cfg.input_file = fullfile(projectRoot, 'data', 'raw', 'exemplar250-257', 'exemplar250-257.bin');
cfg.run_dir = '';                       % 留空：自动建立 runs/codex-learning-时间
cfg.first_complex_sample = 1;           % 原BIN的一基复采样位置，不是int16位置
cfg.read_duration_s = 0.004;             % 先读4ms，足以覆盖开头的一帧和保护区
cfg.capture_fs_hz = reference.capture_fs_hz;
cfg.model_fs_hz = 240e6;
cfg.center_frequency_hz = reference.center_frequency_hz;
cfg.nfft = 1024;
cfg.cp_length = 32;
cfg.frame_symbol_count = 302;            % PSS + SSS + 300个数据符号
cfg.data_column_count = 300;
cfg.slot_rate_hz = 750;
cfg.resample_p = 24;
cfg.resample_q = 25;
cfg.resample_filter_half_length = 50;    % 与原接收机的resample调用相同
cfg.max_sync_candidates = 32;
cfg.frame_rank = 1;                     % 独立检测后，按时间排序选第1个合格帧
cfg.minimum_processing_sss = reference.processing_sss_min_correlation;
cfg.minimum_pss = 0.08;
cfg.minimum_sss = 0.05;
cfg.smoothing_window = reference.smoothing_window;
cfg.smoothing_degree = reference.smoothing_degree;
cfg.kmeans_replicates = reference.kmeans_replicates;
cfg.noise_variance_floor = reference.noise_variance_floor;
cfg.minimum_simple_symbols = reference.minimum_simple_symbols;
cfg.ransac_delay_threshold_samples = reference.ransac_delay_threshold_samples;
cfg.seed = reference.seed;
cfg.channel_mode = 'frame_local';        % 每一轮用本帧SSS；不暗中合并其他帧
cfg.stop_after = 14;                    % 命令行可只跑到某一步，之后从MAT继续
cfg.resume = true;
cfg.make_plots = true;
cfg.show_figures = true;                % 批处理启动器会设为false，PNG仍保存
cfg.display_data_column = 50;
cfg.version = 'learning-receiver-v1';
cfg.owner = 'codex_baseline';
end
