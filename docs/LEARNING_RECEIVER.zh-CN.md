> GitHub源码版：`/path/to/starlink_phy`请换成你的克隆目录。历史 `runs/` 与图片不随仓库上传；资源准备及两种启动方式见[仓库README](../README.md)。

# Codex 接收机逐步学习手册

这份手册对应 `matlab/learning_receiver/` 的实际MATLAB代码。目标是让你能停在任意一步，知道输入是什么、做了什么、结果是什么、怎样检查，以及下一步为什么需要它。原接收机仍在 `matlab/baseline/author_receiver.m`，已有实验没有被覆盖。

## 一、先学一帧，再看多帧

建议顺序是：**一帧前8步 → 一帧完整处理 → 相同模块处理2～3帧 → 再考虑帧间统计及协议分析。**

一帧里已经有PSS、SSS和300个数据OFDM符号，因此包含完整的同步、FFT、信道估计、均衡、跟踪和符号判决问题。多帧会额外引入“这一帧属于哪个候选”“信道能否共用”“哪些时隙没有目标波束”等问题，不会让第一遍学习更容易。

单帧成功也有边界：它不能证明不同时间、不同信道条件都可用，不能发现所有漏帧，更不能只靠一帧确定商业MCS和业务编码。学会一帧以后，多帧是必要的稳定性检查。

默认只读原采集开头4ms，并在其中**独立找一个完整合格帧**。4ms不是已知帧长，也不是预先给定帧头。换分析窗口可修改 `read_duration_s`、`first_complex_sample`；换候选用 `frame_rank`。

## 二、先分清四种“点”

| 名称 | 实际含义 | 例子 |
|---|---|---|
| 原始复采样点 | ADC文件中的一份I+jQ；每份4字节 | 原文件一基采样位置125001对应0.5ms |
| 模型复采样点 | 重采样到240Msps后的时间轴位置 | 1模型采样约4.1667ns |
| OFDM子载波上的复符号 | 对1024个时间采样做FFT后，在某个频率位置上的一个复数 | `frequencyGrid.values(row,column)` |
| 理想星座点 | 判决时假设发射端选取的候选复数 | QPSK几何中的一个点；尚不是已知商业比特标签 |

原采样点是时间坐标，FFT行号是频率坐标，二者不能混用。一个OFDM符号是许多子载波叠加形成的一段时域波形，不等于一个复数。

输入文件小端顺序为 `I0,Q0,I1,Q1,...`，采样率250Msps。除以32768只是幅度归一化，不改变相位、采样率或调制类型。12GHz左右的元数据是射频中心频率；文件已是IQ，不需要再乘12GHz载波。

## 三、目录与职责

```text
matlab/learning_receiver/
  START_HERE.m                    按%%分节的单帧顺序脚本
  RUN_MULTIPLE_FRAMES.m            学完一帧后的顺序多帧入口
  README.zh-CN.md                  最短上手说明
  +slrx/
    defaultConfig.m               配置与单位；不改旧配置
    references.m                  作者序列和明确的行/频率映射
    readIQ.m                      01 读文件、质量检查、PSD
    resampleCapture.m             02 名义重采样和DC去除
    findFrame.m                   03 独立捕获、选择和坐标转换
    extractFrame.m                04 完整帧取样、CFO补偿
    removeCP.m                    05 分符号、去CP
    fftGrid.m                     06 每列FFT
    estimateChannel.m             07 SSS信道估计
    equalizeGrid.m                08 均衡、留出导频误差
    observePilots.m               09 导频初值
    classifyColumns.m             10 各数据列点数识别
    trackFrame.m                  11 逐列ML和整帧跟踪
    refineOffsets.m               12 更新CFO/SFO
    decideSymbols.m               14 条件最近点判决
    measureGuard.m                补充：帧末保护区观察
    +alg/                         具体数值算法；基础主线学完再看
      detectSync.m                PSS重复片段搜索、PSS/SSS联合确认
      interpolateSinc.m           有限长度带限插值
      cardinality.m               kmeans和中位轮廓得分
      fitColumn.m                 单列几何、增益和相位歧义处理
      fitSymbol.m                 9起点筛选、局部Newton优化
      marginalNLL.m               似然、梯度、Hessian
      ransacLine.m                排除异常点后拟合直线
    beginLesson.m、step.m          新建实验、保存和回读；不做DSP
    drawStep.m                    只画已保存结果；不修改分析变量
    runOne.m                      用函数工作区运行主脚本
    validateRun.m                 独立回读检查；不修改原评价器
    sha256.m                      文件指纹
  tests/validate_learning_modules.m  与原算法同输入的工程对照
tools/learning_receiver.py         启动MATLAB和生成图文记录，不做DSP
scripts/run_learning_receiver      终端入口
config/learning_validation_v1.json  学习版检查规则v1
```

