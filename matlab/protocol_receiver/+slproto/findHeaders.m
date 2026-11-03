function headers = findHeaders(stream,opt)
%FINDHEADERS 第一组固定r0；第二组由前缀提议后以完整组CRC核验，不强塞预测位置。
first=slproto.decodeGroup(stream,0,2,opt);first.accepted=first.accepted&&first.fields.role_bit==0;
second=struct([]);trials=struct('start_r0',{},'block_count',{},'accepted',{},'crc_pass',{},'hard_changes',{});
predicted=NaN;
if first.accepted&&first.fields.entries(1).index8==5
    predicted=228+2048*first.fields.entries(1).quantity;
end
candidates=[];
if opt.scan_second_header
    % 论文第二头部共同首字节0x34，只用前24编码位提议，不用CRC拟合前缀。
    pattern=xor(slproto.bccEncode([0 0 1 1 0 1 0 0]),logical(opt.polarity));b=double(real(stream(:))<0);
    errors=conv(b,flipud(1-2*double(pattern)),'valid')+nnz(pattern);
    candidates=find(errors<=opt.prefix_max_bit_errors)-1;
end
if isfinite(predicted),candidates=unique([predicted;candidates(:)]);end
truncated=numel(candidates)>opt.max_scan_candidates;candidates=candidates(1:min(end,opt.max_scan_candidates));
for start=candidates(:).'
    if start<=0||start+114>numel(stream),continue;end
    probe=slproto.bccDecode(stream(start+(1:114)),opt.polarity);
    count=sum(double(probe.word_bits(9:11)).*2.^(0:2)');
    if ~ismember(count,2:7),continue;end
    h=slproto.decodeGroup(stream,start,count,opt);
    trials(end+1)=struct('start_r0',start,'block_count',count,'accepted',h.accepted,'crc_pass',h.crc_pass,'hard_changes',h.hard_changes); %#ok<AGROW>
    if h.accepted&&h.fields.role_bit==1
        if isempty(second),second=h;else,second(end+1)=h;end %#ok<AGROW>
    end
end
headers=struct('first',first,'second_candidates',second,'second_unique',numel(second)==1, ...
    'first_body_predicted_end_r0',predicted,'signal_found_second_start_r0',NaN,'first_body_length_agrees',false, ...
    'scan_prefix_candidates',numel(candidates),'scan_truncated',truncated,'trials',trials, ...
    'scope','Fixed-paper BCC/CRC; scan-conditioned evidence on existing capture; no business payload truth');
if numel(second)==1
    headers.signal_found_second_start_r0=second.start_r0;headers.first_body_length_agrees=second.start_r0==predicted;
end
end
