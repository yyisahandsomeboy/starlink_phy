function value = coordinates(mode, input, cfg)
%COORDINATES 诊断唯一坐标换算入口；不另加resample已补偿的FIR标称延迟。
% 原文件/模型均为连续一基复采样坐标；时间零点为文件第1份复采样。
switch mode
    case 'model_to_capture'
        value = cfg.first_complex_sample + (input-1)*cfg.capture_fs_hz/cfg.model_fs_hz;
    case 'capture_to_model'
        value = 1 + (input-cfg.first_complex_sample)*cfg.model_fs_hz/cfg.capture_fs_hz;
    case 'capture_to_ms'
        value = (input-1)/cfg.capture_fs_hz*1e3;
    case 'model_to_ms'
        raw = slrx.diag.coordinates('model_to_capture',input,cfg);
        value = slrx.diag.coordinates('capture_to_ms',raw,cfg);
    case 'bin_to_mhz'
        value = input*cfg.model_fs_hz/cfg.nfft/1e6;
    otherwise
        error('slrx:DiagnosticCoordinate','未知坐标模式：%s',mode);
end
end
