#!/usr/bin/env python3
"""Document provider and versioned native MATLAB domain tools; JSON CLI boundary."""
import datetime,difflib,hashlib,json,os,pathlib,re,signal,subprocess,sys,time,uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def relative(path):return str(path.relative_to(ROOT))
def save(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
def runpath(run_id):
 if not re.fullmatch(r'[A-Za-z0-9_-]{1,100}',run_id):raise ValueError('Invalid run_id')
 p=(ROOT/'runs'/run_id).resolve()
 if not p.is_relative_to(ROOT/'runs'):raise ValueError('Run escapes runs directory')
 p.mkdir(parents=True,exist_ok=True);return p
def safe_file(base,name):
 p=(base/name).resolve()
 if not p.is_relative_to(base.resolve()):raise ValueError('Path escapes permitted directory')
 return p
def journal(run_dir,event):
 with (run_dir/'tool_events.jsonl').open('a') as f:f.write(json.dumps({'time':now(),**event})+'\n')
def inspect_capture(capture_id):
 if capture_id!='exemplar250-257':raise ValueError('Unknown capture_id')
 base=ROOT/'data/raw'/capture_id;b=base/(capture_id+'.bin');meta=json.loads((base/(capture_id+'.json')).read_text())
 # Statistical summary from deterministic distributed windows, no author verification/TOA.
 import array,math
 total=0;power=0;peak=0;clipped=0
 with b.open('rb') as f:
  for fraction in [0,.25,.5,.75,.99]:
   f.seek(int((b.stat().st_size-40000)*fraction)//4*4)
   v=array.array('h');v.frombytes(f.read(40000))
   if sys.byteorder!='little':v.byteswap()
   total+=len(v)//2;power+=sum(int(x)*int(x) for x in v);peak=max(peak,max(abs(x) for x in v));clipped+=sum(abs(x)>=32767 for x in v)
 return {'status':'passed','capture_id':capture_id,'path':relative(b),'bytes':b.stat().st_size,'sha256':sha(b),'complex_samples':b.stat().st_size//4,'integer_components':b.stat().st_size//2,'fs_capture':float(meta['rate']),'duration_s':b.stat().st_size/4/float(meta['rate']),'format':'little-endian interleaved int16 I,Q','quality_sampled_complex_count':total,'sampled_rms_counts':math.sqrt(power/total),'sampled_peak_component':peak,'sampled_clipped_components':clipped,'metadata':meta,'unix_time_status':'unknown_anomalous_length','metadata_missing':['verified capture timestamp','actual sampling frequency offset'],'annotation_policy':'sliceInfo TOA excluded from acquisition tools'}
def read_research(source_id,query='',page=None,path=None):
 if path:
  p=(ROOT/path).resolve()
  if not p.exists() and source_id=='N02' and pathlib.Path(path).name==path:
   candidates=list((ROOT/'vendor/author_pilots').rglob(path))
   if len(candidates)==1:p=candidates[0].resolve()
  if not p.exists() and path=='source_index.json':p=ROOT/'notes/source_index.json'
  allowed=[ROOT/'sources',ROOT/'notes',ROOT/'vendor/author_pilots',ROOT/'config']
  agent_source=p.is_relative_to(ROOT/'runs') and 'agent-code' in p.relative_to(ROOT/'runs').parts and p.suffix=='.m'
  if not (agent_source or any(p.is_relative_to(a.resolve()) for a in allowed)) or p.suffix not in ['.md','.txt','.m','.json','.yml']:raise ValueError('Research path outside document/code provider')
  if p.name=='baseline.json':raise ValueError('Private baseline config not model-visible; thresholds are config/evaluation.json')
 else:
  mapping={'P01':'P01_frame_structure.txt','N01':'N01_pilots_journal.txt','N03':'N03_supplementary.txt','P07':'P07_simulator.txt'}
  if source_id not in mapping:
   index=json.loads((ROOT/'notes/source_index.json').read_text())
   source=next((item for item in index['sources'] if item['source_id']==source_id),None)
   if source is None:raise ValueError('Unknown source_id')
   p=ROOT/source['local_path']
   if p.suffix=='.pdf':p=p.with_suffix('.txt')
   if p.suffix not in ['.txt','.md','.m','.json']:raise ValueError('Binary source; use indexed document or code path')
  else:p=ROOT/'sources'/mapping[source_id]
 text=p.read_text();pages=text.split('\f')
 physical_pages=p.parent==ROOT/'sources' and p.with_suffix('.pdf').exists()
 if not physical_pages:pages=[text[i:i+5500] for i in range(0,len(text),5500)] or ['']
 if page is not None:
  if page<1 or page>len(pages):raise ValueError('Invalid page')
  selected=[(page,pages[page-1])]
 elif query:
  selected=[(i+1,s) for i,s in enumerate(pages) if query.casefold() in s.casefold()]
 else:selected=list(enumerate(pages,1))
 snippets=[]
 for n,s in selected[:4]:
  if query:
   pos=s.casefold().find(query.casefold()); s=s[max(0,pos-800):pos+3500]
  snippets.append({'page':n,'text':s[:5500],'snippet_truncated':len(s)>5500})
 return {'status':'passed','source_id':source_id,'path':relative(p),'sha256':sha(p),'matching_pages':[n for n,_ in selected],'snippets':snippets,'page_kind':'physical_pdf_page' if physical_pages else 'text_chunk_5500_characters','truncated':len(selected)>4 or any(len(s)>5500 for _,s in selected[:4]),'provider':'documents','kg_enabled':False}
def write_matlab_code(run_id,filename,code):
 run_dir=runpath(run_id);base=run_dir/'agent-code';base.mkdir(exist_ok=True)
 p=safe_file(base,filename)
 if p.suffix!='.m' or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*\.m',p.name):raise ValueError('MATLAB files only, simple function names required')
 if len(code.encode())>200000:raise ValueError('Code exceeds bounded write size')
 old=p.read_text() if p.exists() else '';ident=uuid.uuid4().hex[:12];v=run_dir/'code_versions'/ident/p.name;v.parent.mkdir(parents=True,exist_ok=True);v.write_text(code)
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(code)
 diff=''.join(difflib.unified_diff(old.splitlines(True),code.splitlines(True),fromfile='previous/'+filename,tofile='current/'+filename));d=v.with_suffix('.diff');d.write_text(diff)
 res={'status':'passed','owner':'dsh_agent' if os.environ.get('STARLINK_DSH_CALL_ID') else 'tool_test','path':relative(p),'sha256':sha(p),'version_path':relative(v),'diff_path':relative(d),'version_id':ident,'dsh_call_id':os.environ.get('STARLINK_DSH_CALL_ID'),'dsh_agent_id':os.environ.get('STARLINK_DSH_AGENT_ID')}
 journal(run_dir,{'tool':'write_matlab_code',**res});return res
def matlab_string(s):return "'"+str(s).replace("'","''")+"'"
def native_run(run_dir,expression,label,timeout=300):
 import shutil
 exe=os.environ.get('STARLINK_MATLAB_BIN') or shutil.which('matlab')
 if not exe:return {'status':'blocked','reason':'No native MATLAB executable'}
 launch=run_dir/(label+'_'+uuid.uuid4().hex[:10]+'.m');launch.write_text("try\n"+expression+"\ncatch ME\n fid=fopen("+matlab_string(str(launch.with_suffix('.error.json')))+",'w'); fprintf(fid,'%s',jsonencode(struct('identifier',ME.identifier,'message',ME.message,'stack',ME.stack))); fclose(fid); rethrow(ME);\nend\n")
 log=launch.with_suffix('.log');env={k:v for k,v in os.environ.items() if not re.search(r'(API_KEY|TOKEN|SECRET|PASSWORD)',k,re.I)};env['STARLINK_DEMO_ROOT']=str(ROOT)
 start=time.monotonic();timed=False;cancelled=False
 with log.open('w') as out:
  argv=[exe,'-batch','run('+matlab_string(launch)+')']
  if label=='run_matlab':
   bwrap=shutil.which('bwrap')
   if not bwrap:raise RuntimeError('bubblewrap is required to isolate agent MATLAB from truth/evaluator/credentials')
   prefs=run_dir/'matlab_prefs';prefs.mkdir(exist_ok=True)
   confined=[bwrap,'--die-with-parent','--unshare-pid','--ro-bind','/','/','--bind',str(run_dir),str(run_dir),'--dev-bind','/dev','/dev','--proc','/proc','--tmpfs','/tmp']
   for hidden in [ROOT/'state',ROOT/'matlab/evaluation',ROOT/'matlab/baseline',pathlib.Path.home()/'.codex',pathlib.Path.home()/'.aws',pathlib.Path.home()/'.ssh']:
    if hidden.exists():confined+=['--tmpfs',str(hidden),'--remount-ro',str(hidden)]
   for hidden in (ROOT/'runs').glob('codex-*'):
    if hidden.is_dir():confined+=['--tmpfs',str(hidden),'--remount-ro',str(hidden)]
   annotation=ROOT/'data/raw/exemplar250-257/sliceInfo.json'
   if annotation.exists():confined+=['--ro-bind','/dev/null',str(annotation)]
   for archive in [ROOT/'portable_resources.zip',ROOT/'vendor/author_pilots/raw-iq-data/exemplar250-257.zip']:
    if archive.exists():confined+=['--ro-bind','/dev/null',str(archive)]
   code_dir=run_dir/'agent-code'
   if code_dir.exists():confined+=['--ro-bind',str(code_dir),str(code_dir)]
   confined+=['--setenv','MATLAB_PREFDIR',str(prefs)]
   argv=confined+argv
  process_cwd=ROOT/'matlab/evaluation' if label=='evaluate_run' else run_dir
  p=subprocess.Popen(argv,cwd=process_cwd,stdout=out,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  def stop(_signum,_frame):
   nonlocal cancelled
   cancelled=True
   try:os.killpg(p.pid,signal.SIGTERM)
   except ProcessLookupError:pass
  previous={}
  if __import__('threading').current_thread() is __import__('threading').main_thread():
   for sig in [signal.SIGTERM,signal.SIGINT]:previous[sig]=signal.signal(sig,stop)
  try:
   try:p.wait(timeout=timeout)
   except subprocess.TimeoutExpired:
    timed=True;os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=8)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  finally:
   for sig,handler in previous.items():signal.signal(sig,handler)
 err=launch.with_suffix('.error.json');error=json.loads(err.read_text()) if err.exists() else None
 info={'status':'passed' if p.returncode==0 and not timed and not cancelled else 'failed','exit_code':p.returncode,'timed_out':timed,'cancelled':cancelled,'elapsed_s':time.monotonic()-start,'log_path':relative(log),'launcher_path':relative(launch),'matlab_bin':exe,'matlab_release':json.loads((ROOT/'reports/matlab_smoke.json').read_text()).get('release') if (ROOT/'reports/matlab_smoke.json').exists() else None,'error':error,'log_tail':log.read_text(errors='replace')[-3500:]}
 journal(run_dir,{'tool':label,**info});return info
def run_matlab(run_id,entry,config=None):
 run_dir=runpath(run_id);p=safe_file(run_dir/'agent-code',entry)
 events=run_dir/'tool_events.jsonl'
 attempts=sum(json.loads(line).get('tool')=='run_matlab_completed' and json.loads(line).get('entry')==entry for line in events.read_text().splitlines()) if events.exists() else 0
 if attempts>=7:return {'status':'blocked','reason':'Initial run plus six repair attempts exhausted'}
 if not p.exists() or p.suffix!='.m' or not re.fullmatch('[A-Za-z][A-Za-z0-9_]*',p.stem):raise ValueError('Entry must be existing MATLAB function in agent-code')
 cfg=dict(config or {});mode=cfg.get('data_type','synthetic')
 if mode not in ['synthetic','real_iq']:raise ValueError('Invalid data_type')
 cfg.update(root=str(ROOT),run_dir=str(run_dir),input_mat=str(ROOT/'data/reference/synthetic_holdout.mat'))
 cfg['capture_path']=str(ROOT/'data/raw/exemplar250-257/exemplar250-257.bin')
 cfg.pop('truth_mat',None);cfg['input_path']=cfg['input_mat'] if mode=='synthetic' else cfg['capture_path']
 cp=run_dir/('config_'+uuid.uuid4().hex[:10]+'.json');save(cp,cfg)
 for name in ['result.mat','result.json','evaluation.json']:
  existing=run_dir/name
  if existing.exists():
   dst=run_dir/'artifact_versions'/uuid.uuid4().hex[:12]/name;dst.parent.mkdir(parents=True,exist_ok=True);existing.rename(dst)
 timeout=int(cfg.get('timeout_s',300))
 if not 1<=timeout<=900:raise ValueError('timeout_s must be 1..900 seconds')
 expr="cfg=jsondecode(fileread("+matlab_string(cp)+"));addpath("+matlab_string(run_dir/'agent-code')+");addpath(genpath("+matlab_string(ROOT/'vendor/author_pilots')+"));"+p.stem+"(cfg);"
 input_file=pathlib.Path(cfg['input_path']);attempt_id=uuid.uuid4().hex[:12]
 provenance={'attempt_id':attempt_id,'entry':entry,'code_sha256':sha(p),'all_code_sha256':{relative(f):sha(f) for f in (run_dir/'agent-code').glob('*.m')},'config_path':relative(cp),'config_sha256':sha(cp),'input_sha256':sha(input_file) if input_file.exists() else None,'data_type':mode,'started_at':now()}
 save(run_dir/'attempts'/attempt_id/'execution_started.json',provenance)
 res=native_run(run_dir,expr,'run_matlab',timeout)
 res.update(**provenance,owner='dsh_agent' if os.environ.get('STARLINK_DSH_CALL_ID') else 'tool_test')
 result=run_dir/'result.json'
 if result.exists() and result.stat().st_size<=20000:
  try:res['summary']=json.loads(result.read_text());res['summary_is_agent_reported']=True
  except ValueError:res['result_parse_error']='Invalid JSON'
 res['result_mat_sha256']=sha(run_dir/'result.mat') if (run_dir/'result.mat').exists() else None
 save(run_dir/'attempts'/attempt_id/'execution.json',res)
 res['artifacts']=[relative(f) for f in run_dir.iterdir() if f.suffix in ['.mat','.json','.png']]
 journal(run_dir,{'tool':'run_matlab_completed','entry':entry,**res});save(run_dir/'last_execution.json',res);return res
def verify_frozen_evaluator():
 frozen=ROOT/'config/evaluator_lock.json'
 if not frozen.exists():return False,'Evaluator not frozen'
 lock=json.loads(frozen.read_text())
 if not lock or 'matlab/evaluation/evaluate_receiver.m' not in lock or 'config/evaluation.json' not in lock:return False,'Incomplete evaluator lock'
 for p,h in lock.items():
  if not (ROOT/p).exists() or sha(ROOT/p)!=h:return False,'Frozen evaluator changed: '+p
 return True,None
def evaluate_run(run_id,data_type):
 run_dir=runpath(run_id)
 if data_type not in ['synthetic','real_iq']:raise ValueError('Invalid data_type')
 if not (run_dir/'result.mat').exists():return {'status':'blocked','reason':'No result.mat; no numeric evidence'}
 last_path=run_dir/'last_execution.json'
 last=json.loads(last_path.read_text()) if last_path.exists() else None
 if last and last.get('data_type')!=data_type:return {'status':'failed','reason':'Evaluation mode differs from executed input'}
 if last and last.get('result_mat_sha256') and last['result_mat_sha256']!=sha(run_dir/'result.mat'):return {'status':'failed','reason':'Result MAT changed after recorded execution'}
 ok,reason=verify_frozen_evaluator()
 if not ok:return {'status':'blocked','reason':reason}
 truth=ROOT/'matlab/evaluation/private/synthetic_holdout_truth.mat'
 cfg={'root':str(ROOT),'run_dir':str(run_dir),'truth_path':str(truth),'data_type':data_type,
      'input_path':str(ROOT/'data/reference/synthetic_holdout.mat') if data_type=='synthetic' else str(ROOT/'data/raw/exemplar250-257/exemplar250-257.bin')}
 cp=run_dir/'evaluation_config.json';save(cp,cfg)
 expr="addpath("+matlab_string(ROOT/'matlab/evaluation')+");cfg=jsondecode(fileread("+matlab_string(cp)+"));evaluate_receiver(cfg);"
 res=native_run(run_dir,expr,'evaluate_run',300);p=run_dir/'evaluation.json'
 if res['status']=='passed' and p.exists():
  evaluation=json.loads(p.read_text());res.update(status=evaluation.get('status','unknown'),evaluation=evaluation,evidence_path=relative(p),evaluator_lock_sha256=sha(ROOT/'config/evaluator_lock.json'),result_mat_sha256=sha(run_dir/'result.mat'))
 elif res['status']=='passed':res.update(status='failed',reason='Evaluator did not produce evaluation.json')
 if last and last.get('attempt_id'):
  res['attempt_id']=last['attempt_id'];save(run_dir/'attempts'/last['attempt_id']/'evaluation.json',res)
 save(run_dir/'independent_evaluation.json',res);return res
def record_run(run_id,conclusion,evidence=None):
 p=runpath(run_id);files={relative(f):sha(f) for f in p.rglob('*') if f.is_file() and f.name!='manifest.json'}
 manifest={'run_id':run_id,'owner':'dsh_agent' if os.environ.get('STARLINK_DSH_CALL_ID') else 'tool_test','recorded_at':now(),'conclusion':conclusion,'evidence':evidence or [],'files':files,'knowledge_mode':'documents','kg_enabled':False}
 save(p/'manifest.json',manifest);return {'status':'passed','manifest_path':relative(p/'manifest.json'),'file_count':len(files)}
def dispatch(name,args):
 if name=='analyze_payload':
  import payload
  return payload.analyze_payload(**args)
 table={'inspect_capture':inspect_capture,'read_research':read_research,'write_matlab_code':write_matlab_code,'run_matlab':run_matlab,'evaluate_run':evaluate_run,'record_run':record_run}
 if name not in table:raise ValueError('Unknown domain tool')
 return table[name](**args)
if __name__=='__main__':
 try:
  args=json.loads(sys.argv[2]) if len(sys.argv)>2 else json.load(sys.stdin)
  print(json.dumps(dispatch(sys.argv[1],args),allow_nan=False))
 except Exception as e:
  print(json.dumps({'status':'failed','error_type':type(e).__name__,'reason':str(e)}));sys.exit(1)