MATLAB中 `+slrx` 是包目录，因此调用写成 `slrx.readIQ(cfg)`。不需要把包里每个目录都 `addpath`，只添加 `matlab/learning_receiver`。不要对整个vendor执行 `genpath`：作者不同包有同名函数。

每个处理模块接收结构并返回结构；不会暗中读取上一步MAT。主脚本中箭头是显式的，例如 `frequencyGrid → estimateChannel → channel`。`slrx.step`只统一保存、回读和画图。这样可以单独查看算法，而不用先读文件管理代码。

例如主脚本中的这一行：

```matlab
capture = slrx.step(lesson_cfg,'01_capture',@()slrx.readIQ(lesson_cfg),1);
```

其中 `@()slrx.readIQ(...)` 是一个“需要时再执行”的计算任务。`step`发现已有MAT就回读；没有才执行它。最后的1只是选择画图方式。**实际读文件的算法只有 `slrx.readIQ(lesson_cfg)`。**

如果暂时不想理解保存工具，可以直接在命令窗口调用纯模块：

```matlab
addpath('matlab/learning_receiver')
cfg = slrx.defaultConfig();
refs = slrx.references(cfg);
capture = slrx.readIQ(cfg);
sampled = slrx.resampleCapture(capture,cfg);
synchronization = slrx.findFrame(sampled,refs,cfg);
offsets.cfo_hz = synchronization.selected.coarse_cfo_hz;
offsets.sfo_ppm = offsets.cfo_hz/cfg.center_frequency_hz*1e6;
frameTime = slrx.extractFrame(sampled,synchronization,offsets,cfg);
ofdmTime = slrx.removeCP(frameTime,cfg);
frequencyGrid = slrx.fftGrid(ofdmTime,refs,cfg);
channel = slrx.estimateChannel(frequencyGrid,refs,cfg);
equalized = slrx.equalizeGrid(frequencyGrid,channel,refs);
```

这段调用执行同一套前8步DSP，但不自动保存/画图；正式学习记录建议仍用分节主脚本。它展示了模块之间真实的输入输出关系，而不是另一份接收算法。

## 四、怎么分步执行

### MATLAB界面：适合学习

```matlab
cd('/path/to/starlink_phy')
open('matlab/learning_receiver/START_HERE.m')
```

在编辑器先执行第0节，再用Ctrl+Enter逐节执行。第0节创建 `lesson_cfg`、公开参考 `refs` 和独立学习目录。第1节后工作区有 `capture`；第2节后有 `sampled`；之后按节新增变量。**不先清空工作区**，这样能对照前后结果。

默认图形窗口可见，同时保存PNG。想修改输入或DSP参数，应在第0节的 `slrx.beginLesson` 之前设置，或先在命令窗口创建配置：

```matlab
addpath('matlab/learning_receiver')
lesson_cfg = slrx.defaultConfig();
lesson_cfg.read_duration_s = 0.004;
lesson_cfg.frame_rank = 1;
% 此时再执行START_HERE第0节及后续节。
```

重新打开MATLAB后，恢复同一次实验：

```matlab
S = load('runs/你的学习目录/lesson_config.mat','frozenConfig');
lesson_cfg = S.frozenConfig;
lesson_cfg.show_figures = true;
% 再从第0节顺序执行：已有步骤回读MAT，新步骤计算。
```

`stop_after` 是整份脚本运行时的停止点。交互执行单节时，单节末尾的 `return` 只结束本次执行，不会禁止你手动运行下一节。

### 终端：适合复现

```bash
scripts/run_learning_receiver --through 8
scripts/run_learning_receiver --resume codex-learning-实际目录名 --through 14
```

每次MATLAB批处理只启动一个进程。`--through 1...14` 指跑到指定步骤；13包括13a～13h。`--no-plots` 可跳过画图，数值照常保存。默认超时900秒；不要因算法出错就盲目增加超时。

