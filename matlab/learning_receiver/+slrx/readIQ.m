function capture = readIQ(cfg)
%READIQ 第1步：把文件中的交织整数转换成复数IQ，并检查输入质量。
% 文件顺序 I0,Q0,I1,Q1...；每复采样4字节。/32768仅改变幅度单位。
% 输出 iq 为复列向量；first_complex_sample 是该窗口在原BIN中的位置。
% 本步不找帧头。默认4ms只是分析窗口，帧头要由下一阶段独立检测。

fid = fopen(cfg.input_file, 'r', 'ieee-le');
assert(fid >= 0, '无法打开原始IQ文件');
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
status = fseek(fid, 4*(cfg.first_complex_sample-1), 'bof');
assert(status == 0, '无法移动到指定复采样位置');
requested = round(cfg.read_duration_s * cfg.capture_fs_hz);
components = fread(fid, [2 requested], 'int16=>double');
assert(size(components, 2) == requested, '读取窗口超出原始文件，不能补零冒充采集');
iq = complex(components(1,:), components(2,:)).' / 32768;
capture.iq = iq;
capture.fs_hz = cfg.capture_fs_hz;
capture.first_complex_sample = cfg.first_complex_sample;
capture.duration_s = numel(iq) / capture.fs_hz;
capture.rms = sqrt(mean(abs(iq).^2));
capture.dc = mean(iq);
capture.clipped_fraction = mean(abs(real(iq)) >= 32767/32768 | abs(imag(iq)) >= 32767/32768);
% PSD只使用本窗口，pwelch的频率单位为Hz，不是12GHz射频载波。
[capture.psd_linear, capture.psd_frequency_hz] = pwelch(iq, hann(4096), 2048, 8192, capture.fs_hz, 'centered');
capture.summary = struct('complex_samples', numel(iq), 'duration_s', capture.duration_s, ...
    'fs_hz', capture.fs_hz, 'rms', capture.rms, 'clipped_fraction', capture.clipped_fraction);
end
