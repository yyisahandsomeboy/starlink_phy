function controller = exploreRun(runDirs, root, visible)
%EXPLORERUN 控制窗口与同资源对照窗口；数据光标提供资源及原IQ有效区坐标。
controller=slrx.viz.newFigure('教学诊断浏览器：选择资源，不改变DSP',visible);
controller.Position=[80 80 550 650];cache=cell(size(runDirs));comparison=[];
uicontrol(controller,'Style','text','Units','normalized','Position',[.06 .91 .88 .06], ...
    'String','切换帧/符号/频段/阶段；原始数值不改变。','BackgroundColor','w','FontSize',13);
frame=uicontrol(controller,'Style','popupmenu','Units','normalized','Position',[.06 .84 .88 .05],'String',runDirs,'Tag','slrx-browser-frame');
uicontrol(controller,'Style','text','Units','normalized','Position',[.06 .76 .88 .04],'String','连续数据符号：起点 / 终点（1..300）','BackgroundColor','w');
first=uicontrol(controller,'Style','edit','Units','normalized','Position',[.06 .71 .4 .05],'String','50','Tag','slrx-browser-first');
last=uicontrol(controller,'Style','edit','Units','normalized','Position',[.54 .71 .4 .05],'String','50','Tag','slrx-browser-last');
uicontrol(controller,'Style','text','Units','normalized','Position',[.06 .64 .88 .04],'String','基带频率范围/MHz（留空为全频带）','BackgroundColor','w');
low=uicontrol(controller,'Style','edit','Units','normalized','Position',[.06 .59 .4 .05],'String','');
high=uicontrol(controller,'Style','edit','Units','normalized','Position',[.54 .59 .4 .05],'String','');
carrier=uicontrol(controller,'Style','popupmenu','Units','normalized','Position',[.06 .50 .88 .05], ...
    'String',{'载荷全部','正频率载荷','负频率载荷','频段载荷','FIT导频','EVAL导频'});
stage=uicontrol(controller,'Style','popupmenu','Units','normalized','Position',[.06 .42 .88 .05], ...
    'String',{'两轮全部阶段','第一轮FFT','第一轮均衡','第一轮跟踪','第二轮FFT','第二轮均衡','第二轮跟踪'});
normalization=uicontrol(controller,'Style','popupmenu','Units','normalized','Position',[.06 .34 .88 .05], ...
    'String',{'不归一化（接收原单位）','同轮共同RMS除数（仅显示）'});
uicontrol(controller,'Style','pushbutton','Units','normalized','Position',[.06 .24 .42 .06], ...
    'String','更新对照图','Callback',@(~,~)refresh());
uicontrol(controller,'Style','pushbutton','Units','normalized','Position',[.52 .24 .42 .06], ...
    'String','导出当前完整报告','Callback',@(~,~)exportCurrent());
status=uicontrol(controller,'Style','text','Units','normalized','Position',[.06 .04 .88 .17], ...
    'String','点击更新；在星座图中启用数据光标可追溯资源。','BackgroundColor','w','HorizontalAlignment','left');
controller.UserData=struct('refresh',@refresh,'frame',frame,'first',first,'last',last,'stage',stage,'status',status);
    function [context,opts]=selection()
        index=frame.Value;
        if isempty(cache{index}),cache{index}=slrx.diag.loadLesson(runDirs{index},root);end
        context=cache{index};a=str2double(first.String);b=str2double(last.String);
        validateattributes([a b],{'numeric'},{'integer','>=',1,'<=',context.cfg.data_column_count});assert(b>=a);
        band=[min(context.refs.frequency_bins) max(context.refs.frequency_bins)]*context.cfg.model_fs_hz/context.cfg.nfft/1e6;
        if ~isempty(low.String)||~isempty(high.String),band=[str2double(low.String) str2double(high.String)];assert(all(isfinite(band))&&band(2)>band(1));end
        modes={'payload','positive','negative','band','fit_pilots','eval_pilots'};norms={'none','common_rms'};
        stages=1:6;if stage.Value>1,stages=stage.Value-1;end
        opts=struct('symbols',a:b,'carrier_mode',modes{carrier.Value},'frequency_band_mhz',band, ...
            'geometry_id',[],'normalization',norms{normalization.Value},'grid_columns',1:context.cfg.data_column_count+1, ...
            'selected_row',[],'max_points',6000,'low_channel_fraction',.1, ...
            'show_figures',visible,'stage_indices',stages);
    end
    function refresh()
        try
            [context,opts]=selection();
            if ~isempty(comparison)&&isgraphics(comparison),close(comparison);end
            [comparison,view]=slrx.viz.plotConstellationStages(context,opts);
            status.String=sprintf(['已缓存帧目录%d；符号%d..%d；%d子载波；显示%d点。\n' ...
                'Y=FFT(x)/sqrt(N)，均衡X=Y/H；跟踪使用原ML参数。\n' ...
                '源码：+slrx/+viz/plotConstellationStages.m\n' ...
                '数据光标查看变量值、行/bin/频率和原文件区间。'], ...
                frame.Value,view.symbols(1),view.symbols(end),numel(view.rows),numel(view.display_flat_indices));
            controller.UserData.comparison=comparison;
        catch problem,status.String=problem.message;rethrow(problem);end
    end
    function exportCurrent()
        try
            [context,opts]=selection();stamp=char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'));
            out=fullfile(context.run_dir,'diagnostics',['browser-' stamp]);opts.show_figures=false;
            slrx.diag.exportDiagnostics(context,opts,out);status.String=['报告：' fullfile(out,'index.html')];
        catch problem,status.String=problem.message;rethrow(problem);end
    end
end