改变代码、窗口、DSP参数时建立新运行：

```bash
scripts/run_learning_receiver --duration-ms 50 --frame-rank 2 --through 8
```

不要手动删掉一个前置MAT、却保留并使用其旧下游。要重算整条链，建立新目录最清楚。在MATLAB里可设 `lesson_cfg.run_dir=''` 后重新执行第0节。`resume=false` 会使随后执行的各节重新计算；应顺序重跑所有依赖它的后续步骤。

## 五、每步原理、结果和检查方法

以下路径均相对本次 `lesson_cfg.run_dir`。每个MAT的入口变量统一叫 **`data`**；主脚本给它取了更有意义的工作区名字。完整复数组在MAT中，JSON只放摘要，PNG只负责展示。

### 0. 建立参数和公开参考

`slrx.defaultConfig` 设置Fs、N、CP等；`slrx.references` 直接调用本地作者的 `genPss/genSss/genEdgePilots` 和四点星座生成函数。

| 参数 | 数值与含义 |
|---|---|
| 采集Fs | 250e6复采样/秒 |
| 模型Fs | 240e6复采样/秒 |
| N、Ng | 1024个有效时间采样、32个CP采样 |
| 子载波间隔 | Fs/N = 234375Hz |
| 普通OFDM时长 | (1024+32)/Fs = 4.4μs |
| 占用部分 | PSS + SSS + 300个数据OFDM时隙，共302×1056=318912模型采样 |
| 名义时隙周期 | 1/750秒，对应320000模型采样 |

`refs.pilots` 为1024×301，已去掉作者模板里的PSS列，不把302列模板直接套到301列FFT网格。

### 1. 从BIN得到复数IQ：`readIQ.m`

公式：`r[n] = (I[n] + jQ[n])/32768`。默认4ms读取1,000,000份复采样。

输出 `capture` → `01_capture.mat`：

- `iq`：复数列向量。
- `fs_hz`、`first_complex_sample`、`duration_s`：采样轴。
- `rms`、`dc`、`clipped_fraction`：幅度、直流和截幅检查。
- `psd_linear`、`psd_frequency_hz`：Welch功率谱密度，频率相对中心。

先看IQ有没有全零、明显截幅或异常直流，再看PSD中信号占用区域。PSD不能告诉你具体是哪一帧，也不能证明星座恢复成功。当前例子使用已选定的宽带IQ；此处没有实现任意输入上的自动选频道器。

### 2. 从250Msps到240Msps：`resampleCapture.m`

`resample(x,24,25,50)` 包含插值低通/抗混叠滤波，再按24/25改变样本数。随后减去本窗口均值。这里是**名义采样率**转换，真实时钟/Doppler引起的残余采样速率偏差SFO还没有解决。

输出 `sampled` → `02_resampled.mat`：`iq`、`fs_hz`、`ratio`、`filter`、`removed_dc`、原文件窗口起点。默认应有960000份模型复采样。

MATLAB `resample`处理滤波器的标称群延时，时间零点沿用窗口第一份复采样；FIR边界仍有过渡，因此不要把窗口边缘当成理想完整观测。实际同步位于窗口内部。

### 3. 找PSS/SSS和帧起点：`findFrame.m` → `alg.detectSync.m`

先回答“模板出现在哪里”，再考虑后续解调。完整相关的易读表达是：

\[
\rho(t,f)=\frac{|\sum_l r[t+l]e^{-j2\pi fl/F_s}p^*[l]|}{\sqrt{\sum_l|r[t+l]|^2\sum_l|p[l]|^2}+\epsilon}.
\]

这里保存的是**相关幅度**，不是平方后的相关功率。数值越接近1越像模板，但实际门限依工程配置，不能把所有局部峰都当完整帧。

实际搜索不做整个50ms×全部CFO的大网格：先把PSS拆成8个128点片段相关并加幅度，提便宜候选；利用重复段估粗CFO；处理PSS第一段的已知反号，并枚举有限模糊分支；再用连续PSS+SSS的2112点联合相关确认和细化CFO。最后检查PSS、SSS和完整帧长度。

重复段公式为 `f_hat = Fs/(2πL) * angle(Σr[n+L]conj(r[n]))`，L=128。角度只有2π周期，所以仍有 `Fs/L` 的频偏模糊，不能把这一步直接当最终CFO。

