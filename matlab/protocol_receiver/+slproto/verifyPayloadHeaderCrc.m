function result = verifyPayloadHeaderCrc(informationBits)
%VERIFYPAYLOADHEADERCRC Check the MAC header in decoded LDPC system bits.
% Each column is one codeword's system bits in receiver order. Columns must
% belong to the same allocation and be ordered as transmitted.
validateattributes(informationBits,{'logical'},{'2d'},mfilename,'informationBits');
result = struct('available',false,'reason','unrecognized header', ...
    'header_bytes',NaN,'covered_bytes',NaN,'computed_crc',uint32(0), ...
    'received_crc',uint32(0),'crc_pass',false);
wordBits = size(informationBits,1);
if mod(wordBits,8) ~= 0
    error('slproto:InvalidSystemBitCount','System-bit columns must be byte-aligned.');
end
if numel(informationBits) < 5*8
    result.reason = 'not enough system bits for a header';
    return;
end

serial = false(max(wordBits,15),1);
serial(1:15) = bitget(uint16(hex2dec('01FB')),15:-1:1).';
for k = 16:wordBits
    serial(k) = xor(serial(k-14),serial(k-15));
end
mask = reshape(flipud(reshape(serial(1:wordBits),8,[])),[],1);

prefix = decodePrefix(5);
bytes = uint8((2.^(0:7))*double(reshape(prefix,8,[])));
isFirstHeaderLayout = isequal(bytes(3:5),uint8([1 240 15]));
isExtendedHeaderLayout = bytes(3) == uint8(7);
if ~isFirstHeaderLayout && ~isExtendedHeaderLayout
    return;
end

headerBytes = double(bytes(1)) + 256*double(bytes(2));
result.header_bytes = headerBytes;
if headerBytes < 8 || headerBytes*8 > numel(informationBits)
    result.reason = 'header length is outside the allocation';
    return;
end
result.available = true;
result.covered_bytes = headerBytes - 3;
bits = decodePrefix(headerBytes);
result.computed_crc = crc24(bits(1:end-24));
result.received_crc = uint32((2.^(23:-1:0))*double(bits(end-23:end)));
result.crc_pass = result.computed_crc == result.received_crc;
if result.crc_pass
    result.reason = 'header CRC-24 passed';
else
    result.reason = 'header CRC-24 mismatch';
end

    function bits = decodePrefix(count)
        indices = (1:8*count).';
        bits = xor(informationBits(indices),mask(mod(indices-1,wordBits)+1));
    end
end

function reg = crc24(bits)
reg = uint32(hex2dec('FFFFFF'));
top = uint32(hex2dec('800000'));
mask = uint32(hex2dec('FFFFFF'));
poly = uint32(hex2dec('1F21C5'));
for k = 1:numel(bits)
    feedback = xor(bitand(reg,top) ~= 0,bits(k));
    reg = bitand(bitshift(reg,1),mask);
    if feedback
        reg = bitxor(reg,poly);
    end
end
end
