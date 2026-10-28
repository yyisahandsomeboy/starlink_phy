# CFO与全流程观测量重构：实际验证记录

日期：2026-10-28。审计基线 `651e339e3aca325a13796d9a665b31858b684ac8`；MATLAB R2024b，Windows，物理内存约15.86 GiB。本轮修改已实际运行，不再沿用上一版“暂缓MATLAB验证”的状态；历史验证文件保留原样。

## 1. 修改范围及证据顺序

只修改教学编排、只读诊断、共享绘图、相应测试与阅读文档。`extractFrame`、重采样、同步、FFT、信道/均衡、ML算法、冻结评价器和阈值没有在本轮修改。旧的两处ML运算符修复已在基线之前提交，不能算作本轮新算法修复。

验证顺序：先完成合成/真实MAT绘图测试；完整新鲜接收暴露第12步纯数值更新缺少显式无图分支，修正后从头重跑；随后加入前后共同参考块/权重的显示改进，并通过全套绘图与原有回归；最终只改重采样标签和入口注释，再生成最终只读报告。最后这次没有重复DSP接收。

失败试验保留在 `runs/cfo-fresh-regression-20261028`，错误是绘图分发遗漏kind=12，不是接收数值错误。现有测试显式断言第12步不新增图。

## 2. 新鲜真实IQ接收与逐值回归

- 输入：`data/raw/exemplar250-257/exemplar250-257.bin`，50,000,000字节；SHA-256为 `c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3`。
- 默认4ms窗口：250 MSps的1,000,000个复采样，重采样为240 MSps的960,000点；两者N/Fs均为4ms。
- 完整重跑目录：`runs/cfo-fresh-regression-20261028-retry`。`resume=false`，没有从旧步骤恢复，完成全部22个MAT检查点。
- 对照 `runs/codex-visual-learning-fresh`：22个检查点的`data`结构全部`isequaln`完全一致，包括CFO/SFO、FFT、均衡、ML、条件判决和保护窗。比较的是数值结构，不声称含时间戳/代码指纹的整个新MAT文件字节一致。
- `slrx.validateRun`通过：原始IQ回读准确；独立检测起点raw一基125001；FFT与均衡相对重算误差均为0；最终留出导频EVM为0.21118250302583794，即21.1182503%。
- 数值证据：`runs/cfo-fresh-regression-20261028-retry/numerical_regression.json`及`learning_validation.json`。

## 3. CFO观测的真实数值与边界

统一使用 `t=(saved_positions-start)/Fs`、误差参数`theta=2*pi*f*t`、实际施加角`a=-theta`，因此`z_after=z_before*exp(1j*a)`。I/Q分量混合及模长不变用于解释运算，不能证明估计正确。

两轮实际CFO分别为-173068.240408436395 Hz、-171761.380155397608 Hz。全数组模长相对误差约1.91e-16，运算一致性相对误差约1.04e-13；负CFO对应施加角增加、向量逆时针旋转。

分别剔除PSS/SSS的32点CP，每结构16个64点块；PSS按128点重复结构分两族截距，SSS单独分析。前后使用共同块与共同权重，不跨结构展开相位。以下Hz均为**受信道/展开假设限制的相位斜率代理**：

| 轮次/参考 | 补偿前Hz | 补偿后Hz | 去趋势相位RMS/rad | 归一化相关幅度 |
|---|---:|---:|---|---|
| 1 / PSS | -173171.619966 | -66.637696 | 0.022990→0.022581 | 0.301594→0.973767 |
| 1 / SSS | -172569.626274 | 534.760086 | 0.024601→0.024811 | 0.287777→0.971624 |
| 2 / PSS | -173171.777030 | -1373.937042 | 0.022988→0.022582 | 0.301603→0.973733 |
| 2 / SSS | -172570.578087 | -773.521282 | 0.024535→0.024742 | 0.287794→0.971706 |

这些序列参与原CFO估计，相关增强或斜率减小不是独立证据。第二轮同步参考的代理并未比第一轮更接近0，SSS去趋势RMS也略增加；原样保留，不为图像改变CFO。后续EVAL支持已知留出资源的质量检查，但不能将FFT/均衡/跟踪各阶段之差解释为“仅CFO”的因果效果。比如第二轮均衡EVAL约21.0972%、跟踪约21.1183%，本次没有美化这个略微恶化。

## 4. 已实际执行的测试