输出 `synchronization` → `03_sync.mat`：

| 字段 | 用途 |
|---|---|
| `selected.start_sample_nominal` | 当前240Msps窗口的一基帧起点 |
| `selected.start_sample_capture` | 原BIN的一基连续复采样坐标，可带小数 |
| `selected.coarse_cfo_hz` | 此时的CFO估计，后面仍会更新 |
| `selected.pss_metric/sss_metric` | 两个同步依据分别保存 |
| `selected.sync_local_curve` | −8:8模型采样附近PSS、SSS和联合相关曲线 |
| `selected.sync_window_raw/compensated` | 同步段补偿前后2112份复采样 |
| `candidates`、`rejected` | 候选、拒绝及原因 |
| `scan` | 粗搜索分数，每100模型采样留一个点 |

原采样坐标转换：

`s_capture = first_complex_sample + (s_model−1)×250/240`，`t_global=(s_capture−1)/250e6`。

`frame_rank`按合格候选的时间顺序选择，不是作者帧号。没有读作者sliceInfo。没通过捕获的区域仍然在原BIN中，也有粗分数/拒绝记录；只是不把它伪造为已知完整帧。它可能是噪声、其他波束、截断信号或算法漏检。

### 4. 取完整帧与CFO补偿：`extractFrame.m`

输入帧起点、CFO和SFO，生成需要读取的非整数位置：

\[
p_n=s_0+\frac{n}{1+\epsilon_s},\quad
x[n]=\operatorname{interp}(r,p_n)\exp\left[-j2\pi f_{CFO}\frac{n/(1+\epsilon_s)}{F_s}\right].
\]

`epsilon_s = sfo_ppm×1e−6`。`interpolateSinc`负责有限长度带限插值，不是直接把小数取整。CFO补偿以帧首为时间零点。

输出 `frameTime` → `04_frame_time.mat`：`time_raw`、`time_cfo_compensated`、`sample_positions_nominal`、`sample_position_step`、`cfo_hz`、`sfo_ppm`。二者长度均318912；其中raw指“尚未乘CFO补偿”，**已经是名义重采样后的数据**。

初始SFO用 `CFO/中心频率` 给启发值，沿用原方法，并非已测得ADC晶振真值。第一轮跟踪后再估计总SFO。

### 5. 分符号、去CP：`removeCP.m`

将318912个时间采样整形成1056×302。第1列PSS单独保留；其后301列是SSS+300列数据，去掉各自前32点CP：

`without_cp = blocks(33:1056,2:302)`，尺寸1024×301。

CP是有效符号末尾32点的复制，帮助减轻有限多径下的符号间干扰；PSS具有特殊重复/反号结构，不在这里当普通OFDM重新生成。

输出 `ofdmTime` → `05_without_cp.mat`：`pss_time`、`cp_samples`、`without_cp`、`cp_correlation`。CP相关比较前32点与有效符号末32点；噪声、多径、窗口和残余偏差都可能使其小于1，不能要求每列精确为1。

### 6. FFT得到频域网格：`fftGrid.m`

\[
Y_m[k]=\frac1{\sqrt N}\sum_{n=0}^{N-1}x_m[n]e^{-j2\pi kn/N}.
\]

MATLAB为 `fft(without_cp,[],1)/sqrt(1024)`，即每一列单独FFT。矩阵保持未shift顺序：FFT零基bin为 `0:511,-512:-1`，对应MATLAB行1:1024；`frequency_hz = bin×234375`。

输出 `frequencyGrid` → `06_fft_grid.mat`：`values`、`frequency_bins`、`frequency_hz`。第1列SSS，第2列数据1，第301列数据300。显示网格时才fftshift，**不改变保存的数据顺序**。

1024行中，4行是gutter，16行是公开边缘导频，剩余1004行是当前定义的非导频载荷位置；“载荷位置”尚不等于已知业务数据位，里面仍可能有头部或低熵结构。

### 7. SSS估计信道：`estimateChannel.m`

接收信号大致是 `Y[k]=H[k]X[k]+W[k]`。SSS的X已知，因此非零参考上可先算 `H_LS[k]=Y_SSS[k]/X_SSS[k]`。

