"""Export actual cached MCS66 observations, a fresh decoder trace and frozen proofs.

No model search is performed here. Dependencies: numpy/h5py; the historical cache
is produced by the receiver audit. Raw IQ and the existing presentation stay intact.
"""
from pathlib import Path
import argparse, sys, json, hashlib, base64
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--cache66',type=Path,required=True)
ap.add_argument('--cache70',type=Path,required=True)
ap.add_argument('--repo',type=Path,required=True)
ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--deps',type=Path)
args=ap.parse_args()
if args.deps:sys.path.insert(0,str(args.deps))
import numpy as np
import h5py
P=args.cache66; W=args.cache70
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
pack=lambda a:base64.b64encode(np.packbits(a,bitorder='little').tobytes()).decode('ascii')
model=read(P/'mcs66_qc512_utexas_v1.json');Z=model['Z'];N=model['N'];K=model['K'];M=N-K
rows=[sorted(v//Z*Z+(v%Z+s)%Z for v in seed) for seed in model['seed_supports_0based'] for s in range(Z)]
idx=np.array(rows,dtype=np.int32);inverse=np.load(P/'mcs66_inverse.npz')['inverse_rows']
hu=[sum(1<<v for v in row if v<K) for row in rows]
pop=np.array([v.bit_count() for v in range(256)],dtype=np.uint8)
def encode(u):
 rhs=np.bitwise_xor.reduce(np.r_[u,np.zeros(M,dtype=bool)][idx],axis=1)
 parity=(pop[inverse & np.packbits(rhs,bitorder='little')].sum(axis=1)%2).astype(bool)
 return np.r_[u,parity]
def llr16(z):
 a=np.array([-3,-1,1,3])/np.sqrt(10);x,y=np.meshgrid(a,a);C=x.ravel()+1j*y.ravel()
 labels=np.array([C.real<0,C.imag<0,abs(C.real)<2/np.sqrt(10),abs(C.imag)<2/np.sqrt(10)]).T
 d=abs(z[:,None]-C)**2/.04;out=[]
 for b in range(4):
  d0=d[:,~labels[:,b]];d1=d[:,labels[:,b]];m0=d0.min(axis=1);m1=d1.min(axis=1)
  out.append(m1-m0+np.log(np.exp(m0[:,None]-d0).sum(axis=1))-np.log(np.exp(m1[:,None]-d1).sum(axis=1)))
 return np.stack(out,axis=1).reshape(-1).astype(np.float32)
def trace(llr):
 before=llr<0;bits=before.copy();q=llr[idx].copy();record=[]
 for it in range(81):
  failed=np.bitwise_xor.reduce(bits[idx],axis=1)
  record.append(dict(iteration=it,failed_checks=int(failed.sum()),hard_changes=int(np.count_nonzero(bits!=before)),syndrome_b64=pack(failed)))
  if not failed.any():break
  signs=np.where(q<0,-1,1);a=abs(q);k=a.argmin(axis=1);mins=np.partition(a,1,axis=1)[:,:2]
  mag=np.broadcast_to(mins[:,0,None],q.shape).copy();mag[np.arange(M),k]=mins[:,1]
  r=.8*np.prod(signs,axis=1)[:,None]*signs*mag
  post=llr+np.bincount(idx.ravel(),weights=r.ravel(),minlength=N);bits=post<0
  q=np.clip(post[idx]-r,-50,50)
 return bits,record
audit=read(P/'candidate_audit.json');val=read(P/'validation.json');search=read(P/'public_family_probe.json')
units=np.load(P/'candidate_units.npz')['z_66'];expected=np.load(P/'decoded_mcs66.npz')['bits']
origins=[r for r in audit['units'] if r['id']==66]
examples=[]
for frame in [5,2]:
 i=next(i for i,r in enumerate(origins) if r['frame']==frame and r['word']==1);z=units[i];llr=llr16(z)
 coded,steps=trace(llr);assert np.array_equal(coded,expected[i]);assert np.array_equal(encode(coded[:K]),coded)
 metric=val['words'][i];assert steps[0]['failed_checks']==metric['initial'] and steps[-1]['hard_changes']==metric['changes']
 source=args.repo/audit['sources'][frame-1]['path'].replace('\\','/');assert sha(source)==audit['sources'][frame-1]['sha256']
 with h5py.File(source) as f:
  h=f['result/headers/second_candidates']
  header=dict(bits=h['word_bits'][()].reshape(-1).astype(int).tolist(),crc_observed=int(h['crc_observed'][0,0]),crc_predicted=int(h['crc_predicted'][0,0]),crc_pass=bool(h['crc_pass'][0,0]),start_r0=int(h['start_r0'][0,0]),end_r0_inclusive=int(h['end_r0'][0,0]))
  entries=h['fields/entries'];header['entry_fields']=list(entries.keys())
  # MATLAB struct arrays store one object reference per field and entry.
  header['entries']=[]
  for j in range(entries[next(iter(entries))].size):
   entry={}
   for key,d in entries.items():
    value=d[()].reshape(-1)[j]
    if isinstance(value,h5py.Reference):value=f[value][()]
    v=np.asarray(value).reshape(-1)
    entry[key]=v.astype(int).tolist() if len(v)>1 else int(v[0])
   header['entries'].append(entry)
 golden=[]
 for j in [0,1,511,512,1024,1536,2047,2048,2560,3072,3584,4095]:
  row=int.from_bytes(inverse[j].tobytes(),'little');coeff=0
  while row:
   low=row&-row;k=low.bit_length()-1;coeff^=hu[k];row^=low
  coefficient_bits=np.unpackbits(np.frombuffer(coeff.to_bytes(K//8,'little'),dtype=np.uint8),bitorder='little').astype(bool)
  value=int(np.bitwise_xor.reduce(coded[:K][coefficient_bits]));assert value==int(coded[K+j])
  golden.append(dict(parity_index=j,coefficient_b64=pack(coefficient_bits),weight=coeff.bit_count(),value=value))
 examples.append(dict(frame=frame,word=1,selection_word=frame==2,metrics=metric,header=header,
   normalized_received_IQ=np.round(np.stack([z.real,z.imag],axis=1),7).tolist(),llr=np.round(llr.reshape(-1,4),5).tolist(),
   hard_bits_b64=pack(llr<0),decoded_bits_b64=pack(coded),trace=steps,generator_golden=golden,
   raw_systematic_reencode_parity_disagreements=int(np.count_nonzero(encode((llr<0)[:K])[K:]!=(llr<0)[K:]))))
native70=read(W/'native70_validation.json');py70=read(W/'python70_validation.json');ctrl70=read(W/'controls70_final.json')
evidence=dict(schema='coding-walkthrough-evidence-v1',created='2026-11-06',owner='codex_baseline',
 model66=model,model66_sha256=sha(P/'mcs66_qc512_utexas_v1.json'),search66=search,
 validation66=val,examples=examples,sources=audit['sources'],
 mcs70=dict(model={k:v for k,v in read(W/'mcs70_qc512_utexas_v1.json').items() if not k.startswith('parity_inverse')},
  selection=read(W/'frozen70.json')['selection'],summary={k:v for k,v in py70.items() if k!='words'},
  controls=ctrl70,integration=read(W/'integration70_validation.json'),
  parity_NMSE_range=[min(r['parity_NMSE'] for r in py70['words']),max(r['parity_NMSE'] for r in py70['words'])],
  parity_flip_NMSE_range=[min(r['parity_flip_control_nmse'] for r in native70['words']),max(r['parity_flip_control_nmse'] for r in native70['words'])]),
 source_capture_count=1,new_capture_blind_test=False,transmit_truth_available=False,plaintext_recovered=False,
 note='Full precision cached observations drive the new trace. IQ shown to 7 decimal places; packed bits/syndromes and generator calculations are exact. No generic UP=V recovery is claimed for MCS66.')
args.out.parent.mkdir(parents=True,exist_ok=True)
args.out.write_text(json.dumps(evidence,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
print(json.dumps(dict(out=str(args.out),bytes=args.out.stat().st_size,sha256=sha(args.out),examples=[dict(frame=e['frame'],trace=[(t['iteration'],t['failed_checks'],t['hard_changes']) for t in e['trace']],entries=e['header']['entries']) for e in examples]),ensure_ascii=False))
