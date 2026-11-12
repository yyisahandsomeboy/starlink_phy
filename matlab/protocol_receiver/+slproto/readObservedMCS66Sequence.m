function result = readObservedMCS66Sequence(bytes)
%READOBSERVEDMCS66SEQUENCE Read a sequence from a verified record start.
% Use descrambled protocol-order bytes and B8 boundaries. The accepted
% signatures identify the three observed header variants in this capture.
validateattributes(bytes,{'uint8'},{'vector'},mfilename,'bytes');
result = struct('available',false,'signature','','sequence',NaN);
if numel(bytes) < 20
    return;
end

header = bytes(1:20);
header = reshape(header,1,[]);
firstPrefix = uint8([16 32 232 192 200 70]);
secondPrefix = uint8([16 16 232 192 188 251]);
alternatePrefix = uint8([16 16 232 128 83 139]);
firstTail = uint8([12 238 0 107 3 110 1 179 255 208]);
secondTail = uint8([61 174 14 67 0 107 123 137 0 179 255 208]);
if isequal(header(1:6),firstPrefix) && isequal(header(11:20),firstTail)
    result.signature = 'C846';
elseif isequal(header(9:20),secondTail)
    if isequal(header(1:6),secondPrefix)
        result.signature = 'BCFB';
    elseif isequal(header(1:6),alternatePrefix)
        result.signature = '538B';
    end
end
if isempty(result.signature)
    return;
end
result.available = true;
result.sequence = 256*double(header(7)) + double(header(8));
end
