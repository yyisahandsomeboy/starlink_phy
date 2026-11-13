#!/usr/bin/env python3
"""Verify the committed MCS 35 LDPC model or replay local symbol exports."""

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

import numpy as np


DEFAULT_MODEL = Path(__file__).resolve().parents[1] / 'matlab/protocol_receiver/models/mcs35_complete_16384_model.json'
REVERSE_BYTE = bytes(int(f'{byte:08b}'[::-1], 2) for byte in range(256))
CRC_POLY, CRC_INIT = 0x1F21C5, 0xFFFFFF
SCALES = (.04, .025, .08, .015)


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def inverse_parity(rows, k):
    """Invert H_p over GF(2), with each row packed into a Python integer."""
    parity = [tuple(i - k for i in row if i >= k) for row in rows]
    m = len(parity)
    mask = (1 << m) - 1
    basis = [0] * m
    for j, cols in enumerate(parity):
        value = (1 << (m + j)) | sum(1 << i for i in cols)
        while pivot := value & mask:
            i = (pivot & -pivot).bit_length() - 1
            if not basis[i]:
                basis[i] = value
                break
            value ^= basis[i]
        else:
            raise ValueError('H_p is rank-deficient')

    inverse = [0] * m
    for i in range(m - 1, -1, -1):
        value = basis[i] >> m
        remaining = (basis[i] & mask) ^ (1 << i)
        while remaining:
            pivot = remaining & -remaining
            value ^= inverse[pivot.bit_length() - 1]
            remaining ^= pivot
        inverse[i] = value

    for j, cols in enumerate(parity):
        product = 0
        for i in cols:
            product ^= inverse[i]
        if product != 1 << j:
            raise ValueError('H_p inverse check failed')
    return inverse


class Model:
    def __init__(self, path):
        raw = path.read_bytes()
        model = json.loads(raw)
        self.sha256 = hashlib.sha256(raw).hexdigest()
        self.n, self.k = model['N'], model['K']
        self.rows = model['H_support_0based']
        if (model['id'], self.n, self.k, model['rank'], len(self.rows)) != (35, 16384, 9472, 6912, 6912):
            raise ValueError('Unexpected MCS 35 model dimensions')
        by_degree = defaultdict(list)
        for row in self.rows:
            if len(row) < 2 or len(set(row)) != len(row) or min(row) < 0 or max(row) >= self.n:
                raise ValueError('Invalid parity-check support')
            by_degree[len(row)].append(row)
        self.groups = [np.array(by_degree[degree], dtype=np.int32) for degree in sorted(by_degree)]
        self.inverse = inverse_parity(self.rows, self.k)
        iq = np.asarray(model['alphabet_scaled_by_sqrt10'])
        labels = np.asarray(model['bit_labels'])
        if iq.shape != (8, 2) or len(set(map(tuple, iq))) != 8:
            raise ValueError('Invalid constellation coordinates')
        self.points = (iq[:, 0] + 1j * iq[:, 1]) / np.sqrt(10)
        if labels.shape != (8, 3) or set(labels.ravel()) != {0, 1}:
            raise ValueError('Invalid constellation bit labels')
        self.labels = labels.astype(bool)
        label_numbers = self.labels @ [1, 2, 4]
        if len(set(label_numbers)) != 8:
            raise ValueError('Constellation labels must be unique')
        self.point_for_label = self.points[np.argsort(label_numbers)]
        self.tail = np.asarray(model['trailing_modulation_slot_values'], dtype=bool)
        if model['trailing_modulation_slots_outside_LDPC'] != 2 or self.tail.tolist() != [False, False]:
            raise ValueError('Expected two zero-valued trailing slots')
        self.symbols = (self.n + len(self.tail)) // 3

    def syndrome(self, bits):
        return int(sum(np.bitwise_xor.reduce(bits[group], axis=1).sum() for group in self.groups))

    def encode(self, bits):
        rhs = 0
        for j, row in enumerate(self.rows):
            rhs |= (sum(int(bits[i]) for i in row if i < self.k) % 2) << j
        parity = np.array([(rhs & row).bit_count() % 2 for row in self.inverse], dtype=bool)
        return np.r_[bits, parity]

    def likelihood(self, symbols, scale):
        distance = abs(symbols[:, None] - self.points) ** 2 / scale
        values = []
        for one in self.labels.T:
            a, b = distance[:, ~one], distance[:, one]
            low, high = a.min(axis=1), b.min(axis=1)
            values.append(high - low + np.log(np.exp(low[:, None] - a).sum(axis=1))
                          - np.log(np.exp(high[:, None] - b).sum(axis=1)))
        return np.column_stack(values).ravel()

    def decode(self, likelihood):
        """Normalized min-sum, stopping only when the full syndrome is zero."""
        bits = likelihood < 0
        initial = remaining = self.syndrome(bits)
        incoming = [likelihood[group] for group in self.groups]
        iterations = 0
        while remaining and iterations < 90:
            posterior = likelihood.copy()
            outgoing = []
            for group, q in zip(self.groups, incoming):
                signs = np.where(q < 0, -1, 1)
                magnitudes = abs(q)
                least = np.partition(magnitudes, 1, axis=1)[:, :2]
                minimum = np.broadcast_to(least[:, :1], q.shape).copy()
                minimum[np.arange(len(q)), magnitudes.argmin(axis=1)] = least[:, 1]
                messages = .8 * signs.prod(axis=1)[:, None] * signs * minimum
                outgoing.append(messages)
                posterior += np.bincount(group.ravel(), weights=messages.ravel(), minlength=self.n)
            bits = posterior < 0
            remaining = self.syndrome(bits)
            incoming = [np.clip(posterior[g] - r, -50, 50) for g, r in zip(self.groups, outgoing)]
            iterations += 1
        return bits, dict(initial=initial, final=remaining, iterations=iterations)

    def demodulate(self, symbols):
        power = float(np.mean(abs(symbols) ** 2))
        if not np.isfinite(power) or power <= 0:
            raise ValueError('Invalid symbol power')
        symbols = symbols / np.sqrt(power)
        for _ in range(3):
            ideal = self.points[abs(symbols[:, None] - self.points).argmin(axis=1)]
            gain = np.vdot(ideal, symbols) / np.vdot(ideal, ideal)
            if abs(gain) < np.finfo(float).eps:
                raise ValueError('Could not estimate a nonzero constellation gain')
            symbols = symbols / gain
        best = None
        for scale in SCALES:
            likelihood = self.likelihood(symbols, scale)
            word, stats = self.decode(likelihood[:self.n])
            if best is None or stats['final'] < best[1]['final']:
                best = word, dict(stats, scale=scale, tail_slots=(likelihood[self.n:] < 0).astype(int).tolist())
            if stats['final'] == 0:
                break
        return best


