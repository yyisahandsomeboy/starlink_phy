# Codex接收机协议升级：PN、PDU头部与Code5

本模块把旧工程已经支持的“去PN后出现BPSK两点”继续接到BCC、组CRC、条件资源字段和一个已验证的Code5 QC-LDPC表示。依据[arXiv:2610.29387v2](https://arxiv.org/html/2610.29387v2)，实现身份为`codex_baseline`。

这是根据论文参数与本地旧代码独立实现的版本。截至2026-11-03，没有找到可核实属于论文作者的配套接收代码、原始18帧采集或码矩阵下载；arXiv源包仅提供正文、引用及图表。不能把本模块冒称为作者开源实现。详见[论文、代码与数据来源](../../docs/PAPER_2610_29387_SOURCES.zh-CN.md)。

## 已实现

- 频率升序的1020个已加载载波用于PN计数；剔除16个导频后，1004个非导频资源才进入编码序列。每列按时隙推进。
- 复用旧实验验证过的等效PN状态；保留论文自身采集的另一种固定对齐为显式可选模型。两者不自动互换。
- K=7、码率1/3、八进制`155/123/137`的完整64状态软Viterbi；每114个编码位独立归零，保留32位字与6个零尾。
- CRC8：掩码`0x4D`，初值`0xFF`，MSB优先，无反射、末异或0；校验整组去尾后的`32N−8`位。
- 第二组头部由固定前缀提议、完整BCC/CRC检验；支持三位长度字段候选2～7块。本机第三帧五块组已实际通过，六/七块仍只是允许检验的候选。
- 保存条件19/20位布局、7位索引/未决第8位及12位数量。未知编号保留原值，不根据星座外观补造MCS语义。
- 第一组格式5资源的固定QC128模型：N=2048、K=1024、H满秩1024、行重6；归一化min-sum、重编码及同一奇偶资源上的翻转对照。

## 已有MAT：先只读升级

在仓库根目录的MATLAB里：

```matlab
addpath('matlab/protocol_receiver')
report = RUN_PROTOCOL_ANALYSIS('runs/你的学习运行目录');
% 完整接收机的逐候选检查点也支持：
report = RUN_PROTOCOL_ANALYSIS('runs/你的完整接收目录', 'Frames', 1:9);
```

默认每帧输出三张新教学图及本地HTML。每帧只读取最终网格所在的单个检查点，读取后释放；不加载整份九帧大MAT作为回退，不重读原始IQ。输出目录已存在时拒绝覆盖。

```matlab
report = RUN_PROTOCOL_ANALYSIS(runDir, 'Frames', 1, ...
    'OutputDir', fullfile(runDir,'protocol-check-01'), ...
    'MakePlots', false);
```

源目录需要本机已经产生的MAT。克隆仓库不会自带历史运行；[根README](../../README.md)有公开IQ与参考资源下载方法。

## 从原始IQ运行

教学版默认运行到第18步：

```matlab
open('matlab/learning_receiver/START_HERE.m')
```

第16～18步由[CONTINUE_TO_PDU.m](../learning_receiver/CONTINUE_TO_PDU.m)分节展示，调用与完整入口相同的`slproto`函数。设`lesson_cfg.stop_after=14`可停在原接收链；16/17分别停在去PN/头部阶段。改变源码后使用新的运行目录。

Ubuntu终端启动器仍默认先跑到第8步；导入原完整冻结夹具后，可明确请求完整第18步：

```bash
scripts/run_learning_receiver --through 18
```

该终端入口现在支持原1～14步及完整18步，16/17的中途观察使用MATLAB分节。其批处理元数据读取实际协议摘要，不再无条件写“头部未解码”。本轮在Windows检查了参数和报告生成，未执行Linux原生启动器；仅准备公开资源的用户直接使用上面的MATLAB入口。

完整接收的新包装入口：

```matlab
addpath('matlab/baseline')
cfg = struct('root',pwd,'input_path', ...
    fullfile(pwd,'data','raw','exemplar250-257','exemplar250-257.bin'), ...
    'run_dir',fullfile(pwd,'runs','my-new-full-receiver'),'workers',0);
output = RUN_CODEX_RECEIVER(cfg);
```

该入口先调用原`author_receiver`，再逐帧执行新协议模块；原物理层和评价器保持版本不变。完整50ms物理层可能耗时很久，并继承原入口的工具箱要求；本轮验证范围见[实测记录](../../docs/PROTOCOL_UPGRADE_VALIDATION.zh-CN.md)。新增BCC/GF(2)/LDPC本身不依赖Communications Toolbox。

## 结果文件与解释

每帧的`protocol.mat`保留实际校准/去PN网格、参考、候选编码位、译码输入及重编码；`protocol_summary.json`只保存指标与来源SHA；`figures/16_pn_bpsk.png`、`17_bcc_crc.png`、`18_code5_fec.png`分别回答旋转、头部编码与奇偶约束的问题。

`code5.words.information_bits`是该条件编码器的输入位；可能仍含上层编码、源扰码或其他协议内容，不能称为网络明文。全载荷、未识别格式和真实业务BER仍未恢复。CRC匹配也不认证发射方。

数学、旧卡点与索引约定见[教学说明](../../docs/PN_PDU_TEACHING.zh-CN.md)。

## 模型恢复与测试

```matlab
addpath('matlab/protocol_receiver/tests')
test_protocol_receiver(pwd)
% words为每行一个2048位原始硬判决字；developmentMask按整帧预先划分。
recovered = slproto.recoverQC(words, developmentMask, 1024, 128);
assert(recovered.fit.unique)
P = recovered.P;
save('my-development-P.mat','P','-v7')
```

可选Python研究工具从独立恢复的P寻找并全维核验稀疏校验；需要NumPy/SciPy，日常MATLAB接收不需要这些Python库：

```bash
python tools/recover_qc_checks.py --input my-development-P.mat --output my-QC-checks.json
```

工具只支持本版Code5的1024×1024、QC128、行重6预算。秩不足、P不可逆或没有得到1024个独立稀疏校验时拒绝输出成功模型；不会替调用者猜补缺失的编码器。
