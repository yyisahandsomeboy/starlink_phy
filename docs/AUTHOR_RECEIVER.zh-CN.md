> 此文记录原完整工程的算法及历史实验。源码仓库只交付接收与学习代码，历史运行、作者大矩阵、后续协议研究及DSH未包含。当前可运行入口与资源准备以[仓库README](../README.md)为准。

# 作者代码融合、接收流程与中间变量

本轮保留原有观测接口，优先调用作者的公开函数，公开代码缺失的接收步骤根据论文补齐。代码仍标为 `codex_baseline`；作者处理后的符号和 TOA 只进入比较程序。原冻结评价器与数值门限保留。日常只需看真实接收、观测和作者对照三条链，不需要运行完整合成测试矩阵或在线模型。

## 作者究竟公开了什么

2026-10-14 重新核对了[补充材料目录](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/)、[GUIDE](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/GUIDE.txt)与本地固定版本仿真器。

| 公开模块 | 本地位置 | 如何利用 |
|---|---|---|
| PSS、SSS、导频生成 | `vendor/author_pilots/reference-template/genPss.m`、`genSss.m`、`genEdgePilots.m` | 接收机通过 `author_sequences.m` 直接调用，未重写这些序列 |
| QPSK、4QAM 几何 | `vendor/author_pilots/utils/complexConstellations/genQPSKconst.m`、`gen4QAMconst.m` | 新接收与展示通过 `payload_models.m` 直接调用；内部点编号不等于业务比特映射 |
| 导频时域相关、FFT 相关 | `correlateEdgePilots.m`、`utils/signalProcessing/fftcorr.m` | 可调用的参考检查模块；当前接收主入口不使用它来替代完整捕获/跟踪 |
| PSS/SSS FFT 捕获 | `vendor/simulator/ut-starlink-signal-simulator-main-5de898badd03f6a8b3c7d5196b9b31d4039263ed/utils/fftAcqStrlk.m` | 已在真实 IQ 上单独直接调用；它是捕获器，不是完整真实数据接收机 |
| OFDM、帧、流生成 | 同一仿真器的 `genOFDM.m`、`genStrlkOFDM.m`、`genStrlkFrame.m`、`genStrlkStream.m` | 发射端和合成检查，日常真实分析不需要跑这些模块 |
| 作者结果的显示 | `vendor/author_pilots/loadAndPlotExemplarFrames.m` | 输入是已处理的 `yDec/ySoft` 等数据，不把原始 BIN 解调成这些变量 |
| 作者处理后的符号 | 远程大 MAT；本地比较器的私有小型子集 | 最后的逐帧对照，禁止作为接收输入 |

在这些实际检查的公开目录和固定版本中，没有找到完整的真实 IQ 信道估计、残余同步 ML、调制识别和判决程序。这是代码覆盖范围的结论，并非声称作者没有实现或不存在其他未核实的仓库。无需照搬作者全部仿真工程；有函数的步骤直接用函数，没有函数的步骤按公开方法补齐。

直接调用原版 `fftAcqStrlk.m` 的实际记录在 `runs/codex-author-stock-acquisition-20261014-170650/`。输入为真实采集开头的 320000 个名义模型采样，得到 `tau_s=0.0005000083333333333`、`fdfine_hz=-175000`，保存了 `author_acquisition.mat` 中的相关网格和 `summary.json`、日志。此窗口仅用于捕获验证，不完整覆盖这个帧的载荷。该频偏比精细接收估计约偏数 kHz，说明复用原版函数仍需检查采样和细化约定，不能仅凭可运行就替换整个接收链。

当前已有结果可从 [统一结果导航](../reports/results.html)打开；无需重跑接收机。

导航现为按处理顺序组织的离线阅读报告，直接展示27张单独主题图、公式、读图说明、实际指标和可搜索的变量索引。同步峰、信道幅度/相位、ML相位/时延、CP幅度/相位分别绘制；同一指标的处理前后允许在一图比较。9帧交互星座入口也集中在该页。

没有通信原理基础时，请先读页面新增的四节基础讲解：恢复目标，幅度/相位/IQ，采样与频谱，以及OFDM/子载波/星座。可操作的箭头和混合星座示意仅用于教学；后续27张诊断图仍来自真实接收结果。每个阶段有生活化解释和输入/输出说明，每张图有三步读法，12条公式可展开查看逐项解释，另有术语单位速查。本文件保留实现细节与精确变量路径，适合配合页面回查。

## 入口与输入

```bash
cd /home/a/Desktop/start_link_demo
scripts/run_baseline real
```

