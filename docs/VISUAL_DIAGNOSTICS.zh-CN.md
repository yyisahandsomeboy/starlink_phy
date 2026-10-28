# Starlink PHY 教学诊断：沿真实数据理解处理链

这里解释的是接收机实际保存的复数组和算法估计。它不提供商业 MCS、业务位映射、扰码、FEC、CRC 或真实业务 BER/SER 的证明。代码身份为 `codex_baseline`。

## 2026-10-28：离散教学视图

新增代码保留整体概览，在局部明确显示采样点、FFT频点和符号编号：

- 主线原始IQ与重采样图增加前32点I/Q茎状图；原有时域概览保留。
- 00号诊断图增加原始32个复采样，以及同一真实时间窗内的重采样I分量对照。原始与模型采样间隔分别由Fs计算；250/240 MSps时为4/4.1667 ns。模型点来自已保存MAT，不重新执行重采样；两组幅度仍含原FIR及DC移除差异。
- 02号局部PSS/SSS/联合相关用茎状图，每个整数偏移保留原相关值，局部0仍为选中帧头。
- 07号OFDM图同时保留1056/1024点概览，增加CP边界前64点、去CP后前32点和选中bin附近32个FFT频点。时间局部横轴n/p、频域横轴signed bin各自明确，不做逐点对应。
- 08号CP图用32对茎状样本比较实部、虚部、幅度和相位。标签给出CP n=0..31、对应尾部n=1024..1055。
- 主线CP相关、FIT相位及诊断逐符号EVM/相位用散点；已有拟合线保留。主值相位不跨±180°连接。
- 主线点数识别图保留热力图，增加选中符号候选K得分柱形图和逐符号K台阶。末端多显示一格只为覆盖最后符号，不增加分类结果。

这些是显示方式调整，未量化、旋转或重新估计接收样本。星座仍为散点；FFT网格与误差仍为热力图；PSD、信道、SFO模型趋势保留曲线。主线27张与完整单帧诊断15张的文件数量保持不变，局部细节增加在同一个图文件内。

**验证状态：本轮MATLAB运行因主机内存保护中止，用户选择暂缓运行验证；当前新增视图尚未完成MATLAB绘图与数值回归。静态检查与后续运行方式见[本轮记录](DISCRETE_VISUALIZATION_VALIDATION.zh-CN.md)。2026-10-27的已通过记录属于上一版本。**

## 1. 最短运行流程

先按仓库 README 准备公开序列和 IQ 资源。在 MATLAB 中进入仓库根目录：

```matlab
open('matlab/learning_receiver/START_HERE.m')
```

从第 0 节开始按 **Ctrl+Enter**。可以先停在第 8 节，再继续到第 14 节。工作区中的 `lesson_cfg.run_dir` 是本次输出目录。新版每步自动保存小型 `diagnostics_summary.json`，第 3 步分别生成全局、局部同步图。

生成独立诊断报告：

```matlab
addpath('matlab/learning_receiver')
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 50);
```

终端会给出 `index.html` 的完整路径，直接双击该文件即可。默认不弹出 15 个图形窗口；HTML 使用本地 PNG，无需服务器或网络。已有旧版学习 MAT 也可以传入目录重画，不必重新接收。每次使用新输出目录，避免覆盖旧报告。

```matlab
% 连续多个符号、正频率载荷、限制观察频段
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 45:55, ...
    'CarrierMode', 'positive', 'FrequencyBandMHz', [10 80]);

% 只看独立留出导频；不把导频和载荷混成一种星座
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'CarrierMode', 'eval_pilots');

% 有意使用显示变换：同一轮三个阶段共同除以一个正实数
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Normalization', 'common_rms');

% 原生 MATLAB 选择器：帧、连续符号、频段、阶段、归一化
h = BROWSE_DIAGNOSTICS(lesson_cfg.run_dir);
```

