"""Build a single offline HTML from a saved v2 protocol MAT; never rerun DSP.

Requires numpy and h5py. Example:
python tools/build_frame_explorer.py --input runs/.../frame_01/protocol.mat --output runs/frame1-explorer
"""
from pathlib import Path
import argparse, base64, datetime, hashlib, json

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest()

def crc8(bits):
    crc=255
    for bit in bits:
        feedback=((crc>>7)&1)^int(bit);crc=(crc<<1)&255
        if feedback:crc^=0x4D
    return crc

def bcc(bits):
    state=0;out=[]
    for bit in bits:
        register=(state<<1)|int(bit)
        out.extend((register&g).bit_count()%2 for g in (109,83,95));state=register&63
    return out

def alphabet(name):
    if name=='BPSK':return [[-1,0],[1,0]]
    n={'16QAM':4,'32cross':6}[name];axis=list(range(-n+1,n,2))
    c=[(x,y) for x in axis for y in axis if not(name=='32cross' and abs(x)==5 and abs(y)==5)]
    scale=(sum(x*x+y*y for x,y in c)/len(c))**.5
    return [[x/scale,y/scale] for x,y in c]

def build(source,out):
    import numpy as np
    import h5py
    source=source.resolve();out=out.resolve()
    if out.exists():raise ValueError('Use a new output directory; existing reports are preserved')
    summary_path=source.with_name('protocol_summary.json')
    summary=json.loads(summary_path.read_text(encoding='utf-8'))
    assert summary['allocations']['complete'] and summary['headers']['second_unique']
    assert summary['source']['frame_index']==1,'This viewer currently targets frame1 only'
    digest=sha(source);regions=summary['allocations']['plan']['regions']
    assert [r['id'] for r in regions]==[-1,5,-1,57,66,70,71,85,-2], 'Frame1 profile changed; update the viewer palette/labels explicitly'
    assert regions[0]['start_r0']==0 and regions[-1]['end_exclusive_r0']==301200
    assert all(a['end_exclusive_r0']==b['start_r0'] for a,b in zip(regions,regions[1:]))
    bins=np.r_[np.arange(512),np.arange(-512,0)]
    loaded=np.array(sorted(range(2,1022),key=lambda i:int(bins[i])))
    pilot=np.r_[np.arange(488,496),np.arange(528,536)]
    payload=np.array([i for i in loaded if i not in set(pilot)])
    assert len(payload)==1004 and bins[payload[227]]==-277
    def pack(a,dtype):return base64.b64encode(np.asarray(a,dtype=dtype).tobytes(order='C')).decode('ascii')
    with h5py.File(source,'r') as f:
        r=f['result']
        before=r['calibrated_grid'][()];after=r['derotated_grid'][()]
        assert before.shape==after.shape==(301,1024)
        def complex_pack(a):
            data=np.stack([a['real'],a['imag']],axis=-1)
            assert np.isfinite(data).all()
            return pack(data,'<f4'),float(np.max(np.abs(data-data.astype('<f4').astype('float64'))))
        pre,e1=complex_pack(before);post,e2=complex_pack(after)
        headers=[]
        names=['first','second_candidates'];raw_headers=[summary['headers'][n] for n in names]
        for name,h in zip(names,raw_headers):
            h=json.loads(json.dumps(h));hg=r['headers'][name];bits=hg['word_bits'][()].ravel().astype(int).tolist()
            assert crc8(bits[:-8])==h['crc_predicted']==h['crc_observed']
            assert ''.join(f'{int("".join(map(str,bits[j:j+32])),2):08X}' for j in range(0,len(bits),32))==''.join(h['words_hex'])
            h['retained_bits']=bits
            for j,block in enumerate(h['blocks']):
                for field in ('inputs','reencoded','hard_observed'):
                    ref=hg['blocks'][field][()].ravel()[j]
                    block[field]=f[ref][()].ravel().astype(int).tolist()
                assert bcc(block['inputs'])==block['reencoded']
                assert sum(x!=y for x,y in zip(block['hard_observed'],block['reencoded']))==block['hard_changes']
            h['browser_crc_recheck']=crc8(bits[:-8]);headers.append(h)
        ri=r['allocations']['region_index'][()].ravel().astype('uint8')
        uncertain=r['allocations']['boundary_uncertain'][()].ravel().astype('uint8')
        symbols=r['allocations']['symbol_index'][()].ravel().astype('uint8')
        gain=r['allocations']['calibration']['gain_per_column'][()].ravel()
        assert len(ri)==len(uncertain)==len(symbols)==301200 and len(gain)==300
        assert np.array_equal(ri,np.repeat(np.arange(1,len(regions)+1),[x['resource_count'] for x in regions]))
        stream=r['payload_stream'][()].ravel();grid_after=after[1:,payload].ravel()
        assert np.array_equal(stream,grid_after)
        decided=r['allocations']['decided_symbol'][()].ravel()
        for region in regions:
            a,b=region['start_r0'],region['end_exclusive_r0'];C=np.asarray(alphabet(region['alphabet']))
            expected=C[symbols[a:b].astype(int)-1]
            assert np.max(np.abs(decided['real'][a:b]-expected[:,0]))<1e-14
            assert np.max(np.abs(decided['imag'][a:b]-expected[:,1]))<1e-14
        max_modulus_error=float(np.max(np.abs(np.hypot(before['real'],before['imag'])-np.hypot(after['real'],after['imag']))))
    assert sha(source)==digest
    data={'schema':'starlink-frame-explorer-v1','frame_index':1,'owner':'codex_baseline',
        'created_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'source':{'protocol_mat':f'{source.parent.name}/{source.name}','protocol_mat_sha256':digest,
                  'protocol_summary_sha256':sha(summary_path),'receiver_version':summary['version'],
                  'raw_capture_sha256':summary['allocations']['profile']['raw_sha256'],
                  'scope':'One already-inspected UT Austin public capture, frame1; conditional higher-order allocations',
                  'coordinate_system':'MATLAB column1=SSS, columns2..301=data. q0,r0 zero based; allocation ends exclusive.',
                  'before_stage':'FIT-pilot phase/slope calibrated final grid before PN',
                  'after_stage':'Same grid multiplied by conjugate of fixed PN reference; SSS shown without payload PN operation',
                  'precision':'little-endian float32, interleaved real/imag, column then original FFT row',
                  'float32_max_absolute_component_error':max(e1,e2),'source_PN_modulus_max_error':max_modulus_error},
        'bins':bins.tolist(),'payload_rows0':payload.tolist(),'loaded_rows0':loaded.tolist(),
        'fit_rows0':[488,490,492,494,528,530,532,534],'eval_rows0':[489,491,493,495,529,531,533,535],
        'headers':headers,'regions':regions,'region_metrics':summary['allocations']['regions'],
        'code5':summary['code5'],'boundary':summary['allocations']['boundaries'],
        'mixed_columns':summary['allocations']['mixed_columns'],
        'gain':[1]+gain.tolist(),'alphabets':{n:alphabet(n) for n in ('BPSK','16QAM','32cross')},
        'before_b64':pre,'after_b64':post,'region_b64':pack(ri,'u1'),
        'uncertain_b64':pack(uncertain,'u1'),'symbol_b64':pack(symbols,'u1')}
    template_dir=Path(__file__).parent
    template=(template_dir/'frame_explorer.html').read_text('utf-8')
    template=template.replace('__EXPLORER_CSS__',(template_dir/'frame_explorer.css').read_text('utf-8'))
    template=template.replace('__FRAME_DATA__',json.dumps(data,ensure_ascii=False,separators=(',',':'),allow_nan=False).replace('</','<\\/'))
    template=template.replace('__EXPLORER_JS__',(template_dir/'frame_explorer.js').read_text('utf-8'))
    assert '__FRAME_DATA__' not in template and '__EXPLORER_JS__' not in template
    out.mkdir(parents=True);target=out/'explorer.html';target.write_text(template,encoding='utf-8')
    manifest={'schema':data['schema'],'owner':'codex_baseline','source':data['source'],'headers':[{'words_hex':h['words_hex'],'CRC':h['crc_observed'],'crc_pass':h['crc_pass']} for h in headers],
        'regions':regions,'boundary':data['boundary'],'source_unchanged':True,'resource_count':len(ri),
        'file_bytes':target.stat().st_size,'html_sha256':sha(target),
        'builder_sources':{n:sha(template_dir/n) for n in ['build_frame_explorer.py','frame_explorer.html','frame_explorer.css','frame_explorer.js']}}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'built','html':str(target),'MiB':target.stat().st_size/2**20,'input_unchanged':True,'CRC_rechecks':[h['browser_crc_recheck'] for h in headers],'float32_max_error':max(e1,e2)},ensure_ascii=False))
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();build(args.input,args.output)
