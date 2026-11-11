function result = parseB8Record(bytes)
%PARSEB8RECORD Read a B8 record at the start of a decoded byte stream.
% Input is already descrambled, with each protocol byte in its displayed bit
% order. The returned offsets are zero-based. Trailing input is not consumed.
validateattributes(bytes,{'uint8'},{'vector','nonempty'},mfilename,'bytes');
result = struct('available',false,'reason','unrecognized B8 header', ...
    'counter_octet',NaN,'flags',NaN,'header_bytes',NaN,'record_bytes',NaN, ...
    'span_starts',[],'span_lengths',[]);
if numel(bytes) < 4 || bytes(1) ~= uint8(184)
    return;
end

first = bitor(uint16(bytes(3)),bitshift(uint16(bytes(4)),8));
flags = bitand(first,uint16(31));
firstLength = double(bitshift(first,-5));
result.reason = 'B8 length or descriptor list exceeds input';
if 4 + firstLength > numel(bytes)
    return;
end

headerBytes = 4;
spanLengths = firstLength;
payloadBytes = firstLength;
if bitand(flags,uint16(16)) == 0
    terminated = false;
    for bitOffset = 32:12:(8*numel(bytes)-12)
        byteOffset = floor(bitOffset/8);
        word = bitor(uint16(bytes(byteOffset+1)),bitshift(uint16(bytes(byteOffset+2)),8));
        entry = bitand(bitshift(word,-mod(bitOffset,8)),uint16(4095));
        length = double(bitshift(entry,-1));
        headerBytes = ceil((bitOffset+12)/8);
        payloadBytes = payloadBytes + length;
        if length == 0 || headerBytes + payloadBytes > numel(bytes)
            return;
        end
        spanLengths(end+1) = length; %#ok<AGROW>
        if bitand(entry,uint16(1))
            if mod(bitOffset+12,8) ~= 0 && bitand(bytes(headerBytes),uint8(240))
                result.reason = 'nonzero B8 header alignment bits';
                return;
            end
            terminated = true;
            break;
        end
    end
    if ~terminated
        return;
    end
elseif firstLength == 0
    return;
end

result.available = true;
result.reason = '';
result.counter_octet = double(bytes(2));
result.flags = double(flags);
result.header_bytes = headerBytes;
result.record_bytes = headerBytes + payloadBytes;
result.span_starts = headerBytes + [0 cumsum(spanLengths(1:end-1))];
result.span_lengths = spanLengths;
end
