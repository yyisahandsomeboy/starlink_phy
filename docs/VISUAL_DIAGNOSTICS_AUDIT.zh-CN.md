# 教学可视化现状审计（2026-10-27）

审计起点：本机克隆提交`55082bc`，另有先前实测确认的`fitSymbol`逐元素幂和`marginalNLL`逐元素导频除法两行修复。本轮以这个已跑通版本为数值基线，不将这两行旧修复冒称本轮可视化改进。

## 学习版原有27幅图片

| 步骤/文件 | 数量 | 变量与已有字段 | 展示缺口/适合改进 |
|---|---:|---|---|
| 01_capture_iq、01_capture_psd | 2 | capture.iq、psd_linear、psd_frequency_hz、rms、dc、clipped_fraction | 波形只取窗口前5000点，没有标选中帧；已有全窗口IQ可显示分箱功率和帧附近波形 |
| 02_resampled | 1 | sampled.iq、fs_hz、ratio、filter、removed_dc | 仅I路；应说明时间窗口和物理时间，不作调制结论 |
| 03_sync_pss、03_sync_sss | 2 | sync.scan、candidates、rejected、selected.sync_local_curve | 已保存全局每100点抽取轨迹、联合曲线与精确候选；原图只画±8点局部PSS/SSS，缺少全局坐标与联合比较 |
| 04/13a_frame_time | 2 | time_raw、time_cfo_compensated、sample_positions_nominal、cfo_hz、sfo_ppm | CFO效果只看两条I波形不直观；已有已知PSS/SSS可作补偿前后分块参考相位诊断 |
| 05/13b_without_cp | 2 | cp_samples、without_cp、cp_correlation | 已有CP/尾部；缺少1056=32+1024分解及复数复制对照 |
| 06/13c_fft_grid | 2 | values、frequency_bins、frequency_hz | 已有正确fftshift显示，缺少signed bin与MATLAB行号区别、SSS/数据列及导频/空载波标记 |
| 07/13d_channel_* | 4 | H、LS/平滑响应、噪声功率、noise_variance_equalized | 已有H幅相；缺少单点Y/H解释及深衰落噪声放大代理 |
| 08/13e_equalized | 2 | equalized.values、heldout_pilot_evm_before/after | 原图只显示第50数据列；且载荷行号写死，需从refs读取；新增同轮FFT→均衡→跟踪公平对照 |
| 09/13f_pilots | 2 | 原始/拟合相位、时延、preview_grid | 已计算时间/相位趋势但只画相位；不能把FIT拟合效果冒称独立验证 |
| 10/13g_cardinality | 2 | K4/8/16/32得分、各列记录 | 已有模型得分；几何分类是算法假设，不是真实MCS |
| 11/13h_tracking_* | 4 | 逐列ML相位/时延、内点、残差、拟合线、values、EVM | 已有完整ML诊断数据；原图未连到CFO/SFO更新、逐列EVM与坐标漂移 |
| 14_decisions | 1 | received、hard_symbols、几何ID、增益、行/列/频率映射、posterior | 已有条件最近点及资源映射；理想点来自候选模型，不能据此生成真实BER/SER |
| 15_guard | 1 | 预测区坐标、samples、preguard_samples、功率比 | 有实际IQ与模型边界，不能称为已检测噪声边缘 |

## 已有独立诊断并非空白

`ofdm_view_data.m`已算多阶段及逐列留出导频EVM、去参考导频点云、误差图、正负频率与载荷矩。`plot_ofdm_diagnostics.m`、`plot_readable_diagnostics.m`已有CP幅相、六列星座和信道/同步图。

但这些入口依赖完整接收机的`result.frames`、固定首帧/选列和历史指针，部分坐标和采样率写死，还会再次读取完整BIN。不能直接当学习版独立检查点的通用浏览器。新诊断复用其EVM定义与只用SSS作整体标定的约定，读取学习版已保存MAT，按轮次组织，统一由cfg/refs提供坐标及资源映射。

## 只需少量额外计算

- 连续一基采样↔文件时间↔模型窗口坐标转换；不执行新的同步搜索。
- 已知同步序列的分块参考相位、CP复数幅相、已保存网格的EVM/误差/相位统计。
- 根据已保存sample_positions_nominal追溯FFT有效区1024个样本的位置。
- SFO两轮采样坐标差与累计漂移；不向接收机反馈新的估计。

FFT点组合一整段时间采样，且经历插值和FIR；不能虚构“一个星座点等于一个原始IQ采样点”。均衡/跟踪还依赖SSS和整帧估计，应记录依赖边界。

## 当前无法计算或无法证明

没有真实业务符号/位真值，因此无法算真实业务BER/SER、商业MCS识别准确率、真实扰码状态、FEC和CRC。EVM只针对已知留出导频，不以几何硬判决证明自身正确；ML/CFO/SFO是估计，不能拆解为独立真实卫星Doppler与本振/ADC误差。

同步算法没有保存所有被跳过的粗峰尝试，也未保存精细候选对应的原始粗峰坐标。全局图将抽取轨迹和精确帧头事件分层，明确缺失记录，不把抽取最大值或精细位置伪称完整分辨率粗峰。
