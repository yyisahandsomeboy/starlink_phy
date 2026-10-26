function pilots = observePilots(equalized, refs, cfg)
%OBSERVEPILOTS 第9步：从FIT导频看残余相位/时延，并给ML提供初值。
% 左右导频相位的差表示频率方向的斜率，共同部分表示整体旋转。
% raw_*是每列原始导频初值；line_*是跨列线性拟合，仅用于预览/质量观察。
% ML采用raw_*，不要误把平滑预览当成最终未知数据ML结果。

ratio = equalized.values(refs.fit_rows,2:301)./refs.pilots(refs.fit_rows,2:301);
left = unwrap(angle(mean(ratio(1:4,:),1)));
right = unwrap(angle(mean(ratio(5:8,:),1)));
leftBin = mean(refs.frequency_bins(refs.fit_rows(1:4)));
rightBin = mean(refs.frequency_bins(refs.fit_rows(5:8)));
slope = (right-left)/(rightBin-leftBin);
pilots.raw_phase_rad = (left*rightBin-right*leftBin)/(rightBin-leftBin);
pilots.raw_delay_samples = -slope*cfg.nfft/(2*pi);
columns = 1:cfg.data_column_count;
leftLine = polyval(polyfit(columns,left,1),columns);
rightLine = polyval(polyfit(columns,right,1),columns);
lineSlope = (rightLine-leftLine)/(rightBin-leftBin);
pilots.line_phase_rad = (leftLine*rightBin-rightLine*leftBin)/(rightBin-leftBin);
pilots.line_delay_samples = -lineSlope*cfg.nfft/(2*pi);
pilots.preview_grid = equalized.values;
pilots.preview_grid(:,2:301) = equalized.values(:,2:301).*exp(-1j*( ...
    refs.frequency_bins*lineSlope+ones(cfg.nfft,1)*pilots.line_phase_rad));
pilots.fit_evm = sqrt(mean(abs(pilots.preview_grid(refs.fit_rows,2:301)-refs.pilots(refs.fit_rows,2:301)).^2,'all'));
pilots.summary = struct('fit_rows',refs.fit_rows,'eval_rows_not_fitted',refs.eval_rows, ...
    'fit_evm_after_pilot_preview',pilots.fit_evm,'delay_unit','240Msps model samples');
end
