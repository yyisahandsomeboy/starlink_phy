#!/usr/bin/env python3
"""Check observed MCS dimensions, effective LDPC matrices and GF(2) re-encoding."""

import argparse
import hashlib
import json
from math import gcd
from pathlib import Path

import numpy as np

from verify_mcs35 import inverse_parity


MODELS = Path(__file__).resolve().parents[1] / 'matlab/protocol_receiver/models'
BITS_PER_SYMBOL = {'BPSK': 1, 'QPSK': 2, '八点': 3, '16QAM': 4, '交叉32点': 5}


def verify_matrix(matrix, digest):
    k, n = matrix['K'], matrix['N']
    rows = matrix['H_support_0based']
    content = json.dumps(rows, separators=(',', ':')).encode('ascii')
    if hashlib.sha256(content).hexdigest() != digest:
        raise ValueError('Matrix SHA-256 mismatch')
    if len(rows) != n - k or any(not row or row != sorted(set(row)) or min(row) < 0 or max(row) >= n for row in rows):
        raise ValueError('Invalid parity support')
    ap = inverse_parity(rows, k)
    rng = np.random.default_rng(71 + k)
    u = rng.integers(0, 2, k, dtype=np.int8).tolist()
    rhs = sum((sum(u[column] for column in row if column < k) & 1) << i for i, row in enumerate(rows))
    word = u + [(row & rhs).bit_count() & 1 for row in ap]
    if any(sum(word[j] for j in row) & 1 for row in rows):
        raise ValueError('Re-encoded word violates matrix')
    word[-1] ^= 1
    if not any(sum(word[j] for j in row) & 1 for row in rows):
        raise ValueError('Single-bit negative control passed')


def verify_format(row, matrix):
    n, k = row['N'], row['K']
    kb, m, s, d = (row[key] for key in ('K_B', 'M', 'S', 'D'))
    bits = BITS_PER_SYMBOL[row['modulation']]
    q = (n + bits - 1) // bits
    factor = gcd(n, k)
    if (n, k) != (matrix['N'], matrix['K']) or k != kb * m - s or n != k + 3 * m - d:
        raise ValueError(f"MCS {row['mcs']} has inconsistent code dimensions")
    if (q, q * bits - n, f'{k // factor}/{n // factor}') != (row['resources_per_unit'], row['spare_modulation_bits'], row['rate']):
        raise ValueError(f"MCS {row['mcs']} has inconsistent modulation dimensions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mcs', type=int, help='Check only the matrix for one MCS index')
    args = parser.parse_args()
    inventory = json.loads((MODELS / 'ar4ja_observed_mcs.json').read_text(encoding='utf-8'))
    matrices = json.loads((MODELS / inventory['matrices_path']).read_text(encoding='utf-8'))
    formats = [row for row in inventory['formats'] if args.mcs is None or row['mcs'] == args.mcs]
    if not formats:
        parser.error(f'MCS {args.mcs} is absent from the inventory')
    verified = set()
    for row in formats:
        digest = row['H_sha256']
        matrix = matrices[digest]
        verify_format(row, matrix)
        if digest not in verified:
            verify_matrix(matrix, digest)
            verified.add(digest)
    print(f'Validated {len(formats)} MCS formats and {len(verified)} effective matrices')


if __name__ == '__main__':
    main()