其他参数：`CarrierMode` 为 `payload / positive / negative / band / fit_pilots / eval_pilots`；`GeometryID` 为候选几何编号 1..4（需要第二轮跟踪结果，不是商业调制真值）；`GridColumns` 为 FFT 图列号；`SelectedRow` 为当前资源选择中的 MATLAB FFT 行；`ShowFigures=true` 打开原生图；`OutputDir` 指定一个尚不存在的目录。`Symbols` 为 1..300 中的一个值或连续范围。空频段与无效索引会报错，不默默改成另一组资源。

多帧入口：

```matlab
% 每帧先独立接收；默认先完成两帧前端，不声称完整跟踪成功
batch = RUN_MULTIPLE_FRAMES(2, 8);
dirs = {fullfile(batch,'frame_01'), fullfile(batch,'frame_02')};
r = RUN_DIAGNOSTICS(dirs, 'Symbols', 50);
h = BROWSE_DIAGNOSTICS(dirs);
```

多帧只比较各帧共有的同一阶段。如果某些帧只有均衡结果，不拿另一帧的最终跟踪结果冒充同阶段。`exact_resource_pairing` 表示行号和符号编号是否一致；使用几何筛选时不同帧可能只剩同类资源而非相同位置，应查看此标记。

## 2. 先读懂三个坐标系统

原始采集是 250 MSps，小端交织 int16：两个 int16 才是一份复数采样。归一化 IQ 为 `(I+jQ)/32768`，幅度不是电压 V。

模型采样率是 240 MSps。MATLAB 数组索引一基，而时间公式中的间隔从零开始：

$$
n_{capture}=n_{first}+(n_{model}-1)F_{capture}/F_{model},\qquad
t_{file}=(n_{capture}-1)/F_{capture}.
$$

本工程 `resample` 使用已补偿名义 FIR 延迟的输出约定。诊断统一调用 `+diag/coordinates.m`，不会再凭经验加一个 FIR 延迟。`first_complex_sample` 是当前读取窗口在原始文件的一基起点；改变读取窗口后仍按该起点换算。

连续时间对应的小数采样位置不是数组下标。例如 `raw=125001` 对应 0.5 ms，但这只是本次/历史特定帧的数值，不是代码常量。`nearest_raw_integer` 保存最近整数，`has_fractional_raw_position` 标记是否含小数；小数偏移可由 `raw_sample-nearest_raw_integer` 计算，不能将四舍五入后的值作为原精确位置。

局部同步横轴 `Δn=n−n0` 的 0 是**选定帧头**。它不代表文件第 0 点。全局搜索图的坐标选择器提供文件复采样、文件 ms、模型窗口坐标。原生图放大与数据光标可检查实际候选；静态 PNG 保存默认文件 ms。

FFT 数据保持 MATLAB 原始未移位行序。对偶数 N=1024，原行 1 对应 bin 0，原行 513 对应 bin −512；频率为 `bin*240e6/1024`，间隔 234.375 kHz。展示时按 signed bin 排序，数值与行号一起重排，不改接收网格。

网格为 1024×301：列 1 是 SSS；列 2..301 是数据符号 1..300。帧头 PSS 独立占一个 1056 点时隙，不出现在这个 301 列矩阵中。

## 3. 推荐看图顺序与输出文件

快速查看27张主线图、15张诊断图及2张多帧图各自的作用，见[图像阅读索引](VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)。图像在本机运行后生成，仓库中的文档通过源码链接解释它们。

报告目录包含 `index.html`、`图像索引.md`、`diagnostics_summary.json`、`diagnostics_data.mat`、`sync_candidates.csv`（有同步结果时）、`point_resources.csv` 和 `figures/`。

