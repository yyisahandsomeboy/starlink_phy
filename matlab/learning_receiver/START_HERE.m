%% 0. 学习入口：先跑一帧，按Ctrl+Enter逐节执行
% 本脚本是唯一的顺序学习主线。每节右侧slrx.xxx是真实算法模块，
% slrx.step只负责回读/保存MAT、JSON和画图，不调用旧的整机接收脚本。
% 可选输入5只给绘图传入已经计算的变量，不传入算法句柄，也不提前运行后续算法。
% 第一次运行本节；之后可只运行下一节。变量保留在工作区供你查看。
% 想重新计算某一步：lesson_cfg.resume=false，再顺序重跑其后步骤。
% 想改变DSP参数：clear lesson_cfg，再运行本节，在beginLesson前修改配置。

% mfilename('fullpath')取得本脚本全路径，fileparts只保留所在目录。
% 单引号里的文字是字符数据，不是同名变量。
% =先计算右边，再把结果放进左边变量；行末;不打印大数组。
learning_folder = fileparts(mfilename('fullpath'));

% 把指定目录加入MATLAB搜索路径，使其中函数可以按名字调用；+slrx包只加父目录。
addpath(learning_folder);

% 路径/变量尚不存在时才创建，不覆盖已有运行或用户配置。
% ||是两个标量条件的逻辑“或者”。
if ~exist('lesson_cfg', 'var') || isempty(lesson_cfg)
    % 创建配置结构；函数名后的()表示执行函数，返回结果放在等号左侧。
    lesson_cfg = slrx.defaultConfig();
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

% 创建/核验本次学习目录，记录参数与代码版本；结果仍叫lesson_cfg。
lesson_cfg = slrx.beginLesson(lesson_cfg);

% 读取作者公开序列和频率行映射，返回refs结构，供后续各步骤共享。
refs = slrx.references(lesson_cfg);

% 将数值计算线程上限设为4，避免这台虚拟机上过多线程争用。
maxNumCompThreads(4);

%% 1. 读IQ：得到capture.iq（复数列向量）和输入质量/PSD
% 两个int16才是一份复采样，默认只读开头4ms，不把文件窗口当帧边界。

% 本步做读取IQ，结果放入capture。实际算法是slrx.readIQ，step负责回读/保存。
% @定义函数句柄，保存任务，之后加()才实际调用。
% 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
capture = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '01_capture', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.readIQ(lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    1);  % 输入4：绘图类型；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 1
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 2. 名义重采样：250Msps -> 240Msps，得到sampled.iq
% 保存抗混叠FIR和移除的DC。实际SFO尚未在本步解决。