真实入口转到 `scripts/run_author_receiver`，每次新建 `runs/codex-author-real-<时间>/`。默认一个 MATLAB 进程、最多 3000 秒整批预算，包含多个帧的两次 ML 处理。约8 GB内存机器采用串行方案；可用 `--workers 1` 或 `--workers 2` 显式选择进程工作池。`scripts/run_demo` 会进一步生成诊断图、全帧星座/硬判决和作者对照。

输入是 `data/raw/exemplar250-257/exemplar250-257.bin`，小端交织 int16 I/Q。两个整数是一份复采样；12500000 个复采样，250 Msps，50 ms。归一化除以 32768 只改变幅度单位。中心频率是元数据和 Doppler 换算参数，不把 IQ 重新调制到 12 GHz。`sliceInfo.json` 不进入捕获。

本轮实际结果为7帧符号一致率86.50%、覆盖100%、调制类型一致率94.71%；结果与限制见 [本轮报告](../reports/author_receiver_report.md)。

`reports/author_receiver.json` 指向最近一次运行及其实际状态；取消、失败也会如实记录。只有其评价为 `passed` 才能把该运行称为已通过接收验收，不能依据代码存在作此判断。

## 信号经过哪些处理

统一前向约定为

\[
y_m[k]=A_m c_m[k]\exp\{j\phi_m-j2\pi d[k]\delta_m/N\}+w_m[k].
\]

`d[k]` 为未 shift FFT 的有符号频率索引，`delta` 以 240 Msps 模型采样为单位。补偿取相反指数。文献个别时延斜率/补偿符号不一致；以这个前向式及独立数值检查确定实现符号。

| 步骤 | 原理与实现 | 输出 |
|---|---|---|
| 文件质量检查 | 小端读 I/Q，计算 RMS、直流、分量截幅；前 1000000 采样估计 PSD | `quality`、`input_diagnostics.psd_*`、`iq_psd.png` |
| 名义采样率转换 | `resample(y,24,25,50)`，250 → 240 Msps；随后去均值 | FIR、比例、移除直流保存；全长流只在内存 |
| 独立帧捕获 | 作者 PSS 重复结构形成廉价候选；有限 CFO/延迟搜索，用作者 PSS+SSS 相干参考确认；频偏细化 | 帧起点、相关指标、同步窗口、局部峰、拒绝原因 |
| CP 和 FFT | 302×1056 个模型采样；PSS 单独处理，其后 301 列去 32 点 CP，`fft(x)/sqrt(1024)` | 1024×301 网格；列1为 SSS，列2:301为300列数据 |
| SSS 信道 | 非零参考上 `H_LS=Y_SSS/X_SSS`；去亚采样延迟斜坡后做21点三阶 Savitzky–Golay 平滑，再恢复斜坡及帧增益 | 原始 LS、去斜坡/平滑/归一化 H、帧增益、SSS 延迟和噪声估计 |
| 多 SSS 合并 | 只用独立捕获且 SSS 相关≥0.6的窗口，按相关平方加权归一化 H | 参与候选、权重、各自 H、共享 H；跨候选响应稳定为未核实假设 |
| 均衡 | `Z=Y/H`，深衰落做数值幅度下限保护 | `grid_equalized` |
| 星座点数 | 每列1004个非导频载荷点，K=4/8/16/32、20次 kmeans，取点轮廓系数中位数最大的 K | 各 K 得分、所选中心/标签、SSE；K8为未处理复合类型 |
| 每列时延/相位 | 高斯混合边缘似然；局部多起点数值优化；只用8条 FIT 导频初始化并帮助解除歧义，8条留出导频完全不参加拟合 | 每列 ML 参数、代价、梯度/Hessian、迭代、初值 |
| 整帧残余同步 | 时延 RANSAC 容差0.08模型采样，丢弃同一组相位点；90°周期展开，再拟合时延/相位直线 | 原始点、内点、残差、直线系数、整帧补偿轨迹 |
| CFO/SFO 更新 | 时延线斜率 `b_delta` → `beta_res=b_delta/1056`；总 SFO `(1+sfo0*1e-6)*(1-beta_res)-1`；相位斜率换算残余 CFO | 总/残余 CFO、SFO；按新时间轴再提取并进行第二次 ML |
| 星座与判决 | 用最终网格与该列候选几何做最近点判决；已识别列保留所有点，未知/K8列擦除 | 候选点、硬符号、几何编号、擦除、条件模型后验；没有业务比特 |
| 独立评价 | 重算 PSS/SSS、维度和留出导频；之后才对照作者 TOA | `evaluation.json`；随后单独比较作者硬符号 |

边缘似然的主要项为

\[
-\sum_k\log\left[\frac{1}{M\pi\sigma_k^2}
\sum_{c\in\mathcal C_M}\exp\left(-\frac{|Z_m[k]e^{j2\pi d[k]\delta_m/N-j\phi_m}-A_m c|^2}{\sigma_k^2}\right)\right].
\]

