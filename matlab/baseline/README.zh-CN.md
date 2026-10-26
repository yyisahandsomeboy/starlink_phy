# 完整 Codex 真实IQ接收机

本目录的主入口是 `author_receiver.m`；主要数值运算在 `author_receiver_dsp.m`。两者按原工程逐字节导出，未在上传时改算法。它使用公开作者序列与公开方法，工程补齐部分标为 `codex_baseline`。

## 如何阅读

1. 学习时先看[分步学习版](../learning_receiver/README.zh-CN.md)，它把同类步骤拆成独立函数。
2. 再看本目录 `author_receiver.m`：读IQ/重采样→独立捕获→多SSS响应融合→逐候选两轮处理→保护间隔和输出。
3. 读 `author_receiver_dsp.m` 的dispatcher及对应局部函数：取帧/CP/FFT、信道、点数识别、逐列ML、整帧跟踪。
4. `frame_guard_metrics.m`记录帧末保护区；`baseline_manifest.m`记录输入/配置/代码与MATLAB版本。

公式、物理意义和全部中间字段详见[算法与变量说明](../../docs/AUTHOR_RECEIVER.zh-CN.md)。

## 准备资源

在仓库根目录执行[根README](../../README.md)的资源准备。复用原工程的完整冻结资源以后，可直接运行：

```bash
scripts/run_baseline real --workers 1 --timeout 3000
scripts/plot_ofdm
scripts/analyze_payload --all-frames
```

如果仅下载公开资源，没有旧合成fixture，可直接在MATLAB运行以下完整真实接收入口。原评价器和门限仍然使用仓库中原始文件；未修改旧Python启动器的32文件锁。

```matlab
% 当前目录必须是starlink_phy仓库根目录。
root = pwd;
addpath(fullfile(root,'matlab','baseline'))
addpath(fullfile(root,'matlab','evaluation'))
cfg.root = root;
cfg.input_path = fullfile(root,'data','raw','exemplar250-257','exemplar250-257.bin');
cfg.data_type = 'real_iq';
cfg.run_dir = fullfile(root,'runs',['codex-native-real-' char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'))]);
cfg.workers = 1;
cfg.make_plots = true;
limits = jsondecode(fileread(fullfile(root,'config','real_receiver.json')));
cfg.pilot_fit_evm_max = limits.pilot_fit_evm_max;
maxNumCompThreads(4)
test_author_receiver_dsp(root)
test_frame_guard_metrics
result = author_receiver(cfg);
evaluate_receiver(cfg)
baseline_manifest(cfg)
```

该原生例子产生接收MAT与独立评价，但不生成原Python启动器的 `receiver_lock/run_manifest` 和全局latest索引；不要直接把它当成 `scripts/analyze_payload` 期待的完整批处理目录。原生查看和判决可读下面变量，或使用可独立运行的MATLAB导出函数。要复用原完整CLI后处理，按根README导入原冻结资源，再用原CLI入口运行。

## 输入与输出

原输入：250Msps、50ms、小端交织int16的宽带IQ。**捕获不读取sliceInfo TOA**；独立评价器在结果产生后才用它作时间对照。

每次CLI运行新建 `runs/codex-author-real-时间/`：

| 文件/字段 | 内容 |
|---|---|
| `result.mat` 的 `result` | 所有合格帧和关键中间变量 |
| `result.frames(j).start_sample_capture` | 原文件连续一基复采样坐标；可带小数 |
| `sync_local_curve`、`sync_window_*` | PSS/SSS局部峰与同步窗口 |
| `grid_before/resampled/equalized/after` | 不同时间轴/补偿阶段的网格 |
| `channel_response`、`intermediates.channel_*` | H、LS/平滑/噪声估计 |
| `tracking`、`modulation` | 逐列ML、内点/残差、几何与增益 |
| `frame_guard` | 模型保护边界、原始短IQ及功率 |
| `frame_candidate_*.mat` | 逐候选完成检查点，减少大MAT加载 |
| `evaluation.json/mat` | 原独立评价器的实际数值与状态 |
| `receiver-code/`、`receiver_lock.json` | CLI运行时的代码快照与输入/参数身份 |
| `payload_analysis/` | 后续导出的星座、条件硬符号及浏览器页面 |

FFT网格1024×301，首列SSS，后300列数据；4个gutter和16条公开导频以外有1004个载荷位置/数据列。`matlab/visualization/payload_hard_decision.m`作条件最近几何点判决，未确证的业务位映射、扰码和FEC不补造。

查看一帧示例：

```matlab
R = load(fullfile(cfg.run_dir,'result.mat'),'result');
f = R.result.frames(1);
size(f.grid_after)                         % 1024×301
f.start_sample_capture
(f.start_sample_capture-1)/250e6            % 原文件中的秒坐标
plot(f.sync_local_curve.lag_model_samples,f.sync_local_curve.sss,'o-')
```
