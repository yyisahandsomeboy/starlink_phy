"""Launch and document the section-by-section native MATLAB learning receiver."""
import argparse
import datetime
import html
import json
import pathlib
import sys

import domain
ROOT = domain.ROOT

STEPS = [
('01_capture','1. 读取IQ','readIQ.m','原始int16交织文件','capture.iq：复采样；PSD、RMS、DC和截幅','I+jQ；两个int16才是一份复采样'),
('02_resampled','2. 名义重采样','resampleCapture.m','capture','sampled.iq：240Msps窗口；FIR与移除DC','resample(x,24,25,50)；尚未估计实际SFO'),
('03_sync','3. PSS/SSS同步','findFrame.m','sampled与公开参考','候选、选定起点、相关曲线与粗CFO','重复片段提候选，再用PSS+SSS相干确认'),
('04_frame_time','4. 取帧和CFO补偿','extractFrame.m','sampled、同步起点、初始CFO/SFO','frameTime：318912个时域复采样及坐标','p=start+n/(1+sfo)；乘exp(−j2πfΔt)'),
('05_without_cp','5. 去CP','removeCP.m','frameTime','without_cp：1024×301；CP与PSS另存','普通OFDM去32点CP；PSS单独处理'),
('06_fft_grid','6. FFT','fftGrid.m','ofdmTime.without_cp','frequencyGrid.values：1024×301','Y=fft(x)/sqrt(1024)；第1列SSS'),
('07_channel','7. SSS信道估计','estimateChannel.m','FFT的SSS列和已知SSS','H：1024×1；平滑、时延、噪声等','H_LS=Y_SSS/X_SSS；去斜坡后平滑再恢复'),
('08_equalized','8. 均衡','equalizeGrid.m','FFT网格和H','equalized.values及留出导频EVM','Z=Y/H；导频评价不参与SSS拟合'),
('09_pilot_observations','9. 导频初值','observePilots.m','均衡网格和8条FIT参考','每列相位/时延初值及线性预览','左右频段相位差给斜率，共同部分给旋转'),
('10_cardinality','10. 星座点数','classifyColumns.m','1004个载荷点/数据列','K=4/8/16/32得分、中心与标签','kmeans多次＋点轮廓系数中位数；不是位映射'),
('11_tracking','11. ML与整帧跟踪','trackFrame.m','均衡、噪声、点数与导频初值','逐列参数、内点、趋势和补偿网格','未知星座高斯混合似然＋RANSAC＋相位展开'),
('12_refined_offsets','12. 更新CFO/SFO','refineOffsets.m','第一轮相位/时延趋势','更新后的Hz、ppm及其来源','由每列相位斜率与时延斜率换算残余偏差'),
('13h_tracking','13. 第二轮','trackFrame.m','更新CFO/SFO后重新执行4～11','13a～13h逐个保存；finalGrid为最终网格','同一组模块重复调用；每帧独立SSS估计'),
('14_decisions','14. 条件符号判决','decideSymbols.m','最终网格、几何、幅度和噪声','1004×300最近星座点、擦除与坐标','最近几何点不等于业务位，更不等于FEC'),
('15_guard','补充：保护间隔','measureGuard.m','原IQ、帧头与最终SFO','预测边界、保护区短IQ与功率','1088/240MHz名义长度，经样本比例映射；不是噪声边缘检测')]


