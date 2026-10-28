# 图像阅读索引：每幅图想回答什么

完整单帧默认生成27张主线图片；独立诊断报告生成15张图片；多帧报告另有2张对照图。一张图片可能包含多个子图，不同报告也会重复展示同一批数据。以下按用途梳理。

先阅读本索引，再结合[教学诊断手册](VISUAL_DIAGNOSTICS.zh-CN.md)理解公式、输入变量和坐标。实际复跑结果见[验证报告](VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)，修改前的图像和变量清单见[审计](VISUAL_DIAGNOSTICS_AUDIT.zh-CN.md)。

2026-10-28代码新增局部茎状图、逐符号散点和候选类别柱形/阶梯图，文件数量维持27/15/2。**该轮MATLAB运行验证按用户选择暂缓**；本页描述代码中的新布局，旧版实际图片不代表新版已经渲染通过。见[本轮静态检查与待验证记录](DISCRETE_VISUALIZATION_VALIDATION.zh-CN.md)。

## 1. 独立诊断报告的15张图

文件位于本次诊断输出目录的 `figures/`。图片由本机运行生成，仓库保留阅读说明和源码；表中的源码链接可直接在GitHub查看。

| 文件 / 图名 | 展示内容 | 用它回答的问题 | 源码 |
|---|---|---|---|
| `00_capture.png` 输入IQ与频谱 | 全窗口功率、频谱、I/Q概览与散点；另有32点茎状图和同时间轴重采样对照 | 输入有没有能量、零段、饱和或异常？选中帧在哪里？ | [plotCapture.m](../matlab/learning_receiver/+slrx/+viz/plotCapture.m) |
| `01_sync_global.png` 全局PSS搜索 | 每100点抽取的粗相关轨迹、实际候选及选中帧头 | 在整个文件窗口哪里找到帧？候选为何接受、拒绝或被选择？ | [plotGlobalSync.m](../matlab/learning_receiver/+slrx/+viz/plotGlobalSync.m) |
| `02_sync_local.png` 局部精细同步 | 选中帧头附近PSS、SSS与联合相关的整数偏移茎状图；原文件采样和时间 | 局部峰对应原文件什么位置？当前定时选择有什么依据？ | [plotLocalSync.m](../matlab/learning_receiver/+slrx/+viz/plotLocalSync.m) |
| `03_constellation_stages.png` 两轮同资源星座 | 每轮FFT、均衡、跟踪三个阶段，共六面板 | 同一个符号的相同子载波经过处理后怎样变化？ | [plotConstellationStages.m](../matlab/learning_receiver/+slrx/+viz/plotConstellationStages.m) |
| `04_conditional_models.png` 候选几何模型 | 真实观测与原算法选出的候选理想点 | 当前观测和几何假设是否相容？未知分类有没有被保留？ | [plotConditionalModels.m](../matlab/learning_receiver/+slrx/+viz/plotConditionalModels.m) |
| `05_cfo.png` CFO参考相位 | 已知同步序列补偿前后相位、已有ML相位估计 | 频偏造成的相位旋转是否得到补偿？ | [plotCFO.m](../matlab/learning_receiver/+slrx/+viz/plotCFO.m) |
| `06_sfo.png` SFO采样漂移 | 累积采样位置漂移、两轮坐标差、残余时延拟合 | 采样时钟偏差怎样累积？更新SFO后时间刻度怎样变化？ | [plotSFO.m](../matlab/learning_receiver/+slrx/+viz/plotSFO.m) |
| `07_ofdm_symbol.png` 单个OFDM符号 | 1056/1024点概览；CP边界、有效区局部与32个FFT频点的茎状图 | 1056＝32＋1024怎样落实到数组？时间样本如何成为频域观测？ | [plotOFDM.m](../matlab/learning_receiver/+slrx/+viz/plotOFDM.m) |
| `08_cp_copy.png` CP与尾部复制 | 32对采样的实部、虚部、幅度、相位差茎状图和复相关 | CP与有效区尾部是否相似？补偿前后相位差怎样变化？ | [plotCP.m](../matlab/learning_receiver/+slrx/+viz/plotCP.m) |
| `09_fft_grid.png` FFT资源网格 | 符号×频率的幅度热力图，FIT/EVAL导频和空子载波 | 能量分布在哪些符号和频率？SSS、数据列和导频怎样排列？ | [plotFFTGrid.m](../matlab/learning_receiver/+slrx/+viz/plotFFTGrid.m) |
| `10_channel.png` 信道与均衡 | H的幅度/相位、低H区域、噪声增益代理、单点Y/H | 信道怎样缩放和旋转信号？除以H为何能均衡，又有什么风险？ | [plotChannel.m](../matlab/learning_receiver/+slrx/+viz/plotChannel.m) |
| `11_pilot_evm.png` 留出导频EVM | 各阶段整体误差及逐符号误差，标定约定分开显示 | 在已知参考资源上，误差到底改善多少？哪些符号较差？ | [plotPilots.m](../matlab/learning_receiver/+slrx/+viz/plotPilots.m) |
| `12_pilot_cloud.png` 留出导频点云 | 去除已知参考后的复数点，目标位置(1,0) | 导频误差怎样扩散、偏移？点云和EVM是否相符？ | [plotPilots.m](../matlab/learning_receiver/+slrx/+viz/plotPilots.m) |
| `13_pilot_errors.png` 导频误差与相位 | 误差热力图、正负频率导频相位 | 异常集中在哪些符号、哪些频率？是否还有残余相位问题？ | [plotPilots.m](../matlab/learning_receiver/+slrx/+viz/plotPilots.m) |
| `14_guard.png` 帧末模型保护区 | 预测边界附近实际IQ幅度与相对功率 | 模型预测的保护区内，实际能量是否下降？观察窗口完整吗？ | [plotGuard.m](../matlab/learning_receiver/+slrx/+viz/plotGuard.m) |