直接LS含噪声，代码先在物理频率顺序上寻找一个小的时延斜坡，去掉后做21点三阶Savitzky–Golay平滑，再恢复斜坡与帧复增益。去斜坡是为避免平滑破坏快速旋转的相位，不是抹掉真实信道。

输出 `channel` → `07_channel.mat`：

- `H`：1024×1，与原FFT行顺序一致。
- `sss_ls_frequency_order`、`sss_deramped_ls`、`channel_smoothed_frequency_order`：LS、去斜坡、平滑的过程变量。
- `frequency_order_rows`：上述频率排序数组回到FFT行的映射。
- `sss_delay_samples`、`sss_delay_trial_samples`、`sss_delay_profile`：时延估计依据。
- `channel_normalized`、`frame_complex_gain`：形状与帧级增益。
- `sss_residual_frequency_order`、`noise_power_before_equalization`、`noise_variance_equalized`：残差与噪声估计。

复高斯噪声功率的稳健工程估计为 `median(|residual|²)/log(2)`。它依赖信道平滑模型，不是采集仪器给出的真实噪声标定。

学习版每帧单独估计H，不暗中读取其他帧或旧接收结果。旧整批接收机会合并多帧归一化SSS响应；这是两个入口之间明确的配置差异。

### 8. 均衡：`equalizeGrid.m`

`Z_m[k]=Y_m[k]/H[k]`。可把H理解为各频率上不同的缩放和转动，均衡尝试把这些影响除去。极深衰落处有数值幅度下限，避免除零；下限不代表那里已可靠恢复。

输出 `equalized` → `08_equalized.mat`：`values`及均衡前后留出导频EVM。此时只补偿了SSS描述的信道，后续列仍可能旋转、拉伸或随频率形成相位斜坡，星座不规整并不意外。

EVM定义 `sqrt(Σ|Z−P|²/Σ|P|²)`。已知导频P使误差可测；不把参与信道LS拟合的同一份SSS误差当成独立成功证据。前8步通过只表示读取、坐标、FFT和均衡计算关系正确，**不表示最终信号恢复质量通过**。

### 9. 导频给相位和时延初值：`observePilots.m`

未shift的导频MATLAB行为489:496和529:536。各取交替4条用于FIT，共8条；另8条留作EVAL。SSS信道参考不在这组数据列FIT/EVAL划分中。

相位模型：`angle(Z_m[k]/P_m[k]) ≈ phi_m − 2π d[k] delta_m/N`。左右导频的共同变化描述整体旋转，左右差异描述频率斜坡，后者对应时间偏移。

输出 `pilots` → `09_pilot_observations.mat`：`raw_phase_rad`、`raw_delay_samples`为逐列初值；`line_phase_rad`、`line_delay_samples`为跨列直线预览；`preview_grid`为仅用此预览补偿的网格。后面的ML用raw初值，**不把预览当最终ML结果**。

延迟单位是240Msps模型采样，除以240e6才是秒。相位单位rad，不是度。

### 10. 逐列点数识别：`classifyColumns.m` → `alg.cardinality.m`

对每列1004个非导频点，分别假设K=4/8/16/32，运行多次kmeans，用各点轮廓系数的中位数MSS评分，选最高K。轮廓系数大意是“离自己的簇近，离其他簇远”，不需要预先知道发送的业务比特。

输出 `classes` → `10_cardinality.mat`：`selected_cardinality`、4×300的`scores`、每列`records`里的中心/标签/SSE/轮廓得分。固定随机种子以便复现。

**这是模型选择，不是协议事实。** 每列用一个候选几何，未实现任意子载波混合调制的资源分区识别；不应把差异点强行解释成已知MCS。K=8暂按不支持的复合类型保留，后面擦除。K=4尚需结合相位约定区分QPSK与4QAM；作者这两个名字对应相差45°的四点几何。

### 11. ML和整帧残余跟踪：`trackFrame.m`

这是高级阶段，初学可以先看输入输出，不必一开始推导Hessian。每列模型为：

\[
Z_m[k]=A_m c_m[k]\exp(j\phi_m-j2\pi d[k]\delta_m/N)+w_m[k].
\]

载荷的c未知，不能拿硬判决当真值反复证明自己。算法将c在候选星座C里求和，最小化高斯混合负对数似然：

