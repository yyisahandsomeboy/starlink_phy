function result = parseB8Record(bytes)
%PARSEB8RECORD Read a B8 record at the start of a decoded byte stream.
% Input is already descrambled, with each protocol byte in its displayed bit
% order. The returned offsets are zero-based. Trailing input is not consumed.
result = slproto.parseMacPayloadRecord(bytes,true);
result = rmfield(result,{'record_type','incoming_continuation','outgoing_continuation'});
end