## 2. 怎样读六幅阶段星座

`03_constellation_stages.png` 每一行是一轮完整的内部比较：

| 轮次 | 左面板 | 中面板 | 右面板 |
|---|---|---|---|
| 第一轮 | FFT后、均衡前 | 第一次均衡后 | 第一次残余跟踪后 |
| 第二轮 | 重新取样并FFT后 | 第二次均衡后 | 第二次残余跟踪后 |

默认选第50个数据符号，对应FFT网格第51列；载荷模式选择1004个数据子载波。也可以切换连续多个符号、正负频率、频段和导频。每次比较保留相同资源位置和统一坐标范围，标题标出原始RMS及显示除数。

先观察点的扩散、拉伸与旋转，再用11号EVM图量化已知导频误差。真实结果可以局部变差，不能以所有阶段都“更整齐”为验收条件。多符号混合点云还可能包含多种候选几何与增益。

## 3. 只看I路能看出什么

I路曲线显示复信号的实部随时间变化。它能帮助发现饱和、全零段、突变和局部幅度变化；结合Q路、功率与频谱，才能更完整地检查输入。

原始OFDM时间采样是多个子载波叠加后的结果。00号图中的IQ散点称为“原始时域IQ散点图（非子载波调制星座）”。讨论单个子载波的星座结构，应查看FFT之后的复数点，即03号图所展示的资源。

12号图把每个已知导频都换算到共同参考(1,0)，所以期望看到一个目标点附近的云团。这个显示方式不能用于断言未知载荷的调制类型。

## 4. 逐步学习主线的27张图

主线图在每步运行时生成，适合跟随 `START_HERE.m` 查看变量；同一模块在两轮处理中分别保存图片。绘图入口为 [drawStep.m](../matlab/learning_receiver/+slrx/drawStep.m)。

| 图的类型 | 张数 | 主要用途 |
|---|---:|---|
| 原始IQ波形、输入频谱 | 2 | 检查输入幅度与频率分布 |
| 重采样后波形 | 1 | 模型时间序列概览及前32点I/Q茎状图 |
| 全局、局部同步 | 2 | 定位帧头并检查相关依据 |
| 两轮取帧与CFO补偿波形 | 2 | 查看取出的帧和补偿前后波形 |
| 两轮去CP观察 | 2 | 检查CP与有效区处理 |
| 两轮FFT网格 | 2 | 查看频域资源分布 |
| 两轮信道幅度、相位 | 4 | 查看频率选择性的缩放与旋转 |
| 两轮均衡后星座 | 2 | 查看选中符号的均衡结果 |
| 两轮FIT导频相位观察 | 2 | 查看参与估计的导频初值；独立质量另看EVAL |
| 两轮候选点数得分 | 2 | 整帧热力图、选中符号柱形得分与逐符号K台阶 |
| 两轮ML相位、时延拟合 | 4 | 查看逐符号估计、异常点和整帧趋势 |
| 条件符号判决 | 1 | 查看给定候选几何后的判决结果 |
| 帧末保护区 | 1 | 查看预测保护区实际能量 |

## 5. 多帧额外的两张图

| 文件 | 作用 |
|---|---|
| `multi_frame_constellations.png` | 比较不同帧相同阶段、相同符号和子载波位置的点云；显示是否资源一一配对 |
| `multi_frame_metrics.png` | 比较各帧已有阶段的留出导频EVM，查看帧间误差变化；缺失值不补成0 |

源码为 [plotFrameComparison.m](../matlab/learning_receiver/+slrx/+viz/plotFrameComparison.m)。本机验证中，第一帧完成全部步骤，第二帧只完成前端；因此跨帧星座使用两帧共同具有的第一轮均衡结果。详细范围见验证报告。

## 6. 建议的阅读与生成顺序

先看 **00 → 01/02 → 07/08 → 09 → 10 → 03 → 11**，再用05、06、12、13定位残余误差。04用于理解候选几何，14用于检查帧末窗口。

准备资源、在MATLAB中进入仓库根目录并运行教学步骤后：

```matlab
addpath('matlab/learning_receiver')
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 50);
h = BROWSE_DIAGNOSTICS(lesson_cfg.run_dir);
```

终端给出本机 `index.html` 路径。完整运行默认显示15类诊断图；部分运行会明确指出缺失步骤。坐标切换和资源选择在MATLAB原生窗口操作，静态PNG保留导出时的选择。

图像能支持的结论取决于参考来源：同步相关支持定位，已知EVAL导频支持误差检查，候选几何支持模型相容性。商业业务位、MCS、扰码、FEC、CRC及真实业务BER/SER仍需相应真值和协议信息。
