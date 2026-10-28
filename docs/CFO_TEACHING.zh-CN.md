# CFO教学：旋转、参考诊断和独立观测

本轮默认CFO图替换了2112点I分量叠加图。它显示两份实际IQ向量、真实时间轴上的累计施加角、PSS/SSS各自参考相位，以及后续留出EVAL指标的适用边界。

## 1. 统一相位符号，避免双负号

直接使用接收机实际保存的取样位置：

$$
t_n=\frac{\mathrm{sample\_positions\_nominal}[n]-\mathrm{sample\_position\_start}}{F_\mathrm{model}}.
$$

这里包含 `n/(1+SFO·10⁻⁶)` 的取样调整，不把每个位置假设成整数编号。定义误差相位参数 `theta=2*pi*f*t`、实际施加角 `a=-theta`：

$$
z_\mathrm{after}=z_\mathrm{before}e^{ja}=z_\mathrm{before}e^{-j\theta}.
$$

因此：

$$
I_\mathrm{after}=I\cos\theta+Q\sin\theta,\quad
Q_\mathrm{after}=Q\cos\theta-I\sin\theta.
$$

当估计CFO为负，施加角a随时间增加，向量逆时针旋转；当CFO为正则顺时针。不要再对已带负号的a使用 `exp(-j*a)`，否则方向反了。

## 2. 默认六面板怎样阅读

| 面板 | 目的与来源 | 当前能够判断的事情 |
|---|---|---|
| 两个复平面向量示例 | PSS和SSS有效区中点附近的实际非零IQ；选择位置固定，不按点云美观筛选 | 同一采样的补偿前后向量、采样编号/时间、累计施加角、主值夹角和模长 |
| 累计施加角 | 保存位置与实际CFO计算a，显示首末值、方向和每点增量 | 算法确实施加了什么操作；不能证明估计值正确 |
| PSS参考相位 | 逐块 `sum(z*conj(p))` 的相位、分族展开与共享斜率拟合 | 在模型适用条件下的剩余相位趋势；参与原估计的同参考诊断 |
| SSS参考相位 | 单独对SSS有效区分块，不拼接PSS/CP相位 | 比较另一个结构的相位趋势；不强制与PSS斜率相同 |
| 证据与限制 | 模长/运算一致性误差、原CFO、参考假设、可用的后续EVAL | 区分数学恒等式、训练参考诊断和留出验证；本步未运行FFT时明确缺失 |

向量弧线只画模2π后的主值夹角；标题同时保存累计a，不能把多转一周误认为没补偿。模长相对误差和运算相对误差来自实际数组比较，不用一条理论曲线代替数据。

## 3. 为什么参考分块必须重做

PSS和SSS各有1056点时隙，前32点为CP/结构前缀。旧版把2112点直接每64点切块，1056不是64的整数倍，会跨越PSS/SSS边界，也把CP混入同一参考趋势。

现在分别使用有效区：PSS帧内一基33..1056、SSS一基1089..2112，各形成16个64点块。块不跨CP、PSS和SSS边界。

PSS具有128点重复结构；64点块在重复结构内存在两种位置。为减轻频率选择性信道造成的固定半块相位差，PSS分为两族：各自展开相位，各有截距，共享时间斜率。SSS独立拟合，不把两个结构的固定信道相位强行连成一条线。

块中心时间按已知参考能量加权。前后拟合使用相同有效块与相同权重（取前后块相干度的较小值），避免因筛选不同制造改善。参考块相干度定义为：

$$
\rho=\frac{|\sum z_n p_n^*|}{\sqrt{\sum|z_n|^2\sum|p_n|^2}}.
$$

诊断门限为块相干度至少0.2、总计至少6块、每族至少3块、没有跨缺失块展开、加权去趋势相位RMS不超过0.35 rad。这些只决定斜率代理的显示状态，不改变同步或接收门限。

