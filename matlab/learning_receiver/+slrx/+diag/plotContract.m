function note = plotContract(key,data)
%PLOTCONTRACT 主线每幅图都附六项可追溯说明；不额外运行接收算法。
step=slrx.diag.stepInfo(key);
note=struct('purpose',['理解' step.name '真正改变的量及保留量'], ...
    'data_source',[key '.mat:data / ' step.output_variable], ...
    'calculation',step.formula,'focus','区分原始观测、施加的操作、已有估计与独立验证。', ...
    'current_result',jsonencode(data.summary),'limitations',step.limitations);
if contains(key,'frame_time')
    note.purpose='观察复数旋转与模长不变；分别诊断参考相位和后续留出质量';
    note.calculation='t=(saved_positions-start)/Fs; a=-2*pi*f*t; z_after=z_before*exp(1j*a)';
    note.focus='参考PSS/SSS参与原估计，不能当独立证据；EVAL仅在后续可用时显示。';
elseif strcmp(key,'02_resampled')
    note.focus='N/Fs、同时间网格、原FIR频响、去DC前后均值；波形波动不是成功指标。';
elseif contains(key,'tracking')
    note.focus='逐列估计、内点/拒绝点、已有拟合、拟合残差和留出EVAL分别解释。';
end
end
