% 定义defaultConfig函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function cfg = defaultConfig(projectRoot)
    %DEFAULTCONFIG 建立学习版参数；不修改旧接收机的配置文件。
    % 输入 projectRoot：工程根目录。省略时从本函数路径自动定位。
    % 输出 cfg：小型配置结构，单位写在字段名或注释中。
    % 学习建议：先保持默认参数，运行 START_HERE.m 的前8节；看清网格后
    % 再运行耗时较长的星座识别/ML。修改DSP参数时请创建新的学习目录。

    % nargin是实际输入参数个数；少于1个时在下面补这个可选参数的默认值。
    if nargin < 1
        % 得到/保留当前函数文件所在目录，用来自动定位工程根路径。
        % 单引号里的文字是字符数据，不是同名变量。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        here = fileparts(mfilename('fullpath'));

        % 连续三次fileparts逐级取父目录，从+slrx目录返回工程根目录。
        projectRoot = fileparts(fileparts(fileparts(here)));
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 得到/保留原接收机JSON配置读取后的结构，包含采样率和既定算法参数。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    reference = jsondecode(fileread(fullfile(projectRoot, 'config', ...
        'author_receiver_v1.json')));  % 续接同一调用的其余参数或表达式。

    % 设置工程根目录；后续所有资源路径从这里拼接。
    cfg.project_root = projectRoot;

    % 设置原始IQ BIN路径，采集文件不因学习运行而修改。
    cfg.input_file = fullfile(projectRoot, 'data', 'raw', 'exemplar250-257', ...
        'exemplar250-257.bin');  % 续接同一调用的其余参数或表达式。

    % 设置输出目录；空字符表示自动建立新时间目录。
    cfg.run_dir = '';
    % 留空：自动建立 runs/codex-learning-时间

    % 设置从原BIN第几份复采样开始读；一基坐标，不是int16分量号。
    cfg.first_complex_sample = 1;
    % 原BIN的一基复采样位置，不是int16位置

    % 设置读取窗口时长0.004秒，即4ms；它不是预知帧边界。
    cfg.read_duration_s = 0.004;
    % 先读4ms，足以覆盖开头的一帧和保护区

    % 设置原采集250Msps的采样率，单位Hz。
    cfg.capture_fs_hz = reference.capture_fs_hz;

    % 设置重采样后使用240e6Hz模型采样率。
    cfg.model_fs_hz = 240e6;

    % 设置射频中心频率，仅供初始SFO等换算，不给IQ再乘12GHz载波。
    cfg.center_frequency_hz = reference.center_frequency_hz;

    % 设置每个普通OFDM有效区有1024个时间采样/FFT频率点。
    cfg.nfft = 1024;

    % 设置普通OFDM前置CP有32个模型采样。
    cfg.cp_length = 32;

    % 设置占用部分共302个时隙：PSS、SSS、300个数据符号。
    cfg.frame_symbol_count = 302;
    % PSS + SSS + 300个数据符号

    % 设置数据OFDM列数300，不把SSS算成载荷列。
    cfg.data_column_count = 300;

    % 设置名义时隙重复率750Hz；并非每个时隙都能看见目标波束。
    cfg.slot_rate_hz = 750;

    % 设置名义重采样上采样因子24。
    cfg.resample_p = 24;

    % 设置名义重采样下采样因子25，输出长度约为输入的24/25。
    cfg.resample_q = 25;

    % 设置resample所用FIR半长度参数50，与原接收机相同。
    cfg.resample_filter_half_length = 50;
    % 与原接收机的resample调用相同

    % 设置独立捕获最多保留32个候选，避免无限搜索。
    cfg.max_sync_candidates = 32;

    % 设置独立合格候选按时间排序后选第几个，默认第1个。
    cfg.frame_rank = 1;
    % 独立检测后，按时间排序选第1个合格帧

    % 设置选择进入后续完整处理所需的SSS相关门限。
    cfg.minimum_processing_sss = reference.processing_sss_min_correlation;

    % 设置同步候选PSS归一化相关幅度最低要求。
    cfg.minimum_pss = 0.08;

    % 设置同步候选SSS归一化相关幅度最低要求。
    cfg.minimum_sss = 0.05;

    % 设置SSS信道平滑的窗口点数，读取原配置。
    cfg.smoothing_window = reference.smoothing_window;

    % 设置Savitzky–Golay局部拟合的多项式阶数。
    cfg.smoothing_degree = reference.smoothing_degree;

    % 设置每个候选K使用多少次kmeans初始化，读取原配置。
    cfg.kmeans_replicates = reference.kmeans_replicates;

    % 设置ML噪声方差的数值下限，不把它当实测噪声真值。
    cfg.noise_variance_floor = reference.noise_variance_floor;

    % 设置整帧拟合至少需要多少个可识别的简单星座列。
    cfg.minimum_simple_symbols = reference.minimum_simple_symbols;

    % 设置RANSAC时延内点容差，单位240Msps模型采样。
    cfg.ransac_delay_threshold_samples = reference.ransac_delay_threshold_samples;

    % 设置固定随机种子，保证聚类/RANSAC可复现。
    cfg.seed = reference.seed;

    % 设置frame_local表示只用本帧SSS估信道，不暗中合并其他帧。
    cfg.channel_mode = 'frame_local';
    % 每一轮用本帧SSS；不暗中合并其他帧

    % 设置运行到哪一步就停止；14为完整判决，终端默认可停在8。
    cfg.stop_after = 14;
    % 命令行可只跑到某一步，之后从MAT继续

    % 设置true时回读同目录已有MAT；false时随后执行的步骤重新计算。
    cfg.resume = true;

    % 设置是否为各已运行步骤绘制并保存PNG。
    cfg.make_plots = true;

    % 设置是否弹出图形窗口；批处理设false但可照常保存PNG。
    cfg.show_figures = true;
    % 批处理启动器会设为false，PNG仍保存

    % 设置展示第50个数据OFDM符号；它对应FFT网格第51列。
    cfg.display_data_column = 50;

    % 设置算法配置版本名；本轮只改注释和排版，数值算法不变。
    cfg.version = 'learning-receiver-v1';

    % 设置codex_baseline标记代码由Codex工程实现，不冒称DSH生成。
    cfg.owner = 'codex_baseline';

    % 只增加小型步骤诊断摘要；不改变DSP参数或中间数组。
    cfg.diagnostics_enabled = true;
    cfg.debug_plots = false; % 旧密集波形仅显式调试时另存，非DSP参数。
% 结束这个函数，输出变量按函数声明返回给调用者。
end
