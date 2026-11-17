#!/usr/bin/env python3
"""Try reliability-ordered syndrome decoding and check independent symbol holdouts."""
import argparse
from itertools import combinations
from pathlib import Path

from recover_ut_ldpc_archive import (
    Codes, PN, Profile, Worker, alphabets, frame_channel, frame_data, h5py, initial_parts,
    metric, np, read, save, trained_points,
)
from recover_ut_ldpc_feedback import pilot_variants


def unpack(value, length):
    return np.unpackbits(np.frombuffer(value.to_bytes((length+7)//8,'little'),np.uint8),
                         bitorder='little')[:length].astype(bool)


def column_masks(profile):
    cols = [0]*profile.n
    for i,row in enumerate(profile.rows):
        mask = 1<<i
        for j in row:
            cols[j] |= mask
    return cols


class SyndromeBasis:
    def __init__(self,cols,order,rank):
        # Track every pivot as an XOR of actual transmitted columns.
        self.vectors = [0]*rank
        self.combinations = [0]*rank
        self.index = []
        self.flags = []
        for col in map(int,order):
            residual,selection = self.reduce(cols[col])
            if residual:
                high = residual.bit_length()-1
                self.vectors[high] = residual
                self.combinations[high] = selection^(1<<len(self.index))
                self.index.append(col)
                self.flags.append(1<<col)
                if len(self.index)==rank:
                    break
        if len(self.index)!=rank:
            raise ValueError('No full-rank parity basis in available positions')

    def reduce(self,val):
        select = 0
        while val:
            high = val.bit_length()-1
            pivot = self.vectors[high]
            if not pivot:
                break
            val ^= pivot
            select ^= self.combinations[high]
        return val,select

    def correct(self,syndrome):
        remain,mask = self.reduce(syndrome)
        if remain:
            raise ValueError('Syndrome lies outside the check space')
        word = 0
        while mask:
            low = mask&-mask
            word ^= self.flags[low.bit_length()-1]
            mask ^= low
        return word


def dense_scores(words, profile, metric_values):
    width = profile.width
    nbits = profile.q*width
    stride = (nbits+7)//8
    data = np.frombuffer(b''.join(x.to_bytes(stride,'little') for x in words),dtype=np.uint8).reshape(-1,stride)
    bits = np.unpackbits(data,axis=1,bitorder='little')[:,:nbits]
    labels = (bits.reshape(len(words),profile.q,width)@profile.weights)
    samples = np.arange(profile.q)
    values = metric_values[samples,labels]
    if spare:=nbits-profile.n:
        tail = labels[:,-1]
        last = values[:,-1]
        high = 1<<(width-spare)
        for j in range(1,1<<spare):
            last[:] = np.logaddexp(last,metric_values[-1,tail|j*high])
    return values.sum(axis=1)


def list_decode(profile, cols, score, llr, fixed, list_size):
    ranked = np.argsort(abs(llr),kind='stable')
    # Assign corrections to the least reliable independent columns first.
    chosen = SyndromeBasis(cols,ranked[~fixed[ranked]],profile.n-profile.k)
    bits = llr<0
    syndrome = 0
    for i in np.flatnonzero(bits):
        syndrome ^= cols[i]
    word = int.from_bytes(np.packbits(bits,bitorder='little').tobytes(),'little')
    candidate = word^chosen.correct(syndrome)
    free = ranked[~fixed[ranked]&~np.isin(ranked,chosen.index)]
    likely_errors = [chosen.correct(cols[i])^(1<<int(i)) for i in free[:list_size]]
    changes = [0,*likely_errors]
    changes.extend(x^y for x,y in combinations(likely_errors[:min(list_size,24)],2))
    best_word = candidate
    best_score = -np.inf
    for j in range(0,len(changes),64):
        trials = [candidate^e for e in changes[j:j+64]]
        scores = dense_scores(trials,profile,score)
        i = int(np.argmax(scores))
        if scores[i]>best_score:
            best_score = scores[i]
            best_word = trials[i]
    return unpack(best_word,profile.n),float(best_score)


def osd_trial(worker,profile,cols,score,pad,seed,erased):
    training = score.copy()
    training[erased] = 0
    likelihood = profile.llr(training)
    ext = np.zeros(profile.n,dtype=np.float32)
    options = ('held_out_joint_decode',True,105,4,False,1,1.12,1.)
    decoded,left = worker.decode(profile,training,pad,options,seed,extrinsic=ext,prior=.96,damping=.62)
    if decoded is not None:
        candidate = profile.encode(decoded[0])
        fit = float(dense_scores([int.from_bytes(np.packbits(candidate,bitorder='little'),'little')],
                                 profile,training)[0])
        return candidate,fit,left
    fixed = np.zeros(profile.n,dtype=bool)
    if pad is not None:
        fixed[pad:profile.k] = True
    llr = likelihood+.8*np.clip(ext,-18,18)
    if pad is not None:
        llr[fixed] = 60*(1.-2*PN[:profile.k][fixed[:profile.k]])
    word,fit = list_decode(profile,cols,training,llr,fixed,64)
    return word,fit,left


def compare(profile,score,word):
    raw = profile.unpack(word)
    if not np.array_equal(profile.encode(raw),word):
        raise ValueError('Reliability-ordered candidate has nonzero syndrome')
    hard = profile.llr(score)<0
    agreement = float(np.mean(word[profile.k:]==hard[profile.k:]))
    return raw,agreement


def attempt(worker,profile,cols,make_score,pad,seed,symbol_prior=None):
    score = make_score(None)
    prior = 0 if symbol_prior is None else symbol_prior
    word,_,before = osd_trial(worker,profile,cols,score+prior,pad,seed,np.array([],dtype=int))
    raw,agreement = compare(profile,score,word)
    evidence = dict(full_observation_agreement=agreement,bp_unsatisfied_checks=before)
    if agreement<.88:
        return None,evidence
    available = np.arange((profile.k+profile.width-1)//profile.width,profile.n//profile.width)
    rng = np.random.default_rng(seed)
    holdouts = np.split(rng.choice(available,64,replace=False),2)
    scores = []
    for h in holdouts:
        excluded = np.zeros(profile.q,dtype=bool)
        excluded[h] = True
        trial_score = make_score(excluded)
        independent,_,_ = osd_trial(worker,profile,cols,trial_score+prior,pad,seed,h)
        at = (profile.width*h[:,None]+np.arange(profile.width)).ravel()
        held_agree = float(np.mean(word[at]==(profile.llr(trial_score)[at]<0)))
        scores.append(dict(bits=len(at),agreement=held_agree,reproduced=bool(np.array_equal(independent,word))))
    evidence['holdouts'] = scores
    if all(x['reproduced'] and x['agreement']>=.86 for x in scores):
        evidence.update(method='reliability_ordered_syndrome',reencoded=True,final_syndrome=0,iterations=None)
        if symbol_prior is not None:
            evidence['method'] = 'mac_structure_soft_prior'
        return raw,evidence
    return None,evidence


def hint_prior(profile,rows):
    soft = np.zeros(profile.q*profile.width)
    for row in rows:
        for bit in range(8):
            if not (row['mask']>>bit)&1:
                continue
            j = 8*row['offset']+bit
            if not 0<=j<profile.k:
                raise ValueError('Structure hint lies outside the information bits')
            observed = ((row['value']>>bit)&1) ^ PN[j]
            value = -5.5 if observed else 5.5
            if soft[j] not in (0,value):
                raise ValueError('Conflicting payload structure hints')
            soft[j] = value
    return -(soft.reshape(profile.q,profile.width)@profile.labels.T)


def run(args):
    inventory = read(args.inventory)['frames']
    if args.symbols:
        for row in inventory:
            row['symbol_path'] = args.symbols/f"mac_trace_symbols_{row['frame']:04}.mat"
    catalog,alpha = Codes(),alphabets()
    profiles,columns = {},{}
    hints = {(r['frame'],r['allocation'],r['word']-1):r for r in read(args.hints)} if args.hints else {}

    def get(m):
        if m not in profiles:
            profiles[m] = Profile(m,catalog,alpha[catalog.formats[m]['modulation']])
            columns[m] = column_masks(profiles[m])
        return profiles[m]

    worker = Worker(args.decoder)
    args.output.mkdir(exist_ok=True,parents=True)
    try:
        with h5py.File(args.archive,'r',rdcc_nbytes=96*1024*1024) as archive:
            for f in map(int,args.frames.read_text(encoding='utf-8').split()):
                output = args.output/f'{f:04}.json'
                if output.exists() and output.with_suffix('.npz').exists():
                    continue
                frame,grid,path = frame_data(inventory,args.baseline,f)
                base = initial_parts(path,args.seed,f)
                training_parts = {k:v.copy() for k,v in base.items()}
                controls = {}
                if args.control:
                    for i,a in enumerate(frame['allocations']):
                        valid = base[f'valid_{i}']
                        if a['mcs']>=85 and valid.any():
                            k = int(np.flatnonzero(valid)[-1])
                            training_parts[f'valid_{i}'][k] = False
                            controls[i,k] = base[f'part_{i}'][k]
                training = trained_points(frame,training_parts,get)
                raw_grid = pilot_variants(archive,f,grid)[0]
                gain,_ = frame_channel(raw_grid,training)
                verified,attempted,arrays = [],[],{}
                for i,a in enumerate(frame['allocations']):
                    mask = training_parts[f'valid_{i}'] if args.control else base[f'valid_{i}']
                    pending = np.flatnonzero(~mask)
                    if args.control:
                        pending = [j for j in pending if (i,j) in controls]
                    if args.hints:
                        pending = [j for j in pending if (f,i,j) in hints]
                    for j in pending[:args.limit]:
                        p = get(a['mcs'])
                        start = a['r0']+int(j)*p.q
                        positions = np.arange(start,start+p.q)

                        def make_score(excluded):
                            return metric(p,positions,raw_grid,gain,training,slope=True,
                                          frequency_noise=True,excluded=excluded)[0]
                        n = max(0,(a['quantity']-int(j))*p.k-8*a.get('padding_bytes',0))
                        pad = n if n<p.k else None
                        loc = dict(frame=f,allocation=i,word=int(j)+1,mcs=p.mcs,r0=start)
                        note = hints.get((f,i,j))
                        priors = hint_prior(p,note['hints']) if note else None
                        recovered,evidence = attempt(worker,p,columns[p.mcs],make_score,pad,f*4096+start%4096,priors)
                        attempted.append(dict(**loc,**evidence,accepted=recovered is not None))
                        if args.control:
                            attempted[-1]['known_word_matches'] = (recovered is not None and
                                                                   np.array_equal(recovered,controls[i,j]))
                        elif recovered is not None:
                            arrays[f'{i}_{j}'] = recovered
                            verified.append(dict(**{k:v for k,v in loc.items() if k!='frame'},**evidence))
                        if args.control and recovered is not None and not attempted[-1]['known_word_matches']:
                            raise ValueError('Ordered-statistics validation selected a different known control')
                save(output,dict(frame=f,words=verified,attempts=attempted),arrays)
                print(f'FRAME {f} accepted {sum(a["accepted"] for a in attempted)} of {len(attempted)}',flush=True)
    finally:
        worker.close()


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--decoder',type=Path,required=True)
    parser.add_argument('--frames',type=Path,required=True)
    parser.add_argument('--symbols',type=Path)
    parser.add_argument('--hints',type=Path,help='Optional information-bit hints validated against MAC boundaries')
    parser.add_argument('--seed',type=Path,action='append',default=[])
    parser.add_argument('--limit',type=int)
    parser.add_argument('--control',action='store_true')
    run(parser.parse_args())
