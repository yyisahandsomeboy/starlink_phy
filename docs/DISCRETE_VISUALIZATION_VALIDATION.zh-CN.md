# 离散教学视图：实现与待验证记录（2026-10-28）

**代码实现与静态检查已完成。MATLAB绘图运行、新增自动测试和数值运行回归尚未完成。首轮运行因主机内存保护中止，用户明确选择“先完成代码，暂缓MATLAB运行验证”；此后未再启动MATLAB。**

本记录针对基线提交 `9ab8723` 之后的显示改动。2026-10-27的[已通过验证](VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)属于旧版本，不能作为本轮新布局已经运行通过的证据。

## 已完成的显示修改

| 位置 | 修改 | 数据边界 |
|---|---|---|
| 主线原始IQ、重采样图 | 保留前5000点概览，增加前32点I/Q茎状图，标出真实Fs与ns间隔 | 不重算采样或改变幅度 |
| 00输入诊断 | 增加原始32点茎状图与同一真实时间窗内的原始/模型I分量采样对照 | 使用已保存MAT；重采样包含既有FIR/DC差异，缺少模型数据不补造 |
| 02局部同步 | PSS/SSS/联合相关用茎状图和整数偏移刻度 | 不插值相关峰，不改变帧头与分数 |
| 07单符号OFDM | 保留1056/1024点和全频带概览；增加CP边界64点、有效区前32点及选中bin附近32频点的茎状图 | 时间编号n/p与FFT bin分开；每个FFT点依赖1024点有效区 |
| 08CP复制关系 | 32对茎状采样比较I/Q、幅度和相位 | CP n=0..31对应尾部n=1024..1055；复相关计算保持原式 |
| CP相关、FIT相位、EVAL逐符号指标 | 观测值用散点；原拟合线保留；主值相位不跨±180°连接 | 不平滑EVM或额外估计相位 |
| 主线点数分类 | 保留整帧热力图，增加单符号候选得分柱形和逐符号K台阶 | 候选K直接来自保存记录；末端延长一格仅供显示，不增加分类 |

修改复用原图片文件名，主线27张和独立完整诊断15张的预计文件数量保持不变。新版PNG尚未完成生成和视觉检查。旧运行目录中的图片保持原样。

## 静态检查与身份核对

| 检查 | 本轮结果 |
|---|---|
| MathWorks独立 `mlint.exe` | 69个教学MATLAB文件，未发现语法错误；不启动MATLAB会话 |
| 检查器有效性 | 临时故意错误文件在含中文的路径下得到EOLPAR诊断，证明检查器确实读取并解析文件 |
| 风格/性能提示 | 保留AGROW、ALIGN、MSNU、CCAT1、ISCL、NOCOMMA、NASGU等提示；不是绘图运行通过 |
| 本轮未允许修改的既有MATLAB源码 | 79个SHA-256保持一致，含核心DSP、完整接收机与原评价器 |
| 原冻结文件与门限 | 64个身份一致 |
| 原始IQ | SHA-256保持 `c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3` |
| 既有完整接收检查点 | 22个源MAT文件SHA一致；表示源文件未变，不表示运行了新数值回归 |
| 本轮新增MATLAB自动测试 | `test_discrete_visualization.m`已编写，运行未完成 |

机器记录见 [discrete_visualization_validation.json](../provenance/discrete_visualization_validation.json)。没有修改数值门限、输入数据、同步估计、FFT归一化、信道均衡或符号判决。

## 中止的运行与用户选择

首轮测试启动时系统可用约2.26 GiB。监测器设置1.25 GiB保留内存、3 GiB测试进程树私有内存上限，在22.891秒时因 `stopped_host_memory_reserve` 终止本次测试进程树。系统最低可用约1.24 GiB；退出码124。用户原有MATLAB/浏览器会话未被关闭。

此次中止未完成绘图与单元测试，不能据此判断新图布局正确，也不能得出本轮“内存足够”或“不会卡死”的结论。后续按用户选择暂缓运行，未降低保护阈值强行继续。

## 后续MATLAB验证命令

释放足够内存后，在仓库根目录执行。`source`必须是含22个检查点的完整学习目录；可以使用既有MAT，不必重新接收信号。

```matlab
root = pwd;
addpath(fullfile(root,'matlab','learning_receiver'))
addpath(fullfile(root,'matlab','learning_receiver','tests'))
source = fullfile(root,'runs','codex-visual-learning-fresh'); % 换成你的完整目录
stamp = char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'));

% 新增测试：采样时间基准、CP位置和值、FFT行/bin和频率边缘、散点、类别图
out = fullfile(root,'runs',['discrete-check-' stamp]);
test_discrete_visualization(root, source, out);

% 原有可视化测试仍须执行，不用新增测试替代
oldOut = fullfile(root,'runs',['visual-regression-' stamp]);
test_visual_diagnostics(root, source, oldOut);

% 或单独生成本机报告
r = RUN_DIAGNOSTICS(source, 'Symbols', 50);
```

新增测试同时检查改动后的主线绘图分支，并验证完整报告仍为15个图文件、原BIN读取计数为0、源检查点哈希不变及最终EVAL EVM与保存验证一致。**这些是待执行的断言，不是已经得到的本轮测试结果。**

旧MAT可以只读重画；如果要执行新版完整教学接收机，须建立新学习目录，避免源码指纹不同却混用旧恢复目录。

## 主要文件

- `+slrx/+diag/sampleView.m`：统一时间窗内的原始/模型采样位置与原值。
- `+slrx/+viz/plotSampleWindow.m`：主线时域概览与局部采样。
- `+slrx/+viz/plotCardinality.m`：候选柱形和逐符号分类台阶。
- `+slrx/+viz/plotCapture.m`、`plotOFDM.m`、`plotCP.m`、`plotLocalSync.m`、`plotPilots.m`：更新现有视图。
- `+slrx/drawStep.m`：接入主线并将逐符号观测改为散点。
- `+slrx/+diag/chartCatalog.m`、`exportDiagnostics.m`：更新图像说明与采样元数据摘要。
- `tests/test_discrete_visualization.m`：新增显示数据契约测试。

以上路径相对于 `matlab/learning_receiver/`。读图说明已同步到[教学手册](VISUAL_DIAGNOSTICS.zh-CN.md)和[图像索引](VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)。
