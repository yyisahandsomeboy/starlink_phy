#!/usr/bin/env python3
"""Reproduce the UT 466/482 MCS 92 recovery from local symbol and seed exports."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

import h5py
import numpy as np

from verify_mcs35 import inverse_parity


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'matlab/protocol_receiver/models'
PROVENANCE = ROOT / 'provenance/mcs92'
N, K, Q, EXTRA = 16384, 13056, 3277, 768
WEIGHTS = 1 << np.arange(5)
SUBCARRIERS = 1004


class Codes:
    def __init__(self):
        self.catalog = json.loads((MODELS / 'ar4ja_observed_mcs.json').read_text(encoding='utf-8'))
        self.formats = {row['mcs']: row for row in self.catalog['formats']}
        self.matrices = json.loads((MODELS / self.catalog['matrices_path']).read_text(encoding='utf-8'))
        self.inverses = {}

    def checks(self, mcs):
        return self.matrices[self.formats[mcs]['H_sha256']]['H_support_0based']

    def encode(self, mcs, information):
        rows = self.checks(mcs)
        k = self.formats[mcs]['K']
        if mcs not in self.inverses:
            self.inverses[mcs] = inverse_parity(rows, k)
        rhs = 0
        for i, row in enumerate(rows):
            rhs |= (sum(int(information[column]) for column in row if column < k) & 1) << i
        parity = [(rhs & row).bit_count() & 1 for row in self.inverses[mcs]]
        return np.r_[information, np.asarray(parity, dtype=bool)]


def scrambler():
    mask = [(0x01FB >> j) & 1 for j in range(14, -1, -1)]
    for i in range(15, K):
        mask.append(mask[i-14] ^ mask[i-15])
    return np.asarray(mask, dtype=bool).reshape(-1, 8)[:, ::-1].ravel()


def read_grid(directory, frame):
    with h5py.File(directory / f'mac_trace_symbols_{frame:04}.mat') as source:
        raw = source['points'][()].ravel()
    return raw['real'] + 1j * raw['imag']


def save_graph(path, rows):
    offsets = np.r_[0, np.cumsum([len(row) for row in rows])]
    columns = np.fromiter((v for row in rows for v in row), dtype='<i4')
    with path.open('wb') as handle:
        np.asarray([N+EXTRA, K, N, len(rows), len(columns)], dtype='<i4').tofile(handle)
        offsets.astype('<i4').tofile(handle)
        columns.tofile(handle)


def training(frame, payload, codes, label_to_point, mask):
    positions, points, known = [], [], {}
    for allocation in frame['allocations']:
        mcs = allocation['mcs']
        if mcs not in (71, 75, 85, 88, 92):
            continue
        k = codes.formats[mcs]['K']
        key = f"{frame['frame']}_{mcs}"
        data = np.asarray(payload[key], dtype=np.uint8).ravel()
        if len(data) * 8 != k * allocation['quantity']:
            raise ValueError(f'{key} has the wrong number of information bytes')
        information = np.unpackbits(data, bitorder='little').reshape(-1, k) ^ mask[:k]
        for i, unit in enumerate(allocation['words']):
            if not unit['reencoded']:
                continue
            start = unit['r0']
            word = codes.encode(mcs, information[i])
            coords = np.arange(start, start+Q-1)
            ideal = label_to_point[word[:16380].reshape(-1, 5) @ WEIGHTS]
            if mcs == 92:
                known[unit['word']] = (coords, ideal)
            else:
                positions.append(coords)
                points.append(ideal)
    return np.concatenate(positions), np.concatenate(points), known


def select_training(base, ordinal, count):
    positions, points, recovered = base
    nearest = sorted(recovered, key=lambda word: abs(word-ordinal))[:count]
    return (np.concatenate([positions, *[recovered[j][0] for j in nearest]]),
            np.concatenate([points, *[recovered[j][1] for j in nearest]]))


def channel_fit(positions, truth, observed, points, radius):
    carriers = positions % SUBCARRIERS
    ideal = points[truth]
    weights = np.conj(ideal) * observed
    box = np.ones(2*radius+1)
    total = np.bincount(carriers, weights=abs(ideal)**2, minlength=SUBCARRIERS)
    corr = (np.bincount(carriers, weights=weights.real, minlength=SUBCARRIERS)
            + 1j*np.bincount(carriers, weights=weights.imag, minlength=SUBCARRIERS))
    gain = np.convolve(corr, box, mode='same') / np.convolve(total, box, mode='same')
    equalized = observed / gain[carriers]
    means = np.array([equalized[truth == i].mean() for i in range(len(points))])
    residual = equalized - means[truth]
    frequency = np.bincount(carriers, weights=abs(residual)**2, minlength=SUBCARRIERS)
    counts = np.bincount(carriers, minlength=SUBCARRIERS)
    noise_box = np.ones(25)
    variance = np.convolve(frequency, noise_box, mode='same') / np.convolve(counts, noise_box, mode='same')
    variance = np.clip(variance/variance.mean(), .6, 2.)
    cov = np.array([np.cov([residual[truth == i].real, residual[truth == i].imag])
                    for i in range(len(points))])
    return gain, means, variance, np.linalg.inv(cov), np.log(np.linalg.det(cov))


def chunk_gain(z, constellation):
    z = z.copy()
    for start in range(0, len(z), 384):
        chunk = z[start:start+384]
        for _ in range(2):
            distances = abs(chunk[:, None]-constellation)**2
            nearest = distances.argmin(axis=1)
            selection = distances[np.arange(len(chunk)), nearest] < .042
            x, y = constellation[nearest[selection]], chunk[selection]
            if len(x) < 20:
                continue
            xm, ym = x.mean(), y.mean()
            gain = np.vdot(x-xm, y-ym) / np.sum(abs(x-xm)**2)
            dc = ym-xm*gain
            if abs(gain-1) <= .18 and abs(dc) <= .12:
                chunk[:] = (chunk-dc)/gain
    return z


def probability(cost):
    p = np.exp(cost-cost.max(axis=1, keepdims=True))
    return p/p.sum(axis=1, keepdims=True)


def metric(grid, start, train, constellation, label_to_point, radius, slot_noise=False):
    positions, truth = train
    gain, means, variance, inverse, logdet = channel_fit(positions, truth, grid[positions], constellation, radius)
    r = start+np.arange(Q)
    rows = r % SUBCARRIERS
    z = grid[r] / gain[rows]

    def distance(corrected, selected):
        d = corrected[:, None]-means
        m = inverse[:, 0, 0]*d.real**2 + 2*inverse[:, 0, 1]*d.real*d.imag + inverse[:, 1, 1]*d.imag**2
        return m/variance[rows[selected], None]

    if not slot_noise:
        d = distance(chunk_gain(z, constellation), slice(None))
        metric = -.5*(d+logdet)
    else:
        metric = np.empty((Q, len(means)))
        norm = abs(means)**2
        for slot in np.unique(r//SUBCARRIERS):
            selected = r//SUBCARRIERS == slot
            zg = z[selected]
            freq = rows[selected]/SUBCARRIERS-.5
            if len(zg) >= 120:
                design = np.column_stack((np.ones(len(zg)), freq))
                for _ in range(2):
                    p = probability(-abs(zg[:, None]-means)**2/.036)
                    basis = design.T@(design*(p@norm)[:, None])+np.diag([1., 32.])
                    g = np.linalg.solve(basis, design.T@(np.conj(p@means)*zg)+[1., 0.])
                    zg = zg/(.22+.78*(design@g))
            gain_slot, scale = 1., 1.
            var = variance[rows[selected]]
            for _ in range(5):
                d = distance(zg/gain_slot, selected)
                if len(zg) < 50:
                    break
                p = probability(-.5*(d/scale+logdet))
                scale = np.clip((.5*(p*d).sum()+125.)/(len(zg)+125.), .5, 1.85)
                gain_slot = (np.vdot(p@means, zg/var)+100.)/(np.sum((p@norm)/var)+100.)
            metric[selected] = -.5*(d/scale+logdet)
    return metric[:, label_to_point] - metric.max(axis=1, keepdims=True)


def native(executable, work, metric_values, prior, damping):
    metric_values.astype('<f4').tofile(work / 'symbols.f32')
    command = [str(executable), 'graph.bin', 'symbols.f32', 'belief.f32',
               '140', '2', '1.0', str(prior), str(damping), '1.0', '0', '0', '0', '0']
    output = subprocess.run(command, cwd=work, check=True, text=True, capture_output=True)
    failed, iterations = map(int, output.stdout.split())
    if failed:
        raise ValueError(f'Joint replay left {failed} unsatisfied checks')
    beliefs = np.fromfile(work / 'belief.f32', dtype='<f4')
    if beliefs.shape != (N+EXTRA,):
        raise ValueError('Unexpected joint decoder output length')
    return np.r_[beliefs[:K], beliefs[K+EXTRA:]] < 0, iterations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--symbols', required=True, type=Path, help='Directory with calibrated MATLAB symbol exports')
    parser.add_argument('--seed', required=True, type=Path, help='Local NPZ of previously verified systematic bytes')
    parser.add_argument('--decoder', required=True, type=Path, help='Compiled mcs92_joint_decoder')
    parser.add_argument('--out', required=True, type=Path, help='New NPZ with recovered transmitted bits and systematic bytes')
    args = parser.parse_args()
    if args.out.exists():
        parser.error('--out must not already exist')
    model = json.loads((MODELS / 'mcs92_joint_model.json').read_text(encoding='utf-8'))
    assert (model['N'], model['K'], model['Q'], model['punctured_kept']) == (N, K, Q, EXTRA)
    iq = np.asarray(model['points_integer_iq'])
    points = (iq[:, 0]+1j*iq[:, 1])/np.sqrt(20)
    mapping = np.argsort(np.asarray(model['bit_labels'])@WEIGHTS)
    codes = Codes()
    mask = scrambler()
    frames = json.loads((PROVENANCE / 'joint_seed_layout.json').read_text(encoding='utf-8'))
    grids = {f: read_grid(args.symbols, f) for f in (466, 467, 482)}
    results, recovered = {}, {}
    with TemporaryDirectory() as directory, np.load(args.seed) as data:
        work = Path(directory)
        save_graph(work / 'graph.bin', model['sparse_rows'])
        for frame in frames:
            f = frame['frame']
            base = training(frame, data, codes, mapping, mask)
            allocation, = [a for a in frame['allocations'] if a['mcs'] == 92]
            pending = [u for u in allocation['words'] if not u['reencoded']]
            delayed = 7 if f == 466 else 29
            for unit in sorted(pending, key=lambda u: u['word'] == delayed):
                j, start = unit['word'], unit['r0']
                if j == delayed:
                    base[-1].update(recovered[f])
                    values = metric(grids[f], start, select_training(base, j, 8), points, mapping, 4, True)
                    prior, damping = .9, .55
                elif (f, j) == (466, 16):
                    train = select_training(base, j, len(base[-1]))
                    values = sum(weight*metric(grids[source], start, train, points, mapping, 9)
                                 for weight, source in ((.35, 466), (.65, 467)))
                    prior, damping = .85, .6
                else:
                    values = metric(grids[f], start, select_training(base, j, 5), points, mapping, 6)
                    prior, damping = .8, .5
                word, iterations = native(args.decoder.resolve(), work, values, prior, damping)
                if not np.array_equal(word, codes.encode(92, word[:K])):
                    raise ValueError(f'Frame {f} word {j} failed effective-matrix re-encoding')
                plain = np.packbits(word[:K] ^ mask, bitorder='little')
                label = f'{f}_{j}'
                results[label] = word
                results[label+'_bytes'] = plain
                recovered.setdefault(f, {})[j] = (np.arange(start, start+Q-1), mapping[word[:16380].reshape(-1, 5)@WEIGHTS])
                print(f'{label} {iterations} iterations, SHA256 {hashlib.sha256(plain).hexdigest()}')
    assert len(results) == 24
    np.savez_compressed(args.out, **results)


if __name__ == '__main__':
    main()