已知 FIT 导频加各自的已知符号高斯项；载荷增益不改变公开导频的幅度。曾发现将导频观测除以载荷增益却未同比缩放参考的错误，已经修正，并用非单位增益的导数/似然等价检查验证。数值归一化、优化范围、噪声估计、平滑窗口和异常值容差都是记录在配置/源码的工程设置，不冒称作者公开了同一组参数。当前实现主要对应 journal VI-A–D 与 PLANS V-B–F，尚未声称复现 journal VI-E 的完整整帧联合优化器。

QPSK 与4QAM几何相差45°；识别切换时需要同步处理相位约定。显示页的四个频段只是同一列载荷频率的四等分放大观察区，新方法由整列识别结果传给各区，不声称每区采用不同调制。

## 中间变量保存在哪里

在 MATLAB 中打开任一已完成运行：

```matlab
D = load('runs/<run_id>/result.mat','result');
R = D.result;
f = R.frames(1);  % 最终按原始文件时间排序
```

| MATLAB 路径 | 内容/单位 | 是否保存 |
|---|---|---|
| `R.quality` | 样本数、Fs、RMS、DC、截幅比例 | MAT、JSON摘要 |
| `R.input_diagnostics` | 重采样 FIR、PSD 数值、DC和坐标说明 | MAT |
| `R.acquisition_scan` | 粗分数，每100模型采样保存1点 | MAT；没有保存完整1200万点曲线 |
| `R.rejected`、`R.candidate_diagnostics` | 不完整/质量拒绝、异常及原因 | MAT、部分JSON |
| `f.start_sample_capture` | 原始流连续一基坐标；可有小数；`t=(s-1)/250e6` | MAT、JSON |
| `f.start_sample_nominal` | 24/25名义重采样流一基坐标；`t=(s-1)/240e6` | MAT、JSON |
| `f.sync_window_raw/compensated` | PSS+SSS窗口，固定2112复采样 | MAT |
| `f.sync_local_curve` | 相对起点−8:8模型采样的 PSS、SSS、联合相关值 | MAT |
| `f.grid_before/resampled/equalized/after` | 旧接口保留；粗 CFO、CFO/SFO再提取、均衡、最终补偿四级网格 | MAT |
| `f.channel_response` | 1024×1复数 H，保留原接口 | MAT |
| `f.intermediates.time_*` | 三个采样时间轴阶段的帧时域 IQ、CFO后IQ、CP、去CP、CP相关、起点/步长 | MAT |
| `f.intermediates.channel_first/final` | LS、平滑、归一化 H、SSS延迟/轮廓、帧复增益、均衡后噪声方差 | MAT |
| `f.intermediates.first_ml_tracking/first_modulation` | CFO/SFO更新前第一轮参数和聚类依据 | MAT |
| `f.tracking` | 最终逐列 ML 参数、内点掩码、残差、拟合直线、相位/时延轨迹 | MAT |
| `f.modulation` | 300列几何、载荷增益、4×300 MSS得分和每列记录 | MAT |
| `f.frame_guard` | 下节所有边界、短IQ、功率和检测间距 | MAT；JSON不包含复数IQ短数组 |

`frame_time_raw` 中的raw表示未乘CFO修正，已经名义重采样；它不是原始250 Msps流。CFO不单独区分Doppler/本振，SFO也不单独代表ADC晶振误差。

每个成功候选还保存 `frame_candidate_XX.mat` 的 `completed_frame`，这是完成帧的检查点；最终 `result.mat` 加入了按时间排序后的保护间隔和相邻帧信息。星座导出通过 `load_payload_frame.m` 按最终起点读取一个检查点，避免把约776MB整批MAT反复载入。读取前后检查 `run_manifest.json` 的检查点和摘要哈希；独立回读检查逐字段核实检查点与最终帧除 `frame_guard` 外完全一致，并直接从原始BIN核对保护窗IQ。完整原始/重采样流不重复保存，原始 BIN 保留。中间变量不因最终判决而删除；既有网格接口也不改名。

`receiver-code/` 是当次源码快照，`receiver_lock.json` 在运行前记录代码、配置、原始输入与验收锁的 SHA；`execution.json` 和 `author_receiver_*.log` 保存实际 MATLAB 调用及错误。失败候选不会让其它成功检查点丢失。

## 帧末保护间隔

模型周期320000采样，302个占用时隙共318912采样，所以

\[
T_{guard}=\frac1{750}-\frac{302(1024+32)}{240\times10^6}
=\frac{1088}{240\times10^6}=4.533333\ldots\ \mu s.
\]

这与每个 OFDM 符号的32点 CP不同。一个名义帧周期中，占用302个时隙后剩下的1088点才是这里讨论的帧末保护间隔。

