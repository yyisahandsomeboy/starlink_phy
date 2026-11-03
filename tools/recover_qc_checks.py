#!/usr/bin/env python3
"""Bounded weight-six QC dual recovery from a full-rank 1024x1024 P.

Optional research tool; runtime reception is MATLAB-only. Requires numpy/scipy.
Input MAT must contain binary P, recovered from development words only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.io import loadmat


def pack(row):
    return int.from_bytes(np.packbits(row, bitorder='little').tobytes(), 'little')


def inverse(P):
    n=len(P);mask=(1 << n)-1;piv={}
    for j,row in enumerate(P):
        r=pack(row)|(1 << (n+j));u=r&mask
        while u:
            k=(u&-u).bit_length()-1
            if k in piv:r ^= piv[k];u=r&mask
            else:piv[k]=r;break
        if not u and r:raise ValueError('P must be invertible for this bounded two-basis search')
    if len(piv)!=n:raise ValueError('P is rank deficient; no completion is invented')
    rows={}
    for k in range(n-1,-1,-1):
        u=(piv[k]&mask)^(1 << k);v=piv[k] >> n
        while u:
            j=(u&-u).bit_length()-1;v ^= rows[j];u ^= 1 << j
        rows[k]=v
    return np.array([np.unpackbits(np.frombuffer(rows[k].to_bytes(n//8,'little'),dtype=np.uint8),bitorder='little') for k in range(n)],dtype=bool)


def recover(P,Z=128):
    K=len(P);seeds=set()
    if P.shape!=(1024,1024) or Z!=128:raise ValueError('This search is explicitly bounded to Code5 dimensions')
    for matrix,swapped in [(P,False),(inverse(P),True)]:
        cols=[pack(matrix[:,k]) for k in range(K)]
        def retain(value,parity):
            if value.bit_count()+len(parity)!=6:return
            support=[i for i in range(K) if (value >> i)&1]+[K+i for i in parity]
            if swapped:support=[(i+K)%(2*K) for i in support]
            canonical=min(tuple(sorted(i//Z*Z+(i%Z+s)%Z for i in support)) for s in range(Z))
            seeds.add(canonical)
        for anchor in range(0,K,Z):
            retain(cols[anchor],[anchor])
            for j in range(K):
                if j==anchor:continue
                b=cols[anchor]^cols[j]
                if b.bit_count()==4:retain(b,[anchor,j])
                for k in range(j+1,K):
                    if k==anchor:continue
                    v=b^cols[k]
                    if v.bit_count()==3:retain(v,[anchor,j,k])
    supports=sorted({tuple(sorted(i//Z*Z+(i%Z+s)%Z for i in row)) for row in seeds for s in range(Z)})
    piv={}
    for row in supports:
        r=sum(1 << i for i in row)
        while r:
            k=(r&-r).bit_length()-1
            if k in piv:r ^= piv[k]
            else:piv[k]=r;break
    # Verify every recovered equation in the full dimension, not a projection.
    for row in supports:
        v=np.zeros(K,dtype=bool)
        for i in row:
            if i<K:v[i] ^= True
            else:v ^= P[:,i-K]
        if np.any(v):raise AssertionError('GH transpose is nonzero')
    if len(piv)!=K:raise ValueError(f'Only rank {len(piv)} checks found; not a complete LDPC representation')
    return {'N':2*K,'K':K,'Z':Z,'seed_supports_0based':sorted(seeds), 'sparse_H_rows':len(supports),
            'sparse_H_rank':len(piv),'row_weight':6,'GH_orthogonal':True,
            'scope':'Conditional receiver code space; only development P used. No plaintext or standardized identity claim.'}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    if a.output.exists():raise FileExistsError('Use a new output file')
    raw=loadmat(a.input)['P'];assert np.all((raw==0)|(raw==1));r=recover(raw.astype(bool))
    r['input_sha256']=hashlib.sha256(a.input.read_bytes()).hexdigest();r['input_name']=a.input.name
    a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='seed_supports_0based'},indent=2))


if __name__=='__main__':main()