| 顺序 | 图片 | 核心问题 | 保存数据 |
|---|---|---|---|
| 1 | 00_capture | 读到了什么、选中帧在哪里、I/Q 表示什么 | capture、sync |
| 2 | 01_sync_global / 02_sync_local | 在全窗口哪里找到帧，局部零点在哪里 | sync |
| 3 | 05_cfo / 06_sfo | 相位旋转和采样时间刻度怎样变化 | time1/2、offsets、track1/2 |
| 4 | 07_ofdm_symbol / 08_cp_copy | 1056=32+1024、CP 与尾部是什么关系 | time1/2、ofdm1/2 |
| 5 | 09_fft_grid | 从时间样本变成了哪些频率位置 | fft1/2、refs |
| 6 | 10_channel | H 怎样改变复数点，为什么做 Y/H | channel1/2、fft1/2、eq1/2 |
| 7 | 03_constellation_stages | 同一符号在每一轮的三个阶段发生了什么 | fft/eq/track 两轮 |
| 8 | 11_pilot_evm / 12_pilot_cloud / 13_pilot_errors | 已知留出资源的误差改善多少、坏在哪里 | refs.eval_rows、六阶段网格 |
| 9 | 04_conditional_models | 观测与当前几何假设是否相容 | track1/2 的几何与增益 |
| 10 | 14_guard | 模型预测的帧末区间有什么实际能量 | guard |

全局与局部同步图应对照看；星座图六面板内部按行看（三阶段构成一轮）；EVM、导频点云和误差图一起看。15 个文件不等于 15 幅星座图，也不意味着应该把所有图同时弹出。

## 4. 输入 IQ、同步与采样定位

### 00_capture：输入 IQ 与频谱

- 源码：`+viz/plotCapture.m`；输入已保存 `capture.iq/fs_hz/rms/clipped_fraction`、PSD 和同步元数据。
- 数学：`z[n]=I[n]+jQ[n]`，分段平均 `|z|²`，复用已保存 PSD。局部波形围绕实际选中帧头，不固定画文件开头。
- 坐标：文件 ms → 平均功率；基带 MHz → PSD；概览文件 ms → I/Q；局部茎状图以同一原文件锚点的ns为横轴；散点横I纵Q。幅度均为接收机归一化单位。
- 正常/异常：可检查饱和、全零段、DC、能量区间；OFDM 时域散点像连续点云通常并不异常。
- 能证明输入形状和观测能量。标题固定为**“原始时域IQ散点图（非子载波调制星座）”**，不能据此判断 QPSK/16QAM 或读取业务比特。

### 01_sync_global：全局粗搜索与精确候选

- 源码：`+viz/plotGlobalSync.m`、`+diag/syncSummary.m`；输入 `sync.scan` 中的粗搜索轨迹、实际 `candidates/rejected/selected`。
- 上图纵轴为原算法保存的粗 PSS 搜索分数，轨迹每 100 点抽取。下图是候选事件，纵轴表示状态类别，不能把事件条当成另一条粗分数曲线。
- 候选精确位置来自实际检测记录；粗分数对应的最初粗峰坐标未保存，因此不把“精细位置+粗分数”伪画成原始峰点。
- 阈值只在保存的源码快照中明确找到同一定义的粗搜索阈值时绘制；它不是另一个阶段的 `minimum_pss`。没有来源则报告不可用。
- 正常应看到最终选中候选位于搜索区间内，有独立 PSS/SSS 依据；被拒绝候选不表示一定存在另一帧。
- 选择规则沿用原算法：通过处理 SSS 门限的候选按时间排序，选择 `cfg.frame_rank`，并非选择抽取轨迹的最大点。
- CSV 每行包括 raw/model/ms、PSS/SSS/joint/coarse、CFO、状态和已有拒绝原因。未保存的尝试次数、真实全局最大值或细分拒绝理由不补造。

### 02_sync_local：PSS、SSS、联合局部相关

- 源码：`+viz/plotLocalSync.m`；输入实际 `lags` 与局部三条相关曲线。
- 横轴 `Δn` 是整数模型采样偏移，每根茎对应实际保存的一个分数；纵轴为对应定义的归一化相关幅度。PSS/SSS与联合值使用各自定义，不在偏移之间插值。
- 信息面板保存模型 Fs、精确帧头 raw/model/ms、最近原整数、小数偏移、三项分数、CFO 和候选编号。
- 相容的局部峰支持本次定时选择；错峰或多峰值得检查。它不能作为所有帧成功或 TOA 真值证明。

## 5. CFO 与 SFO：相位变化和时间刻度是两件事

### 05_cfo：已知参考相位

