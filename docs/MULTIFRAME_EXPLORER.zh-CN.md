# 全部9帧离线信号观察台

本版把原第一帧观察台扩展到当前接收结果的全部 **9个完整帧**。保留资源网格、去PN前后星座、控制头位图、CRC、MCS资源分配、Code5卡片与边界审计的联动。编号沿用原接收结果，同时显示原候选文件名；这些编号不代表采集时间排序。

本机入口：`F:/codex_storage/frame_explorer_all_20261106/viewer/explorer.html`。在Windows宿主机的Chrome或Edge中直接打开，不需要服务器、网络或MATLAB。**请保留同目录的assets、frames子目录**；分享时复制或打包整个viewer目录。

原首次汇报版`F:/codex_storage/frame_explorer_20261104/report-before-mcs66/explorer.html`及其四份源码保持原样。新入口是独立的多帧版本。

## 先这样使用

1. 顶部点01～09、下拉帧号，或用“上一帧 / 下一帧”。标题、原候选名和高亮帧号一起变化。
2. 默认勾选“切帧保留当前OFDM列 / bin”，可比较不同帧的同一坐标。它保留的是网格坐标，不代表各帧相同业务包或相同MCS。取消勾选后，新帧默认选中自己的16QAM→交叉32点预测边界所在列。
3. 展开“9帧对比”，先看各帧两组CRC、头部块数、Code5收敛数、两处边界差和实际出现的MCS编号。点表格帧号也能切换。
4. 用“首配置头 / 第二配置头”选择本帧的全部头部资源。切换PDU头后查看位图，点一位定位其3个BCC输出资源；“定位CRC输出”选择本帧实际的24个输出资源。
5. “跨调制混合列”定位本帧主要调制切换；旁边的下拉菜单还列出本帧其他混合列。两幅星座始终显示同一批资源的去PN前后观测。
6. MCS表的“定位”选择本帧该描述项；“二值尾部”选择本帧实际尾部。不同帧的相同MCS编号使用同一颜色，便于比较。
7. 导出所选资源CSV或本页摘要。文件名为`frame-N-selected-resources.csv`和`frame-N-summary.json`，内容含接收帧号及原候选文件名，避免跨帧混淆。

切帧会重新载入一页，区域隐藏、字段选择、缩放范围等恢复默认；只有勾选的列号/bin会带到下一帧。每一页可独立打开，但仍需要相邻的共享assets目录。

## 每帧有什么不同

每帧都有300个数据OFDM列，每列1024个FFT bin，其中1004个非导频资源；共301200个非导频资源。可选加入SSS列1，网格变为1024×301。PSS属于时域同步段，不在该频域检查点内。

| 接收帧号 | 原候选文件编号 | 第二头部块数 / 资源数 | Code5码字数 | 默认跨调制列 | 两处边界差（资源） |
|---|---|---|---|---|---|
| 1 | 01 | 4 / 456 | 4 | 208 | −113 / −1 |
| 2 | 04 | 4 / 456 | 4 | 206 | −9 / 0 |
| 3 | 09 | **5 / 570** | 4 | 202 | −1 / −3 |
| 4 | 03 | 4 / 456 | 4 | 206 | +7 / −1 |
| 5 | 02 | 4 / 456 | 4 | 206 | −1 / +4 |
| 6 | 06 | 4 / 456 | 4 | 204 | +11 / 0 |
| 7 | 05 | 4 / 456 | 4 | 269 | −1 / 0 |
| 8 | 08 | 4 / 456 | 4 | 273 | −3 / −1 |
| 9 | 07 | 4 / 456 | **3** | 235 | +5 / −1 |

“边界差”=信号估计r0−头部推算r0；是两种定位方法的差异，不是误码数。对比表列出两处边界；下方边界图重点展示第一处16QAM→32点切换，以局部r0序列绘图，不假定两种位置一定在同一OFDM列。

首头部在9帧中均为2块、228资源。第9帧第二头部开始于列8，其他帧开始于列10；不能照搬第一帧快捷位置。9帧共18组头部CRC均通过，现有Code5摘要共35个码字收敛；这些是已有结果的只读展示，本次没有重新译码。

坐标、增益归一化、绘图最多12000点的确定性抽样规则和全量CSV约定沿用[原观察台说明](FRAME1_EXPLORER.zh-CN.md)。全帧实际数据均保留，长区域的星座绘图抽样不改变导出CSV。

## 数据来源与解释边界

