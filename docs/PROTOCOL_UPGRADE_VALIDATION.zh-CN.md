# PN/PDU/Code5升级实测记录（2026-11-03）

基线：`0268bf60750515c2a5987fca0aa4b674fa8a318f`。MATLAB R2024b，Windows，实际执行新增单元测试、九帧历史网格后处理、原始IQ一帧重算及回读核验。实现身份`codex_baseline`。

## 1. 本轮结论与范围

- 九帧第一/第二头部共18组全部CRC通过，逐块重新编码与接收硬位差异为0。
- 第三帧第二组有5块、6个条件描述项，超出论文样本的2～4块组合；五块逐位重编码和组CRC支持该扩展。未将其强塞为四块。
- 首项格式5的35个2048位字可由满秩稀疏H表示并完成软译码与重编码。
- 前3帧12个字的QC128增强系统秩为1024，恢复的P与固定H导出的P完全相同；其余23字未参与消元。
- 原始硬位在23个留出字的奇偶预测中有2个差异，位于帧6/8各一个字。归一化min-sum共改变2个硬位；35字随后均零syndrome且重编码一致。不把这些候选位对照叫真实业务BER。
- 仅比较同一奇偶资源，预测NMSE范围0.027863～0.061143，翻转奇偶对照3.911068～4.016886。没有为某个目标字另拟合旋转。

以上来自同一旧UT Austin采集，包含内容重复，并非18组独立新采集。没有恢复完整业务载荷、应用明文或未识别格式的FEC。

## 2. 逐帧结果

| 本机帧 | 第一头部32位字（十六进制） | 第二头部r0 | 第二组块数/候选项数 | Code5字数 | 原奇偶预测差异 | 译码硬位修改 |
|---|---|---:|---|---:|---:|---:|
| 1 | 3048A020 / 000000AD | 8420 | 4 / 5 | 4 | 0 | 0 |
| 2 | 3048A020 / 000000AD | 8420 | 4 / 4 | 4 | 0 | 0 |
| 3 | 3048A020 / 000000AD | 8420 | 5 / 6 | 4 | 0 | 0 |
| 4 | 3048A020 / 000000AD | 8420 | 4 / 5 | 4 | 0 | 0 |
| 5 | 3048A020 / 000000AD | 8420 | 4 / 5 | 4 | 0 | 0 |
| 6 | 3048A020 / 000000AD | 8420 | 4 / 5 | 4 | 1 | 1 |
| 7 | 3048A020 / 000000AD | 8420 | 4 / 4 | 4 | 0 | 0 |
| 8 | 3048A020 / 000000AD | 8420 | 4 / 5 | 4 | 1 | 1 |
| 9 | 3048A0C0 / 0000002E | 6372 | 4 / 4 | 3 | 0 | 0 |

第一组前8帧内容重复，第九帧不同；第二组内容逐帧保存。不能用重复内容数量替代码字多样性。第二组边界由前缀提议后的完整BCC/CRC检查找到，再与首项数量预测比较，九帧均一致。

机器证据：`runs/protocol-upgrade-20261103/validation.json`、各帧`protocol_summary.json`和`independent_QC_recovery.mat`。完整图文入口为`runs/protocol-upgrade-20261103/nine_frames/index.html`。这些大MAT和PNG只在本机，不随源码发布。

## 3. 新鲜原始IQ与22个核心检查点

输入仍为`exemplar250-257.bin`，SHA-256 `c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3`。从头读取4ms，不恢复旧步骤，完成原22个接收检查点及新协议计算。

第一次导图在统一IQ坐标范围时出现行/列拼接错误；原接收和译码已完成。错误日志和不完整输出保留。将选中数组显式转列后，只重跑受影响的教学16～18步，并独立回读原22步，不重复物理接收。

最终22个`data`结构与升级前`runs/cfo-fresh-regression-20261028-retry`全部`isequaln`完全一致。`slrx.validateRun`通过：FFT/均衡重算相对误差0，最终留出导频EVM保持0.21118250302583794，原CFO/SFO、分类和跟踪数值未变。源MAT/原始IQ未写回。

新版入口默认到18步；最终生成原核心22张图和协议3张图。新鲜结果证据为`runs/protocol-fresh-20261103/upgrade_validation.json`；最终教学页为`runs/protocol-fresh-20261103/protocol-teaching-20261103-152255-446/index.html`。

## 4. 已执行测试与未执行项

