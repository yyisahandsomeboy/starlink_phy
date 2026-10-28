# Starlink PHY：Codex 接收机与分步学习版

本仓库保存两套原生 MATLAB 接收入口：**完整真实 IQ 接收机**与**模块化学习接收机**。DSP 源码来自同一工程提交 `f081bab`，逐文件来源与 SHA-256 见 [source_manifest.json](provenance/source_manifest.json)。

| 目的 | 先看哪里 | 运行方式 |
|---|---|---|
| 学习接收顺序、逐步查看变量 | [学习版 README](matlab/learning_receiver/README.zh-CN.md) | 打开 `START_HERE.m`，按 Ctrl+Enter 逐节执行 |
| 阅读完整多帧接收实现 | [完整接收机 README](matlab/baseline/README.zh-CN.md) | `author_receiver(cfg)` 或完整资源准备后的 `scripts/run_baseline real` |
| 原理、公式、维度与保存位置 | [逐步学习手册](docs/LEARNING_RECEIVER.zh-CN.md) | 配合每节的 MATLAB 函数阅读 |
| 按图学习同步、OFDM、均衡与星座 | [图像阅读索引](docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md) | 先了解每张图的作用，再运行诊断报告 |
| 公开方法如何落实到原接收机 | [原算法与中间变量说明](docs/AUTHOR_RECEIVER.zh-CN.md) | 部分历史运行链接属于原工程，不随源码上传 |

建议**先学一帧，再用同一套模块检查多帧**。一帧已有 PSS、SSS 与300个数据 OFDM 符号；多帧进一步检查帧间变化和稳定性。

历史注释版本 `55082bc`：原有32个学习版MATLAB文件加入逐行中文解释，语法检查通过；该版本当时的批处理启动超时记录见[注释版本检查](provenance/learning_comments_validation.json)。后续教学诊断代码 `00eaa4b` 已在 Windows MATLAB R2024b 完成真实单帧复跑，22个步骤与修复后的参考逐值一致，详见[教学诊断验证报告](docs/VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)。

## 1. 文件树

```text
matlab/baseline/           完整接收机、DSP、同步参考接口、保护间隔与数值检查
matlab/learning_receiver/  按节执行的学习入口、单步模块、底层算法与说明
matlab/visualization/      网格诊断、按列星座、条件硬判决和导出
matlab/evaluation/         原独立评价器；规则和文件身份保持不变
config/                   接收参数、评价门限及原始32文件锁
scripts/                  原命令行入口、资源准备脚本
tools/                    原MATLAB子进程运行、诊断和HTML导出支撑
docs/、notes/             算法学习说明、公式与资料索引
reports/                  既有验证的文字/数值摘要，不含运行数组或图片
provenance/               代码来源、资源URL和固定SHA、出版核验记录
```

这个仓库只交付所需源码和文档。原始 IQ、作者参考 MAT、历史运行数组、图片、DSH/在线模型环境、协议头后续研究和凭据不在 Git 中。作者序列由下面的资源脚本下载到被忽略的 `vendor/`，不会把第三方参考实现冒称为 Codex 编写。

## 2. 环境与输入

- 原完整接收机验证环境为原生 Linux MATLAB **R2025a**；教学诊断版本另在 Windows MATLAB **R2024b** 实际复跑，范围见验证报告。
- 当前实现使用 Signal Processing Toolbox（`resample/pwelch/sgolayfilt`）与 Statistics and Machine Learning Toolbox（`kmeans`）；它们不是仓库自带依赖。
- Python 3.10+；本文入口只使用Python标准库。Python负责文件/进程，DSP由MATLAB执行。
- 输入 `data/raw/exemplar250-257/exemplar250-257.bin`：250Msps、小端交织int16 I/Q、50ms、12,500,000份复采样。两个int16才是一份复采样。

原BIN SHA-256：`c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3`。

## 3. 准备外部资源

先进入克隆后的仓库根目录。此虚拟机已有完整原工程，推荐直接复用并核验：

```bash
python3 scripts/prepare_receiver_resources --from-workspace /home/a/Desktop/start_link_demo
python3 scripts/prepare_receiver_resources --check-only
```

脚本只复制到这个克隆目录，不改原工程；已有文件必须与固定SHA相同才会继续。它也复用原Python启动器要求的历史冻结fixture，**不运行合成实验**。