拟合得到 `slope/(2*pi)` 的Hz量，称为**相位斜率代理**。它需要参考信道在该短窗内近似稳定、相位展开无混叠等假设。PSS分族间隔约128/Fs，对应约±937.5kHz的无混叠范围；SSS64点块约±1.875MHz。实际精确范围保存在诊断字段中。近似线性拟合和门限通过不能验证所有物理假设。

多径、噪声、参考幅度和结构差异会影响斜率。真实PSS与SSS代理不必相同，报告保留差异，不将其中一个直接宣称为真实剩余频偏。去掉线性项后的拟合残差也可能基本不变；不能要求补偿后必须降低来证明算法有效。

## 4. 哪些证据独立，哪些不独立

| 观测 | 证据性质 | 不能推断的结论 |
|---|---|---|
| 模长不变、实际z乘exp(ja)一致 | 运算恒等式检查 | 估计CFO正确 |
| 施加角是一条线 | 已采用参数的操作说明 | 真实频偏误差很小 |
| PSS/SSS相关、参考相位趋势 | 同参考诊断：这些序列参与原CFO估计 | 完全独立验证、真实误差置信区间 |
| 后续EVAL导频EVM | EVAL没有参与同步与ML拟合，支持这些留出资源的质量检查 | 改善全部来自CFO，或未知业务比特已正确 |
| FFT→均衡→跟踪的EVM对照 | 同轮同资源、明确标定约定的处理链比较 | 只开关CFO而其余条件完全相同的因果实验 |

当前MAT没有保存“补偿前但同取样/同信道/同流程”的FFT分支。本轮没有为了画指标而另改DSP顺序，因此 `cfo_only_EVM_available=false`。ICI单独验证、真实卫星/本振频偏分离及业务BER仍不可用。

## 5. 如何运行和调试

```matlab
open('matlab/learning_receiver/START_HERE.m')
```

按节运行，第4步即显示新CFO图；第13a步显示第二轮实际补偿。此前尚未计算的EVAL在图中标为不可用，不提前执行FFT。主线通过可选绘图上下文传递已有变量，`slrx.step`返回的数据结构和算法调用保持原样。

对已有完整MAT独立生成报告：

```matlab
addpath('matlab/learning_receiver')
r = RUN_DIAGNOSTICS(runDir, 'CFORound', 1);
% 不指定CFORound时静态图默认展示最后可用轮次。
% ShowFigures=true时，可在CFO图自己的下拉框切换轮次。
r = RUN_DIAGNOSTICS(runDir, 'ShowFigures', true);
```

旧密集图只在明确调试时生成：

```matlab
r = RUN_DIAGNOSTICS(runDir, 'DebugPlots', true);
% 主线的显示开关：在建立新学习配置时设lesson_cfg.debug_plots=true。
```

输出位于报告目录的 `debug/` 或主线 `figures/debug/`。原始时域散点仍明确标注“非子载波调制星座”。不要在旧代码指纹的目录恢复执行新代码；旧MAT可以只读重画，新接收使用新目录。

## 6. 代码与数据来源

- [cfoMetrics.m](../matlab/learning_receiver/+slrx/+diag/cfoMetrics.m)：实际时间轴、运算不变量、选点、分结构参考、条件斜率代理与证据边界。
- [plotCFO.m](../matlab/learning_receiver/+slrx/+viz/plotCFO.m)：共享默认视图和轮次选择，主线与独立报告均复用。
- [resampleMetrics.m](../matlab/learning_receiver/+slrx/+diag/resampleMetrics.m)：只读采样率/时长、PSD/FIR/DC诊断。
- [plotTracking.m](../matlab/learning_receiver/+slrx/+viz/plotTracking.m)：直接展示原有ML残差、内点与EVAL，不重拟合。
- [test_observability.m](../matlab/learning_receiver/tests/test_observability.m)：CFO正负号、非整数SFO时间、结构边界、零信号门限、真实旧MAT及默认/debug输出。

全流程逐图审查见[观测量审计](OBSERVABILITY_AUDIT.zh-CN.md)，实际运行与数值回归见[验证记录](OBSERVABILITY_VALIDATION.zh-CN.md)。
