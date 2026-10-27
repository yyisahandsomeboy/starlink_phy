function report = RUN_DIAGNOSTICS(runDirs, varargin)
%RUN_DIAGNOSTICS 读取学习版MAT的独立教学诊断入口，不重新执行DSP。
% report=RUN_DIAGNOSTICS(runDir,'Symbols',50,'ShowFigures',false)
% RUN_DIAGNOSTICS({frame1,frame2},'Symbols',45:55,'CarrierMode','positive')
p=inputParser;
addParameter(p,'Symbols',50,@isnumeric);
addParameter(p,'CarrierMode','payload',@(x)ismember(char(x),{'payload','positive','negative','band','fit_pilots','eval_pilots'}));
addParameter(p,'FrequencyBandMHz',[],@(x)isnumeric(x)&&(isempty(x)||(numel(x)==2&&all(isfinite(x))&&x(1)<x(2))));
addParameter(p,'GeometryID',[],@(x)isnumeric(x)&&all(ismember(x,1:4)));
addParameter(p,'Normalization','none',@(x)ismember(char(x),{'none','common_rms'}));
addParameter(p,'GridColumns',[],@isnumeric);
addParameter(p,'SelectedRow',[],@isnumeric);
addParameter(p,'MaxPoints',6000,@(x)isnumeric(x)&&isscalar(x)&&x>=1&&x==floor(x));
addParameter(p,'LowChannelFraction',.1,@(x)isnumeric(x)&&isscalar(x)&&x>0&&x<1);
addParameter(p,'ShowFigures',false,@(x)islogical(x)&&isscalar(x));
addParameter(p,'OutputDir','',@(x)ischar(x)||isstring(x));
parse(p,varargin{:});a=p.Results;
options=struct('symbols',a.Symbols,'carrier_mode',char(a.CarrierMode),'frequency_band_mhz',a.FrequencyBandMHz, ...
    'geometry_id',a.GeometryID,'normalization',char(a.Normalization),'grid_columns',a.GridColumns, ...
    'selected_row',a.SelectedRow,'max_points',a.MaxPoints,'low_channel_fraction',a.LowChannelFraction,'show_figures',a.ShowFigures);
if ischar(runDirs)||isstring(runDirs),runDirs=cellstr(runDirs);end
assert(iscell(runDirs)&&~isempty(runDirs),'slrx:DiagnosticInput','请指定一个学习运行目录或目录cell列表');
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
stamp=char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'));
if strlength(string(a.OutputDir))>0,out=char(a.OutputDir);
else,out=fullfile(runDirs{1},'diagnostics',['teaching-' stamp]);end
if numel(runDirs)==1
    context=slrx.diag.loadLesson(char(runDirs{1}),root);
    report=slrx.diag.exportDiagnostics(context,options,out);
else
    assert(~exist(out,'dir'),'slrx:DiagnosticImmutable','多帧输出目录已存在');mkdir(out);
    records=cell(1,numel(runDirs));mapping=[];
    for k=1:numel(runDirs)
        context=slrx.diag.loadLesson(char(runDirs{k}),root);
        identity=[context.cfg.nfft context.cfg.model_fs_hz context.refs.payload_rows(:).'];
        if isempty(mapping),mapping=identity;else,assert(isequal(mapping,identity),'slrx:DiagnosticResources','多帧资源映射/采样率不一致');end
        records{k}=slrx.diag.exportDiagnostics(context,options,fullfile(out,sprintf('frame_%02d',k)));
    end
    comparison=slrx.viz.plotFrameComparison(records,out,options);
    report=struct('status','multi_frame_diagnostics_generated','frames',{records},'comparison',comparison, ...
        'policy','每帧相同资源选择，按轮次分开；候选几何筛选不是商业MCS真值');
    slrx.diag.writeJSON(fullfile(out,'diagnostics_summary.json'),report);
    fid=fopen(fullfile(out,'index.html'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><h1>多帧同类资源教学诊断</h1><p>%s</p>',report.policy);
    if comparison.available
        fprintf(fid,'<p>只比较所有帧共有的同一阶段。资源一一配对=%d。</p><img style="max-width:100%%" src="multi_frame_constellations.png"><img style="max-width:100%%" src="multi_frame_metrics.png">',comparison.exact_resource_pairing);
    end
    for k=1:numel(runDirs),fprintf(fid,'<p><a href="frame_%02d/index.html">帧目录%d的同资源报告</a></p>',k,k);end
    fprintf(fid,'</html>');fclose(fid);
end
fprintf('浏览器报告：%s\n',fullfile(out,'index.html'));
end
