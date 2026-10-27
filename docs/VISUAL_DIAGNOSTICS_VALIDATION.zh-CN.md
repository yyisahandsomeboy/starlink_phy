# 教学诊断本机验证报告（2026-10-27）

## 结果与运行范围

本文记录本机实际验证。教学代码已发布在提交 `00eaa4b`；本地 `runs/`、`memory_audit/` 及图片是实验产物，不随文档上传。文中的运行路径用于辨认本机记录，新克隆需先准备资源并运行代码生成自己的报告。机器记录中的路径已规范为仓库相对路径或明确的本地占位符，测量值与测试结论保持原样。

数值基线是 `55082bc` 加上此前已验证的两处教学代码逐元素运算修复；`00eaa4b` 同时收录了这两处修复和诊断功能。

已在 Windows MATLAB R2024b 实际运行，不借用历史报告冒充本轮测试。真实 IQ 来自已核验的 exemplar250-257；原始 BIN SHA 和 64 个受保护文件全部保持本任务起点的值，详见 [机器记录](../provenance/visual_diagnostics_validation.json)。

新鲜完整单帧从 BIN 开始执行第 1..14 节（包含 13a..13h 与 15_guard，共 22 个 MAT），`resume=false`，每步 `data` 结构与修改前完整参考 `isequaln=true`。最终 EVAL 导频 EVM 为 0.211182503025838。FFT 与均衡独立重算相对误差为 0。没有修改核心 DSP 数学、冻结评价器、IQ、真值、评价门限。

单帧目录：`runs/codex-visual-learning-fresh`。新跑的另一真实帧目录：`runs/codex-visual-learning-second-frame-50ms`，只执行到第 8 步，前端检查通过，不声称做了最终跟踪。

多帧报告：`runs/visual-diagnostics-multi-frame/index.html`。完整单帧教学报告：`runs/visual-diagnostics-multi-frame/frame_01/index.html`。两帧原文件起点分别为 [125001, 1791671.8333333333]；比较阶段索引为 2（第一轮均衡），资源一一配对=True。没有把第一帧的最终跟踪和第二帧的首次均衡混为同阶段。

## 原有与新增测试

| 检查 | 本轮实际结果 |
|---|---|
| MATLAB 语法 | 65 个学习版 MATLAB 文件；PARSE 错误 0；风格/性能提示保留在运行 JSON |
| test_author_receiver_dsp | 通过：似然梯度/Hessian、ML、导频尺度、点数模型、信道 |
| test_frame_guard_metrics | 原 7 个坐标/窗口用例通过 |
| test_ofdm_view_data | 通过：留出行、频率、原始载荷与固定符号选择 |
| test_payload_hard_decision | 通过：候选点、擦除、索引与后验规则 |
| test_author_payload_artifacts | 原合成 fixture 通过；不冒称业务真值 |
| test_payload_artifacts | 对原真实首帧重新导出并核对 301200 个资源、1500 个区域记录通过 |
| validate_learning_modules | 通过；300 个几何标签一致；跟踪网格相对误差 6.09e-16 |
| 冻结 evaluate_receiver | 本轮对历史 9 帧 `result.mat` 重新评分通过；不是本轮新跑 9 帧接收 |
| test_visual_diagnostics | 通过：非零窗口、小数坐标、局部零点、同资源、显示因子、原 IQ 标注、合成 CFO/QPSK/CP、bin/MHz、EVAL 隔离、点区间溯源、原生 UI 回调、缺失步骤提示 |
| 新鲜单帧回归 | 22 个步骤 `data` 结构逐值完全相同 |
| 多帧展示 | 两个不同真实帧；只比较共有同阶段、同行同列；缺失第二轮照实提示 |
| 报告文件 | PNG CRC/尺寸、本地 HTML 链接和图片路径检查通过；桌面与窄窗口截图检查 |

`config/payload_analysis_v1.json` 在源码克隆中缺失，导致两个原导出测试最初无法运行。从原真实接收运行的 `receiver-code/config/` 源码快照按字节恢复后，两项复测通过。源文件 SHA=8cdf356c7a5428779b5cbce31b8e0f62237e40de84e8bcd20cc97377dee75c58；这不是新编配置，也未更改冻结门限。