% 本步做名义重采样，结果放入sampled。实际算法是slrx.resampleCapture，step负责回读/保存。
sampled = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '02_resampled', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.resampleCapture(capture, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    2, struct('capture',capture,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 2
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 3. 找帧头：得到synchronization.selected，保留PSS/SSS曲线和候选
% 不读取sliceInfo或旧接收结果。frame_rank按独立检测后的时间顺序选择。

% 本步做独立PSS/SSS捕获，结果放入synchronization。实际算法是slrx.findFrame，step负责回读/保存。
synchronization = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '03_sync', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.findFrame(sampled, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    3, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 从独立同步结果取粗CFO，Hz为单位，不是12GHz载波频率。
initialOffsets.cfo_hz = synchronization.selected.coarse_cfo_hz;
% 旧方法用CFO/中心频率给初始SFO启发值；不是已知ADC时钟真值。

% 用CFO/中心频率提供初始SFO启发值；1e6把比例换成ppm。
initialOffsets.sfo_ppm = initialOffsets.cfo_hz ...
    / lesson_cfg.center_frequency_hz * 1e6;  % 续接本次计算：用CFO/中心频率提供初始SFO启发值；1e6把比例换成ppm。

% 固定随机种子随检测次序变化；重复运行相同输入能重现同样聚类。
seedBase = lesson_cfg.seed + synchronization.selected.detection_index * 1000;

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 3
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 4. 取完整帧并补偿CFO：得到frameTime的时域向量及采样坐标

% 本步做按时间轴取帧与CFO补偿，结果放入frameTime。实际算法是slrx.extractFrame，step负责回读/保存。
frameTime = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '04_frame_time', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.extractFrame(sampled, synchronization, initialOffsets, ...  % 输入3：@()保存任务，需要时才实际计算。
        lesson_cfg), ...  % 继续传入本步算法所需的结果和配置。
    4, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 4
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 5. 分符号、去CP：得到ofdmTime.without_cp（1024×301）

% 本步做分符号并去CP，结果放入ofdmTime。实际算法是slrx.removeCP，step负责回读/保存。
ofdmTime = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '05_without_cp', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.removeCP(frameTime, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    5, struct('time1',frameTime,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 5
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 6. FFT：得到frequencyGrid.values（1024×301复数网格）
% 第1列是SSS，后300列才是数据。行不是原IQ采样点。

% 本步做逐列FFT，结果放入frequencyGrid。实际算法是slrx.fftGrid，step负责回读/保存。
frequencyGrid = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '06_fft_grid', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.fftGrid(ofdmTime, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    6, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 6
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 7. 用SSS估计信道：得到channel.H（1024×1）与噪声估计
% 学习版默认frame_local，不合并其他帧的SSS。

% 本步做SSS信道估计，结果放入channel。实际算法是slrx.estimateChannel，step负责回读/保存。
channel = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '07_channel', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.estimateChannel(frequencyGrid, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    7, struct('fft1',frequencyGrid,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 7
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 8. 均衡：得到equalized.values，先观察留出导频误差
% 到这里已走完最基础的OFDM时域->频域->信道补偿；建议先停下来理解。

% 本步做频率响应均衡，结果放入equalized。实际算法是slrx.equalizeGrid，step负责回读/保存。
equalized = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '08_equalized', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.equalizeGrid(frequencyGrid, channel, refs), ...  % 输入3：@()保存任务，需要时才实际计算。
    8, struct('fft1',frequencyGrid,'channel1',channel,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 8
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 9. 观察导频：得到每列相位/时延初值，尚非最终ML跟踪

% 本步做FIT导频相位/时延初值，结果放入pilots。实际算法是slrx.observePilots，step负责回读/保存。
pilots = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '09_pilot_observations', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.observePilots(equalized, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    9, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 9
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 10. 点数识别：分别试4/8/16/32个簇，保留得分，不猜业务位
% 本步较耗时，300列都实际处理；K=8保留为当前模型不支持的复合类型。

% 本步做逐列点数识别，结果放入classes。实际算法是slrx.classifyColumns，step负责回读/保存。
classes = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '10_cardinality', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.classifyColumns(equalized, refs, lesson_cfg, seedBase), ...  % 输入3：@()保存任务，需要时才实际计算。
    10, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 10
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 11. 逐列ML与整帧跟踪：得到tracked.values及相位/时延趋势

% 本步做逐列ML与整帧趋势补偿，结果放入tracked。实际算法是slrx.trackFrame，step负责回读/保存。
tracked = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '11_tracking', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.trackFrame(equalized, channel, pilots, classes, refs, ...  % 输入3：@()保存任务，需要时才实际计算。
        lesson_cfg, seedBase), ...  % 继续传入本步算法所需的结果和配置。
    11, struct('eq1',equalized,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 11
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 12. 从趋势更新CFO/SFO：得到refinedOffsets，不直接改原IQ

% 本步做从趋势更新CFO/SFO，结果放入refinedOffsets。实际算法是slrx.refineOffsets，step负责回
% 读/保存。
refinedOffsets = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '12_refined_offsets', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.refineOffsets(synchronization, tracked, initialOffsets, ...  % 输入3：@()保存任务，需要时才实际计算。
        lesson_cfg), ...  % 继续传入本步算法所需的结果和配置。
    12);  % 输入4：绘图类型；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 12
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 13a. 第二轮仍从时间轴取样开始：重复调用同一批模块，不另藏算法

% 本步做按时间轴取帧与CFO补偿，结果放入frameTimeFinal。实际算法是slrx.extractFrame，step负责回读
% /保存。
frameTimeFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13a_frame_time', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.extractFrame(sampled, synchronization, refinedOffsets, ...  % 输入3：@()保存任务，需要时才实际计算。
        lesson_cfg), ...  % 继续传入本步算法所需的结果和配置。
    4, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13b. 第二轮去CP

% 本步做分符号并去CP，结果放入ofdmTimeFinal。实际算法是slrx.removeCP，step负责回读/保存。
ofdmTimeFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13b_without_cp', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.removeCP(frameTimeFinal, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    5, struct('time2',frameTimeFinal,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13c. 第二轮FFT

% 本步做逐列FFT，结果放入frequencyGridFinal。实际算法是slrx.fftGrid，step负责回读/保存。
frequencyGridFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13c_fft_grid', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.fftGrid(ofdmTimeFinal, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    6, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13d. 第二轮单帧SSS信道估计

% 本步做SSS信道估计，结果放入channelFinal。实际算法是slrx.estimateChannel，step负责回读/保存。
channelFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13d_channel', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.estimateChannel(frequencyGridFinal, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    7, struct('fft2',frequencyGridFinal,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13e. 第二轮均衡

% 本步做频率响应均衡，结果放入equalizedFinal。实际算法是slrx.equalizeGrid，step负责回读/保存。
equalizedFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13e_equalized', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.equalizeGrid(frequencyGridFinal, channelFinal, refs), ...  % 输入3：@()保存任务，需要时才实际计算。
    8, struct('fft2',frequencyGridFinal,'channel2',channelFinal,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13f. 第二轮导频初值

% 本步做FIT导频相位/时延初值，结果放入pilotsFinal。实际算法是slrx.observePilots，step负责回读/保
% 存。
pilotsFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13f_pilots', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.observePilots(equalizedFinal, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    9, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13g. 第二轮点数识别；保留旧方法第二轮seed+500的约定

% 本步做逐列点数识别，结果放入classesFinal。实际算法是slrx.classifyColumns，step负责回读/保存。
classesFinal = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13g_cardinality', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.classifyColumns(equalizedFinal, refs, lesson_cfg, ...  % 输入3：@()保存任务，需要时才实际计算。
        seedBase + 500), ...  % 继续传入本步算法所需的结果和配置。
    10, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 13h. 第二轮ML与整帧补偿，得到finalGrid.values

% 本步做第二轮最终ML跟踪，结果放入finalGrid。实际算法是slrx.trackFrame，step负责回读/保存。
finalGrid = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '13h_tracking', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.trackFrame(equalizedFinal, channelFinal, pilotsFinal, ...  % 输入3：@()保存任务，需要时才实际计算。
        classesFinal, refs, lesson_cfg, seedBase + 500), ...  % 继续传入本步算法所需的结果和配置。
    11, struct('track1',tracked,'eq2',equalizedFinal,'refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% 若配置要求停在本步或更早，则结束本次脚本执行，已有变量仍可查看。
if lesson_cfg.stop_after <= 13
    % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
    return;
% 结束这一组条件分支，之后接着执行同层的下一条语句。
end

%% 14. 条件星座硬判决：保存最近理想点、擦除和原资源坐标
% 这里尚没有真实业务位映射、FEC或CRC；不能把几何编号当作业务比特。

% 本步做条件最近星座点判决，结果放入decisions。实际算法是slrx.decideSymbols，step负责回读/保存。
decisions = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '14_decisions', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.decideSymbols(finalGrid, channelFinal, refs, lesson_cfg), ...  % 输入3：@()保存任务，需要时才实际计算。
    14, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

%% 补充观察：帧末保护间隔（边界来自模型，不是噪声边缘检测）

% 本步做帧末模型保护区观察，结果放入guard。实际算法是slrx.measureGuard，step负责回读/保存。
guard = slrx.step( ...
    lesson_cfg, ...  % 输入1：本次的路径、采样率和保存配置。
    '15_guard', ...  % 输入2：本步MAT/JSON文件名前缀。
    @()slrx.measureGuard(capture, synchronization, refinedOffsets, ...  % 输入3：@()保存任务，需要时才实际计算。
        lesson_cfg), ...  % 继续传入本步算法所需的结果和配置。
    15, struct('refs',refs));  % 输入4：绘图类型；输入5：只读绘图上下文；右括号结束调用。

% fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
fprintf('学习主链完成。结果保存在：%s\n', lesson_cfg.run_dir);