def make_report(out, execution):
    esc = html.escape
    sections=[]
    for key,title,module,input_,output,formula in STEPS:
        p=out/(key+'.json')
        record=json.loads(p.read_text()) if p.exists() else None
        metrics=json.dumps(record['metrics'],indent=2,ensure_ascii=False) if record else '本次尚未运行到这里。'
        figs=''.join(f'<figure><a href="figures/{esc(f.name)}"><img src="figures/{esc(f.name)}" alt="{esc(f.stem)}"></a><figcaption>{esc(f.stem)}</figcaption></figure>' for f in sorted((out/'figures').glob(key+'*.png')))
        links=f'<a href="{key}.mat">完整MAT（变量data）</a> · <a href="{key}.json">数值摘要</a>' if record else ''
        repeated=''
        if key=='13h_tracking':
            for sub,base in zip(['13a_frame_time','13b_without_cp','13c_fft_grid','13d_channel','13e_equalized','13f_pilots','13g_cardinality'],STEPS[3:10]):
                summary=out/(sub+'.json')
                if not summary.exists():continue
                submetrics=json.dumps(json.loads(summary.read_text())['metrics'],indent=2,ensure_ascii=False)
                subfigs=''.join(f'<figure><img src="figures/{esc(f.name)}" alt="{esc(f.stem)}"><figcaption>{esc(f.stem)}</figcaption></figure>' for f in sorted((out/'figures').glob(sub+'*.png')))
                repeated+=f'<h3>{sub}：{base[1]}</h3><p><a href="{sub}.mat">MAT变量</a> · <a href="{sub}.json">摘要</a> · <a href="../../matlab/learning_receiver/+slrx/{base[2]}">同一模块源码</a></p><pre>{esc(submetrics)}</pre>{subfigs}'
            if repeated:repeated='<details><summary>展开第二轮13a～13g的实际变量、数值和图片；13h最终跟踪见下方</summary>'+repeated+'</details>'
        sections.append(f'<section id="{key}"><h2>{title}</h2><p><b>输入：</b>{input_}<br><b>输出：</b>{output}</p><pre>{formula}</pre><p><a href="../../matlab/learning_receiver/+slrx/{module}">打开本模块源码</a> · {links}</p><pre>{esc(metrics)}</pre>{repeated}{figs}</section>')
    cfg=json.loads((out/'lesson_config.json').read_text()) if (out/'lesson_config.json').exists() else {}
    body=f'''<header><h1>单帧逐步接收学习记录</h1><p>版本 learning-receiver-v1 · codex_baseline。独立PSS/SSS捕获，不用作者TOA；默认每帧独立信道，没有合并其他帧SSS。</p><p>本次请求运行至第{execution['requested_through']}步；状态：{execution['status']}。配置头、真实业务位映射、FEC和CRC尚未恢复。</p></header><section><h2>怎样使用这份记录</h2><p>先看每一步的输入、输出和公式，再看MAT中的实际变量，最后看图。用MATLAB打开<a href="../../matlab/learning_receiver/START_HERE.m">START_HERE.m</a>，按Ctrl+Enter逐节运行；不必一次跑完整链路。</p><pre>D=load('06_fft_grid.mat','data');\nfrequencyGrid=D.data;\nsize(frequencyGrid.values)  % 1024×301</pre><p>第13步由13a～13h展开，重复第4～11步，各自的MAT/JSON/PNG保留在当前目录。既有步骤可回读恢复，改变DSP参数或代码则建立新目录。</p><p>输入窗口：{cfg.get('read_duration_s','?')}秒；原始起始复采样：{cfg.get('first_complex_sample','?')}；帧选择序号：{cfg.get('frame_rank','?')}。学习版窗口和单帧信道假设不同于旧50ms多帧共享模式，端到端结果不要求与旧结果逐值相同。</p><p><a href="execution.json">批处理记录</a> · <a href="lesson_config.json">本次参数</a> · <a href="lesson_lock.json">输入和代码记录</a> · <a href="../../docs/LEARNING_RECEIVER.zh-CN.md">完整学习说明</a></p></section>'''
    body+='<section><h2>按步骤跳转</h2><p>'+' · '.join(f'<a href="#{key}">{title}</a>' for key,title,*_ in STEPS)+'</p></section>'
    css='body{margin:0;background:#f1f5f7;color:#233d4b;font:16px/1.85 system-ui,sans-serif}main{max-width:1080px;margin:25px auto;padding:0 18px}header,section{background:white;border:1px solid #dce6eb;border-radius:12px;padding:25px;margin:20px 0}header{background:#153f4c;color:white}h1{font-size:28px}h2{font-size:23px}a{color:#087d84}pre{background:#edf3f7;padding:16px;overflow:auto;line-height:1.6}figure{margin:20px 0;border:1px solid #dce6eb}img{width:100%;height:auto;display:block}figcaption{padding:10px;font-size:13px}summary{cursor:pointer;color:#087d84}@media(max-width:650px){header,section{padding:16px}main{padding:0 8px}}'
    (out/'learning_report.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>逐步接收学习记录</title><style>'+css+'</style><main>'+body+''.join(sections)+'</main></html>')


