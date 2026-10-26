"""Read-only native MATLAB OFDM visualization, with separate hashed outputs."""
import datetime
import json
import pathlib
import re

import domain

VIEW_FILES = ['01_capture_overview.png', '02_ofdm_resource_grid.png',
              '03_heldout_pilot_validation.png', '04_channel_and_synchronization.png',
              '05_fixed_symbol_constellations.png', '06_all_frame_metrics.png',
              'diagnostics_data.mat', 'diagnostics.json', 'view_manifest.json']

CAPTURE = domain.ROOT/'data/raw/exemplar250-257/exemplar250-257.bin'

def latest_real_run_id():
    report=domain.ROOT/'reports/author_receiver.json'
    if report.exists():
        value=json.loads(report.read_text());run_id=value.get('run_id','')
        if (value.get('status')=='passed' and re.fullmatch('codex-author-real-[A-Za-z0-9_-]{1,80}',run_id)
                and (domain.ROOT/'runs'/run_id/'result.mat').is_file()):
            return run_id
    raise ValueError('No passed author-method receiver result; run scripts/run_baseline real first')


def verify_capture_identity(expected_hash, path=CAPTURE):
    if not expected_hash or domain.sha(path) != expected_hash:
        raise ValueError('Capture differs from the input retained in the receiver provenance; MATLAB was not started')


def consumed_inputs(run_dir):
    record=json.loads((run_dir/'manifest.json').read_text())
    expected=next((row['sha256'] for row in record['files'] if row['path']==domain.relative(CAPTURE)),None)
    verify_capture_identity(expected)
    inputs={domain.relative(CAPTURE):expected,domain.relative(run_dir/'result.mat'):domain.sha(run_dir/'result.mat')}
    checkpoint_manifest=run_dir/'run_manifest.json'
    if checkpoint_manifest.exists() and run_dir.name.startswith('codex-author-real-'):
        original=json.loads(checkpoint_manifest.read_text())['files']
        files=[run_dir/'result.json',*sorted(run_dir.glob('frame_candidate_*.mat'))]
        for file in files:
            label=domain.relative(file);digest=domain.sha(file)
            if original.get(label)!=digest:raise ValueError('Receiver checkpoint/summary changed: '+label)
            inputs[label]=digest
        inputs[domain.relative(checkpoint_manifest)]=domain.sha(checkpoint_manifest)
    return inputs


def reserve_output_dir(run_dir):
    parent=run_dir/'diagnostics';parent.mkdir(parents=True,exist_ok=True)
    out=parent/'ofdm-v1'
    while True:
        try:
            out.mkdir(exist_ok=False);return out
        except FileExistsError:
            out=parent/('ofdm-v1-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))


def write_view_manifest(run_dir, out, inputs=None):
    files = {domain.relative(out/name): domain.sha(out/name) for name in VIEW_FILES[:-1]}
    guard=out/'07_frame_guard.png'
    if guard.is_file():files[domain.relative(guard)]=domain.sha(guard)
    sources = {domain.relative(p): domain.sha(p) for p in (domain.ROOT/'matlab/visualization').glob('*.m')}
    manifest = {'visualization_version': 'ofdm-v1', 'created_at': domain.now(),
                'source_result_path': domain.relative(run_dir/'result.mat'),
                'source_result_sha256': domain.sha(run_dir/'result.mat'),
                'consumed_input_hashes':inputs or consumed_inputs(run_dir),
                'evaluator_reference_lock_sha256':domain.sha(domain.ROOT/'config/evaluator_lock.json'),
                'reference_helper_hashes':{domain.relative(p):domain.sha(p) for p in [
                    domain.ROOT/'matlab/baseline/author_sequences.m',domain.ROOT/'matlab/baseline/bandlimited_sample.m',
                    domain.ROOT/'vendor/author_pilots/reference-template/genPss.m',
                    domain.ROOT/'vendor/author_pilots/reference-template/genSss.m',
                    domain.ROOT/'vendor/author_pilots/reference-template/genEdgePilots.m',
                    domain.ROOT/'vendor/author_pilots/reference-template/sssVec.mat']},
                'source_hashes': sources, 'files': files, 'algorithm_owner': 'codex_baseline',
                'purpose': 'Postprocessing evidence, no receiver modification or new acceptance'}
    domain.save(out/'view_manifest.json', manifest)
    domain.save(run_dir/'diagnostics/latest.json', {'visualization_version':'ofdm-v1',
                'output_dir':domain.relative(out),'manifest_path':domain.relative(out/'view_manifest.json')})
    return manifest


def render(run_id=None):
    run_id=run_id or latest_real_run_id()
    if not re.fullmatch('[A-Za-z0-9_-]{1,100}', run_id):
        raise ValueError('Invalid run_id')
    if not run_id.startswith('codex-author-real-'):
        raise ValueError('Author-method real IQ outputs only: codex-author-real-*')
    run_dir = (domain.ROOT/'runs'/run_id).resolve()
    if not run_dir.is_relative_to(domain.ROOT/'runs') or not (run_dir/'result.mat').exists():
        raise ValueError('Missing confined receiver result.mat')
    ok, reason = domain.verify_frozen_evaluator()
    if not ok:
        return {'status': 'blocked', 'reason': reason}
    inputs=consumed_inputs(run_dir)
    out = reserve_output_dir(run_dir)
    digest = domain.sha(run_dir/'result.mat')
    expression = ('addpath('+domain.matlab_string(domain.ROOT/'matlab/visualization')+');'
                  'plot_ofdm_diagnostics('+domain.matlab_string(domain.ROOT)+','+
                  domain.matlab_string(run_dir)+','+domain.matlab_string(out)+');')
    result = domain.native_run(out, expression, 'plot_ofdm', 300)
    if result['status'] == 'passed':
        if digest != domain.sha(run_dir/'result.mat'):
            return {**result, 'status': 'failed', 'reason': 'Source receiver result changed'}
        if inputs!=consumed_inputs(run_dir):
            return {**result,'status':'failed','reason':'Consumed input changed during plotting'}
        missing = [name for name in VIEW_FILES[:-1] if not (out/name).exists()]
        if missing:
            return {**result, 'status': 'failed', 'reason': 'Missing visualization outputs', 'missing': missing}
        write_view_manifest(run_dir, out, inputs)
        result.update(output_dir=domain.relative(out), diagnostics=json.loads((out/'diagnostics.json').read_text()),
                      manifest_path=domain.relative(out/'view_manifest.json'), source_result_unchanged=True)
    domain.save(out/'render_execution.json', result)
    return result
