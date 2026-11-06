"""Build one self-contained, offline teaching report from measured evidence.

Usage: python tools/build_coding_walkthrough.py --evidence evidence.json --out walkthrough.html
The input must be produced by collect_coding_evidence.py. No NumPy, MATLAB,
network, web server or browser extension is needed to build or open the report.
"""
from pathlib import Path
import argparse, json, hashlib

def build(evidence_path, out, template_dir):
    data=json.loads(evidence_path.read_text(encoding='utf-8'))
    assert data['schema']=='coding-walkthrough-evidence-v3'
    model=data['model66']
    assert (model['N'],model['K'],model['Z'])==(16384,12288,512)
    assert data['validation66']['converged_words']==376
    assert data['mcs70']['summary']['converged']==142
    for e in data['examples']:
        assert e['header']['crc_pass'] and e['trace'][-1]['failed_checks']==0
    encoded=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    html=(template_dir/'page.template').read_text(encoding='utf-8')
    replacements={'__STYLE__':(template_dir/'style.css').read_text(encoding='utf-8')+'\n'+(template_dir/'complete.css').read_text(encoding='utf-8'),
                  '__DATA__':encoded,'__SCRIPT__':'\n'.join((template_dir/name).read_text(encoding='utf-8') for name in ['app.js','grid.js','complete.js','complete_steps.js','complete_structure.js','complete_algebra.js','complete_decoding.js'])+'\nCompleteCourse.start();',
                  '__EVIDENCE_SHA__':hashlib.sha256(evidence_path.read_bytes()).hexdigest()}
    for key,value in replacements.items():
        assert html.count(key)==1,key
        html=html.replace(key,value)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(html,encoding='utf-8',newline='\n')
    return {'out':str(out),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),
            'evidence_sha256':replacements['__EVIDENCE_SHA__'],'offline':True}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--templates',type=Path,default=Path(__file__).parent/'coding_walkthrough')
    a=p.parse_args();print(json.dumps(build(a.evidence,a.out,a.templates),ensure_ascii=False))
