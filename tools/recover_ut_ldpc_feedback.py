#!/usr/bin/env python3
"""Use LDPC extrinsic likelihoods to refine residual OFDM channel estimates."""
import argparse
from pathlib import Path
from numpy.lib.stride_tricks import sliding_window_view

from recover_ut_ldpc_archive import (
    Codes, PN, Profile, SUBCARRIERS, Worker, alphabets, expected_gain, frame_channel,
    frame_data, h5py, initial_parts, metric, np, read, save, trained_points,
)


def learn(profile, grid, gain, training, r0):
    selected = sorted(training.get(profile.width,()),key=lambda item:abs(item[0].mean()-r0))[:12]
    if not selected:
        return profile.points, .025*np.ones(len(profile.points)), np.ones(SUBCARRIERS)
    at,truth = (np.concatenate(a) for a in zip(*selected,strict=True))
    carriers = at % SUBCARRIERS
    y = grid[at]/gain[carriers]
    errors = y-truth
    power = max(.006,float(np.median(abs(errors)**2)/np.log(2)))
    centers,variance = [],[]
    for point in profile.points:
        e = errors[truth==point]
        offset = e.sum()/(len(e)+50)
        centers.append(point+offset)
        variance.append((np.minimum(abs(e-offset)**2,10*power).sum()+50*power)/(len(e)+50))
    energy = np.bincount(carriers,np.minimum(abs(errors)**2,10*power),minlength=SUBCARRIERS)
    count = np.bincount(carriers,minlength=SUBCARRIERS)
    box = np.ones(17)
    spectrum = (np.convolve(energy,box,'same')+60*power)/(np.convolve(count,box,'same')+60)
    spectrum = np.clip(spectrum/np.median(spectrum),.55,2.2)
    return np.asarray(centers),np.asarray(variance),spectrum