\[
L(\delta,\phi)=-\sum_k\log\left[\frac1{|C|\pi\sigma_k^2}\sum_{c\in C}\exp\left(-\frac{|z_ke^{j2\pi d[k]\delta/N-j\phi}-A c|^2}{\sigma_k^2}\right)\right].
\]

代码会按增益归一化观测/噪声，并为已知FIT导频加入已知符号项；EVAL不参加。`fitSymbol`筛选9个初值，精化其中2个，用梯度/Hessian给更新方向并回溯检查。它是局部优化器，不保证所有任意输入都找全局最优。

逐列结果仍有噪声或异常点，所以再用RANSAC选择时延内点，同一组内点拟合相位，处理90°相位歧义，得到整帧近似直线轨迹：`delta_m≈a_delta+b_delta*m`、`phi_m≈a_phi+b_phi*m`。

补偿为 `Z_corrected = Z * exp(j2π d[k]delta_m/N − jphi_m)`。符号取前向模型的相反方向。

输出 `tracked` → `11_tracking.mat`：

| 字段 | 意义 |
|---|---|
| `values` | 第一轮最终补偿网格，1024×301 |
| `ml_delay_samples`、`ml_phase_rad` | 逐列原始ML估计 |
| `ml_phase_unwrapped_rad` | 解除周期歧义后的相位 |
| `ml_inlier_mask` | 哪些列参与整帧直线拟合 |
| `ml_delay_residual_samples`、`ml_phase_residual_rad` | 原始估计偏离直线的程度 |
| `delay/phase_line_coefficients` | 斜率、截距，MATLAB polyfit顺序 |
| `delay_line_samples`、`phase_line_rad` | 每列实际采用的补偿轨迹 |
| `geometry_id`、`gain_per_data_symbol` | 列几何与幅度，不是MCS编号 |
| `ml_negative_log_likelihood`、`ml_iterations`、`records` | 优化代价、迭代、梯度/Hessian等证据 |
| `heldout_pilot_evm` | 未参加FIT的8条导频上的误差 |

不能只看拟合直线很平就宣布成功；还要看内点数、残差、留出导频误差和按列的星座。

### 12. 从整帧趋势更新CFO/SFO：`refineOffsets.m`

相位随时间积累说明仍有频偏，时间偏移随符号积累说明采样速率仍有偏差。沿用原算法符号约定：

```text
beta = delaySlope / 1056
SFO_total_ppm = ((1 + SFO0_ppm*1e-6)*(1-beta) - 1)*1e6
CFO_residual = phaseSlope*Fs*(1 + SFO0_ppm*1e-6)/(2*pi*1056)
CFO_total = CFO_coarse + CFO_residual
```

输出 `refinedOffsets` → `12_refined_offsets.mat`：总CFO、总SFO、残余CFO与摘要中的初值。CFO未单独拆分卫星Doppler和本振误差；SFO也不能单独归因于ADC时钟。

### 13. 按新时间轴重新走4～11步

时间轴改变影响取样和FFT，不能只旋转最后的散点。因此主脚本明确展开13a～13h：取帧→去CP→FFT→SSS信道→均衡→导频→点数→ML。它们调用同一组模块，不另藏第二套算法。

每个子步骤各自保存MAT/JSON/PNG；最终工作区叫 **`finalGrid`**，文件是 **`13h_tracking.mat`**。第一轮结果仍留在04～11文件中，可以比较修改时间轴前后的变化。

### 14. 条件星座符号判决：`decideSymbols.m`

在选定几何C和幅度A的条件下，`c_hat = argmin_c |z−A*c|²`。每个已识别列的1004个位置输出最近点；未知/K8列保留擦除，不硬凑答案。

输出 `decisions` → `14_decisions.mat`：

- `received`：实际收到的1004×300复数，按**物理频率**排序。
- `hard_symbols`：归一化理想星座点；`hard_symbols_observed_scale`为乘列增益后的参考点。
- `point_id_0based`：本代码几何列表里的零基编号；擦除为−1，不能转成真实商业比特。
- `valid_mask/erasure_mask`：哪些位置给出条件判决，未知点为NaN。
- `conditional_model_posterior`：给定几何和噪声假设的诊断量，不是已标定的业务位置信度。
- `payload_matlab_rows`、`frequency_bins_signed`、`source_grid_columns`：回查原FFT网格的位置。

