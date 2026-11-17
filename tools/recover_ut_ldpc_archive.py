#!/usr/bin/env python3
"""Retry failed codewords in UT archive symbol exports using fixed LDPC models."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import struct
import subprocess

import h5py
import numpy as np

from replay_ut_mcs92 import Codes, MODELS, SUBCARRIERS, chunk_gain
from verify_mcs35 import inverse_parity


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def save(path, report, arrays):
    staging = path.with_suffix('.partial.npz')
    np.savez(staging, **arrays)
    staging.replace(path.with_suffix('.npz'))
    staging = path.with_suffix('.partial.json')
    staging.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    staging.replace(path)


def scrambler():
    bits = [(0x01FB >> i) & 1 for i in range(14, -1, -1)]
    for _ in range(15, 16384):
        bits.append(bits[-14] ^ bits[-15])
    return np.asarray(bits, dtype=bool).reshape(-1, 8)[:, ::-1].ravel()


PN = scrambler()


def alphabets():
    level = np.arange(-3, 4, 2)/np.sqrt(10)
    square = (level[:, None]+1j*level).ravel()
    a16 = (square.real<0)+2*(square.imag<0)+4*(abs(square.real)<2/np.sqrt(10))+8*(abs(square.imag)<2/np.sqrt(10))
    a8 = np.asarray([1,5,4,7,0,6,2,3])
    square8 = square[[0,2,5,7,8,10,13,15]]
    quad = np.exp(1j*(np.pi/4+np.pi/2*np.arange(4)))
    quad = quad[[0,1,3,2]]
    model = read(MODELS/'mcs92_joint_model.json')
    xy = np.asarray(model['points_integer_iq'])
    cross = (xy[:,0]+1j*xy[:,1])/np.sqrt(20)
    label_order = np.asarray(model['bit_labels']) @ (1 << np.arange(5))
    return {'BPSK':np.array([1,-1]), 'QPSK':quad, '八点':square8[np.argsort(a8)],
            '16QAM':square[np.argsort(a16)], '交叉32点':cross[np.argsort(label_order)]}


class Profile:
    def __init__(self, mcs, catalog, constellation):
        spec = catalog.formats[mcs]
        self.mcs, self.k, self.n = mcs, spec['K'], spec['N']
        self.width = len(constellation).bit_length()-1
        self.q = spec['resources_per_unit']
        self.points = constellation
        self.weights = 1 << np.arange(self.width)
        self.labels = np.arange(len(constellation))[:,None]&self.weights != 0
        self.rows = catalog.checks(mcs)
        self.inverse = inverse_parity(self.rows, self.k)
        self.groups = []
        checks = defaultdict(list)
        for row in self.rows:
            checks[len(row)].append(row)
        self.groups = [np.asarray(group) for group in checks.values()]
        systematic = [[i for i in row if i<self.k] for row in self.rows]
        self.columns = np.full((len(systematic), max(map(len,systematic))), self.k, dtype=np.int32)
        for i, row in enumerate(systematic):
            self.columns[i,:len(row)] = row
        self.sparse = None
        self.extra = 0
        if mcs in (85, 88, 92):
            reference = read(MODELS/'mcs92_joint_model.json')
            rows = reference['sparse_rows']
            remove = 13056-self.k
            self.sparse = [[i-remove for i in row if i>=remove] for row in rows]
            self.extra = spec['D']-spec['M']

    def encode(self, raw):
        info = np.unpackbits(raw, bitorder='little') ^ PN[:self.k]
        rhs = np.bitwise_xor.reduce(np.r_[info,False][self.columns], axis=1)
        target = int.from_bytes(np.packbits(rhs, bitorder='little').tobytes(),'little')
        parity = np.fromiter(((target&row).bit_count()&1 for row in self.inverse), bool, self.n-self.k)
        return np.r_[info,parity]

    def unpack(self, word):
        return np.packbits(word[:self.k]^PN[:self.k],bitorder='little')

    def ideal(self, raw):
        word = self.encode(raw)
        full = word[:self.q*self.width - (self.q*self.width-self.n>0)*self.width]
        return self.points[full.reshape(-1,self.width)@self.weights]

    def llr(self, score):
        return np.column_stack([np.logaddexp.reduce(score[:,~bit], axis=1)-
                                np.logaddexp.reduce(score[:,bit], axis=1) for bit in self.labels.T]).ravel()[:self.n]


class Worker:
    def __init__(self, executable):
        self.process = subprocess.Popen([str(executable.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.loaded = set()

    def close(self):
        self.process.stdin.close()
        if self.process.wait():
            raise RuntimeError('Native LDPC decoder exited with an error')

    def decode(self, profile, score, pad, options, seed, extrinsic=None, prior=.85, damping=.6):
        name, sparse, limit, period, minsum, shuffle, scale, check = options
        sparse = sparse and profile.sparse is not None
        group = profile.mcs*2+sparse
        extra = profile.extra if sparse else 0
        n = profile.n+extra
        if group not in self.loaded:
            rows = profile.sparse if sparse else profile.rows
            offsets = np.r_[0,np.cumsum([len(row) for row in rows])].astype('<i4')
            columns = np.fromiter((i for row in rows for i in row),dtype='<i4')
            self.process.stdin.write(struct.pack('<7i',1,group,n,profile.k,profile.n,len(rows),len(columns)))
            self.process.stdin.write(offsets.tobytes()+columns.tobytes())
            self.loaded.add(group)
        constraints = None
        if pad is not None:
            constraints = (60*(1.-2*PN[pad:profile.k])).astype('<f4')
        self.process.stdin.write(struct.pack('<8i4f',2,group,profile.width if period else 0,limit,period,
                                            int(minsum)+2*shuffle,seed,
                                            int(constraints is not None)+2*int(extrinsic is not None),
                                            scale,prior,damping,check))
        if period:
            self.process.stdin.write(np.asarray(score,dtype='<f4').tobytes())
            if constraints is not None:
                expanded = np.zeros(n,dtype='<f4')
                expanded[pad:profile.k] = constraints
                self.process.stdin.write(expanded.tobytes())
        else:
            llr = profile.llr(score)*scale
            if constraints is not None:
                llr[pad:profile.k] = constraints
            tx = np.r_[llr[:profile.k],np.zeros(extra),llr[profile.k:]]
            self.process.stdin.write(tx.astype('<f4').tobytes())
        self.process.stdin.flush()
        reply = self.process.stdout.read(8)
        if len(reply)!=8:
            raise RuntimeError('Native decoder stopped before returning a result')
        left, iteration = struct.unpack('<2i',reply)
        if left:
            if extrinsic is not None:
                reply = self.process.stdout.read(profile.n*4)
                if len(reply)!=profile.n*4:
                    raise RuntimeError('Native decoder returned partial extrinsic likelihoods')
                extrinsic[:] = np.frombuffer(reply,dtype='<f4')
            return None,left
        reply = self.process.stdout.read(profile.n)
        if len(reply)!=profile.n:
            raise RuntimeError('Native decoder returned a partial codeword')
        word = np.frombuffer(reply,dtype=np.uint8).astype(bool)
        raw = profile.unpack(word)
        if not np.array_equal(profile.encode(raw),word):
            raise ValueError('Effective H re-encode rejected native decoder output')
        if pad is not None and raw[pad//8:].any():
            return None,profile.n
        hard = profile.llr(score)<0
        result = dict(reencoded=True,method=name,final_syndrome=0,iterations=iteration,
                      observed_parity_hard_agreement=float(np.mean(hard[profile.k:]==word[profile.k:])))
        return (raw,result),0


def smooth(gain, energy, radius):
    box = np.ones(2*radius+1)
    return (np.convolve(gain,box,mode='same')+1)/(np.convolve(energy,box,mode='same')+1)


def frame_channel(grid, training):
    if not training:
        return np.ones(SUBCARRIERS,dtype=complex),{}
    r,x = [np.concatenate(seq) for seq in zip(*(t for pair in training.values() for t in pair), strict=True)]
    y = grid[r]
    carrier = r % SUBCARRIERS
    corr = y*np.conj(x)
    gain = np.bincount(carrier,corr.real,minlength=SUBCARRIERS)+1j*np.bincount(carrier,corr.imag,minlength=SUBCARRIERS)
    energy = np.bincount(carrier,abs(x)**2,minlength=SUBCARRIERS)
    gain = smooth(gain,energy,6)
    gain[abs(gain)<.2] = 1
    return gain,training


def gain_calibrate(z, points, excluded=None):
    use = slice(None) if excluded is None else ~excluded
    z = z/np.sqrt(max(np.mean(abs(z[use])**2),1e-10))
    for _ in range(3):
        observed = z[use]
        nearest = points[abs(observed[:,None]-points).argmin(axis=1)]
        gain = np.vdot(nearest,observed)/np.vdot(nearest,nearest)
        if abs(gain)<.2:
            break
        z = z/gain
    return z


def expected_gain(z, points, positions, slope, excluded=None):
    adjusted = z.copy()
    groups = positions//SUBCARRIERS
    for group in np.unique(groups):
        selected = groups==group
        fit = selected if excluded is None else selected&~excluded
        if fit.sum()<75:
            continue
        x = z[fit]
        carrier_fit = positions[fit]%SUBCARRIERS/SUBCARRIERS-.5
        carrier = positions[selected]%SUBCARRIERS/SUBCARRIERS-.5
        design = np.column_stack((np.ones(len(x)),carrier_fit)) if slope else np.ones((len(x),1))
        prior = np.diag([45.,65.] if slope else [45.])
        reference = np.r_[1.,np.zeros(design.shape[1]-1)]
        gain = np.ones(len(x),dtype=complex)
        energy = abs(points)**2
        for _ in range(3):
            dist = abs(x[:,None]-gain[:,None]*points)**2
            p = np.exp(-(dist-dist.min(axis=1,keepdims=True))/.028)
            p /= p.sum(axis=1,keepdims=True)
            normal = design.T@(design*(p@energy)[:,None])+prior
            coeff = np.linalg.solve(normal,design.T@(np.conj(p@points)*x)+prior@reference)
            gain = design@coeff
        applied = coeff[0]+carrier*coeff[1] if slope else coeff[0]
        if np.max(abs(applied-1))<.4:
            adjusted[selected] /= applied
    return adjusted


def metric(profile, positions, grid, correction, training, slope=False, frequency_noise=False, excluded=None):
    points = profile.points
    local = expected_gain(grid[positions]/correction[positions%SUBCARRIERS],
                          points,positions,slope,excluded)
    global_grid = gain_calibrate(grid[positions],points,excluded)
    if profile.width==5:
        global_grid = chunk_gain(global_grid,points)
    plain = -abs(global_grid[:,None]-points)**2/.04
    pool = training.get(profile.width)
    if not pool:
        local = gain_calibrate(local,points,excluded)
        dist = abs(local[:,None]-points)**2
        use = slice(None) if excluded is None else ~excluded
        noise = np.clip(dist[use].min(axis=1).mean()*(1.5 if profile.width>=4 else 1.1),.012,.18)
        return -dist/noise,plain
    sample,truth = [np.concatenate(a) for a in zip(*pool,strict=True)]
    observed = grid[sample]/correction[sample%SUBCARRIERS]
    residual = observed-truth
    floor = max(np.median(abs(residual)**2)/1.386,.0035)
    noise = 1.
    if frequency_noise:
        carrier = sample%SUBCARRIERS
        count = np.bincount(carrier,minlength=SUBCARRIERS)
        energy = np.bincount(carrier,np.minimum(abs(residual)**2,12*floor),minlength=SUBCARRIERS)
        box = np.ones(21)
        prior = max(np.median(count)*6,15)
        spectrum = (np.convolve(energy,box,'same')+2*floor*prior)/(np.convolve(count,box,'same')+prior)
        noise = np.clip(spectrum[positions%SUBCARRIERS]/np.median(spectrum),.50,2.8)
    scores = []
    for point in points:
        matched = observed[truth==point]
        offset = (matched-point).sum()/(len(matched)+40)
        r = matched-point-offset
        re, im = r.real, r.imag
        cov = (np.array([[re@re,re@im],[re@im,im@im]])+np.eye(2)*80*floor)/(len(r)+80)
        cov = .9*cov+.1*np.eye(2)*floor
        err = local-point-offset
        a,b,c = cov[0,0], cov[0,1], cov[1,1]
        det = a*c-b*b
        dist = (c*err.real**2-2*b*err.real*err.imag+a*err.imag**2)/det
        scores.append(-.5*(dist/noise+np.log(det)))
    return np.asarray(scores).T,plain


QUICK = [
    ('local_channel_sparse_min_sum',True,55,0,True,0,1.,.83),
    ('local_channel_sparse_sum_product',True,70,0,False,0,1.,1.),
    ('blind_channel_sparse_sum_product',True,70,0,False,0,1.2,1.),
]
JOINT = [
    ('joint_sparse_demapping',True,105,4,False,0,1.05,1.),
    ('joint_sparse_demapping_shuffled',True,115,3,False,1,1.25,1.),
]
AUTHOR = [
    ('soft_with_author_hint',True,100,5,False,0,1.1,1.),
    ('author_hint_min_sum',True,105,0,True,1,1.15,.86),
]
FREQUENCY_NOISE = [
    ('frequency_noise_sparse',True,120,5,False,2,1.2,1.),
    ('frequency_noise_effective',False,115,4,False,1,.95,1.),
]


def author_grid(archive,number,calibrated):
    bins = np.r_[np.arange(512),np.arange(-512,0)]
    active = np.arange(2,1022)
    active = active[np.argsort(bins[active])]
    rows = active[~np.isin(active,np.r_[np.arange(488,496),np.arange(528,536)])]

    def sample(name):
        raw = archive[name][number,1:,:][:,rows].ravel()
        return raw['real']+1j*raw['imag']

    soft,hard = sample('yDataSoft'),sample('yDataDec')
    return calibrated*np.divide(hard,soft,out=np.ones_like(hard),where=abs(soft)>1.e-9)


def hinted_score(profile,points,metric,index):
    experimental = gain_calibrate(points,profile.points)
    likelihood = abs(experimental[:,None]-profile.points)**2
    excess = likelihood-likelihood.min(axis=1,keepdims=True)
    # The archive's decisions come from the same observation. The bounded
    # hint only supplies a different demapper initialization.
    weight = .2 if index==0 else .45
    return metric-weight*np.minimum(excess/.045,8.)


def frame_data(inventory, frames, number):
    row = inventory[number]
    path = frames/f'{number:04}.json'
    audit = read(path)
    with h5py.File(row['symbol_path'],'r') as src:
        raw = src['points'][()].ravel()
    grid = raw['real']+1j*raw['imag']
    return audit, grid, path.with_suffix('.npz')


def trained_points(data, baseline, profiles):
    group = defaultdict(list)
    for i,a in enumerate(data['allocations']):
        profile = profiles(a['mcs'])
        valid = baseline[f'valid_{i}'].nonzero()[0]
        if not len(valid):
            continue
        data_bytes = baseline[f'part_{i}']
        step = max(1,len(valid)//12)
        for j in valid[::step]:
            p = profile.ideal(data_bytes[j])
            start = a['r0']+profile.q*j
            group[profile.width].append((np.arange(start,start+len(p),2),p[::2]))
    return group


def initial_parts(data_path, seeds, number):
    with np.load(data_path) as parts:
        baseline = {key:parts[key] for key in parts.files}
    for folder in seeds:
        path = folder/f'{number:04}.json'
        if not path.exists():
            continue
        audit = read(path)
        with np.load(path.with_suffix('.npz')) as data:
            for proof in audit['words']:
                if not proof['reencoded'] or proof['final_syndrome']!=0:
                    raise ValueError(f'Unverified seed in {path}')
                i,j = proof['allocation'],proof['word']-1
                valid = baseline[f'valid_{i}']
                part = baseline[f'part_{i}']
                word = data[f'{i}_{j}']
                if valid[j] and not np.array_equal(part[j],word):
                    raise ValueError(f'Conflicting seed in {path}, allocation {i}, word {j+1}')
                part[j] = word
                valid[j] = True
    return baseline


def recover_frame(number, inventory, directory, worker, profiles, joint, seeds, author, frequency_noise):
    evidence, grid, data_path = frame_data(inventory,directory,number)
    baseline = initial_parts(data_path,seeds,number)
    if all(z.all() for key,z in baseline.items() if key.startswith('valid_')):
        return {}, {}
    author_decisions = author_grid(author,number,grid) if author is not None else None
    training = trained_points(evidence,baseline,profiles)
    gain,ref = frame_channel(grid,training)
    trials = QUICK
    if frequency_noise:
        trials = FREQUENCY_NOISE
    elif author_decisions is not None:
        trials = AUTHOR
    elif joint:
        trials = JOINT
    recovered, audit, failures = {}, [], []
    attempted = 0
    for i,a in enumerate(evidence['allocations']):
        missing = np.flatnonzero(~baseline[f'valid_{i}'])
        if not len(missing):
            continue
        profile = profiles(a['mcs'])
        for word in missing:
            start = a['r0']+profile.q*word
            p = a.get('padding_bytes',0)
            known = max(0,(a['quantity']-word)*profile.k-8*p)
            pad = known if known<profile.k else None
            positions = np.arange(start,start+profile.q)
            calibrated,baseline_metric = metric(profile,positions,grid,gain,ref,slope=joint,
                                               frequency_noise=frequency_noise)
            best = profile.n
            for index,settings in enumerate(trials):
                score = baseline_metric if not joint and index==2 else calibrated
                if author_decisions is not None:
                    score = hinted_score(profile,author_decisions[positions],score,index)
                result,left = worker.decode(profile,score,pad,settings,int(number*4096+start%4096))
                best = min(left,best)
                if result is not None:
                    raw,method = result
                    key = f'{i}_{word}'
                    recovered[key] = raw
                    audit.append(dict(allocation=i,word=int(word)+1,mcs=a['mcs'],r0=int(start),
                                      padding_aided=pad is not None,**method))
                    break
            else:
                failures.append(dict(allocation=i,word=int(word)+1,mcs=a['mcs'],best_failed_checks=best))
            attempted += 1
    return dict(frame=number,attempted=attempted,words=audit,remaining=failures),recovered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--decoder',type=Path,required=True)
    parser.add_argument('--first',type=int,required=True)
    parser.add_argument('--last',type=int,required=True)
    parser.add_argument('--frame-list',type=Path,help='Optional newline-delimited frame numbers to replay')
    parser.add_argument('--seed',type=Path,action='append',default=[])
    parser.add_argument('--symbols',type=Path,help='Folder containing mac_trace_symbols_*.mat')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--joint',action='store_true')
    mode.add_argument('--frequency-noise',action='store_true',help='Fit per-frequency noise for an alternate replay')
    mode.add_argument('--author-hints',type=Path,help="Try the author's quantized decisions as a bounded demapper hint")
    args = parser.parse_args()
    catalog = Codes()
    constellation = alphabets()
    cache = {}

    def profiles(mcs):
        if mcs not in cache:
            cache[mcs] = Profile(mcs,catalog,constellation[catalog.formats[mcs]['modulation']])
        return cache[mcs]

    inventory = read(args.inventory)['frames']
    if args.symbols:
        for row in inventory:
            row['symbol_path'] = args.symbols/f"mac_trace_symbols_{row['frame']:04}.mat"
    args.output.mkdir(exist_ok=True,parents=True)
    worker = Worker(args.decoder)
    author = h5py.File(args.author_hints,'r') if args.author_hints else None
    try:
        selected = range(args.first,args.last+1)
        if args.frame_list:
            targets = set(map(int,args.frame_list.read_text(encoding='utf-8').split()))
            selected = [f for f in selected if f in targets]
        for f in selected:
            output = args.output/f'{f:04}.json'
            if output.exists() and output.with_suffix('.npz').exists():
                continue
            audit, arrays = recover_frame(f,inventory,args.baseline,worker,profiles,
                                          args.joint or author is not None or args.frequency_noise,
                                          args.seed,author,args.frequency_noise)
            if not audit:
                audit = dict(frame=f,attempted=0,words=[])
            save(output,audit,arrays)
            if f==args.first or f==args.last or f%13==0 or arrays:
                print('FRAME',f,'recovered',len(arrays),'of',audit['attempted'],flush=True)
    finally:
        if author is not None:
            author.close()
        worker.close()


if __name__=='__main__':
    main()
