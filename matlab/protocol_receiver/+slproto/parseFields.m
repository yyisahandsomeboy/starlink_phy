function f = parseFields(bits)
%PARSEFIELDS 条件布局；不把CRC通过等同于字段语义或唯一位宽获证。
bits=double(bits(:));N=numel(bits)/32;assert(ismember(N,2:7));little=@(b)sum(b(:).*2.^(0:numel(b)-1)');
f=struct('block_count_from_length',N,'block_count_field',little(bits(9:11)), ...
    'role_bit',bits(6),'entry_count',little(bits(13:16)),'layout','conditional 16+20D+padding+8', ...
    'entries',struct([]),'alternative_19bit_entries',struct([]),'packing_ok',false,'padding_all_zero',false, ...
    'semantics_verified',false,'unresolved_eighth_index_bit',true);
D=f.entry_count;last=16+20*D;f.packing_ok=D>=1&&last<=numel(bits)-8&&ceil((last+8)/32)==N;
if f.packing_ok
    pad=bits(last+1:end-8);f.padding_all_zero=~any(pad);entries=struct([]);
    for j=1:D
        x=bits(16+(j-1)*20+(1:20));e=struct('ordinal',j,'index7',little(x(1:7)), ...
            'unresolved_bit',x(8),'index8',little(x(1:8)),'quantity',little(x(9:20)), ...
            'raw_bits',x.','meaning','candidate format label and quantity; unknown formats remain unknown');
        if isempty(entries),entries=e;else,entries(end+1)=e;end %#ok<AGROW>
    end
    f.entries=entries;
end
if D>=1&&16+19*D<=numel(bits)-8
    entries=struct([]);
    for j=1:D
        x=bits(16+(j-1)*19+(1:19));e=struct('index7',little(x(1:7)),'quantity',little(x(8:19)));
        if isempty(entries),entries=e;else,entries(end+1)=e;end %#ok<AGROW>
    end
    f.alternative_19bit_entries=entries;
end
end
