# arXiv:2610.29387v2：论文、配套代码与数据检索记录

检索日期：2026-11-03。用户提供的版本是2026-10-29修订的[论文v2](https://arxiv.org/abs/2610.29387v2)，与v1的标题/部分格式标签不同。本轮实现明确按v2参数及本机观测核验。

## 1. 本轮找到和未找到的资源

| 资源 | 核实情况 | 本工程如何使用 |
|---|---|---|
| [arXiv HTML正文](https://arxiv.org/html/2610.29387v2) | 已阅读；含PN、BCC、CRC、条件字段、QC与验证方法 | 参数和数学依据，不复制接收数值当成本机结果 |
| [arXiv TeX源包](https://arxiv.org/src/2610.29387v2) | 已下载并检查成员；有main.tex、references.bib、排版文件、图表及00README.json | 本地复核；包内没有.m/.py接收代码、.mat矩阵或原始.bin/.zip数据 |
| 属于论文作者的GitHub代码 | 截至检索日期未找到可核实的对应仓库 | 本工程为独立实现，不称作者源码；“未找到”不等于证明不存在 |
| 论文的480 MSps、约24ms、18帧连续采集 | 没找到可核实的公开下载地址；源包中也没有 | 本轮未运行论文自己的采集，不声称复现其18帧数值 |
| 论文完整QC生成/校验矩阵 | 未找到可下载矩阵；正文的参数或连接图不能替代完整矩阵 | Code5模型由本机旧接收位独立恢复，另做满秩、GH和留出检验 |
| UT Austin RNL的公开参考和IQ | 本工程已经有逐文件URL与SHA的[资源清单](../provenance/resources.json) | 本轮实际使用这份250 MSps、50ms IQ及其原生接收结果 |

检索覆盖arXiv摘要、正文与全部源包成员；以论文编号、v1/v2完整标题、作者名与Starlink/PDU/LDPC等组合查询网页和GitHub仓库。只出现论文聚合或同名作者页面时，不据此认定为配套代码。没有联系作者、没有使用需凭据的私有数据。

源包下载SHA-256：`b6aeca3e2e3fc6fbb0b49c63a3f375fea994f4080de9242640935a2739d44434`，6,749,950字节。原始论文和图表保留在本机工作资料，不随接收机源码提交。

## 2. 实际输入来自哪里

本机输入仍是UT Austin Radionavigation Laboratory公开的`qin-starlink-pilots`补充资料中的`exemplar250-257`片段：

- [公开IQ ZIP](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/raw-iq-data/exemplar250-257.zip)。
- [作者资料指南](https://rnl-data.ae.utexas.edu/datastore/supplementaryMaterial/qin-starlink-pilots/GUIDE.txt)。
- 250 MSps、50ms、小端交织int16 I/Q，12,500,000个复采样；BIN为50,000,000字节。
- BIN SHA-256：`c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3`。
- 公开PSS/SSS/导频生成函数属于原作者参考；资源脚本按固定SHA下载。本轮没有改这些第三方文件。

仓库不存大数据。在克隆后的根目录执行：

```bash
python3 scripts/prepare_receiver_resources
```

Windows可用`python`。公开资源足够跑MATLAB入口；旧Python启动器另要求历史合成夹具，详见[根README](../README.md)。

## 3. 不把两份数据和模型混为一谈

论文480 MSps的2048/64表示与本机240 MSps模型的1024/32具有相同子载波间隔，但采集、本振、PN对齐和头部内容不同。不能把论文的频偏数值、18帧边界、PN索引或MCS表直接写成本机真值。

本轮采用旧工程已由导频支持的连续双位PN模型；论文自身对齐作为显式可选项`paper_v2_480MHz_capture`保存，未将其自动设为本机默认。BCC/CRC参数迁移是否成立，取决于对本机资源逐位重编码和整组CRC的实际检查。

新Code5模型标记`codex_baseline`，由本机前3帧12个字的QC方程恢复，23个其余字用于随后检验；它不是论文作者提供的矩阵，也不是新采集盲验。未知格式仍不套用该矩阵。