| 测试 | 实际结果与覆盖 |
|---|---|
| `test_observability` | 通过；正/负CFO、23.7ppm SFO、非整数起点123.375、I/Q公式、模长/运算一致性、PSS/SSS不同截距、边界、共同有效块、零信号拒绝代理、轮次选择、主线22图、报告17图及显式debug3图 |
| `test_visual_diagnostics` | 通过；原诊断数值、坐标、部分MAT降级、源MAT不变等断言保留；随新默认输入图更新图形断言 |
| `test_discrete_visualization` | 通过；离散采样/坐标、CP对应关系与交互等；仅适配已合并的主线入口 |
| `test_author_receiver_dsp` / `test_frame_guard_metrics` | 通过；原DSP测试及7个保护窗测试 |
| `test_ofdm_view_data` / `test_payload_hard_decision` | 通过；原OFDM资源和条件判决测试，不等于真实业务BER |
| `test_author_payload_artifacts` / `test_payload_artifacts` | 通过；只读原历史结果，原硬判决/资源文件一致性 |
| `validate_learning_modules` | 通过；300列几何标签全部一致，插值/H/似然/候选得分差为0；FFT相对差约9.81e-17，跟踪网格相对差约6.09e-16 |
| `evaluate_receiver` | 历史9帧数组重新评分通过；9帧accepted，7个标注匹配、2个候选无标注；没有新跑9帧DSP |
| MATLAB独立`mlint` | 79个学习版.m文件通过语法检查；保留AGROW/ALIGN等风格或性能提示，没有将提示等同语法错误 |
| 最终标签/报告重画 | 通过；修正FIR两条Nyquist标签拥挤及微量DC单位字形；最终报告17图、BIN读取0、源MAT哈希未变 |

总体机器证据：`runs/cfo-existing-tests-20261028/existing_tests.json`。最终观测量测试：`runs/cfo-existing-tests-20261028/observability_final/observability_tests.json`。最终页面：`runs/cfo-teaching-final-20261028/report/index.html`。完整主线22张图见`runs/cfo-fresh-regression-20261028-retry/figures`；最新重采样标签示例另见`runs/cfo-teaching-final-20261028/main_resampling/figures`。

原历史九帧结果、完整载荷工件和`payload_analysis_v1.json`是本机已有/恢复的历史测试夹具，不随本次提交上传。新克隆若缺夹具，可先执行新观测量测试与一帧回归；不能把缺夹具的旧测试宣称通过。

## 5. 内存、文件与图像检查

MATLAB独立测试进程置于Windows Job中，0.25秒采样。低于1.25 GiB可用内存或任务私有内存超过3.5 GiB时保护停止。只管理自己启动的进程，没有关闭用户MATLAB、VMware或浏览器。GiB均按2^30字节计算。

| 测试目录（本地memory_audit下） | 状态 | 秒 | 进程树峰值私有/GiB | 系统最低可用/GiB |
|---|---|---:|---:|---:|
| `cfo_observability_20261028` | passed | 84.06 | 2.458 | 2.717 |
| `cfo_fresh_regression_20261028` | failed | 141.55 | 2.191 | 3.108 |
| `cfo_fresh_regression_20261028_retry` | passed | 308.83 | 2.445 | 3.005 |
| `cfo_existing_tests_20261028` | passed | 270.20 | 2.912 | 2.889 |
| `cfo_final_report_20261028` | passed | 56.75 | 2.318 | 3.385 |

本轮成功运行未触发内存保护；这不是任意多帧或长期会话都不会卡顿的保证。本次没有改变DSP内存策略，也未将显示抽取传回接收数组。

受保护的64个配置/算法/参考等文件逐个SHA-256复核；原始BIN不变；原22个历史MAT及本轮新鲜22个MAT在只读绘图后哈希不变。本地`.gitattributes`和历史夹具配置保持原状、不加入提交。PNG数据块CRC、解压、尺寸、HTML本地链接及Markdown相对链接另做自动检查，CFO、重采样、输入质量、信道与跟踪图已人工查看。

机器记录见[observability_validation.json](../provenance/observability_validation.json)。大型运行MAT、PNG和内存CSV留在本地runs/memory_audit，不提交到GitHub。

## 6. 运行入口与仍未验证的事项

在仓库根目录的MATLAB中：

```matlab
addpath('matlab/learning_receiver')
open('matlab/learning_receiver/START_HERE.m') % 按节执行
% 重新接收时使用新run_dir；不要在旧代码指纹的目录resume。
r = RUN_DIAGNOSTICS('runs/cfo-fresh-regression-20261028-retry');
r = RUN_DIAGNOSTICS('runs/cfo-fresh-regression-20261028-retry', ...
    'CFORound', 1, 'ShowFigures', true); % CFO图内也可选轮次
% 只有需要旧密集图时才设 'DebugPlots', true。
```

复现新观测量断言（输出目录须不存在）：

```matlab
root = pwd;
addpath('matlab/learning_receiver/tests')
test_observability(root, fullfile(root,'runs','cfo-fresh-regression-20261028-retry'), ...
    fullfile(root,'runs','my-observability-test'));
```

本次没有新做完整九帧DSP接收、没有仅开关CFO且其他条件相同的EVM/ICI实验、没有独立频偏真值或误差置信区间。有限同步窗口不足以补造全局旁瓣比或检测概率。业务比特、商业MCS、FEC、CRC、BER/SER仍未验证。