| 测试/核验 | 结果 |
|---|---|
| `test_protocol_receiver` | MATLAB通过；两条论文CRC例、软BCC、单错误纠正、错误极性、坐标、H满秩/GH、两处合成LDPC错误纠正、QC留出错误及欠定/不一致拒绝 |
| 九帧逐候选MAT后处理 | 通过；18组CRC/精确重编码、五块组、35字LDPC、同资源奇偶重调制与翻转对照 |
| 错PN/错资源顺序 | 第一帧负对照不被接受为有效第一头部 |
| 独立MATLAB QC恢复 | 12字训练、23字留出，秩1024；P与固定稀疏H导出值一致；原留出差异2位如实保留 |
| Python稀疏恢复工具 | 通过；从独立恢复的P重建8条QC种子、1024秩、行重6并全维GH核验；与本版固定模型种子相同 |
| 终端教学参数/报告 | 通过；允许完整18步、默认仍8步、拒绝19、检查缺失协议输出、按真实摘要生成整合HTML；没有模拟MATLAB接收成功 |
| 新鲜原始IQ与教学回读 | 核心从头计算后，新绘图错误已修复；最终22数据结构精确一致及新增3图通过 |
| MATLAB独立mlint | 29个本轮MATLAB文件检查通过，无语法错误；ALIGN/ISCL/NASGU/NBRAK2仅为提示 |
| 原冻结评价器/门限 | 保持文件身份，没有新建或降低门限，也不以协议CRC覆盖其物理层判定 |

本轮没有重新执行整套旧的全部脚本测试、没有再跑完整50ms九帧物理DSP，也没有拿到论文自己的18帧采集。完整包装入口`RUN_CODEX_RECEIVER`的物理接收部分未另跑；其原实现保持不变，逐帧协议适配已由历史九帧实际运行覆盖。一帧新鲜物理回归走共享学习模块。不得把上述范围改写成论文18帧复现或新九帧接收成功。

## 5. 内存与安全边界

Windows Job只管理自己启动的MATLAB，0.25秒采样；可用内存低于1.25GiB或任务私有内存超过3GiB时停止。没有关闭用户MATLAB、VMware或浏览器。GiB按2^30字节。

| 本地memory_audit目录 | 状态 | 秒 | 峰值进程树私有/GiB | 系统最低可用/GiB |
|---|---|---:|---:|---:|
| `protocol_unit_20261103` | passed | 35.45 | 2.138 | 1.577 |
| `protocol_multiframe_20261103` | passed | 83.03 | 2.224 | 2.420 |
| `protocol_fresh_20261103` | failed | 301.38 | 2.537 | 2.429 |
| `protocol_fresh_finalize_20261103` | passed | 31.88 | 2.252 | 3.430 |

新鲜首次会话的failed来自绘图维度错误，未触发内存保护。协议后处理逐帧加载/释放，不回退到整份九帧巨型MAT；min-sum按稀疏边存消息；GF(2)恢复有维度预算。是否有其他程序占用仍会影响可用内存，本次测量不保证任意并发或长采集规模。

64个既定受保护文件、原始IQ、所读取的候选MAT与本地两项未提交配置逐个SHA复核；核心算法和冻结评价器未变。新增协议输出还保存协议源码与模型的逐文件SHA，不依赖旧学习锁只覆盖学习目录的范围。文件/图像/链接最终检查见[机器记录](../provenance/protocol_upgrade_validation.json)。

## 6. 可复现入口、资源和限制

[协议README](../matlab/protocol_receiver/README.zh-CN.md)提供旧MAT升级、从原始IQ运行、逐节教学、单元测试和QC恢复命令。新克隆先按[根README](../README.md)下载公开资源；仓库不包含历史运行数组。原始数据与论文代码检索分别见[来源记录](PAPER_2610_29387_SOURCES.zh-CN.md)。

旧卡点、PN与1004/1020计数、BCC/CRC、条件字段、LLR和三幅图的解释见[教学说明](PN_PDU_TEACHING.zh-CN.md)。其他编号/高阶格式、完整应用载荷、商业码身份、真实BER、PN物理复位状态及跨新采集泛化仍未验证。19/20位布局与未决第8位没有因CRC通过就被唯一确定。

## 7. 本轮文件清单