设名义流起点 `s`、样本映射比例 `q=1/(1+sfo_ppm*1e-6)`，保存

\[
s_{guard,start}=s+318912q,\quad s_{guard,end}=s+320000q.
\]

边界是连续一基、右端不含的 `[start,end)`；映射到原始流为 `s_capture=1+(s_nominal-1)*25/24`，时间为 `(s_capture-1)/250e6`。短IQ窗取满足该半开区间的整数采样；若只有部分数据则记录截断，不补零。

`f.frame_guard` 保存：名义4.533333µs/1088模型点/SFO映射后持续时间；两个采样网格及秒坐标的边界；`raw_guard`、`nominal_guard`、等长的 `raw_preguard/nominal_preguard` 的索引、IQ、样本数、覆盖率、RMS/平均功率；保护间隔与前窗的功率比；前后相邻检测的实际时间差、间隙和参考时隙倍数。

这些边界的 `endpoint_source=model_predicted`。没有声称用噪声能量独立检测出静默边缘；目标波束静默时其它波束/通道仍可能有能量。等长前窗约包含最后一个1056点符号及此前32点，不是孤立的最后一个 OFDM符号。

**采样时钟与帧时钟未必相同。** 上述1088点窗按波形样本映射推算；若帧时钟有效比例为 `q_f`、波形采样比例为 `q_s`，相邻同束帧真实占用末端到下一帧的间隙应为 `1/(750*q_f)-318912/(240e6*q_s)`。当前没有独立估计 `q_f`。相邻实际检出时间差可直接观测；时隙倍数仅是采用共同速率假设的参考，不据此宣称丢失了几个帧或测到了帧时钟误差。没有帧头检测的区间仍保留在原始 IQ，可能包含弱帧、其它波束或其它信号。

## 如何观察和对照

对一个已完成 `run_id`：

```bash
scripts/plot_ofdm <run_id>
scripts/analyze_payload <run_id> --all-frames --open
scripts/compare_author <run_id>
```

第一条产生资源网格、局部同步、信道/相位/时延、CP和留出导频误差；第二条为每个帧保存 `payload_analysis/` 下的 `analysis_data.mat`、`symbol_candidates.mat`、`symbol_decisions.mat`、JSON、PNG和可离线打开的 `explorer.html`；第三条只在接收输出冻结后按评价匹配关系对照作者。

原始汇总诊断及其数值由 `diagnostics/latest.json` 定位；新的单主题阅读图由 `diagnostics/readable_latest.json` 定位，存放在一个独立的 `readable-v1-*` 子目录。阅读图依据已有诊断数值和第一帧检查点重绘，只有原始功率/PSD视图重新只读采样文件，不更新接收估计。每组新图保存实际MATLAB日志、输入/源码哈希和manifest。

用 `python3 tools/results_page.py` 从已有单图重建HTML；加 `--render` 重新调用本机MATLAB绘制单图后更新HTML。`scripts/run_demo` 在作者对照结束后自动执行这一更新。打开页面本身不执行MATLAB。

`payload_analysis/latest.json` 指向首个帧的网页和判决数组，`all_frames_latest.json` 指向全帧导出清单。显示页四个频段为观察放大，不是协议定义的调制分区。已知列的最近点判决保留全部点；未知/K8列擦除。这是独立的 `author-nearest-symbol-v1` 策略，不是把旧 `.90`后验筛选门限临时降低。后验只用于显示，条件后验高也不能证明识别的调制正确。

对照必须同时报告与作者一致的符号数、全部参考数、保留数、擦除数、条件一致率、覆盖率、全参考一致占比及调制类别混淆。作者也是估计结果，不是业务真值；未恢复商业 LDPC H、码块、位映射、扰码，不能报告真实 BER或声称已完成业务解码。作者7帧的硬/软符号小型子集只在比较侧，未下载整份约5GB矩阵。

## 本轮验证记录

- [x] 核对论文与引用方法，保留原代码快照和资源哈希。
- [x] 保护间隔计算与7项原生MATLAB验证。
- [x] 实现相位/时延似然、星座点数识别、SSS信道处理；原生导数/恢复/归一化检查。
- [x] 接入真实接收、阶段变量和现有观测界面；单帧开发导出检查通过。
- [x] 冻结本轮参数后运行真实IQ、原评价器及作者逐帧对照；9网格/7标注帧。
- [x] 保存实际结果、差异及复现命令；详见 [本轮实际报告](../reports/author_receiver_report.md)。

旧版本实验已清理。当次接收源码证据保留在 `runs/codex-author-real-20261014-170603-942987/receiver-code/`；日常只读当前工作区的实现。新方法引用：`sources/P08_qin_ML_Precise_TOA_PLANS.pdf`（页码由文本 form-feed 保留），下载记录 `sources/P08_manifest.json`。
