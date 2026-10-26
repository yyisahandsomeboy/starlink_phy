function grid = fftGrid(ofdmTime, refs, cfg)
%FFTGRID 第6步：每个普通OFDM列作FFT，把时间采样变成子载波网格。
% Y=fft(x)/sqrt(N)，与旧接收机的/32相同。矩阵不fftshift；显示时才shift。
% grid.values：1024×301；行是原FFT行，列1是SSS、列2:301为数据。

grid.values = fft(ofdmTime.without_cp,[],1)/sqrt(cfg.nfft);
grid.frequency_bins = refs.frequency_bins;
grid.frequency_hz = refs.frequency_bins*cfg.model_fs_hz/cfg.nfft;
grid.summary = struct('grid_size',size(grid.values),'FFT_normalization','1/sqrt(N)', ...
    'first_column','SSS','data_columns',cfg.data_column_count,'fftshift_applied',false);
end