最终星座图只展示 `display_data_column` 指定的一列，默认数据列50，即原网格列51。不要把300列可能有不同几何/幅度的点全堆在一张图里。

此处没有可靠的商业位标签、码块边界、扰码状态、FEC H或业务CRC。判决是下一阶段实验的输入，不等于解扰或译码完成。

### 补充观察：帧末保护间隔 `measureGuard.m`

名义剩余长度 `320000−318912=1088` 模型采样，约4.5333μs。用最终SFO把“帧占用结束”和“名义下一个时隙开始”投影回原采样轴。

输出 `guard` → `15_guard.mat`：`start_sample_capture`、`end_sample_capture_exclusive`、`sample_indices_capture`、该区`samples`、前一同长度区间的`preguard_samples`、功率及`power_ratio`。

区间约定为连续一基、左闭右开 `[start,end)`，整数采样中心取 `ceil(start):ceil(end)−1`。这两个端点是**模型预测**，不是独立检测的噪声边缘；功率不低也应如实保留。一个帧后的空隙不能直接解释为“下一个750Hz时隙必须有同波束帧”。

## 六、变量文件速查与读取例子

| 工作区变量 | MAT文件 | 重点先看 |
|---|---|---|
| `capture` | `01_capture.mat` | `iq,fs_hz,rms,psd_*` |
| `sampled` | `02_resampled.mat` | `iq,ratio,filter,removed_dc` |
| `synchronization` | `03_sync.mat` | `selected,candidates,rejected,scan` |
| `frameTime` | `04_frame_time.mat` | 时域补偿前后、实际读取坐标 |
| `ofdmTime` | `05_without_cp.mat` | `without_cp,cp_samples,cp_correlation` |
| `frequencyGrid` | `06_fft_grid.mat` | `values,frequency_bins` |
| `channel` | `07_channel.mat` | `H`及LS/平滑/噪声过程 |
| `equalized` | `08_equalized.mat` | `values`及导频EVM |
| `pilots` | `09_pilot_observations.mat` | raw初值与line预览分开看 |
| `classes` | `10_cardinality.mat` | 点数及所有候选得分 |
| `tracked` | `11_tracking.mat` | 第一轮ML、内点、残差、补偿网格 |
| `refinedOffsets` | `12_refined_offsets.mat` | CFO、SFO的更新 |
| `...Final` | `13a`至`13g`的对应MAT | 同一模块的第二轮结果 |
| `finalGrid` | `13h_tracking.mat` | 最终网格与跟踪依据 |
| `decisions` | `14_decisions.mat` | 最近点、擦除、原网格坐标 |
| `guard` | `15_guard.mat` | 保护区端点、真实短IQ、功率 |

独立查看已有文件，不必重跑：

```matlab
runDir = '/path/to/starlink_phy/runs/你的学习目录';
D = load(fullfile(runDir,'03_sync.mat'),'data');
sync = D.data;
sync.selected.start_sample_capture
(sync.selected.start_sample_capture-1)/250e6
plot(sync.selected.sync_local_curve.lag_model_samples, ...
     sync.selected.sync_local_curve.sss,'o-')

D = load(fullfile(runDir,'13h_tracking.mat'),'data');
finalGrid = D.data;
col = 50;
D = load(fullfile(runDir,'14_decisions.mat'),'data');
points = D.data.received(:,col);
figure; plot(real(points),imag(points),'.'); axis equal
```

`lesson_config.mat/json`保存参数；`source_code/`保存当次学习代码；`lesson_lock.json`记录原输入SHA、代码SHA和原评价器锁SHA。大IQ/网格不塞进JSON。**教学版有意逐步保存数组，会比生产接收机占更多磁盘**；学习结束后可归档整个学习运行目录，不要删原始数据来腾空间。

`learning_report.html`由终端启动器生成，显示各步摘要与PNG，图片在本地 `figures/`，没有联网依赖。只在MATLAB界面逐节执行时，MAT/JSON/PNG照常产生，但不会自动调用Python生成HTML。

## 七、怎么看是否处理对了