- 源码：`+viz/plotCFO.m`；输入保存的 CFO 前/后时间样本、PSS+SSS 参考、两轮实际 CFO 和 ML 相位。
- 数学：`z_corr[n]=z[n] exp(-j2π*CFO*n/Fs)`；在已知 PSS/SSS 上每 64 点做相干参考比较后取相位。
- 坐标：帧内时间 µs → 相位 rad；数据符号 → 原算法估计的残余相位修正。面板列出实际粗 CFO、两轮 CFO，不重新拟合未知业务 IQ 的相位斜率。
- 相位趋势应结合数值和已知参考解释；多径、噪声、参考内幅度变化也会扰动曲线。原始 `angle(z)` 含未知调制相位，不能直接当 CFO 真值。
- 图可验证补偿操作和参考相位变化，不能区分卫星、多普勒和本振各自贡献，不能单独证明 CFO 已消除。

### 06_sfo：实际保存的取样位置漂移

- 源码：`+viz/plotSFO.m`；输入 `sample_positions_nominal`、保存 SFO/比例和 ML 时延拟合。
- 数学：实际插值位置减去同帧名义位置；模型采样差除以 Fs 转成 ns。第二轮减第一轮另外显示，固定起点偏移与累积斜率不混为一项。
- 坐标：帧内名义时间 ms → 模型采样漂移或 ns；数据符号 → 等效残余时延。
- 斜率与已有比例一致支持实现约定正确；异常跳变提示时间轴问题。初始 SFO 含原算法的频偏比例假设，不等于独立实测 ADC 时钟真值；多径时延与采样时钟误差也不能仅凭一条线分离。

## 6. OFDM、CP 与 FFT

### 07_ofdm_symbol：同一个符号的时间/频率分解

- 源码：`+viz/plotOFDM.m`；输入选定符号的 `time`、`ofdm.without_cp` 和 FFT。优先用第二轮，缺失时明确显示第一轮。
- 数学：`1056=32+1024`；前 32 点 CP、后 1024 点有效区，末尾 32 点是复制参考；`Y=fft(x)/sqrt(1024)`。
- 坐标：符号内零基时间点n=0..1055 → I/Q；有效区p=0..1023 → I/Q；n=p+32。全频带用MHz，局部32点用signed bin。局部时域与频域均为茎状图，零基是当前符号内编号，元数据另存文件坐标。
- 去 CP 有效区必须与保存 `without_cp` 逐值一致。该图解释数组和索引，不要求随机载荷波形肉眼呈周期，也不能用一个时域点代表一个子载波。

### 08_cp_copy：复数 CP 与尾部对照

- 源码：`+viz/plotCP.m`；输入同一符号 CFO 前后的 CP 与尾部复数组。
- 数学：`rho=(cp'*tail)/(norm(cp)*norm(tail))`。同时保留复数 rho，画实部、虚部、幅度和相位差，不仅画一个绝对值。
- 坐标：CP 内编号 0..31 → 归一化幅度/相位差 degree。
- 无噪声单径合成用例应 rho=1；真实数据的噪声、多径、SFO、CFO 可导致偏差。高相关支持局部复制关系，不能证明整条接收链正确。

### 09_fft_grid：资源网格

- 源码：`+viz/plotFFTGrid.m`；输入两轮未均衡 FFT、`refs.frequency_bins`、FIT/EVAL/null 行。
- 数学：颜色 `20log10(abs(Y))`；按频率排序只作用于显示。
- 横轴网格列，列 1 SSS、2..301 数据；纵轴可在 MHz 与 signed bin 间切换。两轮颜色尺度一致。`GridColumns`、频段参数及 MATLAB 原生缩放支持查看局部。
- 导频、空子载波与参考映射应一致；错误错位、空槽异常能量值得排查。颜色代表幅度，不代表业务位、调制阶数或星座点数。

## 7. 信道、星座与独立导频

### 10_channel：复信道与 Y/H

