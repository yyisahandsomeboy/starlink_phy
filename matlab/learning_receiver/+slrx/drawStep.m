function drawStep(cfg, key, kind, data)
%DRAWSTEP 只负责展示已算出的变量，不修改IQ、网格、分类或估计参数。
% key决定文件名；kind对应学习步骤。重复的第二轮用相同画法但不同文件名。
% 每张图只表达同一项物理量；信道幅度/相位、相位/时延、PSS/SSS分开。

if cfg.show_figures, visibility='on'; else, visibility='off'; end
folder = fullfile(cfg.run_dir,'figures');
if ~exist(folder,'dir'),mkdir(folder);end
switch kind
    case 1
        fig = makeFigure(visibility);
        n = min(5000,numel(data.iq));
        plot((0:n-1)/data.fs_hz*1e6,real(data.iq(1:n)), ...
            (0:n-1)/data.fs_hz*1e6,imag(data.iq(1:n)));
        xlabel('窗口内时间 / us');ylabel('归一化幅度');legend('I','Q');title('输入IQ短窗口');
        store(fig,folder,[key '_iq.png'],cfg);
        fig = makeFigure(visibility);
        plot(data.psd_frequency_hz/1e6,10*log10(data.psd_linear));
        xlabel('相对中心频率 / MHz');ylabel('PSD / dB/Hz');title('输入频谱');
        store(fig,folder,[key '_psd.png'],cfg);
    case 2
        fig = makeFigure(visibility);
        plot(real(data.iq(1:min(5000,end))));
        xlabel('240Msps窗口内采样点');ylabel('I分量');title('名义重采样后的时域信号');
        store(fig,folder,[key '.png'],cfg);
    case 3
        names = {'pss','sss'};
        for k=1:2
            fig = makeFigure(visibility);
            curve = data.selected.sync_local_curve;
            plot(curve.lag_model_samples,curve.(names{k}),'o-');
            xlabel('相对检测起点 / 模型采样');ylabel('归一化相关幅度');
            title([upper(names{k}) '局部相关峰']);
            store(fig,folder,[key '_' names{k} '.png'],cfg);
        end
    case 4
        fig = makeFigure(visibility);
        n=min(2112,numel(data.time_raw));
        plot(real(data.time_raw(1:n)));hold on;plot(real(data.time_cfo_compensated(1:n)));
        xlabel('帧内模型采样');ylabel('I分量');legend('CFO前','CFO后');title('帧首PSS/SSS的频偏补偿');
        store(fig,folder,[key '.png'],cfg);
    case 5
        fig = makeFigure(visibility);
        plot(1:size(data.without_cp,2),abs(data.cp_correlation));
        xlabel('网格列，1为SSS');ylabel('CP与符号尾部相关幅度');title('CP复制关系的观测');
        store(fig,folder,[key '.png'],cfg);
    case 6
        fig = makeFigure(visibility);
        imagesc(1:size(data.values,2),fftshift(data.frequency_hz)/1e6,20*log10(max(abs(fftshift(data.values,1)),1e-12)));
        axis xy;colorbar;xlabel('网格列，1为SSS');ylabel('相对中心频率 / MHz');title('FFT网格幅度，shift仅用于显示');
        store(fig,folder,[key '.png'],cfg);
    case 7
        [frequency,order]=sort(data.frequency_bins);
        fig = makeFigure(visibility);plot(frequency,abs(data.H(order)));
        xlabel('有符号FFT bin');ylabel('|H|');title('SSS估计的信道幅度');
        store(fig,folder,[key '_amplitude.png'],cfg);
        fig = makeFigure(visibility);plot(frequency,unwrap(angle(data.H(order))));
        xlabel('有符号FFT bin');ylabel('相位 / rad');title('SSS估计的信道相位');
        store(fig,folder,[key '_phase.png'],cfg);
    case 8
        fig = makeFigure(visibility);
        c=cfg.display_data_column+1;rows=setdiff((3:1022)',[489:496 529:536]');z=data.values(rows,c);
        plot(real(z),imag(z),'.');axis equal;xlabel('I');ylabel('Q');title(sprintf('均衡后：数据列%d，尚未完成跟踪',c-1));
        store(fig,folder,[key '.png'],cfg);
    case 9
        fig = makeFigure(visibility);plot(data.raw_phase_rad);hold on;plot(data.line_phase_rad);
        xlabel('数据OFDM列');ylabel('相位 / rad');legend('导频原始初值','线性预览');title('FIT导频给出的相位观测');
        store(fig,folder,[key '.png'],cfg);
    case 10
        fig = makeFigure(visibility);imagesc(1:300,1:4,data.scores);yticks(1:4);yticklabels({'4','8','16','32'});colorbar;
        xlabel('数据OFDM列');ylabel('候选点数K');title('MSS轮廓得分：点数还不等于位映射');
        store(fig,folder,[key '.png'],cfg);
    case 11
        fig=makeFigure(visibility);plot(data.ml_phase_unwrapped_rad,'.');hold on;plot(data.phase_line_rad);
        xlabel('数据OFDM列');ylabel('相位 / rad');legend('逐列ML','整帧拟合');title('残余相位与整帧趋势');
        store(fig,folder,[key '_phase.png'],cfg);
        fig=makeFigure(visibility);plot(data.ml_delay_samples,'.');hold on;plot(data.delay_line_samples);
        xlabel('数据OFDM列');ylabel('时延 / 模型采样');legend('逐列ML','整帧拟合');title('残余时延与整帧趋势');
        store(fig,folder,[key '_delay.png'],cfg);
    case 14
        fig=makeFigure(visibility);c=cfg.display_data_column;z=data.received(:,c);
        plot(real(z),imag(z),'.');hold on;plot(real(data.hard_symbols_observed_scale(:,c)),imag(data.hard_symbols_observed_scale(:,c)),'ro');
        axis equal;xlabel('I');ylabel('Q');legend('实际接收点','最近理想点');title(sprintf('数据列%d的条件符号判决，不是业务比特',c));
        store(fig,folder,[key '.png'],cfg);
    case 15
        fig=makeFigure(visibility);plot(abs(data.samples));xlabel('预测保护区内的原采样序号');ylabel('|IQ|');
        title('模型预测保护区的实测幅度，未独立检测噪声边缘');
        store(fig,folder,[key '.png'],cfg);
end
end

function fig = makeFigure(visibility)
%MAKEFIGURE 新建学习图；不关闭用户的其他figure。
fig=figure('Visible',visibility,'Color','w','Position',[50 50 1050 650]);
set(gca,'FontName','Noto Sans CJK SC');grid on;
end

function store(fig, folder, filename, cfg)
%STORE 保存PNG。批处理时关闭本图；交互模式保留窗口供检查。
exportgraphics(fig,fullfile(folder,filename),'Resolution',120);
if ~cfg.show_figures,close(fig);end
end