输入为已有`runs/allocation-upgrade-20261103/nine_frames/frame_01`至`frame_09`中各自的`protocol.mat`和`protocol_summary.json`。原始IQ来自UT Austin Radionavigation Laboratory的公开`exemplar250-257`采集，原BIN SHA-256为`c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3`。下载来源、论文及许可说明见[资源检索](PAPER_2610_29387_SOURCES.zh-CN.md)、[接收机README](../README.md)和[资源分配实测](RESOURCE_ALLOCATION_VALIDATION.zh-CN.md)。未混入另一份作者公开的1009帧数据。

页面按float32保存源MAT中的双精度复数，manifest逐帧记录最大分量误差和所有输入SHA。左图使用FIT导频相位/斜率校准后、去固定PN前的观测；右图使用同一网格去PN后的观测。SSS继续使用原SSS列。

本版沿用原汇报阶段的头部、几何分配和Code5展示。高阶区域着色使用已有条件资源解释；不能从颜色本身推断独立调制分类正确，也不能仅凭CRC推出每单位Q。后续MCS66/70的编码关系恢复与FEC验证见[独立交互教程](MCS66_LDPC_WALKTHROUGH.html)及其[范围说明](CODING_WALKTHROUGH.zh-CN.md)。这里的几何点编号不等于发射位标签或业务明文。

## 内存与文件组织

整个viewer约67.3MiB，9个帧页面各约7.5MiB，共享一份CSS和JS。切换使用文档替换，只解码当前帧的数组；旧页面的对象由浏览器回收，未承诺具体回收时刻或进程峰值。打开页面不会运行DSP、MATLAB或一次性载入9帧数组。

```text
viewer/
  explorer.html               第1帧 / 总入口
  assets/
    multiframe_explorer.css
    multiframe_explorer.js
  frames/
    frame-02.html ... frame-09.html
  manifest.json               输入、源码与输出文件SHA及逐帧核对
  README.zh-CN.md
```

HTML含真实接收数组，保留为本机产物，不纳入Git。Git提供生成器、模板、说明与精简验证证据；只克隆代码仓库不会自动得到已有的九份大型接收检查点。

## 从已有九帧检查点重建

需要Python3.10+、NumPy与h5py。无需重新运行MATLAB。先按[协议接收机说明](../matlab/protocol_receiver/README.zh-CN.md)及[资源分配说明](RESOURCE_ALLOCATION_TEACHING.zh-CN.md)准备兼容的真实接收检查点。

在仓库根目录运行：

```powershell
python -m pip install numpy h5py
python tools/build_multiframe_explorer.py --source-root runs/allocation-upgrade-20261103/nine_frames --output runs/my-nine-frame-viewer
Start-Process runs/my-nine-frame-viewer/explorer.html
```

输出默认要求新目录；只允许对已有同schema的生成目录显式使用`--refresh`。它不会覆盖原单帧观察台。若依赖已安装到其他目录，可加`--deps <目录>`。该入口要求当前采集完整连续的frame_01～09，拒绝帧数不全的目录。

新增源码是`tools/build_multiframe_explorer.py`、`tools/multiframe_explorer.html`、`tools/multiframe_explorer.css`及`tools/multiframe_explorer.js`。生成器只复用冻结的旧`build_frame_explorer.py`中SHA、CRC、BCC和候选星座辅助函数，不修改旧生成器及旧模板。

## 实测检查

[机器验证摘要](../provenance/multiframe_explorer_validation.json)记录本次范围与SHA：

- 9帧共2710800个非导频资源：检查全部资源展开顺序、分配掩码及条件理想值；18组CRC与所有头部BCC块重新核算。
- 独立从最终HTML解码数组，与源MAT转为float32后逐值比较：11096064个网格实/虚分量全部一致；3组资源属性共8132400项全部一致。
- Chrome以本地file路径实际连续切换1～9帧；核对每帧头部快捷范围、CRC资源定位、MCS区域、尾部、SSS、隐藏图例和PN模长；验证保留坐标、取消保留、下拉切帧及首末页按钮。
- 浏览器实际导出9份CSV及9份摘要，再核对216行CRC输出资源及63个额外采样位置的原坐标I/Q与来源。
- 检查第3帧5块头部和第9帧3个Code5字；检查同编号颜色跨帧一致；查看桌面与320/390px窄屏截图，无页面横向溢出、脚本异常或外部HTTP请求。
- 原单帧HTML、四份冻结源码、64个受保护文件和原始IQ哈希不变；接收算法、MATLAB、配置、模型和评价门限未变。本次验证针对导出与交互，没有新增DSP实测。
