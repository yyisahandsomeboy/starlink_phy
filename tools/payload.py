"""Native MATLAB geometric modulation research + self-contained human explorer."""
import datetime,json,pathlib,re,time
import domain,plots


def implementation_hashes():
    files=list((domain.ROOT/'matlab/visualization').glob('*payload*.m'))
    files.extend(domain.ROOT/p for p in ['tools/payload.py','tools/payload_explorer.html','scripts/analyze_payload'])
    author_config=domain.ROOT/'config/author_receiver_v1.json'
    if author_config.exists():files.append(author_config)
    return {domain.relative(f):domain.sha(f) for f in sorted(files)}


def browser_data(data):
    records=data['records']
    if len(records)==1500 and isinstance(records[0],dict):
        data={**data,'records':[[records[s*5+r] for s in range(300)] for r in range(5)]}
    if len(data['records'])!=5 or any(len(row)!=300 for row in data['records']):
        raise ValueError('Unexpected region/symbol serialization')
    return data


def finish_outputs(run_dir,out,execution=None,start=None):
    if execution:domain.save(out/'execution.json',execution)
    data=browser_data(json.loads((out/'explorer_data.json').read_text()))
    template=(domain.ROOT/'tools/payload_explorer.html').read_text()
    embedded=json.dumps(data,separators=(',',':'),allow_nan=False).replace('</',r'<\/')
    (out/'explorer.html').write_text(template.replace('__PAYLOAD_JSON__',embedded))
    summary=json.loads((out/'analysis.json').read_text())
    manifest={'owner':'codex_baseline','recorded_at':domain.now(),
              'scope':'Exploratory payload geometry; no commercial bit recovery',
              'source_inputs':start['source_inputs'] if start else plots.consumed_inputs(run_dir),
              'config_sha256':start['classifier_config_sha256'] if start else domain.sha(domain.ROOT/'config/author_receiver_v1.json'),
              'source_hashes':start['source_hashes'] if start else implementation_hashes(),
              'interface_sources':{domain.relative(f):domain.sha(f) for f in [domain.ROOT/'tools/payload.py',domain.ROOT/'tools/payload_explorer.html']},
              'files':{domain.relative(f):domain.sha(f) for f in out.iterdir() if f.is_file() and f.name!='manifest.json'}}
    domain.save(out/'manifest.json',manifest)
    domain.save(run_dir/'payload_analysis/latest.json',{'output_dir':domain.relative(out),'explorer_path':domain.relative(out/'explorer.html'),
                'summary_path':domain.relative(out/'analysis.json'),'symbol_candidates_path':domain.relative(out/'symbol_candidates.mat'),
                'symbol_decisions_path':domain.relative(out/'symbol_decisions.mat')})
    return {'status':'passed','meaning':'Native analysis and artifact generation completed; modulation labels remain hypotheses',
            'summary':summary,'explorer_path':domain.relative(out/'explorer.html'),
            'symbol_candidates_path':domain.relative(out/'symbol_candidates.mat'),
            'symbol_decisions_path':domain.relative(out/'symbol_decisions.mat'),'output_dir':domain.relative(out),
            'manifest_path':domain.relative(out/'manifest.json'),'algorithms_owner':'codex_baseline'}


def analyze_payload(run_id=None,frame_index=1):
    run_id=run_id or plots.latest_real_run_id()
    if not re.fullmatch('codex-author-real-[A-Za-z0-9_-]{1,80}',run_id):
        return {'status':'blocked','reason':'Real run ID must be codex-author-real-*'}
    if type(frame_index) is not int or not 1<=frame_index<=32:
        return {'status':'blocked','reason':'frame_index must be a positive integer <=32'}
    run_dir=(domain.ROOT/'runs'/run_id).resolve()
    if not run_dir.is_relative_to(domain.ROOT/'runs') or not (run_dir/'result.mat').exists():
        return {'status':'blocked','reason':'Missing confined real receiver result'}
    ok,reason=domain.verify_frozen_evaluator()
    if not ok:return {'status':'blocked','reason':reason}
    inputs=plots.consumed_inputs(run_dir)
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    out=run_dir/'payload_analysis'/('payload-geometry-v1-frame'+str(frame_index)+'-'+stamp);out.mkdir(parents=True)
    cfg={'root':str(domain.ROOT),'run_dir':str(run_dir),'out':str(out),'frame_index':frame_index}
    cp=out/'config.json';domain.save(cp,cfg)
    start={'owner':'codex_baseline','source_inputs':inputs,'classifier_config_sha256':domain.sha(domain.ROOT/'config/author_receiver_v1.json'),
           'source_hashes':implementation_hashes(),
           'started_at':domain.now(),'configuration_frozen_before_real_data_validation':True}
    domain.save(out/'analysis_start.json',start)
    expression='addpath('+domain.matlab_string(domain.ROOT/'matlab/visualization')+');cfg=jsondecode(fileread('+domain.matlab_string(cp)+'));analyze_payload_regions(cfg);test_payload_artifacts(cfg.root,cfg.run_dir,cfg.out);'
    result=domain.native_run(out,expression,'analyze_payload',300)
    domain.save(out/'execution.json',result)
    if result['status']!='passed':return result
    failure=None
    if inputs!=plots.consumed_inputs(run_dir):failure='Source inputs changed during payload analysis'
    elif start['classifier_config_sha256']!=domain.sha(domain.ROOT/'config/author_receiver_v1.json'):failure='Classifier rules changed during the run'
    elif start['source_hashes']!=implementation_hashes():failure='Payload implementation changed during the run'
    integrity={'status':'failed' if failure else 'passed','reason':failure,'checked_at':domain.now()}
    domain.save(out/'integrity_check.json',integrity)
    if failure:return {**integrity,'output_dir':domain.relative(out),'native_execution_status':result['status']}
    return finish_outputs(run_dir,out,result,start)