- 源码：`+viz/plotChannel.m`；输入实际 H、SSS 模型噪声方差、FFT Y 与均衡值。
- 数学：`Y≈HX+W`，接收机做 `X_hat=Y./H`。选定行/列显示 Y、H 和 X_hat 的复数值，并核对保存 X_hat 与 Y/H。
- 坐标：基带 MHz → |H|、相位 rad、`1/|H|²`；单点复平面横实部纵虚部。低 H 标线默认有效行最大 |H| 的 0.1 倍，仅为诊断标记，可以通过参数改变，不是接收通过门限。
- 小 H 对应大的除法噪声增益代理；显示原 SSS 估计方差供参考。不能把此代理当真实未知载荷噪声或偷偷改成新的均衡器。

### 03_constellation_stages：两轮、同资源、统一尺度

- 源码：`+diag/constellationData.m`、`+viz/plotConstellationStages.m`。
- 第一行是 `fft1 → eq1 → track1`；第二行是 `fft2 → eq2 → track2`。每行使用相同的帧、数据符号、行号和显示点抽取索引；载荷从 `refs.payload_rows` 获取，不硬编码连续行而误纳导频。
- 数学：FFT 输出 `Y[k,m]` 才是单个子载波观测。均衡除以 H，跟踪使用原算法已保存的相位/时延，不再额外旋转或聚类。
- 坐标横 I 纵 Q；六面板统一坐标范围。标题列出帧 rank、数据符号/网格列、资源数、频率范围、原 RMS 和显示除数。数值差异大时某些面板会显得很小，这是实际增益差异。
- 默认 `Normalization='none'`。`common_rms` 取每轮最后可用阶段所选资源的 RMS，三个阶段共同除以一个正实数：**仅用于显示，不改变接收机输出**。不逐阶段各自归一化，不旋转相位；raw_values 与除数完整保留。
- 可观察聚集、拉伸、相位扩散，但不强求每一步单调改善。已知 EVAL 导频误差更适合判断真实可验证的改善。多列混合点云可能含不同几何/增益，不能据此断言一种商业调制。

### 04_conditional_models：候选模型单独显示

- 源码：`+viz/plotConditionalModels.m`；输入原跟踪的 geometry_id、gain 和候选几何参考。
- 数学：红圈为原算法 `gain*constellation`，观测值保持原样；不是为了漂亮重新求旋转或最近点。两轮分别显示；未知分类不会硬补一种几何。
- 横 I 纵 Q，与选择资源的显示约定一致。分簇与候选点相容仅说明当前模型相容，不证明商业 MCS、比特映射或业务 SER。
- 导频模式显示已知导频参考，不能把导频假装成未知载荷的调制判断。

### 11_pilot_evm、12_pilot_cloud、13_pilot_errors

- 源码：`+diag/pilotMetrics.m`、`+viz/plotPilots.m`；只用 `refs.eval_rows` 和数据列 2..301。FIT 用于原算法估计，EVAL 只评价。主指标覆盖整帧 300 个符号，独立于星座图的显示符号选择；逐符号曲线可查选中符号。
- EVM：

$$
\mathrm{EVM}=\sqrt{\sum|Z-P|^2/\sum|P|^2}.
$$

- 保存两种约定：原接收单位的 raw EVM；SSS 约定的 calibrated EVM。FFT 前均衡的幅度/相位与理想 P 不同，诊断仅从该阶段 SSS 已知非零行估计一个复标量 `alpha=sum(conj(S).*Ysss)/sum(abs(S)^2)`，以 `Z/alpha` 计算比较值；均衡与跟踪不额外拟合。**绝不从 EVAL 拟合 alpha**，原输出不被覆盖。复数 alpha 的实部/虚部同时保存。
- 11 图：阶段 → EVM %，以及数据符号 → EVM %；轮次分开。原 EVM 与标定值都显示，禁止挑一种约定制造单调改善。
- 12 图：对已知 P 去参考旋转后的 `Z/P` 点云，目标 (1,0)，六阶段共同坐标尺度。
- 13 图：数据符号×EVAL 频率行的绝对误差；正/负频率导频分别显示均衡与跟踪后的主值相位 degree。相位包裹跳变不能不经判断当作新 CFO。
- 误差更小支持这些已知留出资源的恢复更好；某些符号可变差。它不证明未知载荷比特、FEC/CRC 或业务 BER。EVAL 已知导频指标也不等于业务 SER。

