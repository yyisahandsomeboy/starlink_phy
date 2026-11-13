# MCS 35 位映射、LDPC 和 MAC CRC-24 验证

在 UT Austin 的 49 帧中，导出的 134 个 MCS 35 码字全部通过 LDPC 校验，重编码逐位一致。每帧首码字解扰后，49 个 MAC 头全部通过既有的 CRC-24。该模型是 `codex_baseline` 接收等价构造。 [UT Austin 示例帧与 MATLAB 数据字段说明](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/exemplar-frames-data/EXEMPLAR_FRAMES_GUIDE.txt)

| 分区 | 作者档案帧号（零基） | MCS 35 帧数 | LDPC 归零且重编码一致 | 首字 MAC CRC-24 |
|---|---|---:|---:|---:|
| 发现 | 455–480 | 25 | 64/64 | 25/25 |
| 留出 | 481–506 | 24 | 70/70 | 24/24 |

每个分配最多导出前三个单位。帧数和码字数指本次导出的样本。 [逐码字结果](../provenance/mcs35/mcs35_complete_verification.json)

## 资源位置与八点星座

若 PHY 头声明了 `C35` 个 MCS 35 单位，后续分配的起点随 `C35 × Q35` 平移。在 25 个发现帧中扫描 `Q35=1…16,384`，用后续已知 MCS 66／70 的 LDPC 校验给位置评分。`Q35=5,462` 的硬判决平均校验违例率为 22.23%，次优 `5,461` 为 29.79%。固定 5,462 后，24 个 MCS 35 留出帧中有 23 帧成功译出至少一个后续码字，共 76 个 MCS 66 和 169 个 MCS 70 码字通过重编码对照。`Q35±1` 的 46 次留出对照均未收敛。发现集中的 9 次相邻假设收敛仍有更高的符号重构误差。 [资源搜索记录](../provenance/mcs35/record80_mcs35_geometry.json)