def descramble(bits):
    mask = [(0x01FB >> i) & 1 for i in range(14, -1, -1)]
    for i in range(len(mask), len(bits)):
        mask.append(mask[i - 14] ^ mask[i - 15])
    aligned_mask = np.asarray(mask, dtype=bool).reshape(-1, 8)[:, ::-1].ravel()
    return np.packbits(bits ^ aligned_mask, bitorder='little').tobytes()


def crc24(data):
    state = CRC_INIT
    for byte in data:
        state ^= byte << 16
        for _ in range(8):
            carry = state >> 23
            state = ((state << 1) & 0xFFFFFF) ^ (CRC_POLY if carry else 0)
    return state


def check_mac(data):
    length = int.from_bytes(data[:2], 'little')
    if not (8 <= length <= len(data) and data[2:3] == b'\x07'):
        return {'pass': False, 'length_candidate': length}
    header = data[:length]
    wire = header.translate(REVERSE_BYTE)
    received = int.from_bytes(wire[-3:], 'big')
    calculated = crc24(wire[:-3])
    return {'pass': calculated == received, 'length': length, 'received_crc': f'{received:06X}',
            'calculated_crc': f'{calculated:06X}', 'header_sha256': hashlib.sha256(header).hexdigest()}


def self_check(model):
    body = bytes.fromhex('08 00 07 EA 07')
    check = crc24(body.translate(REVERSE_BYTE)).to_bytes(3, 'big')
    header = body + check.translate(REVERSE_BYTE)
    rng = np.random.default_rng(3516384)
    data = header + rng.bytes(model.k // 8 - len(header))
    mask = descramble(np.zeros(model.k, dtype=bool))
    bits = np.unpackbits(np.frombuffer(data, dtype=np.uint8), bitorder='little') ^ np.unpackbits(
        np.frombuffer(mask, dtype=np.uint8), bitorder='little')
    word = model.encode(bits)
    labels = np.r_[word, model.tail].reshape(-1, 3) @ [1, 2, 4]
    decoded, stats = model.demodulate(model.point_for_label[labels])
    parity_error = word.copy()
    parity_error[-1] ^= True
    bad_header = bytearray(header)
    bad_header[-1] ^= 1
    if (stats['final'] or not np.array_equal(decoded, word) or not model.syndrome(parity_error)
            or crc24(b'123456789') != 0x95B528 or not check_mac(descramble(decoded[:model.k]))['pass']
            or check_mac(bad_header)['pass']):
        raise ValueError('Synthetic LDPC or MAC CRC control failed')
    return dict(roundtrip=True, parity_error_rejected=True, mac_crc_error_rejected=True)


def replay(path, model):
    import h5py

    with h5py.File(path, 'r') as source:
        metadata = source['mcs35Meta']
        points = source['mcs35Points']
        if metadata.ndim != 2 or metadata.shape[1] != 4 or points.shape != (len(metadata), model.symbols):
            raise ValueError(f'Unexpected export dimensions in {path.name}')
        for i, (frame, r0, word, quantity) in enumerate(metadata[:].astype(int)):
            raw = points[i]
            symbols = raw['real'] + 1j * raw['imag']
            bits, stats = model.demodulate(symbols)
            reencoded = not stats['final'] and np.array_equal(bits, model.encode(bits[:model.k]))
            row = dict(frame=int(frame), r0=int(r0), word=int(word), quantity=int(quantity),
                       fit=bool(frame <= 480), reencoded=bool(reencoded), **stats)
            if word == 1 and reencoded:
                row['mac'] = check_mac(descramble(bits[:model.k]))
            yield row


def compare_expected(report, expected_path):
    expected = json.loads(expected_path.read_text(encoding='utf-8'))
    if (report['model_sha256'], report['N'], report['K']) != (expected['model_sha256'], expected['N'], expected['K']):
        raise ValueError('Model hash or dimensions differ from the expected evidence')
    coords = ('frame', 'r0', 'word', 'quantity')
    word_key = lambda row: tuple(row[key] for key in coords)
    index = {word_key(row): row for row in expected['trials']}
    trials = report['trials']
    if len(trials) != len(index) or {word_key(row) for row in trials} != index.keys():
        raise ValueError('Replay and expected evidence cover different codeword coordinates')
    for row in trials:
        known = index[word_key(row)]
        if any(row[key] != known[key] for key in ('fit', 'initial', 'final', 'reencoded', 'tail_slots')):
            raise ValueError(f'LDPC verification differs at {word_key(row)}')
        if 'mac' in known:
            mac = known['mac']
            expected_mac = {key: mac[key] for key in ('pass', 'length', 'received_crc', 'calculated_crc')}
            expected_mac['header_sha256'] = hashlib.sha256(bytes.fromhex(mac['header_hex'])).hexdigest()
            if row.get('mac') != expected_mac:
                raise ValueError(f'MAC verification differs at {word_key(row)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, default=DEFAULT_MODEL, help='Effective MCS 35 model JSON')
    parser.add_argument('--input', type=Path, nargs='+', default=[], help='Local record80_geo_words_*.mat files')
    parser.add_argument('--expected', type=Path, help='Compare a full replay with published verification JSON')
    parser.add_argument('--output', type=Path, help='Write replay results as JSON')
    args = parser.parse_args()
    if args.expected and not args.input:
        parser.error('--expected requires --input')
    model = Model(args.model)
    trials = [row for path in args.input for row in replay(path, model)]
    report = dict(N=model.n, K=model.k, model_sha256=model.sha256, controls=self_check(model),
                  sources=[dict(filename=path.name, sha256=file_sha256(path)) for path in args.input],
                  trials=trials)
    if args.input and not trials:
        parser.error('No codewords found in the supplied exports')
    if args.expected:
        compare_expected(report, args.expected)
        report['matches_expected_evidence'] = True
    if trials:
        first_words = [row for row in trials if row['word'] == 1]
        report['counts'] = dict(words=len(trials), reencoded=sum(row['reencoded'] for row in trials),
                                mac_headers=len(first_words), mac_crc24_passed=sum(
                                    row.get('mac', {}).get('pass', False) for row in first_words))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: val for key, val in report.items() if key != 'trials'}, indent=2))
    return int(any(not row['reencoded'] or (row['word'] == 1 and not row.get('mac', {}).get('pass', False))
                   for row in trials))


if __name__ == '__main__':
    raise SystemExit(main())
