function report = RUN_PROTOCOL_ANALYSIS(sourceRun,varargin)
%RUN_PROTOCOL_ANALYSIS 完整接收机/学习版共享的升级入口；来源MAT只读、逐帧释放。
here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(here));
addpath(here,fullfile(root,'matlab','learning_receiver'));
p=inputParser;addParameter(p,'Frames',1,@(x)isnumeric(x)&&isvector(x)&&all(x>=1&x==fix(x)));
addParameter(p,'OutputDir','',@(x)ischar(x)||isstring(x));addParameter(p,'MakePlots',true,@islogical);
addParameter(p,'ShowFigures',false,@islogical);addParameter(p,'PNModel','utexas_verified_pairclock',@(x)ischar(x)||isstring(x));
addParameter(p,'Polarity',0,@(x)isscalar(x)&&ismember(x,[0 1]));addParameter(p,'EnableCode5',true,@islogical);addParameter(p,'EnableAllocations',true,@islogical);addParameter(p,'EnableMCS66',true,@islogical);parse(p,varargin{:});
opt=slproto.defaultOptions();opt.make_plots=p.Results.MakePlots;opt.show_figures=p.Results.ShowFigures;
opt.pn_model=char(p.Results.PNModel);opt.polarity=p.Results.Polarity;opt.enable_code5=p.Results.EnableCode5;opt.enable_allocations=p.Results.EnableAllocations;opt.enable_mcs66=p.Results.EnableMCS66;
out=char(p.Results.OutputDir);if isempty(out),out=fullfile(sourceRun,['protocol-' char(datetime('now','Format','yyyyMMdd-HHmmss-SSS'))]);end
assert(~isfolder(out),'slproto:OutputExists','输出目录已存在，请换一个目录');mkdir(out);
cfg=slrx.defaultConfig(root);refs=slrx.references(cfg);frames=p.Results.Frames;items=cell(1,numel(frames));
for j=1:numel(frames)
    [grid,source]=slproto.loadGrid(sourceRun,frames(j));result=slproto.analyzeFrame(grid,refs.pilots,opt);
    folder=sprintf('frame_%02d',frames(j));items{j}=slproto.exportFrame(result,fullfile(out,folder),source);
    items{j}.relative_report=[folder '/index.html'];
    fprintf('PROTOCOL_FRAME %d firstCRC=%d second=%d code5=%d\n',frames(j),result.headers.first.crc_pass,numel(result.headers.second_candidates),result.code5.available);
    clear grid result;
end
report=struct('version',opt.version,'owner','codex_baseline','source_run',sourceRun,'output_dir',out, ...
    'frames',{items},'raw_BIN_reads',0,'business_payload_decoded',false,'existing_receiver_evaluator_modified',false);
slproto.writeJSON(fullfile(out,'protocol_summary.json'),report);
fid=fopen(fullfile(out,'index.html'),'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>升级接收机协议诊断</title><body><h1>PN/PDU/Code5逐帧结果</h1><p>源MAT只读；第一组CRC和第二组候选分别统计；未知格式不默认套用Code5。</p><ul>');
for j=1:numel(items),fprintf(fid,'<li><a href="%s">帧%d：第一组CRC=%d，第二组候选=%d</a></li>',items{j}.relative_report,frames(j),items{j}.headers.first.crc_pass,numel(items{j}.headers.second_candidates));end
fprintf(fid,'</ul><p><a href="protocol_summary.json">总体数值摘要</a></p></body></html>');
fprintf('PROTOCOL_REPORT %s\n',fullfile(out,'index.html'));
end