首次新鲜 DSP 运行已经完成并通过学习检查，但其外部回归脚本的结构体初始化报错；随后独立函数回读新旧 22 个 MAT 全部通过。失败日志保留。6ms 窗口没有足够的第二个 SSS 合格帧，因此保留原门限，使用已有 50ms 数据窗口完成第二帧前端。未将这些失败尝试抹成成功。

## 当前真实数据说明什么

以下是同一完整帧全部 300 个数据符号的 EVAL 导频，FFT 仅通过 SSS 做整体复标量诊断标定；EVAL 不参与拟合。

| 轮次 | 阶段 | SSS 约定 EVM / % |
|---|---|---:|
| 1 | FFT | 140.296809 |
| 1 | 均衡 | 147.887633 |
| 1 | 跟踪 | 21.058672 |
| 2 | FFT | 33.489067 |
| 2 | 均衡 | 21.097201 |
| 2 | 跟踪 | 21.118250 |

第二轮跟踪相对第二轮均衡略高，报告保留这一事实。不能声称每个环节必然单调改善，也不能把 EVM 当业务 BER/SER。

## 内存与读取

单位 GiB；峰值为本次拥有的 MATLAB 子进程树私有内存，最低可用为全系统物理内存。采样间隔 0.25s。用户原来已打开的 MATLAB/VMware 会话保留。

| 检查 | 监控状态 | 峰值私有 GiB | 系统最低可用 GiB |
|---|---|---:|---:|
| fresh_DSP | failed | 2.36 | 2.98 |
| regression_and_export | passed | 2.20 | 3.21 |
| final_tests | passed | 2.50 | 3.00 |
| release_tests | passed | 2.47 | 2.72 |
| historical_frozen_rescore | passed | 2.15 | 3.15 |
| second_frame_and_multi_export | passed | 2.73 | 2.34 |

`fresh_DSP` 的进程退出失败来自完成 DSP 后的外部回归脚本，接收检查已通过；`regression_and_export` 独立完成逐值核对。其余已通过的运行没有触发内存保护停止。为避免误解，这里保留原始监控状态，不把脚本退出码改写成接收成功。

只读诊断每帧每个检查点加载一次，完整帧 22 个 MAT；原 BIN 读取次数为 0，前后源 MAT SHA 一致。新鲜 DSP 和独立读取验证本身会读取 BIN，两者与绘图器的读取计数严格分开。没有更换数据精度、删网格或调整核心读窗来做内存优化。

## 图形与元数据改动

旧学习版 27 张图片仍保留主流程，替换第 3 步的两张局部图为全局/局部两种视图；修正原均衡图载荷行读取为 refs 映射。独立完整报告另生成 15 类图，多帧另有 2 张对照图。旧图清单与字段缺口见 [审计](VISUAL_DIAGNOSTICS_AUDIT.zh-CN.md)，读图解释见 [教学手册](VISUAL_DIAGNOSTICS.zh-CN.md)。

新增字段包括坐标/候选状态、采样整数与小数说明、源 MAT 哈希、可用/缺失步骤、各阶段 RMS/显示除数、同资源行列、SSS 复标定除数、原/标定 EVM、逐符号 EVM、误差/相位、CP 复相关、SFO 漂移、Y/H 残差、噪声增益代理、FFT 有效区原文件区间及依赖限制。复数 JSON 同时保存实部和虚部。

## 复现命令

```matlab
% 接收：当前目录为仓库根，按节继续保持原入口
open('matlab/learning_receiver/START_HERE.m')

% 独立诊断，不运行 DSP；输出路径须是新目录
addpath('matlab/learning_receiver')
r = RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 50);
h = BROWSE_DIAGNOSTICS(lesson_cfg.run_dir);

% 新诊断测试，需要一个已有完整学习目录；out 取尚不存在的新路径
addpath('matlab/learning_receiver/tests')
test_visual_diagnostics(pwd, lesson_cfg.run_dir, fullfile(pwd,'runs','visual-test-new'));
```

原学习模块对照还需要 `runs/codex-author-real-20261014-170603-942987` 的原始真实帧 fixture。本机通过只读目录映射访问共享原工程，未复制历史结果当成新接收。原冻结评价器只读已有结果和 IQ，输出写进 `runs/visual-diagnostics-frozen-rescore`。原始测试调用及监控日志位于旁边的 `memory_audit/visual_diagnostics_*`。

## 完成范围与限制

