#!/usr/bin/env python3
"""Test equal-geometry UT frames for independently corroborated codeword repeats."""
import argparse
from collections import defaultdict
from pathlib import Path

from recover_ut_ldpc_archive import (
    Codes, JOINT, Profile, Worker, alphabets, frame_channel, frame_data, gain_calibrate,
    initial_parts, metric, np, read, save, trained_points,
)


def same_layout(row):
    return tuple((m,n,q) for m,n,_,_,q in row['first']),tuple(tuple(d) for d in row['second'])


def footprint(profile, grid, start):
    observed = gain_calibrate(grid[start:start+profile.q],profile.points)
    distance = abs(observed[:,None]-profile.points)**2
    ids = distance.argmin(axis=1)
    return profile.labels[ids].ravel()[:profile.n]


def combine(f,g,i,j,profile,evidence,signals,observations,worker):
    results = []
    pads = []
    for n in (f,g):
        a = evidence[n]['allocations'][i]
        start = a['r0']+j*profile.q
        grid,gain,training = signals[n]
        calibrated,_ = metric(profile,np.arange(start,start+profile.q),grid,gain,training,slope=True)
        results.append(calibrated)
        offset = max(0,(a['quantity']-j)*profile.k-8*a.get('padding_bytes',0))
        if offset<profile.k:
            pads.append(offset)
    pad = pads[0] if pads and all(x==pads[0] for x in pads) else None
    for index,(fraction,options) in enumerate(zip((.5,.33),JOINT,strict=True)):
        score = fraction*results[0]+(1-fraction)*results[1]
        settings = ('repeat_combined_soft',*options[1:])
        value,_ = worker.decode(profile,score,pad,settings, f*4096+g+index)
        if value is None:
            continue
        raw,status = value
        word = profile.encode(raw)
        agreement = [float((word[profile.k:]==truth[profile.k:]).mean()) for truth in observations]
        if min(agreement)>=.82:
            return raw,dict(**status,source_frame=g,repeat_parity_agreements=agreement)
    return None


def repeats(inventory, baseline, stages, output, worker):
    catalog = Codes()
    points = alphabets()
    profile_cache = {}
    groups = defaultdict(list)
    for row in inventory:
        groups[same_layout(row)].append(row['frame'])
    output.mkdir(exist_ok=True)
    def profile(m):
        if m not in profile_cache:
            profile_cache[m] = Profile(m,catalog,points[catalog.formats[m]['modulation']])
        return profile_cache[m]

    for group in groups.values():
        if len(group)<2:
            continue
        evidence = {}
        decoded = defaultdict(dict)
        missing = defaultdict(dict)
        signals = {}
        for f in group:
            audit,grid,path = frame_data(inventory,baseline,f)
            parts = initial_parts(path,stages,f)
            evidence[f] = audit
            for i,a in enumerate(audit['allocations']):
                p = profile(a['mcs'])
                for j,valid in enumerate(parts[f'valid_{i}']):
                    key = i,j
                    start = a['r0']+j*p.q
                    if valid:
                        raw = parts[f'part_{i}'][j]
                        decoded[key][f] = p.encode(raw),raw
                    else:
                        missing[f][key] = footprint(p,grid,start)
            if worker and missing[f]:
                signals[f] = grid,parts
        combined = {}
        for f in group:
            words = []
            arrays = {}
            for (i,j),observed in missing[f].items():
                matches = []
                a = evidence[f]['allocations'][i]
                p = profile_cache[a['mcs']]
                for source,(bits,raw) in decoded[i,j].items():
                    agree = bits==observed
                    parity_agreement = float(agree[p.k:].mean())
                    overall_agreement = float(agree.mean())
                    if parity_agreement>=.82 and overall_agreement>=.85:
                        matches.append((parity_agreement,overall_agreement,source,raw))
                if matches:
                    if any(not np.array_equal(matches[0][3],x[3]) for x in matches[1:]):
                        continue
                    parity,overall,source,raw = max(matches,key=lambda x:x[:2])
                    details = dict(method='repeat_verified_codeword',reencoded=True,
                                   final_syndrome=0,iterations=None,source_frame=source,
                                   observed_parity_hard_agreement=parity,
                                   observed_word_hard_agreement=overall)
                elif worker:
                    candidates = []
                    for g in group:
                        if g==f or (other:=missing[g].get((i,j))) is None:
                            continue
                        agree = observed==other
                        if agree[p.k:].mean()>=.9 and agree.mean()>=.9:
                            candidates.append((float(agree.mean()),g,other))
                    if not candidates:
                        continue
                    _,g,other = max(candidates,key=lambda x:x[0])
                    key = min(f,g),max(f,g),i,j
                    if key not in combined:
                        for n in (f,g):
                            if len(signals[n])==2:
                                grid,parts = signals[n]
                                gain,training = frame_channel(grid,trained_points(evidence[n],parts,profile))
                                signals[n] = grid,gain,training
                        combined[key] = combine(f,g,i,j,p,evidence,signals,(observed,other),worker)
                    if combined[key] is None:
                        continue
                    raw,details = combined[key]
                    details = dict(details,source_frame=g)
                else:
                    continue
                arrays[f'{i}_{j}'] = raw
                words.append(dict(allocation=i,word=j+1,r0=a['r0']+j*p.q,mcs=p.mcs,**details))
            if words:
                save(output/f'{f:04}.json',dict(frame=f,attempted=len(missing[f]),words=words),arrays)
                print('FRAME',f,'observed matches',len(words),flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--stage',type=Path,action='append',default=[])
    parser.add_argument('--decoder',type=Path,help='Combine closely matching soft observations')
    parser.add_argument('--symbols',type=Path,help='Folder containing mac_trace_symbols_*.mat')
    args = parser.parse_args()
    inventory = read(args.inventory)['frames']
    if args.symbols:
        for row in inventory:
            row['symbol_path'] = args.symbols/f"mac_trace_symbols_{row['frame']:04}.mat"
    worker = Worker(args.decoder) if args.decoder else None
    try:
        repeats(inventory,args.baseline,args.stage,args.output,worker)
    finally:
        if worker is not None:
            worker.close()