1. 读文件：原BIN前32份复采样与保存IQ精确一致；不得把int16分量数当复采样数。
2. 同步：PSS和SSS各自有相关依据，原/模型坐标换算一致；合格帧完整落在窗口内。
3. 去CP/FFT：尺寸1024×301；FFT独立重算一致；列1明确是SSS。
4. 信道/均衡：H有合理幅度和相位，保存网格确实等于Y/H；这些代数检查本身不证明真实信号恢复质量。
5. 跟踪：看原始ML点、内点和残差；留出导频EVM要有改善，避免“用来拟合的点误差很小”循环论证。
6. 符号：按列看接收点与几何，检查未知/擦除；真实业务没有位真值，不报告业务BER。

学习版规则单独标为 `learning-validation-v1`。数学拆分与旧算法做**同输入**对照，检查插值、FFT、信道、似然及完整300列跟踪。原检查点仅作为这项工程回归的输入，**不作为新真实接收的捕获输入**。

真实单帧检查沿用旧评价器的留出导频EVM≤1.2、相对原FFT改善≥5%这两个数值；没有为本轮结果降低门槛。一帧通过仍不替代原评价器“至少2个完整帧”的整体验收要求。前8步的报告状态为partial，表示后半链尚未跑完。

实际已运行的目录、时间和误差见 `reports/learning_receiver_validation.json`；原有 `reports/demo_acceptance.json`没有被本学习实验重写。

## 八、从一帧扩展到多帧

```matlab
addpath('matlab/learning_receiver')
batchDir = RUN_MULTIPLE_FRAMES(2,8);
```

入口对每个独立检测后时间序号各建 `frame_01/frame_02`，调用相同的单帧模块。为使代码容易读，目前每帧各读50ms、各做捕获，没有引入复杂的共享缓存；这会多花一些时间。每帧自己估H，不共享旧接收机的跨帧信道。

多帧应对比：起点与时隙差、PSS/SSS质量、CFO/SFO、H形状、留出导频EVM、各列几何和擦除。不要只对比最终一张叠加散点图。

## 九、与原接收机的关系和资料依据

本学习版保留原接收算法的数值约定、点数识别、逐列ML、整帧趋势与两次处理，但做了两个明确简化：默认从50ms缩到4ms；默认不使用跨帧SSS共享信道。窗口DC估计也随窗口变化。因此**端到端输出不要求与旧多帧共享结果逐值相同**。算法模块在同输入时有单独对照证据。

来源分工：

- `sources/P01_frame_structure.pdf/txt`：公开帧结构与PSS/SSS等基础结构。
- `sources/N01_pilots_journal.pdf/txt`、`sources/N03_supplementary.pdf/txt`：导频、信道处理、残余同步与星座分析方法。预印本/期刊版不当两项独立实验。
- `vendor/author_pilots/reference-template/`：直接使用的序列生成代码。
- `vendor/author_pilots/utils/complexConstellations/`：直接使用的QPSK和4QAM几何。
- `docs/AUTHOR_RECEIVER.zh-CN.md`：原实现与作者公开范围、工程补齐项、既有作者对照结果。

作者公开的参考序列与仿真器并不构成一份完整的原始IQ真实接收程序。ML求解、门限和平滑等工程选择仍应按本地源码与固定版本说明理解，不冒称全部来自作者原版接收代码。

本学习版是理解和逐步实验的入口，不是声称已经完成了新的协议发现。后续若改混合调制识别或物理头解析，应建立明确版本，保留输入/网格/索引接口，再验证对下游判决的影响。

## 十、本版已实际验证到哪里

2026-10-26在Linux MATLAB R2025a实际完成：一帧前8步、从该MAT继续到14步及保护区观察、只执行第1步后停止，以及多帧入口的2帧前8步。完整学习运行是 `runs/codex-learning-20261026-211257-564111/`，可直接打开其中 `learning_report.html`，不必重跑。

该帧最终1024×301网格与1004×300条件判决矩阵均保存；留出导频EVM从刚均衡的1.4789降至最终0.2112。同输入数学模块与原算法对照通过，300列几何标签一致，网格相对差异约6.09e−16。

本机前8步约71秒，继续至完整判决约371秒；主要耗时在两轮300列点数识别，不能用一次FFT的速度估算整帧。两帧仅验证到均衡，尚未运行本学习版两帧完整14步。

查看[实际验证报告](../reports/learning_receiver_report.md)与[机器可读记录](../reports/learning_receiver_validation.json)。不要把本次单帧学习检查当成新的作者一致率、业务译码或在线模型能力证明。
