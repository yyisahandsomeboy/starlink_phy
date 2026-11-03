function h = decodeGroup(stream,startR0,count,opt)
%DECODEGROUP 独立块尾状态、重编码与组CRC分别保存；CRC不包含各块六个尾位。
% 三位长度字段允许更多候选；本机frame3的五块组另由重编码和CRC实测支持。
assert(ismember(count,2:7)&&startR0>=0&&startR0==fix(startR0));
h=struct('start_r0',startR0,'end_r0',startR0+114*count-1,'block_count',count, ...
    'available',startR0+114*count<=numel(stream),'blocks',struct([]),'word_bits',[], ...
    'words_hex',{{}},'crc_predicted',NaN,'crc_observed',NaN,'crc_pass',false, ...
    'hard_changes',NaN,'termination_pass',false,'accepted',false,'exact_reencoding',false,'fields',struct());
if ~h.available,return;end
blocks=cell(1,count);bits=false(32,count);
for j=1:count
    blocks{j}=slproto.bccDecode(stream(startR0+(j-1)*114+(1:114)),opt.polarity);bits(:,j)=blocks{j}.word_bits;
end
h.blocks=[blocks{:}];h.word_bits=bits(:);h.words_hex={h.blocks.word_hex};
h.crc_predicted=slproto.crc8(h.word_bits(1:end-8));h.crc_observed=sum(double(h.word_bits(end-7:end)).*2.^(7:-1:0)');
h.crc_pass=h.crc_predicted==h.crc_observed;h.hard_changes=sum([h.blocks.hard_changes]);
h.termination_pass=all([h.blocks.zero_initial_state]&[h.blocks.zero_final_state]&[h.blocks.zero_tail]);
h.exact_reencoding=h.hard_changes==0;h.fields=slproto.parseFields(h.word_bits);
h.accepted=h.crc_pass&&h.termination_pass&&h.fields.block_count_field==count&&h.fields.packing_ok&&h.fields.padding_all_zero;
end
