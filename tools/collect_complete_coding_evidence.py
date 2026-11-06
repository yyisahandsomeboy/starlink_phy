"""Reproduce frozen MCS66 intermediate calculations for a complete tutorial.

Adds explanatory evidence; never modifies a decoder, model, DSP output or threshold.
CCSDS numeric permutation tables are facts attributed to 131.0-B-5, section 7.4.
"""
from pathlib import Path
import argparse,sys,json,hashlib,base64,zlib,itertools,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base',type=Path,required=True);p.add_argument('--cache66',type=Path,required=True)
p.add_argument('--repo',type=Path,required=True);p.add_argument('--deps',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
a=p.parse_args();P=a.cache66;sys.path[:0]=[str(P),str(a.deps)]
import numpy as np,h5py
import ar4ja_reference as tables
from ccsds_candidate import transmitted_rows,full_rows
from decode_candidate import llr16
start=time.time();read=lambda p:json.loads(p.read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
b64=lambda v:base64.b64encode(v).decode('ascii')
pack=lambda v:b64(np.packbits(v,bitorder='little').tobytes())
compress=lambda v:b64(zlib.compress(v,9))
d=read(a.base);model=d['model66'];N=model['N'];K=model['K'];M=N-K;Z=model['Z']
rows,_=transmitted_rows(8,2048,(0,1),'p0');idx=np.array(rows,dtype=np.int32)
assert all(tuple(sorted(v//Z*Z+(v%Z+s)%Z for v in seed))==rows[b*Z+s] for b,seed in enumerate(model['seed_supports_0based']) for s in range(Z))
units=np.load(P/'candidate_units.npz')['z_66'];audit=read(P/'candidate_audit.json');origins=[r for r in audit['units'] if r['id']==66]
expected=np.load(P/'decoded_mcs66.npz')['bits']
def decoder_trace(soft):
 q=soft[idx].copy();bits=soft<0;result=[];it=0
 while True:
  syndrome=np.logical_xor.reduce(bits[idx],axis=1)
  entry=dict(iteration=it,failed=int(syndrome.sum()),bits_b64=pack(bits),syndrome_b64=pack(syndrome))
  result.append(entry)
  if not syndrome.any():break
  assert it<10
  signs=np.where(q<0,-1,1);absolute=abs(q);minimum=absolute.argmin(axis=1);two=np.partition(absolute,1,axis=1)[:,:2]
  magnitude=np.broadcast_to(two[:,0,None],q.shape).copy();magnitude[np.arange(M),minimum]=two[:,1]
  message=.8*np.prod(signs,axis=1)[:,None]*signs*magnitude
  post=soft+np.bincount(idx.ravel(),weights=message.ravel(),minlength=N)
  nextq=np.clip(post[idx]-message,-50,50)
  entry['edge_goldens']=[dict(check=int(r),edge=int(edge),variable=int(idx[r,edge]),q=float(q[r,edge]),r=float(message[r,edge]),posterior=float(post[idx[r,edge]]),next_q=float(nextq[r,edge])) for r,edge in [(0,0),(0,13),(511,5),(512,1),(1337,7),(2048,9),(3584,10),(4095,13)]]
  q=nextq;bits=post<0;it+=1
 return bits,result
for e in d['examples']:
 i=next(i for i,r in enumerate(origins) if r['frame']==e['frame'] and r['word']==1);z=units[i];soft=llr16(z)
 bits,trace=decoder_trace(soft);assert np.array_equal(bits,expected[i])
 assert [x['failed'] for x in trace]==[x['failed_checks'] for x in e['trace']]
 source=a.repo/audit['sources'][e['frame']-1]['path'].replace('\\','/')
 with h5py.File(source) as f:
  g=f['result'];h=g['headers/second_candidates'];blocks=h['blocks'];export=[]
  for j in range(4):
   item={}
   for key in ['inputs','reencoded','hard_observed']:
    ref=blocks[key][()].ravel()[j];item[key]=f[ref][()].ravel().astype(int).tolist()
   state=0;generated=[];states=[]
   for u in item['inputs']:
    register=(state<<1)|u;triple=[(register&v).bit_count()%2 for v in (109,83,95)]
    states.append(dict(before=state,input=u,register=register,output=triple,after=register&63));generated.extend(triple);state=register&63
   assert generated==item['reencoded'] and state==0 and not any(item['inputs'][32:])
   item['state_trace']=states
   stream=g['payload_stream'][()].ravel();observed=stream[int(h['start_r0'][0,0])+114*j:int(h['start_r0'][0,0])+114*(j+1)]
   x=observed['real'];item['observations_IQ']=np.stack([observed['real'],observed['imag']],axis=1).tolist()
   metric=np.full(64,np.inf);metric[0]=0;metrics=[metric.copy()];predecessors=[]
   for timeindex in range(38):
    nxt=np.full(64,np.inf);prev=np.zeros(64,dtype=np.uint8)
    for ns in range(64):
     u=ns&1;pp=[ns//2,ns//2+32];costs=[]
     for s in pp:
      reg=(s<<1)|u;c=np.array([1-2*((reg&v).bit_count()%2) for v in (109,83,95)])
      costs.append(metric[s]+float(np.sum((c-x[timeindex*3:timeindex*3+3])**2)))
     which=int(np.argmin(costs));nxt[ns]=costs[which];prev[ns]=pp[which]
    metric=nxt;metrics.append(metric.copy());predecessors.append(prev)
   state=0;recovered=[]
   for prev in predecessors[::-1]:recovered.append(state&1);state=int(prev[state])
   assert recovered[::-1]==item['inputs'] and state==0
   metric_ref=blocks['soft_path_metric'][()].ravel()[j]
   native_metric=float(f[metric_ref][()].ravel()[0])
   assert abs(float(metric[0])-native_metric)<1e-8
   item['viterbi_metrics_f64le_deflate_b64']=compress(np.array(metrics,dtype='<f8').tobytes())
   item['viterbi_predecessors_u8_b64']=b64(np.array(predecessors,dtype='u1').tobytes())
   item['viterbi_final_metric']=float(metric[0]);item['viterbi_native_saved_metric']=native_metric;export.append(item)
  begin=e['metrics']['start_r0'];r=np.arange(begin,begin+4096);columns=1+r//1004;rr=np.array(d['coordinates']['payload_rows0'])[r%1004]
  gain=g['allocations/calibration/gain_per_column'][()].ravel()[r//1004]
  before=g['calibrated_grid'][()][columns,rr];reference=g['reference_grid'][()][columns,rr]
  pre=(before['real']+1j*before['imag'])/gain;ref=reference['real']+1j*reference['imag']
  assert np.max(abs(pre*np.conj(ref)-z))<2e-7
  crc=255;crc_trace=[]
  for b in e['header']['bits'][:-8]:
   before_state=crc;feedback=((crc>>7)&1)^b;shifted=(crc<<1)&255;crc=shifted^(77 if feedback else 0)
   crc_trace.append(dict(before=before_state,input=b,feedback=feedback,shifted=shifted,after=crc))
  assert crc==e['header']['crc_observed']
 e['complete']=dict(IQ_f32_b64=b64(np.stack([z.real,z.imag],axis=1).astype('<f4').tobytes()),channel_llr_f32_b64=b64(soft.astype('<f4').tobytes()),
   pre_PN_IQ=np.round(np.stack([pre.real,pre.imag],axis=1),10).tolist(),PN_reference=np.round(np.stack([ref.real,ref.imag],axis=1),10).tolist(),
   decoder=trace,header_blocks=export,crc_trace=crc_trace)
print('EXPORTED_REAL_TRACES',round(time.time()-start,2),flush=True)
# Reproduce the exact old candidate order and RNG consumption; store every score,
# including polarity ties discarded by argmin in the original compact report.
raw=np.stack([units.real<0,units.imag<0,abs(units.real)<2/np.sqrt(10),abs(units.imag)<2/np.sqrt(10)],axis=-1)
chosen=[i for i,r in enumerate(origins) if r['frame']==2 and r['word']<=8];raw=raw[chosen];assert len(raw)==8
mappings=[]
for ib in itertools.combinations([1,4,5],2):
 for qb in itertools.combinations([2,8,10],2):mappings.extend(itertools.permutations(ib+qb))
mappings=sorted(set(mappings));assert len(mappings)==216
base={1:raw[:,:,0],2:raw[:,:,1],4:raw[:,:,2],8:raw[:,:,3],5:raw[:,:,0]^raw[:,:,2],10:raw[:,:,1]^raw[:,:,3]}
words=[np.pad(np.stack([base[k] for k in m],axis=-1).reshape(8,-1),((0,0),(0,1))) for m in mappings]
polarity=np.array([[(b&m).bit_count()%2 for m in range(16)] for b in range(16)],dtype=bool)
models=[];families=[]
for KB,block,punc in [(2,4096,'p0'),(4,4096,'p0'),(8,4096,'p0'),(8,2048,'p0'),(8,2048,'none'),(4,4096,'none'),(8,4096,'none')]:
 count=KB+(2 if punc=='p0' else 3)-N//block;items=list(itertools.combinations(range(KB),count));families.append(dict(KB=KB,M=block,puncture=punc,removed_information_blocks=count,candidates=len(items)))
 for removed in items:models.append(dict(KB=KB,M=block,puncture=punc,shortened_blocks=list(removed)))
rng=np.random.default_rng(1991);scores=np.empty((131,216,16),dtype='<u2');winner=None;compact=[]
for mi,m in enumerate(models):
 rs,n=transmitted_rows(m['KB'],m['M'],m['shortened_blocks'],m['puncture']);assert n==16384
 selected=rng.choice(len(rs),128,replace=False);m['sampled_rows']=selected.astype(int).tolist();sample=[rs[i] for i in selected];width=max(map(len,sample));indices=np.full((128,width),N,dtype=np.int32);masks=np.zeros(128,dtype=np.uint8)
 for j,row in enumerate(sample):
  indices[j,:len(row)]=row
  for v in row:masks[j]^=1<<(v%4)
 expected_polarity=polarity[:,masks]
 for mapping_no,word in enumerate(words):
  syndrome=np.bitwise_xor.reduce(word[:,indices],axis=-1)
  scores[mi,mapping_no]=np.count_nonzero(syndrome[None,:,:]^expected_polarity[:,None,:],axis=(1,2))
  bestpol=int(np.argmin(scores[mi,mapping_no]));compact.append((int(scores[mi,mapping_no,bestpol]),mi,mapping_no,bestpol))
 if m['KB']==8 and m['M']==2048 and m['puncture']=='p0' and m['shortened_blocks']==[0,1]:winner=mi
assert winner is not None
mapping_no=mappings.index((1,2,4,8));assert int(scores[winner,mapping_no,0])==148
top=sorted(compact,key=lambda r:r[0])[:12];old=read(P/'public_family_probe.json')
assert [r[0]/1024 for r in top]==[r['failed_fraction'] for r in old['best']]
hits=np.argwhere(scores<256);pols=np.where(scores[winner,mapping_no]==148)[0].tolist()
selected=models[winner]['sampled_rows'];selected_idx=np.asarray([rows[j] for j in selected]);syndrome=np.bitwise_xor.reduce(raw.reshape(8,-1)[:,selected_idx],axis=-1)
assert int(syndrome.sum())==148
search=dict(families=families,models=models,mappings=[list(m) for m in mappings],scores_u16le_deflate_b64=compress(scores.tobytes()),score_shape=list(scores.shape),
 training_word_ordinals=list(range(1,9)),training_canonical_bits_b64=[pack(v.reshape(-1)) for v in raw],winner_model=winner,winner_mapping=mapping_no,
 winner_polarity_ties=pols,all_polarity_hits_below_025=int(len(hits)),best_model_mapping_records_below_025=sum(r[0]<256 for r in compact),
 winner_sample_syndrome=syndrome.astype(int).tolist(),same_minimum_polarities_explained=True,old_compact_report_sha256=sha(P/'public_family_probe.json'),all_scores_replayed=True)
print('SEARCH_REPLAY',json.dumps(dict(winner_model=winner,tied_polarities=pols,all_hits=len(hits),compact_hits=search['best_model_mapping_records_below_025'],seconds=round(time.time()-start,2))),flush=True)
# Complete integer elimination: retain every forward pivot so any input row can
# replay every XOR, and every back-substitution equation can be inspected offline.
mask=(1<<M)-1;piv={};owner=[-1]*M;counts=[]
for i,row in enumerate(rows):
 value=sum(1<<(v-K) for v in row if v>=K)|(1<<(M+i));steps=0
 while value&mask:
  low=(value&mask)&-(value&mask);j=low.bit_length()-1
  if j in piv:value^=piv[j];steps+=1
  else:piv[j]=value;owner[j]=i;break
 assert value&mask;counts.append(steps)
assert len(piv)==M
inverse=[0]*M;back_counts=[]
for j in range(M-1,-1,-1):
 rest=(piv[j]&mask)^(1<<j);value=piv[j]>>M;back_counts.append(rest.bit_count())
 while rest:
  low=rest&-rest;k=low.bit_length()-1;value^=inverse[k];rest^=low
 inverse[j]=value
expected_inv=np.load(P/'mcs66_inverse.npz')['inverse_rows'];assert b''.join(v.to_bytes(512,'little') for v in inverse)==expected_inv.tobytes()
for i,row in enumerate(rows):
 value=0
 for c in row:
  if c>=K:value^=inverse[c-K]
 assert value==1<<i
packed=b''.join(piv[k].to_bytes(1024,'little') for k in range(M));compressed=zlib.compress(packed,9)
elimination=dict(rank=4096,forward_xor_count=sum(counts),forward_counts_by_original_row=counts,pivot_owner_by_column=owner,
 augmented_pivot_rows_u8_deflate_b64=b64(compressed),augmented_shape=[4096,8192],row_bytes=1024,bitorder='little',
 backward_xor_count=sum(back_counts),full_inverse_matches_frozen=True,all_4096_Hp_times_inverse_rows_equal_identity=True,
 compressed_pivot_bytes=len(compressed),uncompressed_pivot_bytes=len(packed),row_support_seed_sha256=d['model66_sha256'])
qc=[]
for z in [128,256,512,1024,2048]:
 passed=0;first_bad=None
 for r,row in enumerate(rows):
  seed=rows[(r//z)*z];shift=r%z;pred=tuple(sorted(v//z*z+(v%z+shift)%z for v in seed))
  if pred==row:passed+=1
  elif first_bad is None:first_bad=dict(row=r,shift=shift,expected=list(pred),actual=list(row))
 qc.append(dict(Z=z,rows_matching=passed,total_rows=4096,seed_count=4096//z,first_failure=first_bad))
assert next(r for r in qc if r['Z']==512)['rows_matching']==4096
table_data={str(block):[dict(k=k,theta=tables._TABLE_7_3[k][0],phi=[tables._TABLE_7_3[k][1][tables.M_VALUES.index(block)],tables._TABLE_7_3[k][2][tables.M_VALUES.index(block)],tables._TABLE_7_4[k][0][tables.M_VALUES.index(block)],tables._TABLE_7_4[k][1][tables.M_VALUES.index(block)]]) for k in range(1,27)] for block in [512,2048,4096]}
code5=read(a.repo/'matlab/protocol_receiver/models/code5_qc128_utexas_v1.json')
geometry=[]
for frame in range(1,10):
 summary_path=a.repo/f'runs/allocation-upgrade-20261103/nine_frames/frame_{frame:02d}/protocol_summary.json';s=read(summary_path)
 regs=[r for r in s['allocations']['plan']['regions'] if r['kind']=='second_body' and r['alphabet']=='16QAM']
 boundary=s['allocations']['boundaries'];head_end=int(s['headers']['second_candidates']['end_r0'])+1
 coefficients={str(k):sum(int(r['quantity']) for r in regs if r['id']==k) for k in [57,66,70]}
 assert set(r['id'] for r in regs)<=set([57,66,70])
 geometry.append(dict(frame=frame,header_end_r0=head_end,coefficient_by_id=coefficients,signal_fit_first_transition_r0=int(boundary['signal_fit_r0'][0]),
  predicted_first_transition_r0=int(boundary['predicted_r0'][0]),residual=int(boundary['offset_resources'][0]),summary_sha256=sha(summary_path)))
d['schema']='coding-walkthrough-evidence-v3';d['complete_derivation']=dict(schema='mcs66-complete-replay-v1',search=search,elimination=elimination,qc_size_diagnostics=qc,
 permutation_tables=table_data,public_table_source='https://ccsds.org/Pubs/131x0b5.pdf',code5_prior=code5,geometry_quantity_constraints=geometry,
 construction_golden_rows=[dict(row=i,support=list(rows[i]),mother_row=i+2048,mother_support=list(full_rows(8,2048)[i+2048])) for i in [0,1,511,512,1023,2048,3584,4095]],
 freshly_replayed=True,model_or_threshold_changed=False,elapsed_s=time.time()-start,
 limits=['Q4096/N16384 was a prior geometry/length hypothesis, not a value deduced from index66',
 'All-polarity scores are newly replayed; the old report kept only argmin polarity per model/mapping',
 'Full code-family identity is conditional; equivalent label polarities do not authenticate transmitter labels',
 'Earlier DSP and Code5 discovery are existing validated prerequisites, not rerun raw-signal identification'])
a.out.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
print('COMPLETE_EVIDENCE',json.dumps(dict(bytes=a.out.stat().st_size,sha256=sha(a.out),forward_xors=sum(counts),backward_xors=sum(back_counts),compressed_pivots=len(compressed),qc=[(r['Z'],r['rows_matching']) for r in qc],seconds=time.time()-start)),flush=True)
