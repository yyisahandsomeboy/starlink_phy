#!/usr/bin/env python3
"""Index and replay two-frame fragment joins from verified UT archive bytes."""
import argparse
from collections import Counter
from dataclasses import asdict, dataclass
from functools import lru_cache
import hashlib
import json
from pathlib import Path

import numpy as np

from ut_mac import check_header, parse_second_block, record_layout


MAX_FRAME_DISTANCE = 6


@dataclass(frozen=True)
class Location:
    frame: int
    allocation: int
    mcs: int
    start: int
    stop: int


@dataclass(frozen=True)
class Fragment:
    location: Location
    start: int
    data: bytes

    def coordinates(self):
        return dict(**asdict(self.location), fragment_start=self.start,
                    fragment_stop=self.start+len(self.data))


@dataclass(frozen=True)
class OuterRecord:
    location: Location
    counter: int
    incoming: Fragment | None
    following: bytes
    outgoing: Fragment | None
    preceding: bytes


def parse_outer(location, raw, layout):
    spans = []
    offset = layout.header_bytes
    for length in layout.span_lengths:
        fragment = Fragment(location, location.start+offset, raw[offset:offset+length])
        spans.append(fragment)
        offset += length
    incoming = spans[0] if layout.flags & 4 and spans[0].data else None
    outgoing_flag = bool(layout.flags & 8)
    middle = spans[1:-1]
    last = spans[-1] if len(spans) > 1 else None
    following = middle[0].data if middle else last.data if last and not outgoing_flag else b''
    from_here = spans if not layout.flags & 4 else spans[1:]
    from_here = [span for span in from_here if span.data]
    outgoing = from_here[-1] if outgoing_flag and from_here else None
    preceding = from_here[-2].data if outgoing and len(from_here) >= 2 else b''
    return OuterRecord(location, layout.counter, incoming, following, outgoing, preceding)


def inner_identity(raw):
    if len(raw) < 20 or raw[0] != 16 or raw[12:14] != b'\x00\x6b' or raw[17:20] != b'\xb3\xff\xd0':
        return None
    return (raw[10:12]+raw[14:17]).hex().upper(), int.from_bytes(raw[6:8], 'big')


def consecutive(a, b):
    return a is not None and b is not None and a[0] == b[0] and (b[1]-a[1]) % 65536 == 1


def splice(a, b):
    if a.outgoing is None or b.incoming is None:
        return None
    raw = a.outgoing.data + b.incoming.data
    identity = inner_identity(raw)
    if not consecutive(identity, inner_identity(b.following)):
        return None
    if len(a.outgoing.data) < 20 and (
        len(a.preceding) != len(raw) or not consecutive(inner_identity(a.preceding), identity)
    ):
        return None
    return raw, identity


