function drawStep(cfg,key,kind,data,context)
%DRAWSTEP 共用只读诊断视图；默认移除密集I叠加，debug显式另存。
% 第12步仅保存CFO/SFO更新数值，沿用原流程不单独生成重复图片。
if ismember(kind,[0 12]),return;end
if nargin<5,context=struct();end
context.cfg=cfg;if ~isfield(context,'refs'),context.refs=slrx.references(cfg);end
options=slrx.diag.plotOptions(cfg);pass=1;if startsWith(key,'13'),pass=2;end
options.rounds_to_show=pass;fig=[];names={};
switch kind
    case 1
        context.capture=data;fig=slrx.viz.plotCapture(context,options);names={[key '.png']};
    case 2
        context.sampled=data;fig=slrx.viz.plotResampling(context,options);names={[key '.png']};
    case 3
        context.sync=data;
        figs={slrx.viz.plotGlobalSync(data,cfg,cfg.show_figures),slrx.viz.plotLocalSync(data,cfg,cfg.show_figures)};
        names={[key '_global.png'],[key '_local.png']};
    case 4
        context.(sprintf('time%d',pass))=data;options.cfo_round=pass;
        fig=slrx.viz.plotCFO(context,options);names={[key '.png']};
    case 5
        context.(sprintf('ofdm%d',pass))=data;
        if isfield(context,sprintf('time%d',pass))
            fig=slrx.viz.plotCP(context,options);
        else
            % 兼容旧四参数调用；缺少取帧数据时不补造“补偿前CP”。
            fig=slrx.viz.newFigure('CP逐符号相关（缺少取帧上下文）',cfg.show_figures);ax=axes(fig);
            plot(ax,1:numel(data.cp_correlation),abs(data.cp_correlation),'.');grid(ax,'on');
            xlabel(ax,'FFT网格列：1=SSS');ylabel(ax,'|CP复相关|');title(ax,'仅有保存的CP相关；完整复制对照需提供time上下文');
        end
        names={[key '.png']};
    case 6
        context.(sprintf('fft%d',pass))=data;fig=slrx.viz.plotFFTGrid(context,options);names={[key '.png']};
    case 7
        context.(sprintf('channel%d',pass))=data;fig=slrx.viz.plotChannel(context,options);names={[key '.png']};
    case 8
        context.(sprintf('eq%d',pass))=data;options.stage_indices=(pass-1)*3+(1:2);
        fig=slrx.viz.plotConstellationStages(context,options);names={[key '.png']};
    case 9
        fig=slrx.viz.plotPilotFit(data,cfg);names={[key '.png']};
    case 10
        fig=slrx.viz.plotCardinality(data,cfg);names={[key '.png']};
    case 11
        context.(sprintf('track%d',pass))=data;fig=slrx.viz.plotTracking(context,options);names={[key '.png']};
    case 14
        fig=slrx.viz.newFigure('条件硬判决：观测与候选模型',cfg.show_figures);ax=axes(fig);c=cfg.display_data_column;
        plot(ax,real(data.received(:,c)),imag(data.received(:,c)),'.','DisplayName','未知载荷实际观测');hold(ax,'on');
        plot(ax,real(data.hard_symbols_observed_scale(:,c)),imag(data.hard_symbols_observed_scale(:,c)), ...
            'ro','DisplayName','给定候选几何的最近点（非真值）');axis(ax,'equal');grid(ax,'on');legend(ax,'Location','best');
        xlabel(ax,'I / 接收机归一化幅度');ylabel(ax,'Q / 接收机归一化幅度');
        title(ax,sprintf('数据符号%d / FFT列%d：有效%d、擦除%d；导频未混入载荷',c,c+1, ...
            nnz(data.valid_mask(:,c)),nnz(~data.valid_mask(:,c))));names={[key '.png']};
    case 15
        context.guard=data;fig=slrx.viz.plotGuard(context,options);names={[key '.png']};
    otherwise
        error('slrx:PlotKind','未定义绘图类型%d',kind);
end
if kind~=3,figs={fig};end
folder=fullfile(cfg.run_dir,'figures');
for k=1:numel(figs)
    slrx.viz.teachingNotes(figs{k},slrx.diag.plotContract(key,data));
    slrx.viz.saveFigure(figs{k},folder,names{k},cfg.show_figures);
end
slrx.viz.debugPlots(context,options,folder);
end
