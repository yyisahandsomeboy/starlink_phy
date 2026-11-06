(() => {
'use strict';
const W=window.walkthrough,D=W.data,$=id=>document.getElementById(id),fmt=n=>Number(n).toLocaleString('en-US');
const P={ink:'#173348',muted:'#506b7d',line:'#dce6eb',header:'#d69540',allocation:'#acd5e5',systematic:'#23789b',parity:'#8a55ad',other:'#d4dee3',pilot:'#536977',null:'#e8eef1',orange:'#bc7324'};
const payload=D.coordinates.payload_rows0,bins=D.coordinates.bins,pilotSet=new Set(D.coordinates.pilot_rows0);
const qForBin=new Int32Array(1024).fill(-1);payload.forEach((row,q)=>qForBin[bins[row]+512]=q);
const panels=[...document.querySelectorAll('[data-panel]')],buttons=[...document.querySelectorAll('[data-lesson]')];
let lesson=0,focus='allocation',chosenR0=0,bitmap=null,bitmapExample=-1;
const geometry=new Map();let rendering=false;
const current=()=>D.examples[W.state.example];
const coord=r0=>{const q=r0%1004,row=payload[q];return {r0,column:2+Math.floor(r0/1004),q0:q,fft_row1:row+1,bin:bins[row]};};
function resource(column,bin){if(column<2||column>301||bin< -512||bin>511)return null;const q=qForBin[bin+512];return q<0?null:(column-2)*1004+q;}
function regionAt(r0){return current().regions.find(r=>r0>=r.start_r0&&r0<r.end_exclusive_r0);}
function range(){const e=current(),a=e.metrics.start_r0,reg=e.regions.find(r=>r.id===66);if(focus==='header')return [e.header.start_r0,e.header.end_r0_inclusive+1];if(focus==='crc'){const begin=e.header.start_r0+3*114+24*3;return [begin,begin+24];}if(focus==='parity')return [a+3072,a+4096];if(focus==='word')return [a,a+4096];return [reg.start_r0,reg.end_exclusive_r0];}
function colorAt(r0){const e=current(),a=e.metrics.start_r0;if(r0>=a&&r0<a+4096)return r0<a+3072?P.systematic:P.parity;const r=regionAt(r0);return r.id===-1?P.header:r.id===66?P.allocation:r.id===-2?'#ecf0f2':P.other;}
function canvas(id){const el=$(id),w=el.clientWidth||600,h=el.clientHeight||250,d=Math.min(devicePixelRatio||1,2);el.width=Math.round(w*d);el.height=Math.round(h*d);const ctx=el.getContext('2d');ctx.scale(d,d);ctx.font='12px "Segoe UI","Microsoft YaHei",sans-serif';ctx.fillStyle=P.ink;return {ctx,w,h};}
function text(ctx,s,x,y,align='left',color=P.muted){ctx.textAlign=align;ctx.fillStyle=color;ctx.fillText(s,x,y);}
function line(ctx,x1,y1,x2,y2,color=P.line){ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=1;ctx.moveTo(x1,y1);ctx.lineTo(x2,y2);ctx.stroke();}
function getBitmap(){
 if(bitmap&&bitmapExample===W.state.example)return bitmap;
 bitmap=document.createElement('canvas');bitmap.width=300;bitmap.height=1024;const ctx=bitmap.getContext('2d'),im=ctx.createImageData(300,1024),rgbCache=new Map();
 const rgb=color=>{if(!rgbCache.has(color))rgbCache.set(color,[parseInt(color.slice(1,3),16),parseInt(color.slice(3,5),16),parseInt(color.slice(5,7),16)]);return rgbCache.get(color);};
 for(let y=0;y<1024;y++){const k=511-y,row=k>=0?k:k+1024,q=qForBin[k+512];for(let x=0;x<300;x++){const color=q>=0?colorAt(x*1004+q):pilotSet.has(row)?P.pilot:P.null,a=rgb(color),i=(y*300+x)*4;im.data[i]=a[0];im.data[i+1]=a[1];im.data[i+2]=a[2];im.data[i+3]=255;}}
 ctx.putImageData(im,0,0);bitmapExample=W.state.example;return bitmap;
}
function drawGrid(id,zoom=false){
 const {ctx,w,h}=canvas(id),e=current(),a=e.metrics.start_r0,b=a+4096,first=zoom?Math.floor(a/1004):0,last=zoom?Math.floor((b-1)/1004):299;
 const left=43,right=12,top=35,bottom=35,width=w-left-right,height=h-top-bottom,count=last-first+1;
 geometry.set(id,{left,top,width,height,first,last});ctx.imageSmoothingEnabled=false;ctx.drawImage(getBitmap(),first,0,count,1024,left,top,width,height);
 for(const k of [-512,-256,0,256,511]){const y=top+(511-k+.5)/1024*height;line(ctx,left,y,left+width,y,'rgba(64,89,105,.16)');text(ctx,String(k),left-7,y+4,'right');}
 const xticks=zoom?Array.from({length:count},(_,i)=>first+i):[0,49,99,149,199,249,299];
 for(const c of xticks){const x=left+(c-first+.5)/count*width;text(ctx,String(c+2),x,top+height+20,'center');if(zoom)line(ctx,left+(c-first)/count*width,top,left+(c-first)/count*width,top+height,'#fff');}
 text(ctx,'子载波 k',left,13);text(ctx,'OFDM列',left+width,h-2,'right');
 const [ra,rb]=zoom?[a,b]:range(),ca=Math.floor(ra/1004),cb=Math.floor((rb-1)/1004),x1=left+(ca-first)/count*width,x2=left+(cb-first+1)/count*width;
 ctx.strokeStyle=focus==='header'||focus==='crc'?P.orange:P.ink;ctx.lineWidth=2;ctx.strokeRect(x1,top,Math.max(2,x2-x1),height);
 if(!zoom){const reg=e.regions.find(r=>r.id===66),mid=(reg.start_r0+reg.end_exclusive_r0)/2/1004;const mx=left+(mid+.5)/300*width;
  text(ctx,'编号66 × '+reg.quantity,mx,25,'center',P.ink);
  text(ctx,'头部',left+10,25,'left',P.orange);line(ctx,left+20,29,left+(e.header.start_r0/1004+.5)/300*width,top+12,P.orange);
 }
 const c=coord(chosenR0);if(c.column-2>=first&&c.column-2<=last){const x=left+(c.column-2-first+.5)/count*width,y=top+(511-c.bin+.5)/1024*height;ctx.beginPath();ctx.strokeStyle=P.orange;ctx.lineWidth=2;ctx.arc(x,y,5,0,Math.PI*2);ctx.stroke();}
 if(focus==='crc'&&!zoom){for(let r=ra;r<rb;r++){const c=coord(r),x=left+(c.column-2+.5)/300*width,y=top+(511-c.bin+.5)/1024*height;ctx.fillStyle='#a84621';ctx.fillRect(x-2,y-1,4,2);}}
}
function drawAllocation(){
 const {ctx,w,h}=canvas('allocation-strip'),left=9,width=w-18,y=27,height=27,e=current();geometry.set('allocation-strip',{left,width,first:0,last:301200});
 e.regions.forEach(r=>{const x=left+r.start_r0/301200*width,sw=r.resource_count/301200*width;ctx.fillStyle=r.id===-1?P.header:r.id===66?P.allocation:r.id===-2?'#ecf0f2':P.other;ctx.fillRect(x,y,sw,height);if(sw>45)text(ctx,r.id>0?'MCS '+r.id:'末区',x+sw/2,y+19,'center',P.ink);});
 const a=e.metrics.start_r0,x=left+a/301200*width;ctx.fillStyle=P.systematic;ctx.fillRect(x,y,3072/301200*width,height);ctx.fillStyle=P.parity;ctx.fillRect(x+3072/301200*width,y,1024/301200*width,height);
 const [ra,rb]=range();ctx.strokeStyle=P.ink;ctx.lineWidth=2;ctx.strokeRect(left+ra/301200*width,y-3,Math.max(2,(rb-ra)/301200*width),height+6);
 text(ctx,'r0 = 0',left,16);text(ctx,'301,200',left+width,16,'right');text(ctx,'展开方向：每列先按频率升序，再进入下一列 →',left,h-7);
 $('allocation-strip-detail').textContent=`第${e.frame}帧的301,200个非导频资源按顺序排列；编号66从r0=${fmt(a)}开始，共${e.regions.find(r=>r.id===66).quantity}单位。黑框对应上方选中范围。`;
}
function drawWordStrip(){
 const {ctx,w,h}=canvas('word-strip'),left=12,width=w-24,y=26,sh=28,j=Number($('symbol').value);geometry.set('word-strip',{left,width,first:0,last:4096});
 ctx.fillStyle=P.systematic;ctx.fillRect(left,y,width*.75,sh);ctx.fillStyle=P.parity;ctx.fillRect(left+width*.75,y,width*.25,sh);
 text(ctx,'u：3072资源',left+width*.375,y+19,'center','#fff');text(ctx,'p：1024',left+width*.875,y+19,'center','#fff');
 const sx=left+(j+.5)/4096*width;line(ctx,sx,y-8,sx,y+sh+7,P.orange);text(ctx,String(j),Math.min(left+width-13,Math.max(left+13,sx)),16,'center',P.orange);
 const {hard,decoded}=W.state;ctx.fillStyle=P.orange;for(let q=0;q<4096;q++)if([0,1,2,3].some(b=>hard[q*4+b]!==decoded[q*4+b]))ctx.fillRect(left+(q+.5)/4096*width,y+sh+10,Math.max(.9,width/4096),5);
 text(ctx,'橙点：相对初始硬判决改变过的资源位置（非BER）',left,h-2);
}
function drawGeneratorStrip(){
 const {ctx,w,h}=canvas('generator-strip'),left=12,width=w-24,y=28,j=Number($('parity-index').value),x=left+(12288+j+.5)/16384*width;
 ctx.fillStyle=P.systematic;ctx.fillRect(left,y,width*.75,29);ctx.fillStyle=P.parity;ctx.fillRect(left+width*.75,y,width*.25,29);
 text(ctx,'u：12,288位',left+width*.375,y+20,'center','#fff');text(ctx,'p：4,096位',left+width*.875,y+20,'center','#fff');
 line(ctx,x,y-7,x,y+39,P.orange);text(ctx,'奇偶位 j='+fmt(j),Math.min(left+width-45,Math.max(left+45,x)),15,'center',P.orange);
 const r=coord(current().metrics.start_r0+3072+Math.floor(j/4));text(ctx,`回到OFDM：第${r.column}列，k=${r.bin}，该资源的第${j%4+1}个位`,left,h-10);
}
function describeSelection(){const c=coord(chosenR0),e=current(),a=e.metrics.start_r0,r=regionAt(chosenR0),inside=chosenR0>=a&&chosenR0<a+4096;
 $('map-selection').innerHTML=`<b>OFDM 第${c.column}列 · k=${c.bin}</b><br>资源 r0=${fmt(chosenR0)}，列内q0=${c.q0}<br>${inside?'当前码字资源 '+fmt(chosenR0-a)+'；'+(chosenR0<a+3072?'输入u区域':'奇偶p区域'):r.id===-1?'控制头的卷积编码资源':r.id>0?'编号'+r.id+'的条件分配':'末区'}`;
 const title={allocation:'先找到编号66这一段',header:'控制头是资源地图的起点',word:'一个码字跨过了多列',parity:'奇偶位集中在码字后部',crc:'CRC输入位对应哪些输出时刻？'};
 const reg=e.regions.find(r=>r.id===66),first=coord(a),last=coord(a+4095);
 const descriptions={allocation:`头部读到66和数量${reg.quantity}。当前解释中，一单位4096资源，先在整帧里标出${reg.quantity}个单位的连续区域。`,header:`本帧第二控制头占r0 [${fmt(e.header.start_r0)}, ${fmt(e.header.end_r0_inclusive+1)})。BCC译码与CRC通过后，才获得后续描述项。`,word:`第1字从第${first.column}列延伸到第${last.column}列，共4096个非导频资源。进入下一步可看每个资源的真实I/Q。`,parity:'66恢复模型把前3072资源解释为输入u，后1024资源解释为奇偶p。它们的星座都可呈16QAM；分色依据编码关系。',crc:'标记24个编码输出时刻，并非24个独立CRC位。8个CRC输入位经过卷积编码，输出还依赖先前记忆；尾部也受其状态影响。'};
 $('map-focus-title').textContent=title[focus];$('map-focus-text').textContent=descriptions[focus];
 $('word-grid-caption').textContent=`当前第1字：第${first.column}列k=${first.bin}起，到第${last.column}列k=${last.bin}止。已排除每列16个导频和4个DC位置，4096资源不是“4个完整OFDM符号”。`;
}
function redraw(){if(rendering)return;rendering=true;try{describeSelection();if(lesson===0){drawGrid('ofdm-map');drawAllocation();}if(lesson===1){drawGrid('word-grid',true);drawWordStrip();}if(lesson===3)drawGeneratorStrip();}finally{rendering=false;}}
function selectResource(r0){if(!Number.isInteger(r0)||r0<0||r0>=301200)return;chosenR0=r0;const a=current().metrics.start_r0;if(r0>=a&&r0<a+4096){$('symbol').value=r0-a;$('symbol').dispatchEvent(new Event('input'));}redraw();}
function setFocus(value){focus=value;document.querySelectorAll('[data-focus]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.focus===focus)));const [a,b]=range();selectResource(a);if(value==='crc')$('header-details').open=true;redraw();}
function activate(n,scroll=true){lesson=Math.max(0,Math.min(4,n));panels.forEach((p,i)=>p.hidden=i!==lesson);buttons.forEach((b,i)=>{if(i===lesson)b.setAttribute('aria-current','step');else b.removeAttribute('aria-current');});$('lesson-prev').disabled=lesson===0;$('lesson-next').disabled=lesson===4;$('lesson-progress').textContent=`第${lesson+1}步 / 共5步`;$('lesson-status').textContent=buttons[lesson].textContent;W.repaint();redraw();if(scroll){const bar=document.querySelector('.case-bar');window.scrollTo({top:bar.getBoundingClientRect().bottom+scrollY,behavior:'instant'});}}
function mapClick(id,event){const box=$(id).getBoundingClientRect(),g=geometry.get(id);if(!g)return;const x=event.clientX-box.left,y=event.clientY-box.top;if(x<g.left||x>=g.left+g.width||y<g.top||y>=g.top+g.height)return;const col=Math.floor((x-g.left)/g.width*(g.last-g.first+1))+g.first+2,k=511-Math.floor((y-g.top)/g.height*1024),r=resource(col,k);if(r!==null)selectResource(r);else $('map-selection').textContent=`OFDM第${col}列，k=${k}：导频或DC，不属于数据资源序列。`;}
for(const id of ['ofdm-map','word-grid'])$(id).addEventListener('click',e=>mapClick(id,e));
$('allocation-strip').addEventListener('click',ev=>{const box=$('allocation-strip').getBoundingClientRect(),g=geometry.get('allocation-strip'),x=ev.clientX-box.left;if(x>=g.left&&x<g.left+g.width)selectResource(Math.floor((x-g.left)/g.width*301200));});
$('word-strip').addEventListener('click',ev=>{const box=$('word-strip').getBoundingClientRect(),g=geometry.get('word-strip'),x=ev.clientX-box.left;if(x>=g.left&&x<g.left+g.width)selectResource(current().metrics.start_r0+Math.floor((x-g.left)/g.width*4096));});
buttons.forEach(b=>b.addEventListener('click',()=>activate(Number(b.dataset.lesson))));document.querySelectorAll('[data-focus]').forEach(b=>b.addEventListener('click',()=>setFocus(b.dataset.focus)));
$('lesson-prev').addEventListener('click',()=>activate(lesson-1));$('lesson-next').addEventListener('click',()=>activate(lesson+1));
$('decode-failed').addEventListener('click',()=>$('next-failed').click());
$('open-reference').addEventListener('click',()=>{$('references').open=true;$('references').scrollIntoView({behavior:'instant'});});
document.querySelectorAll('details').forEach(el=>el.addEventListener('toggle',()=>{if(el.open){W.repaint();redraw();}}));
window.addEventListener('walkthrough:symbol',()=>{if(W.state.example===bitmapExample||bitmapExample<0){chosenR0=current().metrics.start_r0+Number($('symbol').value);redraw();}});
window.addEventListener('walkthrough:parity',()=>{if(lesson===3)drawGeneratorStrip();});
window.addEventListener('walkthrough:example',()=>{bitmap=null;bitmapExample=-1;chosenR0=current().metrics.start_r0;redraw();});
window.addEventListener('resize',()=>requestAnimationFrame(redraw));
Object.assign(W,{activateLesson:activate,selectResource,setFocus,coordinate:coord,resourceAt:resource,drawGrid,getMapGeometry:id=>geometry.get(id),getLesson:()=>lesson,getSelection:()=>({focus,r0:chosenR0})});
chosenR0=current().metrics.start_r0;activate(0,false);
// Old bookmarked chapter fragments now open the matching teaching step.
const route={'#known':0,'#signal':1,'#search':2,'#qc':2,'#generator':3,'#decode':4,'#validate':4};if(location.hash in route)activate(route[location.hash],false);
})();
