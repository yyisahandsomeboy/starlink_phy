# QC-LDPC恢复过程：独立交互教学页

2026-11-06，新建独立页面，不替换固定在1743f72的首次汇报观察台。

下载或克隆仓库后，直接用Windows浏览器打开 [MCS66_LDPC_WALKTHROUGH.html](MCS66_LDPC_WALKTHROUGH.html)。GitHub网页只显示源码时，请先下载该HTML再双击；它自带脚本、样式和证据，无需服务器、MATLAB或联网。本机交付为 `F:/codex_storage/coding_walkthrough_20261106/mcs66-ldpc-walkthrough.html`，与仓库文件逐字节相同。

页面用MCS66第5帧第1字贯穿讲解（未参与模型选择），也可切换第2帧第1字（模型选择样本）。章节按控制头→复数观测和位标签→有限公开族识别→QC与Z→Hp逆和隐式G→真实译码迭代→完整统计和反例→论文方法区别排列，最后对照MCS70新进展。

可操作内容：CRC位翻转实验、4096资源的I/Q和LLR、512位块内循环移位、14位稀疏校验的真实XOR、4096个奇偶位对应P列的按需精确计算、实际综合征网格和逐次迭代、376字指标切换、全部证据JSON导出。所有人为翻转均标为教学实验，不改真实结果。

不能误述：index/length本身不能推出G。66本次先利用Code5与公开AR4JA置换族吻合，识别H，再推导隐式G；没有执行一次仅靠8字、满秩的任意UP=V盲恢复。零综合征不认证绝对码字边界；偏移1资源仍通过的反例在页面中保留。重编码输入取自软译码结果，不是未见奇偶位预测。改变量不是BER；未恢复业务明文。

页面保存真实接收点的两个小子集、精确位/综合征、冻结66模型和逐字精简指标，不含原始IQ、完整作者MAT或历史大运行数组。数据署名和CC BY 4.0说明在页面末尾，数值置换来源链接CCSDS官方文档。

## 从已导出的证据重建

页面末尾点“下载本页完整分析证据JSON”，然后在仓库根目录：

```bash
python tools/build_coding_walkthrough.py --evidence coding-walkthrough-evidence-v1.json --out my-walkthrough.html
```

此步骤仅需Python标准库。重新提取完整精度的真实轨迹则需要本机先前研究缓存（不随源码Git分发）、9个protocol.mat、NumPy和h5py：

```bash
python tools/collect_coding_evidence.py --cache66 /path/to/mcs66-research-cache --cache70 /path/to/mcs70-research-cache --repo /path/to/starlink_phy --out evidence.json
python tools/build_coding_walkthrough.py --evidence evidence.json --out my-walkthrough.html
```

收集器只读取既有冻结模型、真实资源单位与MAT头部，重算两字迭代轨迹，并与原译码位逐位比较；它不重新搜索码型。独立数据导出需要缓存，单文件HTML阅读与从页内JSON重建不需要这些缓存。

浏览器QA：file://离线打开、无外部请求/运行异常，验证两个真实字全部4096条检查，24个P列（每字12列，覆盖8个QC组及块边界）的全部12288个系数与Python参考相同；检查CRC翻转、校验行导航、位翻转、例子/迭代/指标切换、证据下载，以及1440/390/320像素布局。见[精简记录](../provenance/coding_walkthrough_validation.json)。
