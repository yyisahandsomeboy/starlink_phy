(() => {
'use strict';
const D=JSON.parse(document.getElementById('evidence').textContent), model=D.model66;
const $=id=>document.getElementById(id), N=model.N,K=model.K,Z=model.Z,M=N-K;
const C={ink:'#173348',muted:'#506b7d',line:'#dce6eb',blue:'#23789b',teal:'#087e77',purple:'#8a55ad',orange:'#bc7324',zero:'#e7edef'};
const fmt=n=>Number(n).toLocaleString('en-US'), fixed=(n,d=5)=>Number(n).toFixed(d);
const bits64=(s,n)=>{const b=Uint8Array.from(atob(s),c=>c.charCodeAt(0));return Uint8Array.from({length:n},(_,i)=>(b[i>>3]>>(i&7))&1);};
const bytes64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const fromhex=s=>Uint8Array.from(s.match(/../g),v=>parseInt(v,16));
const invSeeds=model.parity_inverse_first_rows_hex_little_endian.map(fromhex);
const support=row=>{const g=Math.floor(row/Z),s=row%Z;return model.seed_supports_0based[g].map(v=>Math.floor(v/Z)*Z+(v%Z+s)%Z).sort((a,b)=>a-b);};
const crc=bits=>{let r=255;for(const b of bits){const t=((r>>7)&1)^b;r=(r<<1)&255;if(t)r^=77;}return r;};
const hex=n=>'0x'+n.toString(16).toUpperCase().padStart(2,'0');
const little=a=>a.reduce((v,b,i)=>v+b*2**i,0);
let example=0,e,hard,decoded,traceStep=0,selectedRow=0;
const columnCache=new Map();
function generatorColumn(j){
 if(!Number.isInteger(j)||j<0||j>=M)throw Error('Parity coordinate outside model');
 if(columnCache.has(j))return columnCache.get(j);
 const seed=invSeeds[Math.floor(j/Z)],shift=j%Z,a=new Uint8Array(K);
 for(let q=0;q<M;q++)if((seed[q>>3]>>(q&7))&1){
  const row=Math.floor(q/Z)*Z+(q%Z+shift)%Z;
  for(const col of support(row))if(col<K)a[col]^=1;
 }
 if(columnCache.size>32)columnCache.clear();columnCache.set(j,a);return a;
}
function setupCanvas(id){const el=$(id),w=el.clientWidth||600,h=el.clientHeight||250,dpr=Math.min(window.devicePixelRatio||1,2);el.width=Math.round(w*dpr);el.height=Math.round(h*dpr);const ctx=el.getContext('2d');ctx.scale(dpr,dpr);ctx.clearRect(0,0,w,h);ctx.font='12px "Segoe UI","Microsoft YaHei",sans-serif';ctx.fillStyle=C.ink;ctx.lineWidth=1;return {ctx,w,h};}
function line(ctx,x1,y1,x2,y2,color=C.line){ctx.beginPath();ctx.strokeStyle=color;ctx.moveTo(x1,y1);ctx.lineTo(x2,y2);ctx.stroke();}
function text(ctx,s,x,y,color=C.muted,align='left'){ctx.fillStyle=color;ctx.textAlign=align;ctx.fillText(s,x,y);}
function drawScatter(){
 const {ctx,w,h}=setupCanvas('scatter'),pad=35,size=Math.min(w-2*pad,h-2*pad),left=(w-size)/2,top=14,bound=1.35;
 const x=v=>left+(v+bound)/(2*bound)*size,y=v=>top+(bound-v)/(2*bound)*size;
 for(const v of [-1,0,1]){line(ctx,x(v),top,x(v),top+size);line(ctx,left,y(v),left+size,y(v));text(ctx,String(v),x(v),top+size+17,C.muted,'center');text(ctx,String(v),left-10,y(v)+4,C.muted,'right');}
 ctx.fillStyle='rgba(25,116,154,.33)';for(const p of e.normalized_received_IQ)ctx.fillRect(x(p[0])-1,y(p[1])-1,2,2);
 ctx.strokeStyle=C.ink;for(const a of [-3,-1,1,3])for(const b of [-3,-1,1,3])ctx.strokeRect(x(a/Math.sqrt(10))-3,y(b/Math.sqrt(10))-3,6,6);
 const j=Number($('symbol').value),p=e.normalized_received_IQ[j];ctx.beginPath();ctx.strokeStyle=C.orange;ctx.lineWidth=2;ctx.arc(x(p[0]),y(p[1]),7,0,2*Math.PI);ctx.stroke();text(ctx,'I',left+size+12,y(0),C.ink);text(ctx,'Q',x(0)+8,top+5,C.ink);
}
function renderSymbol(){const j=Number($('symbol').value),p=e.normalized_received_IQ[j],llr=e.llr[j];$('symbol-value').value=fmt(j);$('symbol-detail').innerHTML=`接收 z = ${fixed(p[0])} ${p[1]>=0?'+':'−'} ${fixed(Math.abs(p[1]))}j<br>初始硬位 <b>${Array.from(hard.slice(j*4,j*4+4)).join(' ')}</b> → 译码位 <b>${Array.from(decoded.slice(j*4,j*4+4)).join(' ')}</b><br>四路LLR [${llr.map(v=>fixed(v,3)).join(', ')}]<br>全局资源 r0 = ${fmt(e.metrics.start_r0+j)}；${j<3072?'恢复模型的信息坐标':'恢复模型的奇偶坐标'}`;drawScatter();window.dispatchEvent(new Event('walkthrough:symbol'));}
function renderHeader(){
 const h=e.header,entries=h.entries,Dn=entries.length,end=16+Dn*20,target=entries.find(v=>v.index7===66),first=16+(target.ordinal-1)*20;
 $('header-bits').innerHTML=h.bits.map((b,i)=>{let cls=i<16?'prefix':i>=120?'crc':i>=end?'pad':'';if(i>=first&&i<first+20)cls+=' selected';return `<span class="${cls}" title="信息位${i}（0基）">${b}</span>`;}).join('');
 $('crc-status').textContent=`CRC通过 · ${hex(h.crc_observed)}`;
 $('header-caption').textContent=`第${e.frame}帧第二头部：r0 [${fmt(h.start_r0)}, ${fmt(h.end_r0_inclusive+1)})，456个已编码资源 → 4×32=128个保留信息位；描述项D=${Dn}。`;
 const b=target.raw_bits;
 $('entry-bits').innerHTML=`${b.slice(0,7).join('')} | ${b[7]} | ${b.slice(8).join('')}<br>LSB先行：index ${little(b.slice(0,7))} · 未决位 ${b[7]} · length ${little(b.slice(8))}`;
 $('crc-detail').textContent=`本例存储CRC ${hex(h.crc_observed)}，对前120位重新计算也得到${hex(crc(h.bits.slice(0,120)))}。参数：多项式掩码0x4D，初值0xFF，无反射、无末异或。`;
 const experiment=h.bits.slice(0,120);if($('crc-flip').checked)experiment[first]^=1;const value=crc(experiment);
 $('crc-experiment').innerHTML=`${$('crc-flip').checked?'仅教学实验，翻转信息位'+first+'后':'原始头部'}：计算 ${hex(value)}，存储 ${hex(h.crc_observed)} → <b class="${value===h.crc_observed?'good-text':'fail-text'}">${value===h.crc_observed?'相同':'不相同'}</b>`;
 const start=e.metrics.start_r0; $('resource-detail').textContent=`本例${target.quantity}单位：r0 [${fmt(start)}, ${fmt(start+target.quantity*4096)})；本页第1字：[${fmt(start)}, ${fmt(start+4096)})。区间统一左闭右开；第1帧起点还用到了前置57的候选长度。`;
}
function drawQC(){
 const {ctx,w,h}=setupCanvas('qc-grid'),left=25,top=35,cw=(w-left-7)/32,rh=(h-top-28)/8,g=Math.floor(selectedRow/Z);
 for(let b=0;b<32;b++){if(w>600||b%4===0)text(ctx,String(b),left+(b+.5)*cw,18,C.muted,'center');}
 for(let r=0;r<8;r++){
  text(ctx,String(r),12,top+(r+.65)*rh,C.muted,'center');
  for(let b=0;b<32;b++){
   const seeds=model.seed_supports_0based[r].filter(v=>Math.floor(v/Z)===b),x=left+b*cw,y=top+r*rh;
   ctx.fillStyle=b<24?'#eaf1f3':'#f0e9f5';ctx.fillRect(x+1,y+1,cw-2,rh-2);
   ctx.fillStyle=b<24?C.blue:C.purple;
   for(let k=0;k<seeds.length;k++){const f=(seeds[k]%Z+(r===g?selectedRow%Z:0))%Z/Z;ctx.fillRect(x+2+f*Math.max(1,cw-6),y+rh*.35,Math.max(2,cw*.18),rh*.3);}
  }
 }
 ctx.strokeStyle=C.teal;ctx.lineWidth=2;ctx.strokeRect(left,top+g*rh,w-left-7,rh);line(ctx,left+24*cw,top,left+24*cw,top+8*rh,C.purple);
 text(ctx,'列块0～23：输入；24～31：奇偶',left,h-4,C.muted);
}
function renderQC(){
 const group=Number($('qc-group').value),shift=Number($('qc-shift').value);selectedRow=group*Z+shift;
 $('qc-shift-value').value=shift;const row=support(selectedRow),raw=row.reduce((s,v)=>s^hard[v],0),dec=row.reduce((s,v)=>s^decoded[v],0);
 $('qc-detail').textContent=`H行 ${fmt(selectedRow)} = 种子组${group} × 512 + 移位${shift}。非零列（0基）：${row.join(', ')}。行重 ${row.length}。`;
 $('check-bits').innerHTML=row.map(v=>`<div class="bit-cell ${v>=K?'parity':''}"><small>位${v}</small><b>${hard[v]} → ${decoded[v]}</b><small>${v<K?'输入坐标':'奇偶坐标'}</small></div>`).join('');
 $('check-result').innerHTML=`原始14位的 XOR = <b class="${raw?'warn-text':'good-text'}">${raw}</b>；译码后 XOR = <b class="good-text">${dec}</b>${$('check-flip').checked?'；教学翻转后 XOR = <b class="fail-text">'+(dec^1)+'</b>':''}。`;
 drawQC();
}
function renderGenerator(){
 const j=Number($('parity-index').value),coeff=generatorColumn(j);let value=0,weight=0;const first=[];
 for(let k=0;k<K;k++)if(coeff[k]){value^=decoded[k];weight++;if(first.length<48)first.push(k);}
 const received=decoded[K+j];if(value!==received)throw Error(`G column ${j}: parity mismatch`);
 $('parity-index-value').value=fmt(j);
 $('generator-result').innerHTML=`P第 ${fmt(j)} 列有 <b>${fmt(weight)}</b> 个系数为1。对这些真实输入位做XOR → <b>${value}</b>；译码字的第 ${fmt(K+j)} 位（奇偶${fmt(j)}）= <b>${received}</b>。<span class="good-text">精确相同</span>`;
 $('generator-detail').textContent=`P列前48个非零输入坐标（0基）：${first.join(', ')}${weight>48?' …':''}。这一列不是14个系数：14是H的行重，G的稠密度是另一回事。`;
 const {ctx,w,h}=setupCanvas('generator-column'),cw=w/128,ch=h/96;
 ctx.fillStyle=C.zero;ctx.fillRect(0,0,w,h);ctx.fillStyle=C.purple;
 for(let k=0;k<K;k++)if(coeff[k])ctx.fillRect((k%128)*cw,Math.floor(k/128)*ch,Math.max(cw,1),Math.max(ch,1));
 window.dispatchEvent(new Event('walkthrough:parity'));
}
function renderTrace(){
 const seq=e.trace;traceStep=Math.min(traceStep,seq.length-1);$('trace-step').max=seq.length-1;$('trace-step').value=traceStep;$('trace-value').value=seq[traceStep].iteration;
 $('trace-prev').disabled=traceStep===0;$('trace-next').disabled=traceStep===seq.length-1;
 const {ctx,w,h}=setupCanvas('trace-chart'),pad=38,max=seq[0].failed_checks,x=i=>pad+i*(w-2*pad)/Math.max(1,seq.length-1),y=v=>h-33-v*(h-65)/(max*1.12);
 for(const t of [0,Math.round(max/2),max]){line(ctx,pad,y(t),w-10,y(t));text(ctx,String(t),pad-6,y(t)+4,C.muted,'right');}
 ctx.beginPath();ctx.strokeStyle=C.teal;ctx.lineWidth=2;seq.forEach((s,i)=>i?ctx.lineTo(x(i),y(s.failed_checks)):ctx.moveTo(x(i),y(s.failed_checks)));ctx.stroke();
 seq.forEach((s,i)=>{ctx.beginPath();ctx.fillStyle=i===traceStep?C.orange:C.teal;ctx.arc(x(i),y(s.failed_checks),i===traceStep?6:4,0,2*Math.PI);ctx.fill();text(ctx,String(s.failed_checks),x(i),y(s.failed_checks)-12,C.ink,'center');text(ctx,'迭代'+i,x(i),h-10,C.muted,'center');});
 const s=seq[traceStep],bits=bits64(s.syndrome_b64,M),cv=setupCanvas('syndrome'),size=Math.min(cv.w,cv.h),left=(cv.w-size)/2,c=size/64;
 cv.ctx.fillStyle=C.zero;cv.ctx.fillRect(left,0,size,size);cv.ctx.fillStyle=C.orange;
 bits.forEach((b,i)=>{if(b)cv.ctx.fillRect(left+(i%64)*c,Math.floor(i/64)*c,c,c);});
 $('trace-detail').innerHTML=`第${e.frame}帧第1字，迭代 <b>${s.iteration}</b>：<b>${fmt(s.failed_checks)} / 4096</b> 条失败；相对于原始硬判决修改 <b>${s.hard_changes}</b> 位。${s.failed_checks===0?'所有检查归零。':'当前仍不能接受为有效码字。'} ${e.selection_word?'本字参与了模型选择。':'本字未参与本轮模型选择。'}`;
}
function drawValidation(){
 const records=D.validation66.words,key=$('metric').value,{ctx,w,h}=setupCanvas('validation-chart'),pad=45,bottom=h-36,max=Math.max(...records.map(r=>r[key]))*1.12;
 const x=i=>pad+i*(w-pad-8)/(records.length-1),y=v=>bottom-v*(h-64)/max;
 for(const v of [0,max/2,max]){line(ctx,pad,y(v),w-5,y(v));text(ctx,key==='parity_NMSE'?v.toFixed(3):Math.round(v).toString(),pad-7,y(v)+4,C.muted,'right');}
 let lastFrame=0;
 records.forEach((r,i)=>{
  if(r.frame!==lastFrame){if(lastFrame)line(ctx,x(i),15,x(i),bottom);text(ctx,String(r.frame),x(i),h-14,C.muted);lastFrame=r.frame;}
  ctx.fillStyle=r.parameter_fitting_word?C.orange:C.teal;ctx.fillRect(x(i)-1,y(r[key])-2,2,4);
 });
 $('validation-caption').textContent=`横轴按第1～9帧顺序排列全部376字（下方数字为帧号）。橙色8点参与参数选择，绿色368点未参与本轮参数选择。${key==='parity_NMSE'?'NMSE越小表示重调制符号与接收观测的归一化平方距离越小。':'纵轴只是当前指标，不能当成发送真值下的BER。'}`;
}
function staticViews(){
 $('search-bars').innerHTML=D.search66.best.slice(0,6).map((r,i)=>`<div class="bar-row"><span class="bar-label">${i===0?'胜出 · ':''}母图${r.KB}×${r.M}，${r.puncture}，缩短[${r.shortened_blocks.join(',')}]</span><div class="bar-track"><div class="bar-fill ${i===0?'winner':''}" style="width:${r.failed_fraction*200}%"></div></div><span class="bar-value">${(100*r.failed_fraction).toFixed(3)}%</span></div>`).join('');
 const names={wrong_mapping_signI_innerI:'错误位标签：交换符号位和幅度位',wrong_shortening_blocks23:'错误缩短：改为信息块2、3',symbol_shuffle:'固定随机打乱资源顺序',actual_stream_shift_1_resources:'真实资源流起点偏移1资源',actual_stream_shift_257_resources:'真实资源流起点偏移257资源'};
 $('control-table').innerHTML='<table><thead><tr><th>真实对照条件</th><th>初始失败</th><th>最终失败</th><th>迭代</th><th>结果</th></tr></thead><tbody>'+D.validation66.controls.map(r=>`<tr><td>${names[r.name]}</td><td>${r.initial}</td><td>${r.final}</td><td>${r.iterations}</td><td class="${r.converged?'warn-text':'fail-text'}">${r.converged?'仍能收敛 · 边界反例':'未收敛'}</td></tr>`).join('')+'</tbody></table>';
 $('qc-group').innerHTML=Array.from({length:8},(_,i)=>`<option value="${i}">${i}</option>`).join('');
 $('example').innerHTML=D.examples.map((r,i)=>`<option value="${i}">第${r.frame}帧 · 第1个66码字${r.selection_word?'（参数选择样本）':'（未参与本轮参数选择）'}</option>`).join('');
 $('hashes').innerHTML=`<p>原始exemplar250-257.bin SHA-256<br>c69e82022d45173cdcaf1a5fdc8a2b864e2d61e85ae819af54b16002044adae3</p><p>MCS66冻结模型 SHA-256<br>${D.model66_sha256}</p><p>MCS70冻结模型 SHA-256<br>${D.mcs70.summary.model_sha256}</p>`+D.sources.filter(s=>[1,2,5].includes(s.frame)).map(s=>`<p>第${s.frame}帧protocol.mat SHA-256<br>${s.sha256}</p>`).join('');
}
function setExample(i){
 example=i;e=D.examples[i];hard=bits64(e.hard_bits_b64,N);decoded=bits64(e.decoded_bits_b64,N);traceStep=0;
 $('example').value=i;$('case-status').textContent=e.selection_word?'模型选择样本':'未参与模型选择';$('case-status').className='badge '+(e.selection_word?'':'good');
 if(crc(e.header.bits.slice(0,120))!==e.header.crc_observed)throw Error('Header CRC integrity check failed');
 $('crc-flip').checked=false;$('check-flip').checked=false;renderHeader();renderSymbol();renderQC();renderGenerator();renderTrace();drawValidation();window.dispatchEvent(new Event('walkthrough:example'));
}
staticViews();setExample(0);
$('example').addEventListener('change',()=>setExample(Number($('example').value)));
$('symbol').addEventListener('input',renderSymbol);$('crc-flip').addEventListener('change',renderHeader);
for(const id of ['qc-group','qc-shift','check-flip'])$(id).addEventListener(id==='qc-shift'?'input':'change',renderQC);
$('next-failed').addEventListener('click',()=>{let row=(selectedRow+1)%M;for(let i=0;i<M;i++,row=(row+1)%M)if(support(row).reduce((v,c)=>v^hard[c],0)){selectedRow=row;$('qc-group').value=Math.floor(row/Z);$('qc-shift').value=row%Z;break;}renderQC();});
$('parity-index').addEventListener('input',renderGenerator);
$('trace-step').addEventListener('input',()=>{traceStep=Number($('trace-step').value);renderTrace();});
$('trace-prev').addEventListener('click',()=>{traceStep=Math.max(0,traceStep-1);renderTrace();});$('trace-next').addEventListener('click',()=>{traceStep=Math.min(e.trace.length-1,traceStep+1);renderTrace();});
$('metric').addEventListener('change',drawValidation);
$('download').addEventListener('click',()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(D,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='coding-walkthrough-evidence-v3.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);});
let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{drawScatter();drawQC();renderGenerator();renderTrace();drawValidation();},100);});
window.walkthrough={ready:true,setExample,generatorColumn,support,crc,bits64,repaint(){renderHeader();drawScatter();renderQC();renderGenerator();renderTrace();drawValidation();},get data(){return D;},get state(){return {example,selectedRow,traceStep,hard,decoded};}};
})();