def analyze_all_payload(run_id=None):
    run_id=run_id or plots.latest_real_run_id()
    if not re.fullmatch('codex-author-real-[A-Za-z0-9_-]{1,80}',run_id):
        return {'status':'blocked','reason':'Invalid real run ID'}
    run_dir=(domain.ROOT/'runs'/run_id).resolve()
    if not run_dir.is_relative_to(domain.ROOT/'runs') or not (run_dir/'result.json').is_file():
        return {'status':'blocked','reason':'Missing real receiver summary'}
    source_summary=json.loads((run_dir/'result.json').read_text());count=source_summary.get('frame_count')
    estimates=source_summary.get('estimates',[])
    if isinstance(estimates,dict) and count==1:estimates=[estimates]
    if type(count) is not int or not 1<=count<=32 or not isinstance(estimates,list) or count!=len(estimates):
        return {'status':'blocked','reason':'Invalid real receiver frame count'}
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    path=run_dir/'payload_analysis'/('all-frames-'+stamp+'.json');started=time.monotonic()
    batch={'status':'running','run_id':run_id,'frame_count':count,'frames':[],
           'source_summary_sha256':domain.sha(run_dir/'result.json'),'owner':'codex_baseline',
           'source_inputs':plots.consumed_inputs(run_dir),
           'classifier_config_sha256':domain.sha(domain.ROOT/'config/author_receiver_v1.json'),
           'implementation_hashes':implementation_hashes(),
           'frozen_evaluator_lock_sha256':domain.sha(domain.ROOT/'config/evaluator_lock.json'),
           'consistency_failures':[]}
    for frame in range(1,count+1):
        try:result=analyze_payload(run_id,frame)
        except Exception as error:result={'status':'failed','reason':str(error),'frame_index':frame}
        if result['status']=='passed':
            manifest=json.loads((domain.ROOT/result['output_dir']/'manifest.json').read_text())
            if (manifest['source_inputs']!=batch['source_inputs'] or
                manifest['config_sha256']!=batch['classifier_config_sha256'] or
                manifest['source_hashes']!=batch['implementation_hashes']):
                batch['consistency_failures'].append({'frame_index':frame,'reason':'Frame source/config/implementation differs from batch snapshot'})
        batch['frames'].append(result);domain.save(path,batch)
    batch['status']='passed' if all(r['status']=='passed' for r in batch['frames']) else 'failed'
    if batch['source_summary_sha256']!=domain.sha(run_dir/'result.json'):
        batch.update(status='failed',reason='Source receiver summary changed during batch')
    if (batch['source_inputs']!=plots.consumed_inputs(run_dir) or
        batch['classifier_config_sha256']!=domain.sha(domain.ROOT/'config/author_receiver_v1.json') or
        batch['implementation_hashes']!=implementation_hashes() or
        batch['frozen_evaluator_lock_sha256']!=domain.sha(domain.ROOT/'config/evaluator_lock.json') or
        batch['consistency_failures']):
        batch.update(status='failed',reason='Batch input/config/implementation/evaluation version changed')
    batch['elapsed_s']=time.monotonic()-started;batch['recorded_at']=domain.now()
    domain.save(path,batch)
    batch['batch_path']=domain.relative(path)
    if batch['status']=='passed':
        domain.save(run_dir/'payload_analysis/all_frames_latest.json',{'batch_path':domain.relative(path),'frame_count':count})
        # Human default remains first frame, even after analyzing all frames.
        first=batch['frames'][0];domain.save(run_dir/'payload_analysis/latest.json',{
            'output_dir':first['output_dir'],'explorer_path':first['explorer_path'],
            'summary_path':first['output_dir']+'/analysis.json','symbol_candidates_path':first['symbol_candidates_path'],
            'symbol_decisions_path':first['symbol_decisions_path']})
        batch['explorer_path']=first['explorer_path']
    return batch
