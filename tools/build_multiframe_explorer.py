"""Read-only export of every existing protocol frame into a paged offline viewer.

Each frame is a separate HTML page sharing renderer assets. Switching frames
replaces the document, so only one pair of source grids is decoded at a time.
No MATLAB, raw IQ read or new signal processing is performed.
"""
from pathlib import Path
import argparse,base64,json,datetime,shutil,re,sys
from build_frame_explorer import sha,crc8,bcc,alphabet

def array(value):return value if isinstance(value,list) else [value]

def build(source_root,out,refresh=False):
    import numpy as np
    import h5py
    source_root=source_root.resolve();out=out.resolve();templates=Path(__file__).parent
    sources=sorted(source_root.glob('frame_*/protocol.mat'))
    if not sources:raise ValueError('No frame_*/protocol.mat found')
    if len(sources)!=9:raise ValueError('This capture viewer requires all nine existing receiver frames')
    ids=[int(p.parent.name.split('_')[-1]) for p in sources]
    if ids!=list(range(1,len(sources)+1)):raise ValueError('Frame IDs must be complete and ordered, starting at 1')
    if out.exists():
        if not refresh or not (out/'manifest.json').is_file():raise ValueError('Use a new folder or --refresh for this generated viewer')
        if json.loads((out/'manifest.json').read_text('utf-8')).get('schema')!='starlink-multiframe-manifest-v1':raise ValueError('Not a generated multiframe folder')
    out.mkdir(parents=True,exist_ok=True);(out/'assets').mkdir(exist_ok=True);(out/'frames').mkdir(exist_ok=True)
    catalog=[];summaries=[]
    for frame,src in zip(ids,sources):
        summary_path=src.with_name('protocol_summary.json');s=json.loads(summary_path.read_text('utf-8'));summaries.append(s)
        assert s['allocations']['complete'] and s['headers']['second_unique']
        assert s['source']['frame_index']==frame
        headers=[s['headers'][n] for n in ['first','second_candidates']]
        catalog.append(dict(frame=frame,page='explorer.html' if frame==1 else f'frames/frame-{frame:02d}.html',
            protocol_mat_sha256=sha(src),protocol_summary_sha256=sha(summary_path),
            original_checkpoint=Path(s['source']['checkpoint'].replace('\\','/')).name,
            original_checkpoint_sha256=s['source']['sha256'],header_blocks=[h['block_count'] for h in headers],
            crc=[h['crc_observed'] for h in headers],crc_pass=[h['crc_pass'] for h in headers],
            code5_words=s['code5']['word_count'],code5_converged=sum(bool(w['converged']) for w in array(s['code5']['words'])),
            boundary_offsets=s['allocations']['boundaries']['offset_resources'],
            mcs_ids=[r['id'] for r in s['allocations']['plan']['regions'] if r['id']>=0]))
    bins=np.r_[np.arange(512),np.arange(-512,0)];loaded=np.array(sorted(range(2,1022),key=lambda i:int(bins[i])))
    pilot=np.r_[np.arange(488,496),np.arange(528,536)];payload=np.array([i for i in loaded if i not in set(pilot)])
    assert len(payload)==1004
    def pack(a,dtype):return base64.b64encode(np.asarray(a,dtype=dtype).tobytes(order='C')).decode('ascii')
    frame_records=[];files={}
    for frame,src,s,cat in zip(ids,sources,summaries,catalog):
        digest=sha(src);regions=s['allocations']['plan']['regions']
        assert regions[0]['start_r0']==0 and regions[-1]['end_exclusive_r0']==301200
        assert all(a['end_exclusive_r0']==b['start_r0'] for a,b in zip(regions,regions[1:]))
        assert sum(r['resource_count'] for r in regions)==301200
        for r in regions:
            assert r['alphabet'] in ['BPSK','16QAM','32cross']
        with h5py.File(src,'r') as f:
            r=f['result'];before=r['calibrated_grid'][()];after=r['derotated_grid'][()]
            assert before.shape==after.shape==(301,1024)
            def complex_pack(a):
                values=np.stack([a['real'],a['imag']],axis=-1);assert np.isfinite(values).all()
                return pack(values,'<f4'),float(np.max(abs(values-values.astype('<f4').astype('float64'))))
            pre,e1=complex_pack(before);post,e2=complex_pack(after);headers=[]
            for name in ['first','second_candidates']:
                h=json.loads(json.dumps(s['headers'][name]));hg=r['headers'][name];bits=hg['word_bits'][()].ravel().astype(int).tolist()
                assert crc8(bits[:-8])==h['crc_predicted']==h['crc_observed']
                h['retained_bits']=bits;h['blocks']=array(h['blocks'])
                for j,block in enumerate(h['blocks']):
                    for field in ['inputs','reencoded','hard_observed']:
                        ref=hg['blocks'][field][()].ravel()[j];block[field]=f[ref][()].ravel().astype(int).tolist()
                    assert bcc(block['inputs'])==block['reencoded']
                    assert sum(a!=b for a,b in zip(block['hard_observed'],block['reencoded']))==block['hard_changes']
                h['browser_crc_recheck']=crc8(bits[:-8]);headers.append(h)
            ri=r['allocations/region_index'][()].ravel().astype('u1');uncertain=r['allocations/boundary_uncertain'][()].ravel().astype('u1');symbols=r['allocations/symbol_index'][()].ravel().astype('u1')
            assert np.array_equal(ri,np.repeat(np.arange(1,len(regions)+1),[v['resource_count'] for v in regions]))
            stream=r['payload_stream'][()].ravel();assert np.array_equal(stream,after[1:,payload].ravel())
            gain=r['allocations/calibration/gain_per_column'][()].ravel();assert len(gain)==300
            decided=r['allocations/decided_symbol'][()].ravel()
            for reg in regions:
                lo,hi=reg['start_r0'],reg['end_exclusive_r0'];points=np.asarray(alphabet(reg['alphabet']));expected=points[symbols[lo:hi].astype(int)-1]
                assert np.max(abs(decided['real'][lo:hi]-expected[:,0]))<1e-14
                assert np.max(abs(decided['imag'][lo:hi]-expected[:,1]))<1e-14
            modulus=float(np.max(abs(np.hypot(before['real'],before['imag'])-np.hypot(after['real'],after['imag']))))
        assert sha(src)==digest
        source=dict(protocol_mat=f'{src.parent.name}/{src.name}',protocol_mat_sha256=digest,protocol_summary_sha256=cat['protocol_summary_sha256'],receiver_version=s['version'],
            raw_capture_sha256=s['allocations']['profile']['raw_sha256'],original_checkpoint=cat['original_checkpoint'],original_checkpoint_sha256=cat['original_checkpoint_sha256'],
            scope=f'Receiver result frame {frame}/{len(sources)} from the already-inspected UT Austin exemplar250-257 capture; IDs preserve existing receiver order, not chronological order.',
            coordinate_system='MATLAB column1=SSS; columns2..301=data; q0/r0 zero based; ends exclusive',
            before_stage='FIT-pilot phase/slope calibrated final grid before fixed PN reference removal',after_stage='Same grid multiplied by conjugate PN; viewer keeps SSS as the same observation',
            precision='little-endian float32, interleaved real/imag, column then original FFT row',float32_max_absolute_component_error=max(e1,e2),source_PN_modulus_max_error=modulus,
            presentation_scope='Original geometry/header/Code5 observation stage; later MCS66/70 FEC work is documented separately.')
        code5=s['code5'];code5['words']=array(code5['words'])
        data=dict(schema='starlink-multiframe-page-v1',owner='codex_baseline',frame_index=frame,total_frames=len(sources),page_root='' if frame==1 else '../',catalog=catalog,
            created_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),source=source,bins=bins.tolist(),payload_rows0=payload.tolist(),loaded_rows0=loaded.tolist(),
            fit_rows0=[488,490,492,494,528,530,532,534],eval_rows0=[489,491,493,495,529,531,533,535],headers=headers,regions=regions,region_metrics=s['allocations']['regions'],code5=code5,
            boundary=s['allocations']['boundaries'],mixed_columns=s['allocations']['mixed_columns'],gain=[1]+gain.tolist(),alphabets={v:alphabet(v) for v in ['BPSK','16QAM','32cross']},
            before_b64=pre,after_b64=post,region_b64=pack(ri,'u1'),uncertain_b64=pack(uncertain,'u1'),symbol_b64=pack(symbols,'u1'))
        text=(templates/'multiframe_explorer.html').read_text('utf-8').replace('__FRAME_DATA__',json.dumps(data,ensure_ascii=False,separators=(',',':'),allow_nan=False).replace('</','<\\/')).replace('__ASSET_PREFIX__',data['page_root'])
        assert '__FRAME_DATA__' not in text and '__ASSET_PREFIX__' not in text
        target=out/cat['page'];target.write_text(text,encoding='utf-8',newline='\n');files[cat['page']]=sha(target)
        frame_records.append(dict(frame=frame,page=cat['page'],bytes=target.stat().st_size,sha256=sha(target),source=source,headers=[dict(N=h['block_count'],CRC=h['crc_observed'],bits=len(h['retained_bits'])) for h in headers],
            region_count=len(regions),region_resources=[v['resource_count'] for v in regions],all_301200_geometry_indices_checked=True,source_unchanged=True,code5_words=code5['word_count']))
        print(f'EXPORTED_FRAME {frame}/{len(sources)} bytes={target.stat().st_size}',flush=True)
    for name in ['multiframe_explorer.css','multiframe_explorer.js']:
        dest=out/'assets'/name;shutil.copyfile(templates/name,dest);files['assets/'+name]=sha(dest)
    manifest=dict(schema='starlink-multiframe-manifest-v1',date='2026-11-06',owner='codex_baseline',frame_count=len(sources),frames=frame_records,catalog=catalog,
        loading='One document/frame at a time; shared assets; location.replace on frame switch; old arrays become eligible for browser garbage collection',
        total_resource_count=301200*len(sources),total_file_bytes=sum((out/p).stat().st_size for p in files),files_sha256=files,
        builder_sources_sha256={n:sha(templates/n) for n in ['build_multiframe_explorer.py','multiframe_explorer.html','multiframe_explorer.css','multiframe_explorer.js']},
        shared_helpers_sha256=sha(templates/'build_frame_explorer.py'),originals_unchanged=True,raw_DSP_rerun=False)
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    (out/'README.zh-CN.md').write_text('打开explorer.html；请保留assets和frames两个子目录。覆盖当前接收结果全部9帧；保留原结果编号，可看到原候选文件名。切帧会重新载入一页，不同时解码全部九帧。高阶分色沿用原几何观察阶段，后续66/70的FEC验证见仓库独立教程。\n',encoding='utf-8')
    print(json.dumps(dict(status='built',frames=len(sources),resources=manifest['total_resource_count'],bytes=manifest['total_file_bytes'],entry=str(out/'explorer.html')),ensure_ascii=False))
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--refresh',action='store_true');p.add_argument('--deps',type=Path);a=p.parse_args()
    if a.deps:sys.path.insert(0,str(a.deps))
    build(a.source_root,a.output,a.refresh)