删除/合并的默认图及全函数审查见[审计表](OBSERVABILITY_AUDIT.zh-CN.md)；新增观测量的数学条件见[CFO教学说明](CFO_TEACHING.zh-CN.md)；逐图用途见[图像索引](VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)。

## 7. 本轮文件清单

- [`README.md`](../README.md)
- [`docs/CFO_TEACHING.zh-CN.md`](../docs/CFO_TEACHING.zh-CN.md)
- [`docs/OBSERVABILITY_AUDIT.zh-CN.md`](../docs/OBSERVABILITY_AUDIT.zh-CN.md)
- [`docs/OBSERVABILITY_VALIDATION.zh-CN.md`](../docs/OBSERVABILITY_VALIDATION.zh-CN.md)
- [`docs/VISUAL_DIAGNOSTICS.zh-CN.md`](../docs/VISUAL_DIAGNOSTICS.zh-CN.md)
- [`docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md`](../docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)
- [`matlab/learning_receiver/+slrx/+diag/cfoMetrics.m`](../matlab/learning_receiver/+slrx/+diag/cfoMetrics.m)
- [`matlab/learning_receiver/+slrx/+diag/chartCatalog.m`](../matlab/learning_receiver/+slrx/+diag/chartCatalog.m)
- [`matlab/learning_receiver/+slrx/+diag/exportDiagnostics.m`](../matlab/learning_receiver/+slrx/+diag/exportDiagnostics.m)
- [`matlab/learning_receiver/+slrx/+diag/plotContract.m`](../matlab/learning_receiver/+slrx/+diag/plotContract.m)
- [`matlab/learning_receiver/+slrx/+diag/plotOptions.m`](../matlab/learning_receiver/+slrx/+diag/plotOptions.m)
- [`matlab/learning_receiver/+slrx/+diag/resampleMetrics.m`](../matlab/learning_receiver/+slrx/+diag/resampleMetrics.m)
- [`matlab/learning_receiver/+slrx/+diag/stepFigures.m`](../matlab/learning_receiver/+slrx/+diag/stepFigures.m)
- [`matlab/learning_receiver/+slrx/+diag/writeReport.m`](../matlab/learning_receiver/+slrx/+diag/writeReport.m)
- [`matlab/learning_receiver/+slrx/+viz/debugPlots.m`](../matlab/learning_receiver/+slrx/+viz/debugPlots.m)
- [`matlab/learning_receiver/+slrx/+viz/plotCFO.m`](../matlab/learning_receiver/+slrx/+viz/plotCFO.m)
- [`matlab/learning_receiver/+slrx/+viz/plotCapture.m`](../matlab/learning_receiver/+slrx/+viz/plotCapture.m)
- [`matlab/learning_receiver/+slrx/+viz/plotChannel.m`](../matlab/learning_receiver/+slrx/+viz/plotChannel.m)
- [`matlab/learning_receiver/+slrx/+viz/plotFFTGrid.m`](../matlab/learning_receiver/+slrx/+viz/plotFFTGrid.m)
- [`matlab/learning_receiver/+slrx/+viz/plotPilotFit.m`](../matlab/learning_receiver/+slrx/+viz/plotPilotFit.m)
- [`matlab/learning_receiver/+slrx/+viz/plotResampling.m`](../matlab/learning_receiver/+slrx/+viz/plotResampling.m)
- [`matlab/learning_receiver/+slrx/+viz/plotTracking.m`](../matlab/learning_receiver/+slrx/+viz/plotTracking.m)
- [`matlab/learning_receiver/+slrx/+viz/teachingNotes.m`](../matlab/learning_receiver/+slrx/+viz/teachingNotes.m)
- [`matlab/learning_receiver/+slrx/beginLesson.m`](../matlab/learning_receiver/+slrx/beginLesson.m)
- [`matlab/learning_receiver/+slrx/defaultConfig.m`](../matlab/learning_receiver/+slrx/defaultConfig.m)
- [`matlab/learning_receiver/+slrx/drawStep.m`](../matlab/learning_receiver/+slrx/drawStep.m)
- [`matlab/learning_receiver/+slrx/step.m`](../matlab/learning_receiver/+slrx/step.m)
- [`matlab/learning_receiver/README.zh-CN.md`](../matlab/learning_receiver/README.zh-CN.md)
- [`matlab/learning_receiver/RUN_DIAGNOSTICS.m`](../matlab/learning_receiver/RUN_DIAGNOSTICS.m)
- [`matlab/learning_receiver/START_HERE.m`](../matlab/learning_receiver/START_HERE.m)
- [`matlab/learning_receiver/tests/test_discrete_visualization.m`](../matlab/learning_receiver/tests/test_discrete_visualization.m)
- [`matlab/learning_receiver/tests/test_observability.m`](../matlab/learning_receiver/tests/test_observability.m)
- [`matlab/learning_receiver/tests/test_visual_diagnostics.m`](../matlab/learning_receiver/tests/test_visual_diagnostics.m)
- [`provenance/observability_validation.json`](../provenance/observability_validation.json)
