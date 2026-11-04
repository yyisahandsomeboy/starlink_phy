# 第一帧离线交互观察台（2026-11-04）

本页由真实 `pdu-receiver-v2` 第一帧检查点导出，可叠加v3的编号66验证摘要，身份 `codex_baseline`。交付是一个约7.52 MiB的HTML文件，数据、样式、Canvas绘图和交互代码全部内嵌，不需要服务器、网络、MATLAB或浏览器插件。按用户要求在Windows宿主机打开。

本机文件：最新版 `F:/codex_storage/frame_explorer_20261104/output-mcs66-v3/explorer.html`。旧 `output/explorer.html` 与 `runs/frame1-interactive-20261104/explorer.html` 保留为升级前展示。这些均为本机产物，克隆Git仓库不会自带。

## 建议按这个顺序看

1. **全帧资源网格**：默认显示数据OFDM列2～301，1024×300格。点一下选资源，拖拽框选放大，双击恢复全帧；也可以输入精确列/bin范围。点击图例可以隐藏/恢复某区域。可选加入SSS列1，变为1024×301。
2. **首配置头 / 第二配置头**：快捷按钮放大头部并选取该头部的全部228/456个实际资源。去PN前后使用同一批接收点、相同坐标尺度，可以看到参考相位去除后的二值结构。
3. **混合列208**：查看同列的708个候选16QAM资源及296个候选交叉32点资源。颜色来自头部与候选长度表的分配，不能把着色本身当成独立分类证据。
4. **配置头位图**：切换PDU头1/2。每行是一个32位保留字，按前缀、MCS index、MCS length、零区、CRC着色；点击某位，定位该输入时刻对应的3个BCC输出资源。可展开查看每块114个编码位及18个归零尾输出。
5. **CRC定位**：首头部接收/重算均为0xAD，第二头部均为0x0D。CRC8的8个输入时刻对应24个BCC输出资源。首头部为r0=186…209；第二头部为8834…8857。输出还依赖前6个输入位，颜色表示编码时间来源，不表示字段直接以3份副本发送。
6. **MCS表**：查看每项index、数量C、每单位Q、C×Q资源数及零基右端开区间。点击“定位”联动网格与区域星座。首头部Code5为4×2048=8192资源；第二头部的5项为(57,1)、(66,39)、(70,9)、(71,1)、(85,27)。
7. **113资源边界分歧**：比较列208/q595与q708，即r0=207419与207532。按钮放大该区域。阴影含分歧位置及附近资源，不能据此计算实际误码数。
8. **Code5/66状态与CSV**：新增编号66的N16384/K12288、3/4与本帧39字全部通过、每字前3072/后1024资源坐标和区域定位。Code5仍可逐字查看校验、修改数和奇偶重调制NMSE；导出当前所选的全部资源，包含原坐标I/Q、区域、边界标记和条件几何索引。

## 坐标和显示约定

- OFDM列沿用MATLAB列号：1=SSS，2～301=300个数据列。旧页面的“数据符号1”对应这里的列2。
- y轴采用有符号FFT bin −512…511；每列包含1004个非导频资源、16个导频及4个未加载bin。导频和未加载bin单独显示，不混入载荷星座。
- q0是非导频资源按物理频率升序排列的0…1003编号，不等于bin；r0=1004×(col−2)+q0。头部分配区间采用[start,end)。
- PSS属于时域同步段，不在本次频域检查点内，帧结构条明确说明；SSS使用真实列1，显示时不施加载荷PN去旋转。
- 左图为最终网格经FIT导频相位/斜率校准后的去PN前观测，右图为相同点去固定PN后的观测。默认两图均除以同一列FIT导频增益；可关闭增益归一化。跨列未归一化时，不叠加一个统一幅度的理想点参考。
- 单列及头部展示全部资源；长区域最多显示12000个确定性抽样点，界面同时注明绘图数与总数。CSV导出所选范围的全部资源，不采用绘图抽样，且输出未作显示增益归一化的原坐标。
- 可切换右图到“条件几何判决后的理想点”；该显示独立于原始观测，不会写回源数据。几何点编号只是字母表枚举；66另有经过FEC验证的独立4位标签，不能混同。

## 数值来源与限制

输入：`runs/allocation-upgrade-20261103/nine_frames/frame_01/protocol.mat`及同目录`protocol_summary.json`，来自同一UT Austin公开采集。导出器以SHA-256校验只读来源，核对完整301200资源的展开顺序和全部几何索引对应的理想值，并独立核算两组CRC和每块BCC重新编码。

页面以float32保存复数值，以减少文件大小。与源双精度相比，最大实/虚分量绝对误差约1.052e−7；原MAT仍保留双精度。原网格、译码器、冻结评价和门限均不修改。

这是一帧既有数据的交互展示，不是新采集验证。第一帧边界偏差、条件20位布局、候选高阶资源长度以及其余未确认的位映射/FEC均保留。66的本次恢复与反例见[验证报告](MCS66_RECOVERY_VALIDATION.zh-CN.md)。CRC通过支持头部位内容；完整业务明文仍未恢复。详见[资源分配原理](RESOURCE_ALLOCATION_TEACHING.zh-CN.md)与[接收机验证](RESOURCE_ALLOCATION_VALIDATION.zh-CN.md)。

## 从已有检查点重新生成

生成器采用Python序列化已保存数据，不重新执行DSP。需要Python3.10+、NumPy与h5py；打开生成的HTML不需要这些依赖。

```powershell
python -m pip install numpy h5py
python tools/build_frame_explorer.py --input runs/allocation-upgrade-20261103/nine_frames/frame_01/protocol.mat --output runs/my-frame1-explorer
Start-Process runs/my-frame1-explorer/explorer.html
```

输出目录必须全新，生成器拒绝覆盖。当前模板针对已验证的第一帧ID序列，遇到其他帧或不同配置会拒绝，不默默套用颜色与固定快捷位置。要从原始IQ开始，请先按根README运行接收机和协议分析，生成对应MAT；原始数据和大MAT未纳入Git。

源码为`tools/build_frame_explorer.py`及`tools/frame_explorer.{html,css,js}`。生成器将模板、样式和脚本内嵌成单文件。`manifest.json`记录来源与生成文件SHA；可提交的精简实测见[frame_explorer_validation.json](../provenance/frame_explorer_validation.json)。生成HTML包含接收数据，作为本机产物保留，不随源码提交。

## 叠加编号66验证

先按[恢复报告](MCS66_RECOVERY_VALIDATION.zh-CN.md)用`RUN_MCS66_ANALYSIS`生成摘要，再运行：

```powershell
python tools/build_frame_explorer.py --input runs/allocation-upgrade-20261103/nine_frames/frame_01/protocol.mat --mcs66 runs/my-mcs66-frame1/mcs66_summary.json --output runs/my-frame1-with-mcs66
```

来源MAT的SHA必须相同，且全部码字收敛并重编码一致，生成器才显示已验证状态；不匹配时拒绝合并。直接从含`result.mcs66`和匹配协议摘要的v3检查点生成时不必另传摘要。浏览器文件不修改原MAT。
