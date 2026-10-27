function record = summarizeStep(cfg, key, data, sourceRunDir, relatedImages)
%SUMMARIZESTEP 单步小型摘要；不读取大MAT，不修改data，不打印整矩阵。
file=fullfile(cfg.run_dir,'diagnostics_summary.json');
if nargin<4,sourceRunDir=cfg.run_dir;end
if nargin<5,relatedImages={};end
if exist(file,'file')
    document=jsondecode(fileread(file));
else
    document=struct('schema_version','slrx-diagnostics-v1','role','codex_baseline', ...
        'steps',struct([]),'business_BER_available',false,'business_SER_available',false, ...
        'MCS_status','unknown','FEC_status','unknown','CRC_status','unknown');
end
info=slrx.diag.stepInfo(key);
outputs=struct('field',{},'shape',{},'class',{},'units',{},'preview',{});
fields=fieldnames(data);
for k=1:numel(fields)
    field=fields{k};value=data.(field);
    if isnumeric(value)||islogical(value)
        preview=value(1:min(3,numel(value)));
        units='无量纲；详见字段定义';
        if contains(field,'hz'),units='Hz';elseif contains(field,'ppm'),units='ppm';
        elseif contains(field,'rad'),units='rad';elseif contains(field,'sample'),units='采样/索引，详见字段坐标约定';end
        if ismember(field,{'iq','values','time_before_cfo','time_cfo_compensated','pss','with_cp','without_cp','samples','pre_samples','hard_symbols'})
            units='归一化复幅度（阶段增益约定不同），不是V';
        elseif ismember(field,{'duration_s','time_s'}),units='s';
        elseif contains(field,'phase_deg'),units='degree';
        elseif contains(field,'variance'),units='归一化幅度平方';
        elseif contains(field,'rows')||contains(field,'columns'),units='MATLAB一基数组索引';
        elseif strcmp(field,'H'),units='归一化复信道增益';
        elseif contains(field,'frequency_bins'),units='signed FFT bin';end
        outputs(end+1)=struct('field',field,'shape',size(value),'class',class(value), ...
            'units',units,'preview',preview); %#ok<AGROW>
    end
end
inputs=struct('source_key',{},'status',{},'arrays',{});
for k=1:numel(info.input_keys)
    source=info.input_keys{k};found=[];
    if ~isempty(document.steps),found=find(strcmp({document.steps.key},source),1);end
    arrays=struct([]);state='尚无诊断摘要，不能推断为已执行';
    if ~isempty(found),arrays=document.steps(found).output_arrays;state='from_previous_step_summary';end
    inputs(end+1)=struct('source_key',source,'status',state,'arrays',arrays); %#ok<AGROW>
end
images=dir(fullfile(cfg.run_dir,'figures',[key '*.png']));
if isempty(relatedImages),relatedImages={images.name};end
record=struct('key',key,'name',info.name,'input_arrays',inputs,'output_variable',info.output_variable, ...
    'output_arrays',outputs,'formula',info.formula,'parameters',struct( ...
    'capture_fs_hz',cfg.capture_fs_hz,'model_fs_hz',cfg.model_fs_hz,'nfft',cfg.nfft, ...
    'cp_length',cfg.cp_length,'first_complex_sample',cfg.first_complex_sample), ...
    'metrics',data.summary,'limitations',info.limitations,'figures',{relatedImages}, ...
    'mat_file',fullfile(sourceRunDir,[key '.mat']),'step_json',fullfile(sourceRunDir,[key '.json']), ...
    'step_json_available',isfile(fullfile(sourceRunDir,[key '.json'])),'sync',struct());
if strcmp(key,'03_sync')
    sync=slrx.diag.syncSummary(data,cfg,sourceRunDir);
    record.sync=sync;
    writetable(struct2table(sync.candidates),fullfile(cfg.run_dir,'sync_candidates.csv'),'Encoding','UTF-8');
end
if isempty(document.steps),document.steps=record;
else
    found=find(strcmp({document.steps.key},key),1);
    if isempty(found),document.steps(end+1)=record;else,document.steps(found)=record;end
end
slrx.diag.writeJSON(file,document);
fprintf('\n========== %s：%s ==========\n',key,info.name);
fprintf('输入步骤：%s\n',strjoin(info.input_keys,', '));
fprintf('输出变量：%s；MAT：%s\n',info.output_variable,record.mat_file);
for k=1:min(5,numel(outputs)),fprintf('  %s : %s %s；%s\n',outputs(k).field,mat2str(outputs(k).shape),outputs(k).class,outputs(k).units);end
fprintf('主要指标：%s\n',jsonencode(data.summary));
if strcmp(key,'03_sync')
    s=record.sync.selected;
    fprintf(['模型Fs=%.6gHz；窗口原起点=%.12g\n候选：接受%d 拒绝%d\n' ...
        '原文件一基帧头=%.12g；模型帧头=%.12g；采集时间=%.9fms\n' ...
        'PSS=%.9f；SSS=%.9f；联合=%.9f；粗CFO=%.6fHz\n%s\n'], ...
        cfg.model_fs_hz,cfg.first_complex_sample,numel(data.candidates),numel(data.rejected), ...
        s.raw_sample,s.model_sample,s.time_ms,s.pss_score,s.sss_score,s.joint_score,s.coarse_cfo_hz,record.sync.selection_rule);
end
fprintf('图像目录：%s\n完整小型摘要：%s\n',fullfile(cfg.run_dir,'figures'),file);
end