def frame_records(folder, frame, expected_allocations=None):
    stem = folder / f'{frame:04}'
    ledger = json.loads(stem.with_suffix('.json').read_text(encoding='utf-8'))
    if ledger['frame'] != frame:
        raise ValueError(f'Invalid frame ledger at {stem}')
    allocations = ledger['allocations']
    observed = [(a['part'], a['mcs'], a['quantity']) for a in allocations]
    if expected_allocations is not None and observed != expected_allocations:
        raise ValueError(f'Frame {frame} allocations differ from its PHY inventory')
    second = [i for i, allocation in enumerate(allocations) if allocation['part'] == 2]
    if not second or not allocations or allocations[0]['part'] != 1:
        raise ValueError(f'Missing PHY allocation plan for frame {frame}')

    with np.load(stem.with_suffix('.npz')) as arrays:
        words = [arrays[f'part_{i}'] for i in range(len(allocations))]
        valid = [arrays[f'valid_{i}'] for i in range(len(allocations))]
    plan = [(a['mcs'], a['quantity'], a['information_bytes_per_word']) for a in allocations]
    for i, ((_, count, width), data, mask) in enumerate(zip(plan, words, valid, strict=True)):
        if (width <= 0 or data.dtype != np.uint8 or data.shape != (count, width)
                or mask.shape != (count,) or mask.dtype != np.bool_
                or not np.array_equal(mask, [w['reencoded'] for w in allocations[i]['codewords']])
                or int(mask.sum()) != allocations[i]['valid_words']):
            raise ValueError(f'Invalid data or codeword mask in frame {frame}, allocation {i}')

    def verified_prefix(i):
        end = next(iter(np.flatnonzero(~valid[i])), len(valid[i]))
        return words[i][:end].tobytes()

    first_header = check_header(verified_prefix(0), 1)
    header, status, layout = parse_second_block(verified_prefix(second[0]), [plan[i] for i in second])
    summary = dict(frame=frame, first_mac_crc_pass=first_header['crc_pass'],
                   second_mac_crc_pass=header['crc_pass'], second_block_status=status,
                   second_header_bytes=header['length'], verified_words=sum(int(m.sum()) for m in valid),
                   declared_words=sum(m.size for m in valid), outer_record_types={},
                   nonzero_padding_ranges=0, unverified_padding_ranges=0)
    unresolved = []
    records = {}
    tags = Counter()
    for i, region in zip(second, layout):
        mcs, _, width = plan[i]
        flat = words[i].ravel()
        verified = valid[i]
        start = region.record_start
        for length in region.record_lengths:
            stop = start + length
            location = Location(frame, i, mcs, start, stop)
            lo, hi = start//width, (stop-1)//width+1
            gaps = [k+1 for k in range(lo, hi) if not verified[k]]
            if gaps:
                unresolved.append(dict(**asdict(location), reason='missing_codewords', codewords=gaps))
            else:
                raw = flat[start:stop].tobytes()
                parsed = record_layout(raw)
                if parsed is None or parsed.length != length:
                    unresolved.append(dict(**asdict(location), reason='record_length_disagreement'))
                else:
                    tags[f'{raw[0]:02X}'] += 1
                    if raw[0] in (0x90, 0xB8) and parsed.flags & 12:
                        records[location] = parse_outer(location, raw, parsed)
            start = stop
        if region.padding_bytes:
            if not verified[region.padding_start//width:].all():
                summary['unverified_padding_ranges'] += 1
            elif flat[region.padding_start:].any():
                summary['nonzero_padding_ranges'] += 1
    summary['outer_record_types'] = dict(tags)
    summary['record_count'] = sum(tags.values())
    summary['unresolved_record_count'] = len(unresolved)
    return summary, records, unresolved


def join_entry(a, b, raw, identity):
    return dict(source=a.outgoing.coordinates(), target=b.incoming.coordinates(),
                source_counter=a.counter, target_counter=b.counter,
                key=identity[0], sequence=f'{identity[1]:04X}',
                next_sequence=f'{(identity[1]+1)%65536:04X}', joined_bytes=len(raw),
                sha256=hashlib.sha256(raw).hexdigest())


def possible_joins(frames):
    destinations = {
        f: [r for r in records if r.incoming is not None and inner_identity(r.following)]
        for f, records in frames.items()
    }
    reverse = Counter()
    unambiguous = []
    for f, records in frames.items():
        targets = [r for delta in range(1, MAX_FRAME_DISTANCE+1)
                   for r in destinations.get(f+delta, ())]
        for a in records:
            if a.outgoing is None:
                continue
            matches = [(b, result) for b in targets if (result := splice(a, b)) is not None]
            reverse.update(b.location for b, _ in matches)
            if len(matches) == 1:
                b, (raw, identity) = matches[0]
                unambiguous.append((a, b, raw, identity))
    return [
        join_entry(a, b, raw, identity) for a, b, raw, identity in unambiguous
        if reverse[b.location] == 1 and (b.counter-a.counter) % 256 == 1
    ]


def build(folder, inventory):
    count = inventory['frame_count']
    if [row['frame'] for row in inventory['frames']] != list(range(count)):
        raise ValueError('Expected a contiguous zero-based PHY inventory')
    frame_reports = []
    by_frame = {}
    unresolved = []
    for row in inventory['frames']:
        frame = row['frame']
        expected = [(part, *a[:2]) for part, key in ((1, 'first'), (2, 'second')) for a in row[key]]
        summary, records, gaps = frame_records(folder, frame, expected)
        frame_reports.append(summary)
        by_frame[frame] = list(records.values())
        unresolved.extend(gaps)
    joins = possible_joins(by_frame)
    for i, entry in enumerate(joins, start=1):
        entry['id'] = i
    statuses = Counter(row['second_block_status'] for row in frame_reports)
    return dict(
        version=1, maximum_frame_distance=MAX_FRAME_DISTANCE, frame_count=count,
        summary=dict(first_mac_crc_pass=sum(r['first_mac_crc_pass'] for r in frame_reports),
                     second_mac_crc_pass=sum(r['second_mac_crc_pass'] for r in frame_reports),
                     second_block_statuses=dict(statuses),
                     verified_words=sum(r['verified_words'] for r in frame_reports),
                     outer_records=sum(r['record_count'] for r in frame_reports),
                     unresolved_records=len(unresolved), joined_records=len(joins),
                     joined_frame_pairs=len({(j['source']['frame'], j['target']['frame']) for j in joins})),
        frames=frame_reports, unresolved_records=unresolved, joins=joins,
    )


def replay(folder, index, frame=None, sequence=None, join_id=None, bytes_out=None):
    if index.get('version') != 1:
        raise ValueError('Unrecognized join index version')
    selected = [
        entry for entry in index['joins']
        if (frame is None or frame in (entry['source']['frame'], entry['target']['frame']))
        and (sequence is None or sequence == entry['sequence'])
        and (join_id is None or join_id == entry['id'])
    ]
    if not selected:
        raise ValueError('No matching fragment join in the index')
    if bytes_out is not None and len(selected) != 1:
        raise ValueError('--bytes-out requires exactly one selected join')

    @lru_cache(maxsize=12)
    def records(f):
        return frame_records(folder, f)[1]

    for entry in selected:
        endpoints = []
        for key in ('source', 'target'):
            location = Location(**{k: entry[key][k] for k in Location.__dataclass_fields__})
            record = records(location.frame).get(location)
            if record is None:
                raise ValueError(f'Join {entry["id"]} lacks a verified {key} record')
            endpoints.append(record)
        a, b = endpoints
        result = splice(a, b)
        if (result is None or not 1 <= b.location.frame-a.location.frame <= MAX_FRAME_DISTANCE
                or (b.counter-a.counter) % 256 != 1):
            raise ValueError(f'Join {entry["id"]} failed the fragment checks')
        raw, identity = result
        if join_entry(a, b, raw, identity) != {k: v for k, v in entry.items() if k != 'id'}:
            raise ValueError(f'Join {entry["id"]} differs from the index')
        if bytes_out is not None:
            with bytes_out.open('xb') as handle:
                handle.write(raw)
    if frame is None and sequence is None and join_id is None:
        return dict(replayed=len(selected))
    return dict(replayed=len(selected), joins=selected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('build', help='Build a MAC layout and fragment index')
    create.add_argument('inventory', type=Path)
    create.add_argument('archive', type=Path)
    create.add_argument('output', type=Path)
    play = commands.add_parser('replay', help='Re-extract and verify joins from the original archive bytes')
    play.add_argument('archive', type=Path)
    play.add_argument('index', type=Path)
    play.add_argument('--frame', type=int, help='Select joins touching this zero-based frame')
    play.add_argument('--sequence', type=lambda text: f'{int(text, 16):04X}', help='Select by hexadecimal inner sequence')
    play.add_argument('--join', type=int, help='Select by index entry ID')
    play.add_argument('--bytes-out', type=Path, help='Write the bytes from one selected join to a new file')
    args = parser.parse_args()
    if args.command == 'build':
        inventory = json.loads(args.inventory.read_text(encoding='utf-8'))
        data = build(args.archive, inventory)
        args.output.write_text(json.dumps(data, indent=2)+'\n', encoding='utf-8')
        result = data['summary']
    else:
        data = json.loads(args.index.read_text(encoding='utf-8'))
        result = replay(args.archive, data, args.frame, args.sequence, args.join, args.bytes_out)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
