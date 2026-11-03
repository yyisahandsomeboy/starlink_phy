%% 16. 去掉PN四相位参考：已校准网格 → 相同资源上的BPSK观测
% 先完成START_HERE第14步。这里保留原finalGrid，不把理想符号写回接收机。
assert(exist('finalGrid','var')==1&&exist('refs','var')==1,'请先运行START_HERE至第14步');
addpath(fullfile(lesson_cfg.project_root,'matlab','protocol_receiver'));
protocol_opt=slproto.defaultOptions();protocol_opt.make_plots=lesson_cfg.make_plots;
protocol_opt.show_figures=lesson_cfg.show_figures;
[protocol_calibrated,protocol_calibration]=slproto.calibrateGrid(finalGrid.values,refs.pilots);
[protocol_reference,protocol_pn]=slproto.pnReference(protocol_opt.pn_model);
protocol_derotated=protocol_calibrated.*conj(protocol_reference);
protocol_coordinates=slproto.coordinates();
protocol_payload=protocol_derotated(protocol_coordinates.payload_rows,2:301);
protocol_stream=protocol_payload(:); % 先物理频率升序，再沿时隙排列；不把FFT行序当序列
if lesson_cfg.stop_after<=16,return;end

%% 17. 114位BCC块 → 32位字+六零尾 → 整组CRC → 条件字段
% findHeaders与完整接收机共用。第二组由短前缀提议，整组CRC和尾状态再核验。
protocol_headers=slproto.findHeaders(protocol_stream,protocol_opt);
disp(protocol_headers.first.words_hex);
fprintf('第一组CRC=%d；第二组唯一=%d\n',protocol_headers.first.crc_pass,protocol_headers.second_unique);
if lesson_cfg.stop_after<=17,return;end

%% 18. Code5条件分配：固定稀疏H/P、软译码及奇偶位重调制对照
% 只识别第一组已验证的code5；其他格式编号保留，不按点云外观强行译码。
protocol_code5=slproto.analyzeCode5(protocol_stream,protocol_headers,protocol_opt);
protocol_result=slproto.finishFrame(finalGrid.values,protocol_calibrated,protocol_reference, ...
    protocol_calibration,protocol_pn,protocol_headers,protocol_code5,protocol_opt);
protocol_out=fullfile(lesson_cfg.run_dir,['protocol-teaching-' char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'))]);
protocol_source=struct('checkpoint',fullfile(lesson_cfg.run_dir,'13h_tracking.mat'), ...
    'sha256',slrx.sha256(fullfile(lesson_cfg.run_dir,'13h_tracking.mat')),'frame_index',lesson_cfg.frame_rank,'raw_BIN_reads',0);
protocol_report=slproto.exportFrame(protocol_result,protocol_out,protocol_source);
fprintf('PN/PDU/Code5教学报告：%s\n',fullfile(protocol_out,'index.html'));
% protocol_code5.words.information_bits是条件编码器输入，不是已恢复的网络明文。