没有原工程的新机器，可以下载公开参考和约40.7MB的IQ ZIP：

```bash
python3 scripts/prepare_receiver_resources
```

每个文件核验SHA，下载内容不符时停止，不覆盖原件，不下载约5GB的作者解调矩阵。

**注意两种资源范围：**公开资源足够运行下面的原生MATLAB入口。原Python入口保留旧32文件完整性检查，其中还包括本工程早期生成的合成fixture；这些不是公开下载数据，也不是当前真实接收算法的输入。只下载公开资源时，脚本如实列出 `legacy_missing`，请使用MATLAB入口；若需要原Python入口，必须从原工程导入完整冻结资源。这里没有删除旧锁、修改门限或伪造fixture。

## 4. 先跑学习版

**2026-10-28观测量重构：CFO改为复数旋转、实际时间轴与分结构参考诊断；默认主线22张、独立报告17张。** 采样点、CP和局部FFT改用茎状图，逐符号观测用散点，保留概览和拟合线。旧版暂缓记录保留；现行测试范围与结果见[本轮验证](docs/OBSERVABILITY_VALIDATION.zh-CN.md)，读图原理见[CFO教学](docs/CFO_TEACHING.zh-CN.md)。

新增教学诊断入口：接收后运行 `RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 50)` 生成本地中文HTML、17类诊断图及资源追溯表；`BROWSE_DIAGNOSTICS(lesson_cfg.run_dir)` 打开 MATLAB 原生选择器。两轮分别比较同一符号的 FFT、均衡和跟踪，不额外修饰接收点。完整坐标、公式、每幅图的读法及运行示例见 [教学诊断手册](docs/VISUAL_DIAGNOSTICS.zh-CN.md)，本次实际复跑与旧测试见 [验证报告](docs/VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)。

在MATLAB中将当前目录切换到仓库根目录：

```matlab
open('matlab/learning_receiver/START_HERE.m')
```

从第0节开始按 **Ctrl+Enter**，第一次建议只执行到第8节“均衡”。工作区会依次出现 `capture → sampled → synchronization → frameTime → ofdmTime → frequencyGrid → channel → equalized`。

后续是导频初值、点数识别、ML跟踪、CFO/SFO更新、第二轮取样与处理、条件符号判决。每节的原理、输入输出和保存字段见[学习手册](docs/LEARNING_RECEIVER.zh-CN.md)。

默认读开头4ms、独立捕获一个完整合格帧，不把作者TOA当帧头输入。每步在 `runs/codex-learning-时间/` 保存一个MAT（入口变量 `data`）、JSON摘要和 `figures/` 图片。`lesson_cfg.run_dir`给出实际路径。

完整冻结资源导入后，终端也能分步执行：

```bash
scripts/run_learning_receiver --through 8
scripts/run_learning_receiver --resume codex-learning-实际目录名 --through 14
```

终端入口额外生成 `learning_report.html`。改变代码/DSP配置应建立新运行，已有运行按固定代码和参数回读。

## 5. 运行完整多帧接收机

完整冻结资源导入后：

```bash
scripts/run_baseline real --workers 1 --timeout 3000
scripts/plot_ofdm
scripts/analyze_payload --all-frames
```

全50ms、两轮逐列识别与跟踪可能需要约40～50分钟；学习前8步短得多。只准备公开资源时，使用[完整接收机README](matlab/baseline/README.zh-CN.md)的原生MATLAB调用，不经过历史fixture检查。

## 6. 结果与边界

既有学习版验证：最终网格1024×301（第1列SSS），条件判决1004×300；留出导频EVM约0.211；同输入模块与原实现对照的网格相对差异约6.09e−16。[验证说明](reports/learning_receiver_report.md)、[数值摘要](reports/learning_receiver_validation.json)记录的是原工程已完成实验；其历史MAT/PNG不随本源码仓库上传。

完整接收机默认50ms及跨帧SSS共享信道；学习版默认4ms、每帧独立估计H。因此两个不同配置的端到端结果不应要求逐值相同。

终点是同步/均衡后的复数网格和**条件星座符号判决**。每列一种几何仍是当前模型假设。真实MCS/资源映射、业务位标签、商业扰码状态、码块边界、FEC及CRC没有因此被确证；几何点编号不等于业务比特。
