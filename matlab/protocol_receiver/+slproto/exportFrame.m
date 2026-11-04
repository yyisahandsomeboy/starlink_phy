function report = exportFrame(result,out,source)
%EXPORTFRAME 新目录保存；完整复数/译码位只留本机MAT，摘要不含明文或全网格。
assert(~isfolder(out),'slproto:OutputExists','使用新的输出目录，保留原记录');mkdir(out);
report=slproto.smallSummary(result);report.source=source;
report.protocol_source_manifest=slproto.sourceManifest();
save(fullfile(out,'protocol.mat'),'result','-v7.3');
report.figures=[slproto.plotFrame(result,out,result.options) slproto.plotAllocations(result,out,result.options)];
if isfield(source,'checkpoint')
    assert(strcmp(slrx.sha256(source.checkpoint),source.sha256),'slproto:SourceChanged','后处理修改了来源MAT');
    report.source_checkpoint_hash_unchanged=true;
end
slproto.writeJSON(fullfile(out,'protocol_summary.json'),report);
fid=fopen(fullfile(out,'index.html'),'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PN、PDU头部与Code5教学</title><style>body{font:17px/1.7 sans-serif;max-width:1200px;margin:24px auto;padding:0 16px}img{width:100%%;height:auto}pre{white-space:pre-wrap;background:#f4f6fa;padding:16px}a{color:#075cad}</style><body><h1>PN去旋转、BCC/CRC与Code5</h1>');
h=report.headers.first;fprintf(fid,'<p>第一组CRC通过：%d；重编码改变硬位：%d；第二组候选：%d。字段采用条件布局，未识别格式保持未知。</p>',h.crc_pass,h.hard_changes,numel(report.headers.second_candidates));
fprintf(fid,'<p>Code5可用：%d；仅恢复条件编码器输入，不代表业务明文。原始接收与冻结评价未改。</p><p><a href="protocol_summary.json">数值摘要</a> · <a href="protocol.mat">本机完整数值</a></p>',report.code5.available);
if isfield(report,'allocations')
    fprintf(fid,'<p>逐资源判决采用UT公开采集专用候选表，完整分配=%d。高阶格式的几何索引不是已确认发射位映射；边界偏差保留，未知格式停止推算。详见数值摘要。</p>',report.allocations.complete);
end
if isfield(report,'mcs66')&&report.mcs66.available
    fprintf(fid,'<p>编号66：N=16384、K=12288、rate=3/4；%d个字，全收敛=%d，重编码一致=%d。其他未识别格式保持未知。</p>',report.mcs66.word_count,report.mcs66.all_converged,report.mcs66.all_reencode_matches);
end
for j=1:numel(report.figures),fprintf(fid,'<p><img src="%s" alt="PN/BCC/LDPC教学图%d"></p>',report.figures{j},j);end
fprintf(fid,'<p>论文：<a href="https://arxiv.org/html/2610.29387v2">arXiv:2610.29387v2</a>。本实现由Codex依据论文和旧工程独立实现，不冒称作者配套源码。</p></body></html>');
end