### 14_guard：模型预测边界的实际能量

- 源码：`+viz/plotGuard.m`；输入原 `measureGuard` 保存的实际 IQ 窗口和预测边界。
- 坐标：相对预测边界 µs → 幅度、相对前窗功率 dB。31 点移动平均只帮助显示，原样本和原功率比保留。
- 能说明模型区间的观测能量及窗口完整性；边界并非通过噪声突变重新检测，不能要求功率比必小于新设门限。

## 8. 一个星座点怎样追到原文件

对照图启用 MATLAB 数据光标，点选后显示帧、轮次、阶段、数据符号、网格列、MATLAB 行、signed bin、MHz、原始复值和显示除数。`point_resources.csv` 保存实际显示的每个点（所有阶段使用同一组抽取位置），完整所选矩阵在 MAT 中。

一个 FFT 点是 1024 个有效时间样本的加权和，不对应唯一 ADC 点。`tracePoint` 用保存的 `sample_positions_nominal` 还原这 1024 个连续模型取样位置，再通过统一坐标变换给出原文件区间、最近整数、字节位置和时间。

区间表示**该符号直接 FFT 有效区的采样中心范围**，不是完整因果依赖边界：sinc 插值还有 256 点邻域，重采样 FIR 也有支持长度；均衡 H 又依赖 SSS，跟踪依赖帧内拟合。MAT 保存完整 1024 点位置向量，JSON/数据光标保留精简区间和限制，不伪称精确到唯一原 IQ。

## 9. 步骤摘要、缺失数据与实现边界

每步终端只打印少量字段的形状、类、单位与主要指标，数值预览最多前三项。`diagnostics_summary.json` 包含各步输入来源、输出变量/尺寸/单位、公式、Fs/N/CP/窗口起点、源 MAT/JSON、关联图片和限制。

复数 JSON 使用 `{real,imag}`，不会悄悄丢掉虚部。原步骤 JSON 若缺失，`step_json_available=false`；缺少步骤列入 `missing_checkpoints`，图的 `available=false`，数值为 NaN/null，**不表示零误差或接收成功**。全报告 `status=generated_for_available_checkpoints` 只表示生成成功；是否通过接收验证另看 `source_validation`，它明确是已有保存验证，不是绘图器新跑 DSP。

诊断器每个检查点加载一次，各图复用，原 BIN 读取次数为 0。绘图前后核对所有来源 MAT 的 SHA。它不会生成新的 DSP 中间结果来补齐缺失步骤。多帧按帧顺序加载，交互控制器缓存已经打开的帧；用户打开大量长窗口帧仍需留意实际内存。

这次没有为节省接收内存更换数据精度、压缩核心网格、修改读窗或改滤波器。单独报告导出、已加载数据复用属于诊断模块自身组织。运行与内存实测、旧测试和本次数值回归见 [验证报告](VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)。

## 10. 代码组织与复核

| 位置 | 作用 |
|---|---|
| `+slrx/+diag/` | 单次回读、坐标、同步候选表、同资源选择、EVM、点溯源、摘要、HTML/索引 |
| `+slrx/+viz/` | 只读图形、数据光标、坐标切换、原生控制窗口、多帧对照 |
| `RUN_DIAGNOSTICS.m` | 单帧或多帧报告入口 |
| `BROWSE_DIAGNOSTICS.m` | 轻量 MATLAB 原生选择器 |
| `tests/test_visual_diagnostics.m` | 坐标、资源配对、EVAL 隔离、CP/CFO 合成用例、部分报告、UI 回调 |
| `drawStep/step/defaultConfig/beginLesson.m` | 与现有入口的小型连接；不修改数学模块 |

现状 27 张旧图及已计算但未展示的变量见 [审计](VISUAL_DIAGNOSTICS_AUDIT.zh-CN.md)。完整更改清单与验证边界见验证报告。需要真正业务 BER/SER 时，仍缺商业比特映射、扰码状态、FEC 矩阵/边界和业务真值；本诊断不填补这些未知项。