- [README.md](../README.md)
- [docs/LEARNING_RECEIVER.zh-CN.md](../docs/LEARNING_RECEIVER.zh-CN.md)
- [docs/PAPER_2610_29387_SOURCES.zh-CN.md](../docs/PAPER_2610_29387_SOURCES.zh-CN.md)
- [docs/PN_PDU_TEACHING.zh-CN.md](../docs/PN_PDU_TEACHING.zh-CN.md)
- [docs/PROTOCOL_UPGRADE_VALIDATION.zh-CN.md](../docs/PROTOCOL_UPGRADE_VALIDATION.zh-CN.md)
- [docs/VISUAL_DIAGNOSTICS.zh-CN.md](../docs/VISUAL_DIAGNOSTICS.zh-CN.md)
- [docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md](../docs/VISUAL_DIAGNOSTICS_FIGURES.zh-CN.md)
- [matlab/baseline/README.zh-CN.md](../matlab/baseline/README.zh-CN.md)
- [matlab/baseline/RUN_CODEX_RECEIVER.m](../matlab/baseline/RUN_CODEX_RECEIVER.m)
- [matlab/learning_receiver/+slrx/defaultConfig.m](../matlab/learning_receiver/+slrx/defaultConfig.m)
- [matlab/learning_receiver/CONTINUE_TO_PDU.m](../matlab/learning_receiver/CONTINUE_TO_PDU.m)
- [matlab/learning_receiver/README.zh-CN.md](../matlab/learning_receiver/README.zh-CN.md)
- [matlab/learning_receiver/START_HERE.m](../matlab/learning_receiver/START_HERE.m)
- [matlab/protocol_receiver/+slproto/analyzeCode5.m](../matlab/protocol_receiver/+slproto/analyzeCode5.m)
- [matlab/protocol_receiver/+slproto/analyzeFrame.m](../matlab/protocol_receiver/+slproto/analyzeFrame.m)
- [matlab/protocol_receiver/+slproto/bccDecode.m](../matlab/protocol_receiver/+slproto/bccDecode.m)
- [matlab/protocol_receiver/+slproto/bccEncode.m](../matlab/protocol_receiver/+slproto/bccEncode.m)
- [matlab/protocol_receiver/+slproto/calibrateGrid.m](../matlab/protocol_receiver/+slproto/calibrateGrid.m)
- [matlab/protocol_receiver/+slproto/code5Model.m](../matlab/protocol_receiver/+slproto/code5Model.m)
- [matlab/protocol_receiver/+slproto/coordinates.m](../matlab/protocol_receiver/+slproto/coordinates.m)
- [matlab/protocol_receiver/+slproto/crc8.m](../matlab/protocol_receiver/+slproto/crc8.m)
- [matlab/protocol_receiver/+slproto/decodeGroup.m](../matlab/protocol_receiver/+slproto/decodeGroup.m)
- [matlab/protocol_receiver/+slproto/defaultOptions.m](../matlab/protocol_receiver/+slproto/defaultOptions.m)
- [matlab/protocol_receiver/+slproto/exportFrame.m](../matlab/protocol_receiver/+slproto/exportFrame.m)
- [matlab/protocol_receiver/+slproto/findHeaders.m](../matlab/protocol_receiver/+slproto/findHeaders.m)
- [matlab/protocol_receiver/+slproto/finishFrame.m](../matlab/protocol_receiver/+slproto/finishFrame.m)
- [matlab/protocol_receiver/+slproto/gf2Solve.m](../matlab/protocol_receiver/+slproto/gf2Solve.m)
- [matlab/protocol_receiver/+slproto/loadGrid.m](../matlab/protocol_receiver/+slproto/loadGrid.m)
- [matlab/protocol_receiver/+slproto/minsum.m](../matlab/protocol_receiver/+slproto/minsum.m)
- [matlab/protocol_receiver/+slproto/parseFields.m](../matlab/protocol_receiver/+slproto/parseFields.m)
- [matlab/protocol_receiver/+slproto/plotFrame.m](../matlab/protocol_receiver/+slproto/plotFrame.m)
- [matlab/protocol_receiver/+slproto/pnReference.m](../matlab/protocol_receiver/+slproto/pnReference.m)
- [matlab/protocol_receiver/+slproto/recoverQC.m](../matlab/protocol_receiver/+slproto/recoverQC.m)
- [matlab/protocol_receiver/+slproto/smallSummary.m](../matlab/protocol_receiver/+slproto/smallSummary.m)
- [matlab/protocol_receiver/+slproto/sourceManifest.m](../matlab/protocol_receiver/+slproto/sourceManifest.m)
- [matlab/protocol_receiver/+slproto/writeJSON.m](../matlab/protocol_receiver/+slproto/writeJSON.m)
- [matlab/protocol_receiver/README.zh-CN.md](../matlab/protocol_receiver/README.zh-CN.md)
- [matlab/protocol_receiver/RUN_PROTOCOL_ANALYSIS.m](../matlab/protocol_receiver/RUN_PROTOCOL_ANALYSIS.m)
- [matlab/protocol_receiver/models/code5_qc128_utexas_v1.json](../matlab/protocol_receiver/models/code5_qc128_utexas_v1.json)
- [matlab/protocol_receiver/tests/test_protocol_receiver.m](../matlab/protocol_receiver/tests/test_protocol_receiver.m)
- [provenance/protocol_upgrade_validation.json](../provenance/protocol_upgrade_validation.json)
- [tools/learning_receiver.py](../tools/learning_receiver.py)
- [tools/recover_qc_checks.py](../tools/recover_qc_checks.py)
