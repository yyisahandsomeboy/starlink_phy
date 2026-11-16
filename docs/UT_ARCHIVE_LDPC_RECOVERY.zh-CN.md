# UT 全档案的 LDPC 码字恢复记录

实验覆盖 UT 作者公开归档的 1,009 帧。归档名为 `decodedExemplarFrames_20251019T2214.mat`，文件大小为 5,415,856,507 字节。[文件指纹与新档位证据](../provenance/ut_ldpc_archive/new_models.json) · [公开归档](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/exemplar-frames-data/decodedExemplarFrames_20251019T2214.mat)

逐帧的 PHY 配置头通过检查后，按每个 MCS 的资源长度建立分配。帧号、资源和分配索引从 0 开始。分配内的码字序号从 1 开始。覆盖率以 PHY 配置头声明的码字为分母。[归档配置与资源位置](../provenance/ut_ldpc_archive/phy_inventory.json)

## MCS 42 和 MCS 93

| 档位 | 调制 | Q 资源数 | N 传输位 | K 信息位 | AR4JA 参数 K_B、M、S、D | 归档样本 |
|---:|---|---:|---:|---:|---|---:|
| 42 | 16QAM | 4,096 | 16,384 | 8,704 | 4、4096、7680、4608 | 16/16 |
| 93 | 交叉 32 点 | 3,277 | 16,384 | 13,568 | 8、2048、2816、3328 | 4/4 |

**MCS 42** 后面紧接已知档位。移动候选边界并比较下游首码字的校验，锁定 Q=4,096。固定边界后，七个留出帧的下游首码字全部通过。MCS 42 自身的粗解扰零尾在 8,704 位出现明显转折。选出的有效矩阵使 16 个 MCS 42 码字全部重编码一致，其中 7 个为留出码字。两组母码参数 `(4,4096,7680,4608)` 和 `(8,4096,24064,4608)` 投影后的有效矩阵逐行相同，样本支持这一个发射域矩阵。

**MCS 93** 位于四帧的最后分配，通过星座拟合与后方尾序列的位置锁定 Q=3,277。每单位有 16,385 个调制标签位，前 16,384 位进入 LDPC。粗解扰把信息段末端定位在 13,568 位。由于直接硬判决的错误率较高，先从此前独立译出的、通过 CRC-24 的第二 MAC 头取得填充长度，再用已知填充约束辅助译码。4 个码字全部通过，其中 2 个是留出字。随后把合计 13,554 个填充位从先验中拿掉，四个码字仍通过且全部保留位解扰为零。

## 遇到的问题和处理

| 问题 | 处理与验证 |
|---|---|
| 高阶星座使用统一的信道参数，部分软比特置信度失真 | 将同一帧中已经通过的码字重编码并重新映射成星座点。利用这些带标签的点估计复增益和星座点的噪声协方差。使用归一化最小和与和积重试。 |
| 高码率下，有效矩阵消去删余位后部分校验变密 | 从同一 AR4JA 母图恢复稀疏表示，把额外删余位保留为中性先验的未知变量。MCS 92 保留 768 个这样的变量。候选输出仍由发射域有效矩阵独立逐位重编码核对。 |
| 每个星座点只做一次边缘化，遗漏多个标签位之间的联合信息 | 在星座软解映射器和 LDPC 校验图间迭代交换外部信息，并允许每个 OFDM 时隙有残余复增益和线性频率斜率。 |
| 相同 PHY 分配可能对应不同帧内容 | 先检查对应码字的校验段和全字硬判决相似度，再使用已证实的重复码字或合并高相似观测。第 314、315 帧布局相同，普通数据码字的校验段一致率约 50%，未作为重复数据。第 515、516 帧那组 MCS 92 的 55 对校验段平均一致率为 99.1%。 |
| 同一帧里的子载波噪声不均匀 | 用通过的码字在各子载波的残差估计相对噪声，对未知字重新加权，并分别尝试稀疏图与有效图。 |
| 作者保存的硬判决与软网格来自同一观测 | 在额外一轮只把硬判决当作有界的解映射提示。验收继续使用实际信号、零综合征和有效矩阵重编码。 |
| 尾部有可预知填充，直接固定会减少独立观测 | 只使用 CRC 已通过的 MAC 描述符提供长度。MCS 93 增加部分填充位留出实验，逐位检查译码能否自己恢复这些位置。 |

对 11 个有 MAC 填充长度的 MCS 92 分配末字，把起点在预期位置前后移动 7 个资源。所有帧的最佳位置都是零偏移，预期填充位的硬判决一致率为 89.35% 到 95.80%。第 515、516 帧的观测高度相似，合并后的结果仍需分别检查两份观测的校验段匹配。最近星座点的误差只衡量点云的集中程度，不能单独确定当前码字是否能解开。[对齐和星座误差明细](../provenance/ut_ldpc_archive/mcs92_diagnostics.json)

## 归档相位与剩余信号的复核

作者说明 `yDataSoft` 已完成相位、时序和功率归一化。对 13 帧，把此前的八导频校正还原，再比较直接使用归档相位和对校正量做时间中值滤波两种输入。用已通过 LDPC 的符号作为参考，从一半子载波估计每个 OFDM 时隙的复增益，再在另一半计算按拟合信号能量归一化的误差。保留归档相位在 13 帧上均减少了误差，降幅约为 4.0%–8.6%。流式译码器返回的外部似然用于重估局部增益和观测噪声，候选由固定有效矩阵逐位重编码验收。[作者数据字段说明](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/exemplar-frames-data/EXEMPLAR_FRAMES_GUIDE.txt) · [留出检查与各轮结果](../provenance/ut_ldpc_archive/followup_review.json)

