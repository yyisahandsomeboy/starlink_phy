#!/usr/bin/env python3
"""Reconcile per-word archive results and write publishable coverage ledgers."""
import argparse
from collections import Counter, defaultdict
import csv
from pathlib import Path

from recover_ut_ldpc_archive import initial_parts, np, read, save


def write_csv(path, rows, fields):
    with path.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def summarize(inventory, baseline, stages, output, combined):
    by_mcs = defaultdict(Counter)
    frames = []
    holes = []
    methods = Counter()
    phy = read(inventory)
    count = phy['frame_count']
    for f in range(count):
        stem = f'{f:04}'
        doc = read(baseline/f'{stem}.json')
        assert doc['frame']==f
        path = baseline/f'{stem}.npz'
        parts = initial_parts(path,stages,f)
        additions = {}
        remaining = {}
        for folder in stages:
            status = folder/f'{stem}.json'
            if not status.exists():
                continue
            new = read(status)
            assert new['frame']==f
            for trial in new.get('remaining',[]):
                k = (trial['allocation'],trial['word'])
                n = trial['best_failed_checks']
                remaining[k] = min(n,remaining.get(k,n))
            for trial in new['words']:
                k = (trial['allocation'],trial['word'])
                additions.setdefault(k,trial)
        stats = Counter(expected=0,baseline_verified=0,verified=0,recovered=0,unresolved=0)
        with np.load(path) as before:
            for i,a in enumerate(doc['allocations']):
                mcs,qty = a['mcs'],a['quantity']
                old,valid = before[f'valid_{i}'],parts[f'valid_{i}']
                assert len(old)==len(valid)==qty and (valid|~old).all()
                assert np.array_equal(parts[f'part_{i}'][old],before[f'part_{i}'][old])
                prior = int(old.sum())
                verified = int(valid.sum())
                part_count = Counter(expected=qty,baseline_verified=prior,verified=verified,
                                     recovered=verified-prior,unresolved=qty-verified)
                by_mcs[mcs].update(part_count)
                stats.update(part_count)
                for j,old_valid in enumerate(old):
                    start = a['r0']+j*a['q']
                    if valid[j] and not old_valid:
                        trial = additions[i,j+1]
                        assert (trial['mcs'],trial['r0'])==(mcs,start)
                        methods[trial['method']] += 1
                        if combined:
                            a['codewords'][j] = trial
                    elif not valid[j]:
                        info = a['codewords'][j]
                        holes.append(dict(frame=f,allocation=i,mcs=mcs,word=j+1,r0=start,
                                          r_end=start+a['q'],baseline_failed_checks=info.get('final_syndrome'),
                                          retry_failed_checks=remaining.get((i,j+1))))
                if combined:
                    a['valid_words'] = verified
                    # This ledger carries PHY continuity only. MAC boundaries were
                    # computed in the baseline and can be re-parsed with the new bytes.
                    for key in ('records','record_boundaries','verified_zero_padding'):
                        a.pop(key,None)
        if combined:
            doc.pop('mac1',None)
            doc.pop('mac2',None)
            save(combined/f'{stem}.json',doc,parts)
        frames.append(dict(frame=f,**stats))
    totals = sum((Counter({k:v for k,v in row.items() if k!='frame'}) for row in frames),Counter())
    assert totals['expected']==totals['verified']+len(holes)
    assert totals['recovered']==sum(methods.values())
    assert {str(k):v['expected'] for k,v in by_mcs.items()}==phy['declared_codewords_by_mcs']
    totals['frames'] = count
    totals['complete_frames'] = sum(row['unresolved']==0 for row in frames)
    from json import dumps
    result = dict(totals=totals,by_mcs=dict(sorted(by_mcs.items())),methods=methods)
    (output/'coverage.json').write_text(dumps(result,indent=2)+'\n',encoding='utf-8')
    write_csv(output/'frames.csv',frames,list(frames[0]))
    fields = ('frame','allocation','mcs','word','r0','r_end','baseline_failed_checks','retry_failed_checks')
    write_csv(output/'unresolved.csv',holes,fields)
    print(result['totals'],flush=True)
    print(methods,flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--stage',type=Path,action='append',default=[])
    parser.add_argument('--combined',type=Path)
    args = parser.parse_args()
    args.output.mkdir(exist_ok=True,parents=True)
    if args.combined:
        args.combined.mkdir(exist_ok=True,parents=True)
    summarize(args.inventory,args.baseline,args.stage,args.output,args.combined)
