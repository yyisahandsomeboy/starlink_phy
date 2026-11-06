(() => {
'use strict';
const W=window.walkthrough,D=W.data,E=D.complete_derivation,$=id=>document.getElementById(id),N=16384,K=12288,M=4096;
const bytes=s=>Uint8Array.from(atob(s),v=>v.charCodeAt(0));
const to64=a=>{let s='';for(let i=0;i<a.length;i+=8192)s+=String.fromCharCode(...a.subarray(i,i+8192));return btoa(s);};
async function inflate(s){const data=bytes(s);if(typeof DecompressionStream!=='function')throw Error('请用支持本地解压的新版Chrome或Edge打开；全部数值仍保存在证据JSON中。');return new Uint8Array(await new Response(new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate'))).arrayBuffer());}
const numbers=(data,kind)=>{const dv=new DataView(data.buffer,data.byteOffset,data.byteLength),size=kind===64?8:4;return Array.from({length:data.byteLength/size},(_,i)=>kind===64?dv.getFloat64(i*size,true):dv.getFloat32(i*size,true));};
const fmt=n=>Number.isFinite(n)?Number(n).toLocaleString('en-US'):n===Infinity?'∞':String(n),num=(v,p=7)=>Number.isFinite(v)?Number(v).toPrecision(p):'∞';
const bit=(a,i)=>(a[i>>3]>>(i&7))&1;
const binary=(v,n=8)=>v.toString(2).padStart(n,'0'),hex=v=>'0x'+v.toString(16).toUpperCase().padStart(2,'0');
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
function table(headers,rows){return '<div class="table-wrap"><table><thead><tr>'+headers.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+rows.map(r=>'<tr>'+r.map(v=>'<td>'+v+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';}
function bind(id,event,fn){const el=$(id);if(el)el.addEventListener(event,fn);}
function range(id,min,max,value,label){return `<label class="complete-field" for="${id}">${label}<input id="${id}" type="range" min="${min}" max="${max}" value="${value}"></label>`;}
function integer(id,min,max,value,label){return `<label class="complete-field" for="${id}">${label}<input id="${id}" type="number" min="${min}" max="${max}" value="${value}"></label>`;}
function select(id,options,value,label){return `<label class="complete-field" for="${id}">${label}<select id="${id}">${options.map((v,i)=>{const item=typeof v==='object'?v:{value:i,label:v};return `<option value="${item.value}" ${String(item.value)===String(value)?'selected':''}>${esc(item.label)}</option>`;}).join('')}</select></label>`;}
function bounded(id,min,max){const n=Math.max(min,Math.min(max,Math.trunc(Number($(id).value)||0)));$(id).value=n;return n;}
function bitplot(id,a,cols=128){const el=$(id);if(!el)return;const w=el.clientWidth||700,h=el.clientHeight||150,d=Math.min(devicePixelRatio||1,2),rows=Math.ceil(a.length/cols);el.width=w*d;el.height=h*d;const ctx=el.getContext('2d');ctx.scale(d,d);ctx.fillStyle='#e2eaf0';ctx.fillRect(0,0,w,h);ctx.fillStyle='#8650ab';for(let i=0;i<a.length;i++)if(a[i])ctx.fillRect(i%cols*w/cols,Math.floor(i/cols)*h/rows,w/cols+.3,h/rows+.3);}
function xor(a,b){for(let i=0;i<a.length;i++)a[i]^=b[i];return a;}
function bits(a,count=a.length*8){return Uint8Array.from({length:count},(_,i)=>bit(a,i));}
const pop=a=>{let n=0;for(const v of a){let x=v;while(x){x&=x-1;n++;}}return n;};
const sourceBits=e=>W.bits64(e.hard_bits_b64,N),decodedBits=e=>W.bits64(e.decoded_bits_b64,N);
const current=()=>D.examples[W.state.example];
const iq=e=>numbers(bytes(e.complete.IQ_f32_b64),32),llrs=e=>numbers(bytes(e.complete.channel_llr_f32_b64),32);
function cells(KB){const m=Array.from({length:3},()=>Array.from({length:KB+3},()=>[])),add=(r,c,...v)=>m[r][c].push(...v);
 add(0,KB,0);add(0,KB+2,0,1);add(1,KB-2,0);add(1,KB-1,0);add(1,KB+1,0);add(1,KB+2,2,3,4);add(2,KB-2,0);add(2,KB-1,5,6);add(2,KB+1,7,8);add(2,KB+2,0);
 for(let pair=0;pair<(KB-2)/2;pair++){const c=KB-4-pair*2,k=9+pair*6;add(1,c,k,k+1,k+2);add(1,c+1,0);add(2,c,0);add(2,c+1,k+3,k+4,k+5);}return m;}
function permutation(k,i,block){if(k===0)return i;const p=E.permutation_tables[String(block)][k-1],q=block/4,j=Math.floor(i/q);return q*((p.theta+j)%4)+(p.phi[j]+i)%q;}
function motherRow(KB,block,row){const rb=Math.floor(row/block),i=row%block,out=new Set();cells(KB)[rb].forEach((ps,c)=>ps.forEach(k=>{const v=c*block+permutation(k,i,block);if(out.has(v))out.delete(v);else out.add(v);}));return [...out].sort((a,b)=>a-b);}
const columnMaps=new Map();
function columnMap(m){const key=JSON.stringify([m.KB,m.M,m.puncture,m.shortened_blocks]);if(columnMaps.has(key))return columnMaps.get(key);const out=new Int32Array((m.KB+3)*m.M).fill(-1),removed=new Set(m.shortened_blocks);let next=0;for(let c=0;c<out.length;c++){const b=Math.floor(c/m.M);if(removed.has(b)||m.puncture==='p0'&&b===m.KB)continue;out[c]=next++;}if(next!==N)throw Error('Candidate N mismatch');columnMaps.set(key,out);return out;}
function candidateRow(m,r){const map=columnMap(m),mr=r+(m.puncture==='p0'?m.M:0);return motherRow(m.KB,m.M,mr).filter(v=>map[v]>=0).map(v=>map[v]);}
const canonical=E.search.training_canonical_bits_b64.map(s=>W.bits64(s,N));
function labelBit(word,v,mapping,polarity){const symbol=Math.floor(v/4),b=v%4,mask=mapping[b];let value=0;for(let k=0;k<4;k++)if(mask&(1<<k))value^=canonical[word][4*symbol+k];return value^((polarity>>b)&1);}
let scorePromise,pivotPromise;
async function scores(){if(!scorePromise)scorePromise=inflate(E.search.scores_u16le_deflate_b64).then(a=>{if(a.length!==131*216*16*2)throw Error('Score array length');return new Uint16Array(a.buffer,a.byteOffset,a.byteLength/2);});return scorePromise;}
async function pivots(){if(!pivotPromise)pivotPromise=inflate(E.elimination.augmented_pivot_rows_u8_deflate_b64).then(a=>{if(a.length!==4096*1024)throw Error('Pivot matrix size');return a;});return pivotPromise;}
function inverseRow(j){const seed=bytesFromHex(D.model66.parity_inverse_first_rows_hex_little_endian[Math.floor(j/512)]),s=j%512,out=new Uint8Array(512);for(let q=0;q<M;q++)if(bit(seed,q)){const v=Math.floor(q/512)*512+(q%512+s)%512;out[v>>3]|=1<<(v&7);}return out;}
function bytesFromHex(s){return Uint8Array.from(s.match(/../g),v=>parseInt(v,16));}
function originalAugmented(row){const a=new Uint8Array(1024);for(const c of W.support(row))if(c>=K)a[(c-K)>>3]|=1<<((c-K)&7);a[512+(row>>3)]|=1<<(row&7);return a;}
function lowest(a){for(let i=0;i<512;i++)if(a[i]){const v=a[i]&-a[i];return i*8+Math.log2(v);}return -1;}
async function forward(row,stop=Infinity){const all=await pivots(),a=originalAugmented(row),operations=[];let j;while((j=lowest(a))>=0&&E.elimination.pivot_owner_by_column[j]<row){operations.push(j);if(operations.length<=stop)xor(a,all.subarray(j*1024,(j+1)*1024));else break;}
 if(stop===Infinity){if(j<0||E.elimination.pivot_owner_by_column[j]!==row)throw Error('Forward owner mismatch');if(operations.length!==E.elimination.forward_counts_by_original_row[row])throw Error('Forward operation count mismatch');}
 return {state:a,operations,pivot:j};}
async function forwardAt(row,step){const final=await forward(row),all=await pivots(),a=originalAugmented(row);for(const k of final.operations.slice(0,step))xor(a,all.subarray(k*1024,(k+1)*1024));return {...final,state:a,step:Math.min(step,final.operations.length)};}
async function backward(j,stop=Infinity){const all=await pivots(),p=all.subarray(j*1024,(j+1)*1024),rhs=p.slice(512),deps=[];for(let c=j+1;c<M;c++)if(bit(p,c))deps.push(c);for(const c of deps.slice(0,stop))xor(rhs,inverseRow(c));if(stop===Infinity){const expected=inverseRow(j);if(rhs.some((v,i)=>v!==expected[i]))throw Error('Back substitution mismatch');}return {rhs,deps};}
const decoderCache=new Map();
function decode(e){if(decoderCache.has(e.frame))return decoderCache.get(e.frame);const soft=Float64Array.from(llrs(e)),supports=Array.from({length:M},(_,r)=>W.support(r)),flat=Int32Array.from(supports.flat()),edges=flat.length,neighbours=Array.from({length:N},()=>[]);for(let k=0;k<edges;k++)neighbours[flat[k]].push(k);
 let q=Float64Array.from(flat,v=>soft[v]),hard=Uint8Array.from(soft,v=>v<0?1:0);const trace=[];
 for(let it=0;it<10;it++){
  const syndrome=Uint8Array.from(supports,row=>row.reduce((x,c)=>x^hard[c],0)),expected=e.complete.decoder[it];if(!expected)throw Error('Unexpected extra iteration');const wantBits=W.bits64(expected.bits_b64,N),wantS=W.bits64(expected.syndrome_b64,M);if(hard.some((b,i)=>b!==wantBits[i])||syndrome.some((b,i)=>b!==wantS[i]))throw Error('Full Python/JS decoder trace mismatch');
  const entry={iteration:it,bits:hard,syndrome,failed:syndrome.reduce((s,v)=>s+v,0),q};trace.push(entry);if(entry.failed===0)break;
  const r=new Float64Array(edges),sum=new Float64Array(N);
  for(let row=0;row<M;row++){const begin=row*14;let sign=1,min1=Infinity,min2=Infinity,index=-1;for(let k=0;k<14;k++){const x=q[begin+k],v=Math.abs(x);if(x<0)sign=-sign;if(v<min1){min2=min1;min1=v;index=k;}else if(v<min2)min2=v;}
   for(let k=0;k<14;k++){const edge=begin+k;r[edge]=.8*sign*(q[edge]<0?-1:1)*(k===index?min2:min1);sum[flat[edge]]+=r[edge];}}
  const post=Float64Array.from(soft,(v,i)=>v+sum[i]),nextq=Float64Array.from(flat,(v,k)=>Math.max(-50,Math.min(50,post[v]-r[k])));
  entry.r=r;entry.posterior=post;entry.nextq=nextq;
  for(const g of expected.edge_goldens){const edge=g.check*14+g.edge;for(const [value,want] of [[q[edge],g.q],[r[edge],g.r],[post[g.variable],g.posterior],[nextq[edge],g.next_q]])if(Math.abs(value-want)>1e-8)throw Error('Actual message mismatch');}
  hard=Uint8Array.from(post,v=>v<0?1:0);q=nextq;
 }
 if(trace.at(-1).failed!==0)throw Error('Decoder did not converge');const result={soft,supports,flat,neighbours,trace};decoderCache.set(e.frame,result);return result;}
function symbolLikelihood(e,symbol){const z=iq(e),x=z[symbol*2],y=z[symbol*2+1],levels=[-3,-1,1,3].map(v=>v/Math.sqrt(10)),points=[];
 for(const im of levels)for(const re of levels){const distance=(x-re)**2+(y-im)**2;points.push({I:re,Q:im,label:[re<0?1:0,im<0?1:0,Math.abs(re)<2/Math.sqrt(10)?1:0,Math.abs(im)<2/Math.sqrt(10)?1:0],distance,scaled:distance/.04});}
 const values=[];for(let b=0;b<4;b++){const zero=points.filter(p=>p.label[b]===0).map(p=>p.scaled),one=points.filter(p=>p.label[b]===1).map(p=>p.scaled),m0=Math.min(...zero),m1=Math.min(...one),s0=zero.reduce((s,v)=>s+Math.exp(m0-v),0),s1=one.reduce((s,v)=>s+Math.exp(m1-v),0);values.push(m1-m0+Math.log(s0)-Math.log(s1));}return {x,y,points,llr:values};}
const encodingCache=new Map();
function reencode(e){if(encodingCache.has(e.frame))return encodingCache.get(e.frame);const final=decode(e).trace.at(-1).bits,u=final.slice(0,K),rhs=Uint8Array.from({length:M},(_,r)=>W.support(r).filter(v=>v<K).reduce((s,v)=>s^u[v],0)),packed=new Uint8Array(512),parity=new Uint8Array(M);
 for(let i=0;i<M;i++)if(rhs[i])packed[i>>3]|=1<<(i&7);
 const counts=Uint8Array.from({length:256},(_,v)=>{let n=0;while(v){v&=v-1;n++;}return n&1;});
 for(let j=0;j<M;j++){const row=inverseRow(j);let value=0;for(let b=0;b<512;b++)value^=counts[row[b]&packed[b]];parity[j]=value;}
 const codeword=new Uint8Array(N);codeword.set(u);codeword.set(parity,K);let mismatches=0;for(let i=0;i<N;i++)if(codeword[i]!==final[i])mismatches++;if(mismatches)throw Error('Exact reencoding mismatch');const result={u,rhs,packed,parity,codeword,mismatches};encodingCache.set(e.frame,result);return result;}
function download(name,value){const u=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),10000);}
const chapters=[];let active=0,version=0,mode='full',renderPromise=Promise.resolve();
function add(chapter){chapters.push(chapter);}
async function render(n=active,scroll=false){active=Math.max(0,Math.min(chapters.length-1,n));const v=++version,c=chapters[active];$('complete-step').value=active;$('complete-position').textContent=`第${active+1}步 / 共${chapters.length}步`;$('complete-prev').disabled=active===0;$('complete-next').disabled=active===chapters.length-1;
 $('complete-body').innerHTML=`<p class="eyebrow">完整推导 · ${String(active+1).padStart(2,'0')}</p><h2>${c.title}</h2><p class="complete-question">${c.question}</p><div class="complete-contract"><div><b>本步输入</b><p>${c.input}</p></div><div><b>本步要交付</b><p>${c.output}</p></div></div><div id="complete-work" aria-busy="true"><p>正在载入这一步的真实中间状态…</p></div><div class="complete-delivery">本步完成后才进入：${active+1<chapters.length?chapters[active+1].title:'全部证据与限制已列明'}</div>`;
 if(scroll){const bar=document.querySelector('.case-bar');window.scrollTo({top:bar.getBoundingClientRect().bottom+scrollY,behavior:'instant'});}
 const ctx={...API,e:current(),mount(html){if(v===version)$('complete-work').innerHTML=html;},valid:()=>v===version};await c.render(ctx);if(v===version)$('complete-work').setAttribute('aria-busy','false');return active;}
function show(n,scroll=false){renderPromise=render(n,scroll).catch(err=>{$('complete-work').innerHTML='<p role="alert">这一步载入失败：'+esc(err.message)+'</p>';throw err;});return renderPromise;}
function setMode(value){mode=value;document.body.classList.toggle('full-mode',value==='full');document.body.classList.toggle('overview-mode',value==='overview');document.querySelectorAll('[data-course-mode]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.courseMode===value)));if(value==='full')show(active);else W.activateLesson(W.getLesson(),false);}
const API={W,D,E,N,K,M,$,bytes,to64,inflate,numbers,fmt,num,binary,hex,esc,table,bind,range,integer,select,bounded,bitplot,xor,bits,pop,sourceBits,decodedBits,current,iq,llrs,cells,permutation,motherRow,candidateRow,labelBit,scores,pivots,inverseRow,originalAugmented,lowest,forward,forwardAt,backward,decode,symbolLikelihood,reencode,download,add,show,setMode,get chapters(){return chapters;},get active(){return active;},get mode(){return mode;},get rendered(){return renderPromise;},start(){
 $('complete-step').innerHTML=chapters.map((c,i)=>`<option value="${i}">${String(i+1).padStart(2,'0')} · ${esc(c.title)}</option>`).join('');
 bind('complete-step','change',()=>show(Number($('complete-step').value),true));bind('complete-prev','click',()=>show(active-1,true));bind('complete-next','click',()=>show(active+1,true));
 document.querySelectorAll('[data-course-mode]').forEach(el=>el.addEventListener('click',()=>setMode(el.dataset.courseMode)));
 window.addEventListener('walkthrough:example',()=>{if(mode==='full')show(active);});
 window.addEventListener('resize',()=>{if(mode==='full')show(active);});
 setMode('full');API.ready=true;
 }};
window.CompleteCourse=API;
})();
