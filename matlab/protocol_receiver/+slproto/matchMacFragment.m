function result = matchMacFragment(outgoing, nextRecords)
%MATCHMACFRAGMENT Select and validate a fragment continuation in the next frame.
% Inputs are uint8 vectors of complete, descrambled MAC records in protocol
% byte order. Supply records from the immediately following frame as a cell
% vector, with an empty entry for each known but unreadable candidate.
% A byte match selects candidates. Counters, sequence, and length are checked
% separately before returning any reconstructed bytes.
if ~iscell(nextRecords) || (~isempty(nextRecords) && ~isvector(nextRecords))
    error('slproto:InvalidMacCandidates','Next-frame records must be supplied as a cell vector.');
end
result = struct('status','unreadable_outgoing','match_index',0, ...
    'readable_matches',0,'unreadable_candidates',0,'counter_pass',false, ...
    'sequence_pass',false,'length_pass',false,'joined_bytes',uint8([]));
layout = slproto.parseMacPayloadRecord(outgoing);
if ~layout.available || layout.record_bytes ~= numel(outgoing)
    return;
end
if ~layout.outgoing_continuation
    result.status = 'no_outgoing_continuation';
    return;
end
tail = outgoing(layout.span_starts(end)+1:end);
[sourceKey, sourceSequence] = innerHeader(tail,0,numel(tail));
if isempty(sourceKey)
    return;
end

for i = 1:numel(nextRecords)
    record = nextRecords{i};
    if isempty(record)
        result.unreadable_candidates = result.unreadable_candidates+1;
        continue;
    end
    candidate = slproto.parseMacPayloadRecord(record);
    if ~candidate.available || candidate.record_bytes ~= numel(record)
        result.unreadable_candidates = result.unreadable_candidates+1;
        continue;
    end
    if ~candidate.incoming_continuation
        continue;
    end
    [firstKey, sequences, lengths] = completeHeaders(record,candidate);
    if isempty(firstKey)
        result.unreadable_candidates = result.unreadable_candidates+1;
        continue;
    end
    if isequal(firstKey,sourceKey)
        result.readable_matches = result.readable_matches+1;
        result.match_index = i;
        selected = candidate;
        selectedSequences = sequences;
        selectedLengths = lengths;
    end
end

if result.readable_matches == 0
    result.status = 'no_visible_match';
    return;
end
if result.readable_matches > 1
    result.status = 'multiple_visible_matches';
    result.match_index = 0;
    return;
end
rightLength = selected.span_lengths(1);
nextSequence = mod(sourceSequence+1,65536);
next = selectedSequences==nextSequence;
result.counter_pass = mod(selected.counter_octet-layout.counter_octet,256)==1;
result.sequence_pass = any(next);
result.length_pass = any(next & (selectedLengths==numel(tail)+rightLength));
if result.unreadable_candidates > 0
    result.status = 'unreadable_incoming_candidate';
elseif result.counter_pass && result.sequence_pass && result.length_pass
    record = nextRecords{result.match_index};
    head = record(selected.span_starts(1)+(1:rightLength));
    result.status = 'verified';
    result.joined_bytes = [tail(:);head(:)];
else
    result.status = 'counter_sequence_or_length_mismatch';
end
end

function [key,sequences,lengths] = completeHeaders(record,layout)
key = uint8([]);
sequences = zeros(1,0);
lengths = zeros(1,0);
% Only interior spans are used as reference headers in this rule.
for j = 2:numel(layout.span_lengths)-1
    [current, sequence] = innerHeader(record,layout.span_starts(j),layout.span_lengths(j));
    if isempty(current)
        continue;
    end
    if isempty(key)
        key = current;
    end
    sequences(end+1) = sequence; %#ok<AGROW>
    lengths(end+1) = layout.span_lengths(j); %#ok<AGROW>
end
end

function [key, sequence] = innerHeader(record,offset,length)
key = uint8([]);
sequence = NaN;
if length < 20
    return;
end
head = reshape(record(offset+(1:20)),1,[]);
if head(1) ~= 16 || ~isequal(head(13:14),uint8([0 107])) || ...
        ~isequal(head(18:20),uint8([179 255 208]))
    return;
end
key = head([11:12 15:17]);
sequence = 256*double(head(7)) + double(head(8));
end
