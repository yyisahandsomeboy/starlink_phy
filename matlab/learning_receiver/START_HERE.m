%% 0. 学习入口：先跑一帧，按Ctrl+Enter逐节执行
% 本脚本是唯一的顺序学习主线。每节右侧slrx.xxx是真实算法模块，
% slrx.step只负责回读/保存MAT、JSON和画图，不调用旧的整机接收脚本。
% 第一次运行本节；之后可只运行下一节。变量保留在工作区供你查看。
% 想重新计算某一步：lesson_cfg.resume=false，再顺序重跑其后步骤。
% 想改变DSP参数：clear lesson_cfg，再运行本节，在beginLesson前修改配置。

learning_folder = fileparts(mfilename('fullpath'));
addpath(learning_folder);
if ~exist('lesson_cfg','var') || isempty(lesson_cfg)
    lesson_cfg = slrx.defaultConfig();
end
lesson_cfg = slrx.beginLesson(lesson_cfg);
refs = slrx.references(lesson_cfg);
maxNumCompThreads(4);

%% 1. 读IQ：得到capture.iq（复数列向量）和输入质量/PSD
% 两个int16才是一份复采样，默认只读开头4ms，不把文件窗口当帧边界。
capture = slrx.step(lesson_cfg,'01_capture',@()slrx.readIQ(lesson_cfg),1);
if lesson_cfg.stop_after<=1,return;end

%% 2. 名义重采样：250Msps -> 240Msps，得到sampled.iq
% 保存抗混叠FIR和移除的DC。实际SFO尚未在本步解决。
sampled = slrx.step(lesson_cfg,'02_resampled',@()slrx.resampleCapture(capture,lesson_cfg),2);
if lesson_cfg.stop_after<=2,return;end

%% 3. 找帧头：得到synchronization.selected，保留PSS/SSS曲线和候选
% 不读取sliceInfo或旧接收结果。frame_rank按独立检测后的时间顺序选择。
synchronization = slrx.step(lesson_cfg,'03_sync',@()slrx.findFrame(sampled,refs,lesson_cfg),3);
initialOffsets.cfo_hz = synchronization.selected.coarse_cfo_hz;
% 旧方法用CFO/中心频率给初始SFO启发值；不是已知ADC时钟真值。
initialOffsets.sfo_ppm = initialOffsets.cfo_hz/lesson_cfg.center_frequency_hz*1e6;
seedBase = lesson_cfg.seed+synchronization.selected.detection_index*1000;
if lesson_cfg.stop_after<=3,return;end

%% 4. 取完整帧并补偿CFO：得到frameTime的时域向量及采样坐标
frameTime = slrx.step(lesson_cfg,'04_frame_time',@()slrx.extractFrame(sampled,synchronization,initialOffsets,lesson_cfg),4);
if lesson_cfg.stop_after<=4,return;end

%% 5. 分符号、去CP：得到ofdmTime.without_cp（1024×301）
ofdmTime = slrx.step(lesson_cfg,'05_without_cp',@()slrx.removeCP(frameTime,lesson_cfg),5);
if lesson_cfg.stop_after<=5,return;end

%% 6. FFT：得到frequencyGrid.values（1024×301复数网格）
% 第1列是SSS，后300列才是数据。行不是原IQ采样点。
frequencyGrid = slrx.step(lesson_cfg,'06_fft_grid',@()slrx.fftGrid(ofdmTime,refs,lesson_cfg),6);
if lesson_cfg.stop_after<=6,return;end

%% 7. 用SSS估计信道：得到channel.H（1024×1）与噪声估计
% 学习版默认frame_local，不合并其他帧的SSS。
channel = slrx.step(lesson_cfg,'07_channel',@()slrx.estimateChannel(frequencyGrid,refs,lesson_cfg),7);
if lesson_cfg.stop_after<=7,return;end

%% 8. 均衡：得到equalized.values，先观察留出导频误差
% 到这里已走完最基础的OFDM时域->频域->信道补偿；建议先停下来理解。
equalized = slrx.step(lesson_cfg,'08_equalized',@()slrx.equalizeGrid(frequencyGrid,channel,refs),8);
if lesson_cfg.stop_after<=8,return;end