对前一轮 768 个缺口，按档位在整个归档搜索可能的重复码字，允许帧布局、资源位置和码字序号不同。只有第 515 和 516 帧的 112 个缺口找到了高度相关的对应观测，两帧的近星座点残差相关系数约为 0.991。补出新码字后，这批对应观测中又核实了一个码字。加入相邻子载波预测在 15 帧的留出符号上均小幅增加误差。30 个有已知填充的分配末字也支持原有的标签顺序和极性，10 个 MCS 92 样本支持信息段在第 13,056 位结束。[复核数值](../provenance/ut_ldpc_archive/followup_review.json)

## 复跑结果

全部 69,631 个码字已逐个重放。累计 69,284 个通过 LDPC、固定有效矩阵重编码比对并完成解扰，通过率为 **99.50%**。此前已验证 68,863 个，本轮新增 **421** 个。共有 979/1,009 帧的全部码字通过。

| 本轮新增验证的方法 | 通过数 |
|---|---:|
| LDPC 外部信息反馈 | 6 |
| 保留归档相位或平滑导频校正 | 369 |
| 核对高相关帧的已验证码字 | 1 |
| 更新训练与联合译码配置 | 45 |
| 原始归档相位下的相关帧联合协方差 | 0 |
| 邻近训练结合外部信息反馈 | 0 |
| 少量低档位缺口的定点回放 | 0 |

仍有 **347 个**码字待恢复，分布在 30 帧。

| MCS | 通过／声明 | 待恢复 |
|---:|---:|---:|
| 85 | 3,822／3,823 | 1 |
| 88 | 1,630／1,678 | 48 |
| 92 | 3,161／3,459 | 298 |

公开原始 IQ 目录只列涵盖第 250–257 帧的片段，这些帧的码字已全部通过。其余有缺口的帧目前可用的是作者处理后的频域软网格。归档记录的源录波名为 `pizza_sl_reference_9_ch0`。匹配该录波或同一发送码字的独立观测，可以进一步复核同步、均衡和软译码。[UT 原始 IQ 目录](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/raw-iq-data/)

逐帧数据用掩码标记有效码字。完整发送位可对通过的系统信息重新施加扰码，并用有效矩阵重算校验位。[按档位覆盖](../provenance/ut_ldpc_archive/coverage.json) · [逐帧统计](../provenance/ut_ldpc_archive/frames.csv) · [未通过码字位置](../provenance/ut_ldpc_archive/unresolved.csv)

## 校验

本次重新校验了模型表的 25 个 MCS 和 20 个有效矩阵，包括参数一致性、合成码字通过和翻转一位拒绝测试。用 MATLAB 对归档第 4 和 54 帧重新导出，得到与原导出逐样点一致的软符号，并展开了 MCS 42 和 93 的完整资源区段。

## 重放

在 MATLAB 从公开归档导出软符号。以下命令在仓库根目录运行，输出目录需已存在。批量读取沿用归档的 HDF5 分块，每次最多读取 13 帧。

```matlab
addpath('tools')
frames = (0:1008).';
export_ut_mcs92_symbols('/path/to/symbols', pwd, [frames frames], '/path/to/decodedExemplarFrames_20251019T2214.mat')
```

用 C++17 编译流式译码器。Python 依赖 NumPy 和 h5py。以下例子使用第 515、516 帧。完整重放可将范围改为 0 到 1008，并把各分片输出写到同一阶段目录。已有基线目录每帧应含带 `allocations`、`codewords` 的 JSON 和同名 NPZ。`part_i` 每行是一字的解扰字节，`valid_i` 是对应的布尔掩码，分配的长度和坐标来自 PHY 清单。

```sh
c++ -O3 -std=c++17 tools/ldpc_archive_worker.cpp -o ldpc_archive_worker
I=provenance/ut_ldpc_archive/phy_inventory.json
python tools/recover_ut_ldpc_archive.py "$I" /path/to/baseline /path/to/first-pass \
  --symbols /path/to/symbols --decoder ./ldpc_archive_worker --first 515 --last 516
python tools/recover_ut_ldpc_archive.py "$I" /path/to/baseline /path/to/joint-pass \
  --symbols /path/to/symbols --decoder ./ldpc_archive_worker --first 515 --last 516 \
  --seed /path/to/first-pass --joint
python tools/summarize_ut_ldpc_archive.py "$I" /path/to/baseline /path/to/summary \
  --stage /path/to/first-pass --stage /path/to/joint-pass --combined /path/to/verified-words
```

其他重试包括 `--frequency-noise`、`--author-hints /path/to/archive.mat` 和 `tools/find_ut_ldpc_repeats.py`。每阶段只增加通过的码字。汇总会检查新增字的资源坐标、原验证掩码，以及不同阶段对同一码字的字节一致性。原始网格和解扰字节用于本地重放。

对有缺口的帧，把零基帧号逐行写入 `frames.txt`。重新编译流式译码器后，可以重放保留归档相位的处理。加上 `--pilot-refine` 会尝试不同的校验图和消息调度。`--seed` 可以传入前一阶段新增的验证结果。

```sh
python tools/recover_ut_ldpc_feedback.py "$I" /path/to/verified-words /path/to/pilot-replay \
  --frames frames.txt --symbols /path/to/symbols --decoder ./ldpc_archive_worker \
  --pilot-archive /path/to/decodedExemplarFrames_20251019T2214.mat
```