星座中心从发现集估计后固定。留出集每个单位用偶数号符号估计复增益，奇数号符号评分，共 191,170 个评分符号。逐单位中位归一化平方误差为 4.825%。在离理论十六格任一点小于 0.12 的留出样本中，48,424 个落在预期八点附近，其余位置共有 207 个。按单位拟合复增益后，西电 MCS 28 的八点模板在发现集和留出集的中位误差分别为 5.30% 和 4.78%，8PSK 模板分别为 16.61% 和 16.39%。 [星座验证数据](../provenance/mcs35/mcs35_constellation_analysis.json) · [西电公开 IQ 数据](https://github.com/misaka666/Starlink-Downlink-Analysis/releases/tag/v1.0.0)

## 位标签、码字边界和信息区长度

对发现集的首码字枚举 40,320 种标签排列和 0、1、2 个起始比特偏移，沿用逐字解扰和外层 MAC CRC-24。唯一通过的标签表如下。各符号从标签的最低位开始输出，码字从第一个输出位开始。

| `(I,Q)×√10` | 三位标签数值 |
|---|---:|
| `(-3,-3)` | 1 |
| `(-3,1)` | 5 |
| `(-1,-1)` | 4 |
| `(-1,3)` | 7 |
| `(1,-3)` | 0 |
| `(1,1)` | 6 |
| `(3,-1)` | 2 |
| `(3,3)` | 3 |

固定标签后，两套硬判校准分别有 15/24 和 12/24 个留出首字在 LDPC 译码前通过 CRC，差异来自符号增益估计。独立复核中，16 个硬判通过的 MAC 头逐位翻转，共 10,144 个单比特反例均被拒绝。有限符号替换另找回 8 个头，24 个通过头都与完整 LDPC 译码逐字节一致。 [标签与边界证据](../provenance/mcs35/mcs35_lane_boundaries.json) · [独立 MAC 复核](../provenance/mcs35/mcs35_mac_systematic_results.json)

每单位有 `5,462 × 3 = 16,386` 个调制槽。最后一个符号的第一槽可变，后两槽在 70 个留出单位均为 0。发现集有两次低置信硬判将最后一槽判为 1。LDPC 输入取前 16,384 位。

信息区的边界也可从分配末字的零填充观察。用远离边界的区间筛选解扰后含长零填充的分配末字，再观察零基位区间 `[9440,9472)` 和 `[9472,9504)`。留出数据中，前一区间 192 位全为 0，后一区间 192 位有 98 个 1。档案帧 497 和 501 的首个 MAC 长度描述也各自与每码字 1,184 信息字节相容。

## 有效校验矩阵和重编码

AR4JA 候选测试信息位前缀缩短和校验位前缀删余。216 组参数中有 202 组可用至少 64 条稀疏方程评分，同时另测 897 个已有 QC 候选。胜出的两种母码构造在 GF(2) 消元后得到相同的校验方程集合。 [候选搜索记录](../provenance/mcs35/mcs35_ar4ja_prefix_results.json)

| 参数 | 接收等价构造一 | 接收等价构造二 |
|---|---:|---:|
| `k_b` | 4 | 8 |
| `M` | 4,096 | 4,096 |
| 缩短的信息位前缀 | 6,912 | 23,296 |
| 删余的校验位前缀 | 5,376 | 5,376 |
| 发送的信息位／校验位 | 9,472／6,912 | 9,472／6,912 |

以 `k_b=4` 为例，母码有 `4 × 4096 = 16,384` 个信息位和 `3 × 4096 = 12,288` 个校验位。缩短与删余后，有效矩阵 `H=[H_u H_p]` 有 6,912 行和 16,384 列。`H_p` 在 GF(2) 上可逆，程序逐行验证其逆矩阵，并用 `p=H_p⁻¹H_u u` 重算所有校验位。该式也给出系统生成矩阵的等价实现。134 个码字最多 4 轮 min-sum 即满足 `Hc=0`。发送端选择哪种母码构造仍无法由相同的有效矩阵区分。 [有效校验矩阵模型](../matlab/protocol_receiver/models/mcs35_complete_16384_model.json)

## 首字 MAC CRC 示例

留出帧 481 的首字解扰后以 `8C 00 07 EA 07` 开头。`8C 00` 按小端读取为 140 字节的头长。既有 CRC-24 覆盖前 137 字节，最后 3 字节携带校验值。接收与复算的校验值均为 `4BB9A4`。49 个通过的头中有 48 个不同的字节串。 [MAC CRC-24 参数和字节顺序](MCS_PAYLOAD_HEADER_CRC.zh-CN.md)

## 复核入口与输入数据

从仓库根目录将 `matlab/protocol_receiver` 加入 MATLAB 路径，可对已经去 PN、完成增益归一化的 `5462×N` 复数符号矩阵独立译码。每一列是一个 MCS 35 单位。

```matlab
addpath('matlab/protocol_receiver')
result = slproto.decodeMCS35(calibratedSymbols);
```

要重放这批样本，先按仓库说明准备公开参考，再从作者档案取得 `decodedExemplarFrames_20251019T2214.mat`。MATLAB 导出只读取四组帧，将符号和坐标写到本地运行目录。输入档的 `mcs35Points` 保存单位复数符号，`mcs35Meta` 保存作者帧号、资源起点、单位序号和分配单位数。 [作者档案和输入指纹](../provenance/mcs35/source_frames.json) · [导出入口](../matlab/protocol_receiver/EXPORT_MCS35_REPLAY.m)

```matlab
addpath('matlab/protocol_receiver')
EXPORT_MCS35_REPLAY('/path/to/decodedExemplarFrames_20251019T2214.mat','runs/mcs35-replay');
```

Python 的模型检查需要 NumPy，读取导出档还需要 h5py。 [Python 复核入口](../tools/verify_mcs35.py)

```sh
# 仅检查模型并运行合成对照
python tools/verify_mcs35.py

# 重放已准备好的四组 MATLAB 导出并与版本库结果比较
python tools/verify_mcs35.py --input runs/mcs35-replay/record80_geo_words_0455.mat runs/mcs35-replay/record80_geo_words_0468.mat runs/mcs35-replay/record80_geo_words_0481.mat runs/mcs35-replay/record80_geo_words_0494.mat --expected provenance/mcs35/mcs35_complete_verification.json --output runs/mcs35-replay/result.json
```