P0/P1 已实现；P2 已实现原生帧/符号/频段/阶段/归一化选择器、全局/FFT 坐标切换、资源数据光标和本地 HTML。UI 通过自动调用真实控件回调核验，未宣称人工点选覆盖所有图形后端。

未重新运行完整九帧 DSP；本轮是一帧完整新跑、另一帧前端新跑、历史九帧重评分。缺少完整粗峰尝试日志不能补造；FFT 点不能归于唯一 ADC 点。业务 MCS/比特/FEC/CRC/BER/SER 仍无真值。

## 本任务文件清单

以下是本机任务改动的历史清单，不等同于GitHub提交范围。代码提交 `00eaa4b` 只包含39个教学MATLAB源码/测试文件（包含两处旧修复）；本次文档提交补充README、教学文档与机器记录。`config/payload_analysis_v1.json` 和 `.gitattributes` 仍为本地文件，未上传。两行旧修复包含在本轮数值基线中。机器记录中的 `changed_files` 为原验证时的文件SHA，不因后续文档编辑而回填。

- `config/payload_analysis_v1.json`
- `docs/VISUAL_DIAGNOSTICS.zh-CN.md`
- `docs/VISUAL_DIAGNOSTICS_AUDIT.zh-CN.md`
- `matlab/learning_receiver/+slrx/+diag/chartCatalog.m`
- `matlab/learning_receiver/+slrx/+diag/constellationData.m`
- `matlab/learning_receiver/+slrx/+diag/coordinates.m`
- `matlab/learning_receiver/+slrx/+diag/exportDiagnostics.m`
- `matlab/learning_receiver/+slrx/+diag/loadLesson.m`
- `matlab/learning_receiver/+slrx/+diag/pilotMetrics.m`
- `matlab/learning_receiver/+slrx/+diag/stepFigures.m`
- `matlab/learning_receiver/+slrx/+diag/stepInfo.m`
- `matlab/learning_receiver/+slrx/+diag/summarizeStep.m`
- `matlab/learning_receiver/+slrx/+diag/syncSummary.m`
- `matlab/learning_receiver/+slrx/+diag/tracePoint.m`
- `matlab/learning_receiver/+slrx/+diag/writeJSON.m`
- `matlab/learning_receiver/+slrx/+diag/writeReport.m`
- `matlab/learning_receiver/+slrx/+viz/exploreRun.m`
- `matlab/learning_receiver/+slrx/+viz/newFigure.m`
- `matlab/learning_receiver/+slrx/+viz/plotCapture.m`
- `matlab/learning_receiver/+slrx/+viz/plotCFO.m`
- `matlab/learning_receiver/+slrx/+viz/plotChannel.m`
- `matlab/learning_receiver/+slrx/+viz/plotConditionalModels.m`
- `matlab/learning_receiver/+slrx/+viz/plotConstellationStages.m`
- `matlab/learning_receiver/+slrx/+viz/plotCP.m`
- `matlab/learning_receiver/+slrx/+viz/plotFFTGrid.m`
- `matlab/learning_receiver/+slrx/+viz/plotFrameComparison.m`
- `matlab/learning_receiver/+slrx/+viz/plotGlobalSync.m`
- `matlab/learning_receiver/+slrx/+viz/plotGuard.m`
- `matlab/learning_receiver/+slrx/+viz/plotLocalSync.m`
- `matlab/learning_receiver/+slrx/+viz/plotOFDM.m`
- `matlab/learning_receiver/+slrx/+viz/plotPilots.m`
- `matlab/learning_receiver/+slrx/+viz/plotSFO.m`
- `matlab/learning_receiver/+slrx/+viz/saveFigure.m`
- `matlab/learning_receiver/+slrx/beginLesson.m`
- `matlab/learning_receiver/+slrx/defaultConfig.m`
- `matlab/learning_receiver/+slrx/drawStep.m`
- `matlab/learning_receiver/+slrx/step.m`
- `matlab/learning_receiver/BROWSE_DIAGNOSTICS.m`
- `matlab/learning_receiver/README.zh-CN.md`
- `matlab/learning_receiver/RUN_DIAGNOSTICS.m`
- `matlab/learning_receiver/tests/test_visual_diagnostics.m`
- `README.md`

- 本验证文档与 `provenance/visual_diagnostics_validation.json`。