def estimate(z, positions, centers, variance, spectrum, priors, group_width):
    """Estimate local gain, offset and noise using bounded soft symbol probabilities."""
    corrected = z.copy()
    confidence = np.ones(len(z))
    groups = (positions//SUBCARRIERS)*((SUBCARRIERS+group_width-1)//group_width)+(positions%SUBCARRIERS)//group_width
    energy = abs(centers)**2
    for g in np.unique(groups):
        idx = groups==g
        x = z[idx]
        if len(x)<64:
            continue
        v = spectrum[idx,None]*variance
        h,dc,ratio = 1.,0.,1.
        for _ in range(3):
            distance = abs((x-dc)[:,None]-h*centers)**2/v
            logits = -4*np.log1p(distance/(3*ratio))-np.log(v)+priors[idx]
            prob = np.exp(logits-logits.max(axis=1,keepdims=True))
            prob /= prob.sum(axis=1,keepdims=True)
            mean = prob@centers
            moment = prob@energy
            h = (np.vdot(mean,x-dc)+90)/(moment.sum()+90)
            dc = (x-h*mean).sum()/(len(x)+130)
            ratio = np.clip(((prob*np.minimum(distance,9)).sum()+110)/(len(x)+110),.65,1.9)
        if abs(h-1)<.19 and abs(dc)<.12:
            corrected[idx] = (x-dc)/h
        confidence[idx] = ratio
    distance = abs(corrected[:,None]-centers)**2/(spectrum[:,None]*variance)
    return -4*np.log1p(distance/(3*confidence[:,None]))-np.log(variance)


def attempt(worker, profile, grid, gain, training, r0, pad, seed):
    r = np.arange(r0,r0+profile.q)
    centers,variance,frequency = learn(profile,grid,gain,training,r0)
    norm = expected_gain(grid[r]/gain[r%SUBCARRIERS],centers,r,True)
    spectrum = frequency[r%SUBCARRIERS]
    evidence = np.zeros((profile.q,len(centers)))
    extrinsic = np.zeros(profile.n,dtype=np.float32)
    minimum = profile.n
    options = ((1004,True,4,0,1.0,.9,.6),
               (502,True,3,1,1.12,1.,.56),
               (1004,False,4,1,.95,.72,.68),
               (251,True,5,2,1.18,.95,.59))
    for i,(width,sparse,period,shuffle,scale,prior,damping) in enumerate(options):
        score = estimate(norm,r,centers,variance,spectrum,evidence,width)
        settings = ('ldpc_channel_feedback' if i else 'slot_student_mixture',
                    sparse,105,period,False,shuffle,scale,1.)
        outcome,left = worker.decode(profile,score,pad,settings,seed+i,extrinsic=extrinsic,
                                     prior=prior,damping=damping)
        if outcome is not None:
            raw,details = outcome
            if details['observed_parity_hard_agreement']>=.88:
                return (raw,dict(**details,channel_config=i+1,best_previous_syndrome=minimum)),0
        elif left:
            minimum = min(minimum,left)
        written = np.zeros(profile.q*profile.width)
        written[:profile.n] = np.clip(extrinsic,-3.,3.)
        if pad is not None:
            written[pad:profile.k] = 7*(1.-2*PN[pad:profile.k])
        evidence = -.50*(written.reshape(-1,profile.width)@profile.labels.T)
    return None,minimum


def payload_coordinates():
    bins = np.r_[np.arange(512),np.arange(-512,0)]
    rows = np.arange(2,1022)
    rows = rows[np.argsort(bins[rows])]
    active = ~np.isin(rows,np.r_[np.arange(488,496),np.arange(528,536)])
    state = [False]*15
    state[1] = True
    bits = []
    for _ in range(32767):
        bits.append(state[-1])
        state = [state[-2]^state[-1],*state[:-1]]
    sequence = np.asarray(bits,dtype=np.int8)
    clock = 2*np.arange(1020,301*1020).reshape(300,1020)
    rotations = (1j)**(2*sequence[clock%32767]+sequence[(clock+1)%32767])
    return rows[active],bins[rows[active]],rotations[:,active]


def pilot_variants(archive,frame,exported):
    columns,frequency,rotations = payload_coordinates()
    grid = archive['yDataSoft'][frame,1:,:][:,columns]
    z = (grid['real']+1j*grid['imag'])*np.conj(rotations)
    corrected = exported.reshape(300,SUBCARRIERS)
    ratio = np.divide(corrected,z,out=np.ones_like(z),where=abs(z)>1.e-7)
    phase = np.unwrap(np.angle(ratio),axis=1)
    slope = np.median(np.diff(phase,axis=1)/np.diff(frequency),axis=1)
    offset = np.unwrap(np.angle(np.mean(ratio*np.exp(-1j*slope[:,None]*frequency),axis=1)))
    magnitude = np.median(abs(ratio),axis=1)
    reconstructed = z*magnitude[:,None]*np.exp(1j*(offset[:,None]+slope[:,None]*frequency))
    if np.linalg.norm(reconstructed-corrected)>.001*np.linalg.norm(corrected):
        raise ValueError(f'Archived and exported symbols do not align for frame {frame}')

    def median(values):
        return np.median(sliding_window_view(np.pad(values,7,mode='edge'),15),axis=1)

    smooth = z*median(magnitude)[:,None]*np.exp(1j*(median(offset)[:,None]+median(slope)[:,None]*frequency))
    return z.ravel(),smooth.ravel()


def pilot_attempt(worker,profile,variants,training,r0,pad,seed,depth):
    positions = np.arange(r0,r0+profile.q)
    minimum = profile.n
    if depth:
        order = ((0,True,True,0,True,0,1.05,.82),
                 (0,False,True,3,False,0,.99,1.),
                 (0,True,True,2,False,1,1.23,1.),
                 (1,False,True,4,False,1,1.16,1.),
                 (0,True,False,5,False,2,.93,1.))
    else:
        order = ((0,True,True,4,False,1,1.12,1.),(1,True,True,4,False,1,1.12,1.))
    cache = {}
    for index,(k,slope,sparse,period,minsum,shuffle,scale,check) in enumerate(order):
        grid,gain = variants[k]
        key = k,slope
        if key not in cache:
            cache[key],_ = metric(profile,positions,grid,gain,training,slope=slope,frequency_noise=True)
        name = ('original_archive_phase','smoothed_archive_pilot_phase')[k]
        if depth:
            name += '_refinement'
        settings = (name,sparse,115,period,minsum,shuffle,scale,check)
        result,left = worker.decode(profile,cache[key],pad,settings,seed+index,prior=.96,damping=.62)
        if result is not None and result[1]['observed_parity_hard_agreement']>=.88:
            return result,0
        if left:
            minimum = min(minimum,left)
    return None,minimum


def nearby_channel(grid,global_gain,training,start,width):
    same_width = sorted(training.get(width,()),key=lambda item:abs(item[0].mean()-start))[:12]
    close = [pair for pair in same_width if abs(pair[0].mean()-start)<36000]
    if len(close)<4:
        return global_gain,training
    subset = {width:close}
    local,_ = frame_channel(grid,subset)
    local = np.where(abs(local/global_gain-1)<.18,local,global_gain)
    return .68*local+.32*global_gain,subset


def run(args):
    frames = read(args.inventory)['frames']
    if args.symbols:
        for row in frames:
            row['symbol_path'] = args.symbols/f"mac_trace_symbols_{row['frame']:04}.mat"
    catalog,alpha = Codes(),alphabets()
    cache = {}

    def profile(m):
        if m not in cache:
            cache[m] = Profile(m,catalog,alpha[catalog.formats[m]['modulation']])
        return cache[m]

    worker = Worker(args.decoder)
    archive = h5py.File(args.pilot_archive,'r',rdcc_nbytes=96*1024*1024) if args.pilot_archive else None
    args.output.mkdir(exist_ok=True,parents=True)
    try:
        for f in map(int,args.frames.read_text(encoding='utf-8').split()):
            output = args.output/f'{f:04}.json'
            if output.exists() and output.with_suffix('.npz').exists():
                continue
            frame,grid,path = frame_data(frames,args.baseline,f)
            baseline = initial_parts(path,args.seed,f)
            if all(a.all() for key,a in baseline.items() if key.startswith('valid_')):
                save(output,dict(frame=f,attempted=0,words=[],remaining=[]),{})
                continue
            training = trained_points(frame,baseline,profile)
            gain,_ = frame_channel(grid,training)
            variants = None
            if archive is not None:
                variants = [(z,frame_channel(z,training)[0]) for z in pilot_variants(archive,f,grid)]
            verified,remaining,arrays = [],[],{}
            for i,a in enumerate(frame['allocations']):
                todo = np.flatnonzero(~baseline[f'valid_{i}'])
                if not len(todo):
                    continue
                p = profile(a['mcs'])
                for j in todo[:args.limit]:
                    start = a['r0']+int(j)*p.q
                    known = max(0,(a['quantity']-int(j))*p.k-8*a.get('padding_bytes',0))
                    pad = known if known<p.k else None
                    seed = f*4096+start%4096
                    if variants and args.pilot_feedback:
                        z,h = variants[0]
                        local_gain,near = nearby_channel(z,h,training,start,p.width)
                        result,left = attempt(worker,p,z,local_gain,near,start,pad,seed)
                        if result is not None:
                            raw,details = result
                            result = raw,dict(details,method='archive_phase_'+details['method'])
                    elif variants:
                        result,left = pilot_attempt(worker,p,variants,training,start,pad,seed,args.pilot_refine)
                    else:
                        result,left = attempt(worker,p,grid,gain,training,start,pad,seed)
                    loc = dict(allocation=i,word=int(j)+1,mcs=p.mcs,r0=start)
                    if result is None:
                        remaining.append(dict(**loc,best_failed_checks=left))
                    else:
                        arrays[f'{i}_{j}'],details = result
                        verified.append(dict(**loc,**details))
            audit = dict(frame=f,attempted=len(verified)+len(remaining),words=verified,remaining=remaining)
            save(output,audit,arrays)
            print(f'FRAME {f} recovered {len(verified)} of {audit["attempted"]}',flush=True)
    finally:
        if archive is not None:
            archive.close()
        worker.close()


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    parser.add_argument('baseline',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--frames',type=Path,required=True)
    parser.add_argument('--decoder',type=Path,required=True)
    parser.add_argument('--seed',type=Path,action='append',default=[])
    parser.add_argument('--symbols',type=Path,help='Folder containing mac_trace_symbols_*.mat')
    parser.add_argument('--limit',type=int,default=None)
    parser.add_argument('--pilot-archive',type=Path,help='Retry the archive phase and a smoothed pilot estimate')
    strategy = parser.add_mutually_exclusive_group()
    strategy.add_argument('--pilot-refine',action='store_true',
                          help='Vary the graph and message schedule after pilot replay')
    strategy.add_argument('--pilot-feedback',action='store_true',
                          help='Use LDPC feedback on the original archived phase')
    args = parser.parse_args()
    if (args.pilot_refine or args.pilot_feedback) and not args.pilot_archive:
        parser.error('Pilot replay strategies require --pilot-archive')
    run(args)