%% 9. 观察导频：得到每列相位/时延初值，尚非最终ML跟踪
pilots = slrx.step(lesson_cfg,'09_pilot_observations',@()slrx.observePilots(equalized,refs,lesson_cfg),9);
if lesson_cfg.stop_after<=9,return;end

%% 10. 点数识别：分别试4/8/16/32个簇，保留得分，不猜业务位
% 本步较耗时，300列都实际处理；K=8保留为当前模型不支持的复合类型。
classes = slrx.step(lesson_cfg,'10_cardinality',@()slrx.classifyColumns(equalized,refs,lesson_cfg,seedBase),10);
if lesson_cfg.stop_after<=10,return;end

%% 11. 逐列ML与整帧跟踪：得到tracked.values及相位/时延趋势
tracked = slrx.step(lesson_cfg,'11_tracking',@()slrx.trackFrame(equalized,channel,pilots,classes,refs,lesson_cfg,seedBase),11);
if lesson_cfg.stop_after<=11,return;end

%% 12. 从趋势更新CFO/SFO：得到refinedOffsets，不直接改原IQ
refinedOffsets = slrx.step(lesson_cfg,'12_refined_offsets',@()slrx.refineOffsets(synchronization,tracked,initialOffsets,lesson_cfg),12);
if lesson_cfg.stop_after<=12,return;end

%% 13a. 第二轮仍从时间轴取样开始：重复调用同一批模块，不另藏算法
frameTimeFinal = slrx.step(lesson_cfg,'13a_frame_time',@()slrx.extractFrame(sampled,synchronization,refinedOffsets,lesson_cfg),4);

%% 13b. 第二轮去CP
ofdmTimeFinal = slrx.step(lesson_cfg,'13b_without_cp',@()slrx.removeCP(frameTimeFinal,lesson_cfg),5);

%% 13c. 第二轮FFT
frequencyGridFinal = slrx.step(lesson_cfg,'13c_fft_grid',@()slrx.fftGrid(ofdmTimeFinal,refs,lesson_cfg),6);

%% 13d. 第二轮单帧SSS信道估计
channelFinal = slrx.step(lesson_cfg,'13d_channel',@()slrx.estimateChannel(frequencyGridFinal,refs,lesson_cfg),7);

%% 13e. 第二轮均衡
equalizedFinal = slrx.step(lesson_cfg,'13e_equalized',@()slrx.equalizeGrid(frequencyGridFinal,channelFinal,refs),8);

%% 13f. 第二轮导频初值
pilotsFinal = slrx.step(lesson_cfg,'13f_pilots',@()slrx.observePilots(equalizedFinal,refs,lesson_cfg),9);

%% 13g. 第二轮点数识别；保留旧方法第二轮seed+500的约定
classesFinal = slrx.step(lesson_cfg,'13g_cardinality',@()slrx.classifyColumns(equalizedFinal,refs,lesson_cfg,seedBase+500),10);

%% 13h. 第二轮ML与整帧补偿，得到finalGrid.values
finalGrid = slrx.step(lesson_cfg,'13h_tracking',@()slrx.trackFrame(equalizedFinal,channelFinal,pilotsFinal,classesFinal,refs,lesson_cfg,seedBase+500),11);
if lesson_cfg.stop_after<=13,return;end

%% 14. 条件星座硬判决：保存最近理想点、擦除和原资源坐标
% 这里尚没有真实业务位映射、FEC或CRC；不能把几何编号当作业务比特。
decisions = slrx.step(lesson_cfg,'14_decisions',@()slrx.decideSymbols(finalGrid,channelFinal,refs,lesson_cfg),14);

%% 补充观察：帧末保护间隔（边界来自模型，不是噪声边缘检测）
guard = slrx.step(lesson_cfg,'15_guard',@()slrx.measureGuard(capture,synchronization,refinedOffsets,lesson_cfg),15);
fprintf('学习主链完成。结果保存在：%s\n',lesson_cfg.run_dir);