def run(args):
    ok,reason=domain.verify_frozen_evaluator()
    if not ok:raise RuntimeError(reason)
    if args.resume:
        out=domain.runpath(args.resume)
        config=json.loads((out/'lesson_config.json').read_text())
        for name,key,scale in [('duration_ms','read_duration_s',.001),('first_sample','first_complex_sample',1),('frame_rank','frame_rank',1)]:
            value=getattr(args,name)
            if value is not None and config[key]!=value*scale:raise ValueError('DSP参数变化需要新学习目录，不可恢复旧缓存')
    else:
        out=domain.runpath('codex-learning-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        config={}
        if args.duration_ms is not None:config['read_duration_s']=args.duration_ms*.001
        if args.first_sample is not None:config['first_complex_sample']=args.first_sample
        if args.frame_rank is not None:config['frame_rank']=args.frame_rank
    config.update(run_dir=str(out),stop_after=args.through,resume=True,show_figures=False,make_plots=not args.no_plots)
    request=out/'request.json';domain.save(request,config)
    q=domain.matlab_string
    expr=('addpath('+q(ROOT/'matlab/learning_receiver')+');lesson_cfg=slrx.defaultConfig('+q(ROOT)+');'
          'patch=jsondecode(fileread('+q(request)+'));names=fieldnames(patch);for n=1:numel(names),lesson_cfg.(names{n})=patch.(names{n});end;'
          'slrx.runOne(lesson_cfg);slrx.validateRun('+q(out)+');')
    print(json.dumps({'phase':'running','run_id':out.name,'through':args.through},ensure_ascii=False),flush=True)
    e=domain.native_run(out,expr,'learning_receiver',args.timeout)
    status='completed' if e['status']=='passed' and args.through==14 else 'partial' if e['status']=='passed' else 'failed'
    record={'status':status,'owner':'codex_baseline','run_id':out.name,'requested_through':args.through,'execution':e,
            'configuration_header_status':'not_decoded','business_bits_recovered':False,'original_evaluator_changed':False,'online_model_calls':0}
    domain.save(out/'execution.json',record)
    # Keep each invocation when the same learning directory is resumed.
    invocation=out/'invocations'/pathlib.Path(e.get('launcher_path','unavailable')).stem
    domain.save(invocation.with_suffix('.json'),record)
    if (out/'learning_validation.json').exists():
        domain.save(invocation.with_name(invocation.name+'_validation.json'),json.loads((out/'learning_validation.json').read_text()))
    assert domain.verify_frozen_evaluator()[0]
    if (out/'lesson_config.json').exists():make_report(out,record)
    domain.save(ROOT/'reports/learning_receiver_latest.json',{**record,'report_path':domain.relative(out/'learning_report.html')})
    if status=='completed':domain.save(ROOT/'reports/learning_receiver_full.json',{**record,'report_path':domain.relative(out/'learning_report.html')})
    print(json.dumps(record,ensure_ascii=False),flush=True)
    return 0 if e['status']=='passed' else 2


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--through','--step',type=int,choices=range(1,15),default=8,help='Run through this step; existing steps are read from MAT')
    p.add_argument('--resume',help='Existing codex-learning run_id')
    p.add_argument('--duration-ms',type=float)
    p.add_argument('--first-sample',type=int)
    p.add_argument('--frame-rank',type=int)
    p.add_argument('--no-plots',action='store_true')
    p.add_argument('--timeout',type=int,default=900)
    return run(p.parse_args())

if __name__=='__main__':
    try:sys.exit(main())
    except Exception as e:print(json.dumps({'status':'failed','reason':str(e)},ensure_ascii=False));sys.exit(1)
