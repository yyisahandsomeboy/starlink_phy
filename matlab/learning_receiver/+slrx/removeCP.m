function ofdmTime = removeCP(frameTime, cfg)
%REMOVECP 第5步：把连续帧分成符号，PSS单列保留，普通OFDM去32点CP。
% 输入长度302*1056。输出without_cp为1024×301，第一列对应SSS。
% PSS的特殊重复/反号结构不在这里按普通OFDM解释。
% cp_correlation比较普通OFDM前32点和有效符号末32点，仅作诊断。

symbolLength = cfg.nfft + cfg.cp_length;
blocks = reshape(frameTime.time_cfo_compensated, symbolLength, cfg.frame_symbol_count);
ofdmTime.pss_time = blocks(:,1);
ofdmTime.cp_samples = blocks(1:cfg.cp_length,2:end);
ofdmTime.without_cp = blocks(cfg.cp_length+1:end,2:end);
tail = blocks(end-cfg.cp_length+1:end,2:end);
cp = ofdmTime.cp_samples;
ofdmTime.cp_correlation = sum(tail.*conj(cp),1) ./ ...
    max(sqrt(sum(abs(tail).^2,1).*sum(abs(cp).^2,1)),eps);
ofdmTime.summary = struct('without_cp_size',size(ofdmTime.without_cp), ...
    'cp_size',size(cp),'mean_abs_cp_correlation',mean(abs(ofdmTime.cp_correlation)));
end
