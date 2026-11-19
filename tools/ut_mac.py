"""Parse the observed UT MAC headers, allocation lengths and records."""
from dataclasses import dataclass

from verify_mcs35 import REVERSE_BYTE, crc24


EMPTY_HEADER_PREFIX = bytes.fromhex('08 00 88 07 FF')


def check_header(data, block):
    length = int.from_bytes(data[:2], 'little')
    if block == 1:
        kind = 'first' if data[2:5] == b'\x01\xf0\x0f' else None
    elif data.startswith(EMPTY_HEADER_PREFIX):
        kind = 'short_second'
    else:
        kind = 'second' if data[2:3] == b'\x07' else None
    if kind is None or not 8 <= length <= len(data):
        return dict(format=kind, length=length, crc_pass=False)
    wire = data[:length].translate(REVERSE_BYTE)
    calculated = crc24(wire[:-3])
    received = int.from_bytes(wire[-3:], 'big')
    return dict(format=kind, length=length, crc_pass=calculated == received,
                calculated_crc=f'{calculated:06X}', received_crc=f'{received:06X}')


def descriptor_fields(data, header_bytes):
    end = header_bytes - 3
    pos = 5
    lengths = []
    padding = []
    while pos + 2 <= end:
        value = int.from_bytes(data[pos:pos+2], 'little')
        tag = value & 15
        if tag == 3 and pos + 5 <= end:
            size = int.from_bytes(data[pos+2:pos+5], 'little')
            if not size or size & 15:
                break
            lengths.append(size >> 4)
            pos += 5
        elif tag == 7:
            padding.append(value >> 4)
            pos += 2
        elif tag == 15 and all(b == 255 for b in data[pos+2:end]):
            return lengths, [*padding, value >> 4]
        else:
            break
    raise ValueError('invalid regular MAC length table')


@dataclass(frozen=True)
class AllocationLayout:
    record_start: int
    record_lengths: tuple[int, ...]
    padding_start: int
    padding_bytes: int


def parse_second_block(prefix, plan):
    """Return the CRC result, layout status and per-allocation byte ranges.

    prefix contains consecutive verified bytes from the first allocation.
    plan holds (MCS, codeword count, information bytes per codeword).
    """
    header = check_header(prefix, 2)
    if not header['crc_pass']:
        return header, 'header_crc_unavailable_or_failed', ()
    length = header['length']
    if header['format'] == 'short_second':
        if tuple(plan) != ((5, 1, 128),):
            return header, 'short_header_unrecognized_allocation', ()
        if len(prefix) != 128:
            return header, 'short_header_padding_unverified', ()
        if any(prefix[length:]):
            return header, 'short_header_nonzero_padding', ()
        return header, 'empty', (AllocationLayout(length, (), length, 128-length),)
    try:
        sizes, padding = descriptor_fields(prefix, length)
    except ValueError:
        return header, 'invalid_length_table', ()
    if len(padding) != len(plan):
        return header, 'invalid_length_table', ()
    layouts = []
    cursor = 0
    for i, ((_, count, width), pad) in enumerate(zip(plan, padding, strict=True)):
        start = length if i == 0 else 0
        end = count * width - pad
        capacity = end - start
        if capacity <= 0:
            return header, 'invalid_length_table', ()
        records = []
        used = 0
        while cursor < len(sizes) and used < capacity:
            records.append(sizes[cursor])
            used += sizes[cursor]
            cursor += 1
        if used > capacity or (i < len(plan)-1 and used != capacity):
            return header, 'invalid_length_table', ()
        if used < capacity:
            records.append(capacity-used)
        layouts.append(AllocationLayout(start, tuple(records), end, pad))
    if cursor != len(sizes):
        return header, 'invalid_length_table', ()
    return header, 'payload', tuple(layouts)


@dataclass(frozen=True)
class RecordLayout:
    counter: int
    flags: int
    header_bytes: int
    span_lengths: tuple[int, ...]

    @property
    def length(self):
        return self.header_bytes + sum(self.span_lengths)


def record_layout(data):
    if len(data) < 4 or data[0] not in (0x80, 0x90, 0xB8):
        return None
    word = int.from_bytes(data[2:4], 'little')
    flags = word & 31
    first_length = word >> 5
    if flags & 16:
        if first_length and 4 + first_length <= len(data):
            return RecordLayout(data[1], flags, 4, (first_length,))
        return None
    lengths = [first_length]
    size = first_length
    for bit in range(32, 8*len(data)-11, 12):
        index, shift = divmod(bit, 8)
        entry = (int.from_bytes(data[index:index+2], 'little') >> shift) & 0xfff
        length = entry >> 1
        header_bytes = (bit + 19) // 8
        size += length
        if not length or header_bytes + size > len(data):
            return None
        lengths.append(length)
        if entry & 1:
            if (bit+12) % 8 and data[header_bytes-1] & 0xf0:
                return None
            return RecordLayout(data[1], flags, header_bytes, tuple(lengths))
    return None
