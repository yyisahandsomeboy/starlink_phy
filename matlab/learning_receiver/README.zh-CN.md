> GitHub源码版：`/path/to/starlink_phy`请换成你的克隆目录。历史 `runs/` 与图片不随仓库上传；资源准备及两种启动方式见[仓库README](../../README.md)。

# 从这里学习 Codex 接收机

**先学一帧，再用相同模块检查多帧。** 一帧已经包含同步、信道、300个数据OFDM符号和残余跟踪，足够走完整条接收链。多帧主要用于检查稳定性、帧间变化和漏检情况，不宜一开始就把这些问题混在一起。

本目录是可独立执行的学习版，标记为 `codex_baseline`。算法从原接收机拆解、展开并进行同输入数值对照；不是把旧整机函数改个名字再调用。原接收机、旧实验和原始IQ保留。

原有32个学习版MATLAB文件采用逐行中文注释：每行旁说明操作的目的，首次用到的矩阵索引、转置、逐元素运算、函数句柄等语法也就地解释。多条命令已拆成独立行，统一4空格缩进；长调用分行显示。不需要另读MATLAB语法教程才能开始。

阅读时先打开 `START_HERE.m`，运行一节后，只打开该节注释标出的实际算法函数。例如第1节接着看 `+slrx/readIQ.m`，第2节看 `+slrx/resampleCapture.m`。保存、画图和底层优化文件可以等主线走到它们时再看，不需要一次读完所有文件。

## 1. 在 MATLAB 中按节运行

**2026-10-28观测量重构：CFO改为复数旋转、实际时间轴与分结构参考诊断；默认主线22张、独立报告17张。** 采样点、CP和局部FFT改用茎状图，逐符号观测用散点，保留概览和拟合线。旧版暂缓记录保留；现行测试范围与结果见[本轮验证](../../docs/OBSERVABILITY_VALIDATION.zh-CN.md)，读图原理见[CFO教学](../../docs/CFO_TEACHING.zh-CN.md)。

新增教学诊断入口：接收后运行 `RUN_DIAGNOSTICS(lesson_cfg.run_dir, 'Symbols', 50)` 生成本地中文HTML、17类诊断图及资源追溯表；`BROWSE_DIAGNOSTICS(lesson_cfg.run_dir)` 打开 MATLAB 原生选择器。两轮分别比较同一符号的 FFT、均衡和跟踪，不额外修饰接收点。完整坐标、公式、每幅图的读法及运行示例见 [教学诊断手册](../../docs/VISUAL_DIAGNOSTICS.zh-CN.md)，本次实际复跑与旧测试见 [验证报告](../../docs/VISUAL_DIAGNOSTICS_VALIDATION.zh-CN.md)。

打开 `START_HERE.m`。从第0节开始，把光标放进一节，按 **Ctrl+Enter** 执行当前节，再看 Workspace 和新图。不要第一次就按 Run 跑整份文件。

```matlab
cd('/path/to/starlink_phy')
open('matlab/learning_receiver/START_HERE.m')
```

每节的具名变量留在当前工作区。例如运行第6节后：

```matlab
size(frequencyGrid.values)          % 1024 × 301
frequencyGrid.values(:,1)           % SSS的频域列
frequencyGrid.values(:,51)          % 第50个数据OFDM符号
lesson_cfg.run_dir                 % 这次学习的保存目录
```

建议第一次只运行第0～8节。看清楚输入采样、帧起点、去CP矩阵、FFT网格和信道响应，再进行9～14节。第10、11节需要处理整帧300列，运行时会报告进度，明显比单次FFT耗时。

## 2. 在终端分阶段运行

```bash
cd /path/to/starlink_phy
scripts/run_learning_receiver --through 8
```

终端会给出新的 `codex-learning-时间`。继续同一实验时，把下列占位符换成实际目录名：

```bash
scripts/run_learning_receiver --resume codex-learning-实际时间 --through 14
```

`--through 1` 表示只读IQ；`--through 6` 表示跑到FFT；默认是8。`--through 13` 包含第二轮13a～13h，14再作符号判决和保护间隔观察。已有MAT直接回读，后续步骤实际计算。改变算法、输入窗口或DSP参数，应建立新目录；不会把新算法输出混入旧缓存。

MATLAB源码变化会改变源码SHA。以前的运行仍可直接加载MAT或使用 `RUN_DIAGNOSTICS` 查看；执行新版接收代码时应建立新学习目录。各类图的作用和推荐顺序见[图像阅读索引](../../docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)。

输出目录含 `learning_report.html`，用浏览器直接打开；图片是同目录 `figures/` 中的本地PNG。`reports/learning_receiver_latest.json` 指向最近一次终端运行，`reports/learning_receiver_full.json` 指向最近一次完整运行。

## 3. 只看三层

```text
START_HERE.m                  第1层：处理顺序；学习时先看它
+slrx/readIQ.m 等             第2层：一个模块完成一个明确步骤
+slrx/+alg/                   第3层：相关搜索、聚类、ML等算法细节
```

`step.m`、`beginLesson.m`、`drawStep.m`、`sha256.m` 属于保存/画图辅助；初学不必先读。Python只负责启动本机MATLAB和生成HTML，不执行接收DSP。

## 4. 数据在哪里

默认输入 `data/raw/exemplar250-257/exemplar250-257.bin` 的开头4ms；这只是查找窗口，不是已知帧边界。接收机独立搜索帧头，不用作者标注位置。

每步固定保存三个入口：

```text
runs/codex-learning-时间/
  01_capture.mat、01_capture.json
  02_resampled.mat、02_resampled.json
  ...
  13a_frame_time.mat ... 13h_tracking.mat
  14_decisions.mat、15_guard.mat
  figures/                    每项物理量的图片
  source_code/                当次学习代码快照
  lesson_config.json          参数和路径
  lesson_lock.json            输入、代码及原评价器锁的哈希
  learning_validation.json    实际已运行部分的数值检查
  learning_report.html        终端运行生成的图文记录
```

每个步骤MAT里统一只有入口结构 `data`：

```matlab
D = load(fullfile(lesson_cfg.run_dir,'06_fft_grid.mat'),'data');
frequencyGrid = D.data;
```

**完整解释、公式、逐项字段和索引约定见 [学习手册](../../docs/LEARNING_RECEIVER.zh-CN.md)。**

## 5. 一帧学会以后

```matlab
addpath('matlab/learning_receiver')
RUN_MULTIPLE_FRAMES(2,8)       % 2帧都跑到均衡，分别保存
% RUN_MULTIPLE_FRAMES(2,14)   % 2帧完整处理，耗时更长
```

多帧入口读取50ms、按独立检测后的时间序号选帧，每帧各自估计信道。它和原接收机的多帧共享信道模式不是同一配置。

此学习版的终点是频域网格与**条件星座符号判决**。配置头、实际业务位映射、解扰、FEC及业务CRC仍是未知项。每列选一个星座几何是当前模型假设，不能据此断言同列不存在混合调制。
