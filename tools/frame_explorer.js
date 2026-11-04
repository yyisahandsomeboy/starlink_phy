/* Offline renderer: source grids stay immutable; all decisions are separate arrays. */
(() => {
'use strict';
const $=id=>document.getElementById(id), dataNode=$('frameData');
const D=JSON.parse(dataNode.textContent);
const decode=s=>{const t=atob(s),a=new Uint8Array(t.length);for(let i=0;i<t.length;i++)a[i]=t.charCodeAt(i);return a;};
const before=new Float32Array(decode(D.before_b64).buffer),after=new Float32Array(decode(D.after_b64).buffer);
const regionIndex=decode(D.region_b64),uncertain=decode(D.uncertain_b64),symbolIndex=decode(D.symbol_b64);
delete D.before_b64;delete D.after_b64;delete D.region_b64;delete D.uncertain_b64;delete D.symbol_b64;dataNode.textContent='';
const colors=['#4267d5','#07866e','#8760c9','#ecb365','#db8b30','#b66723','#df79a3','#bd3e76','#87968d'];
const regionNames=['PDU 头 1','Code5 · BPSK','PDU 头 2','16QAM · ID57','16QAM · ID66','16QAM · ID70','32点 · ID71','32点 · ID85','二值尾部'];
const modulationColors={BPSK:'#20878b','16QAM':'#d88b2e','32cross':'#c64983'};
const fieldColors={prefix:'#4267d5',index:'#9156b8',length:'#d78629',padding:'#8b98a6',crc:'#cd4c5c',tail:'#526273'};
const fieldNames={prefix:'前缀 / 控制位',index:'MCS index 候选字段',length:'MCS length 数量字段',padding:'未分配零区',crc:'CRC8 校验字段',tail:'六位归零尾'};
const qByRow=new Int16Array(1024).fill(-1);D.payload_rows0.forEach((row,q)=>qByRow[row]=q);
const loaded=new Set(D.loaded_rows0),fit=new Set(D.fit_rows0),evaluation=new Set(D.eval_rows0);
const state={col:208,bin:140,colLo:2,colHi:301,binLo:-512,binHi:511,header:1,scope:'column',normalize:true,models:true,
    decision:false,showUncertain:true,colorMode:'region',includeSSS:false,hidden:new Set(),explicit:[],selectedBit:null};
const int=(n,a,b)=>Math.max(a,Math.min(b,Math.round(Number(n))||0));
const nf=n=>Number(n).toLocaleString('en-US'),hex=n=>'0x'+Number(n).toString(16).toUpperCase().padStart(2,'0');
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rowOfBin=bin=>bin>=0?bin:bin+1024;
const coord=r=>{const col=2+Math.floor(r/1004),q=r%1004,row=D.payload_rows0[q];return{col,q,row,bin:D.bins[row],r,index:(col-1)*1024+row};};
function info(col,bin){
    const row=rowOfBin(bin),q=qByRow[row],r=col>1&&q>=0?(col-2)*1004+q:-1;
    let kind=col===1?(loaded.has(row)?'SSS':'SSS · 未加载bin'):fit.has(row)?'FIT 导频':evaluation.has(row)?'EVAL 导频':q<0?'未加载载波':regionNames[regionIndex[r]-1];
    return{col,bin,row,q,r,index:(col-1)*1024+row,region:r>=0?regionIndex[r]-1:-1,kind};
}
const headerResource=new Map();
function bitField(h,b){
    const length=h.retained_bits.length,endEntries=16+20*h.fields.entry_count;
    if(b>=length-8)return{type:'crc',name:`CRC8 · 位 ${b-(length-8)}（MSB先行）`};
    if(b<16){let name='固定 / 未解析前缀位';if(b===5)name=`头部角色位：${h.fields.role_bit}`;
        if(b>=8&&b<=10)name=`块数 N 的小端位 ${b-8}，N=${h.block_count}`;
        if(b>=12&&b<=15)name=`描述项数 D 的小端位 ${b-12}，D=${h.fields.entry_count}`;
        return{type:'prefix',name};}
    if(b>=endEntries)return{type:'padding',name:'CRC前未分配零位（语义未定）'};
    const e=Math.floor((b-16)/20),within=(b-16)%20;
    return within<8?{type:'index',entry:e,name:`第${e+1}项 index 位 ${within}（小端；第8位语义未定）`}:
        {type:'length',entry:e,name:`第${e+1}项 quantity 位 ${within-8}（小端）`};
}
D.headers.forEach((h,hi)=>h.blocks.forEach((b,bi)=>{
    for(let t=0;t<38;t++)for(let k=0;k<3;k++){
        const r=h.start_r0+bi*114+t*3+k,bit=t<32?bi*32+t:null;
        headerResource.set(r,{header:hi,block:bi,input:t,output:k,bit,field:bit===null?{type:'tail',name:'归零尾输入时刻'}:bitField(h,bit)});
    }
}));
function colorFor(inf){
    if(inf.col===1)return loaded.has(inf.row)?'#416b7c':'#e4e9e3';
    if(inf.region<0)return fit.has(inf.row)?'#39afb7':evaluation.has(inf.row)?'#77a9d1':'#e6ebe4';
    if(state.colorMode==='header'&&headerResource.has(inf.r))return fieldColors[headerResource.get(inf.r).field.type];
    return state.colorMode==='modulation'?modulationColors[D.regions[inf.region].alphabet]||'#87968d':colors[inf.region];
}
let toastTimer;function toast(text){$('toast').textContent=text;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').hidden=true,4000);}
function download(name,text,type='application/json'){
    const url=URL.createObjectURL(new Blob([text],{type})),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),2000);
}
function canvasSetup(canvas){
    const rect=canvas.getBoundingClientRect(),w=rect.width,h=rect.height,dpr=Math.min(2,window.devicePixelRatio||1);
    if(canvas.width!==Math.round(w*dpr)||canvas.height!==Math.round(h*dpr)){canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);}
    const ctx=canvas.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);return{ctx,w,h};
}
const mapSource=document.createElement('canvas');mapSource.width=301;mapSource.height=1024;
let rasterDirty=true,mapBox=null,drag=null;
function raster(){
    const ctx=mapSource.getContext('2d'),image=ctx.createImageData(301,1024),a=image.data;
    for(let col=1;col<=301;col++)for(let bin=-512;bin<=511;bin++){
        const inf=info(col,bin),color=colorFor(inf),pos=((511-bin)*301+col-1)*4;
        let rgb=[1,3,5].map(k=>parseInt(color.slice(k,k+2),16));
        if(inf.region>=0&&state.hidden.has(inf.region))rgb=rgb.map(x=>Math.round(x*.15+255*.85));
        if(state.showUncertain&&inf.r>=0&&uncertain[inf.r]){
            const shade=(Math.floor(bin/3)%2+2)%2;rgb=rgb.map((x,k)=>Math.round(x*.45+[shade?35:255,shade?44:211,shade?41:123][k]*.55));
        }
        a[pos]=rgb[0];a[pos+1]=rgb[1];a[pos+2]=rgb[2];a[pos+3]=255;
    }
    ctx.putImageData(image,0,0);rasterDirty=false;
}
function drawMap(){
    if(rasterDirty)raster();const{ctx,w,h}=canvasSetup($('resourceMap'));
    const l=49,t=17,pw=w-l-16,ph=h-t-40;mapBox={l,t,pw,ph};ctx.imageSmoothingEnabled=false;
    ctx.drawImage(mapSource,state.colLo-1,511-state.binHi,state.colHi-state.colLo+1,state.binHi-state.binLo+1,l,t,pw,ph);
    ctx.strokeStyle='#b8c7b8';ctx.lineWidth=.7;ctx.strokeRect(l,t,pw,ph);
    ctx.font='10px "Microsoft YaHei",sans-serif';ctx.fillStyle='#788578';ctx.textAlign='center';
    const xt=[...new Set(Array.from({length:6},(_,i)=>Math.round(state.colLo+(state.colHi-state.colLo)*i/5)))];
    xt.forEach(n=>{const x=l+(n-state.colLo+.5)/(state.colHi-state.colLo+1)*pw;ctx.fillText(n,x,t+ph+17);});
    ctx.fillText('OFDM 列号 · 列 1 为 SSS',l+pw/2,h-6);
    ctx.textAlign='right';for(let i=0;i<=4;i++){const n=Math.round(state.binHi-(state.binHi-state.binLo)*i/4),y=t+(state.binHi-n+.5)/(state.binHi-state.binLo+1)*ph;ctx.fillText(n,l-8,y+3);}
    ctx.save();ctx.translate(12,t+ph/2);ctx.rotate(-Math.PI/2);ctx.textAlign='center';ctx.fillText('有符号 bin（频率升序向上）',0,0);ctx.restore();
    if(state.col>=state.colLo&&state.col<=state.colHi){
        const x=l+(state.col-state.colLo)/(state.colHi-state.colLo+1)*pw,cw=pw/(state.colHi-state.colLo+1);
        ctx.strokeStyle='#142f2c';ctx.lineWidth=1.5;ctx.strokeRect(x+.5,t+.5,Math.max(cw-1,1),ph-1);
        if(state.bin>=state.binLo&&state.bin<=state.binHi){const y=t+(state.binHi-state.bin+.5)/(state.binHi-state.binLo+1)*ph;ctx.beginPath();ctx.arc(x+cw/2,y,4,0,Math.PI*2);ctx.strokeStyle='#fff';ctx.lineWidth=2.5;ctx.stroke();ctx.strokeStyle='#19352e';ctx.lineWidth=1;ctx.stroke();}
    }
    if(state.explicit.length&&state.scope==='selection'){
        ctx.strokeStyle='#172c36';ctx.lineWidth=1.5;
        for(const r of state.explicit){const c=coord(r);if(c.col<state.colLo||c.col>state.colHi||c.bin<state.binLo||c.bin>state.binHi)continue;
            const x=l+(c.col-state.colLo)/(state.colHi-state.colLo+1)*pw,y=t+(state.binHi-c.bin)/(state.binHi-state.binLo+1)*ph;
            ctx.strokeRect(x,y,Math.max(1,pw/(state.colHi-state.colLo+1)),Math.max(1,ph/(state.binHi-state.binLo+1)));}
    }
    if(drag&&drag.moved){ctx.fillStyle='#087c7020';ctx.strokeStyle='#087c70';ctx.fillRect(drag.x,drag.y,drag.lastX-drag.x,drag.lastY-drag.y);ctx.strokeRect(drag.x,drag.y,drag.lastX-drag.x,drag.lastY-drag.y);}
    $('mapRange').textContent=`列 ${state.colLo}…${state.colHi} · bin ${state.binLo}…${state.binHi}`;
    ['colLo','colHi','binLo','binHi'].forEach(k=>$(k).value=state[k]);
}
function mapPosition(event){
    const rect=$('resourceMap').getBoundingClientRect(),x=event.clientX-rect.left,y=event.clientY-rect.top;
    if(!mapBox||x<mapBox.l||x>mapBox.l+mapBox.pw||y<mapBox.t||y>mapBox.t+mapBox.ph)return null;
    return{x,y,col:int(state.colLo+(x-mapBox.l)/mapBox.pw*(state.colHi-state.colLo+1)-.5,state.colLo,state.colHi),
        bin:int(state.binHi-(y-mapBox.t)/mapBox.ph*(state.binHi-state.binLo+1)+.5,state.binLo,state.binHi)};
}
function select(col,bin,clear=true){state.col=int(col,1,301);state.bin=int(bin,-512,511);if(clear){state.explicit=[];state.selectedBit=null;if(state.scope==='selection')state.scope='column';}
    const inf=info(state.col,state.bin);if(headerResource.has(inf.r))state.header=headerResource.get(inf.r).header;render();}
function selectR(r){const c=coord(r);select(c.col,c.bin,false);}
function focusList(list,label){
    state.explicit=[...new Set(list)].sort((a,b)=>a-b);if(!state.explicit.length)return;
    const cs=state.explicit.map(coord);state.col=cs[0].col;state.bin=cs[0].bin;state.scope='selection';
    state.colLo=Math.max(2,Math.min(...cs.map(c=>c.col))-1);state.colHi=Math.min(301,Math.max(...cs.map(c=>c.col))+1);
    state.binLo=Math.max(-512,Math.min(...cs.map(c=>c.bin))-20);state.binHi=Math.min(511,Math.max(...cs.map(c=>c.bin))+20);
    state.colorMode='header';rasterDirty=true;$('selectionHint').textContent=label;render();
}
function preset(name){
    state.scope='column';state.explicit=[];state.selectedBit=null;state.binLo=-512;state.binHi=511;
    if(name==='first'){state.colLo=2;state.colHi=3;state.binLo=-512;state.binHi=-235;state.col=2;state.bin=-400;state.header=0;state.colorMode='header';state.scope='region';state.hidden.delete(0);}
    else if(name==='second'){state.colLo=9;state.colHi=11;state.col=10;state.bin=100;state.header=1;state.colorMode='header';state.scope='region';state.hidden.delete(2);}
    else if(name==='mixed'){state.colLo=206;state.colHi=210;state.col=208;state.bin=140;state.colorMode='region';}
    else if(name==='tail'){state.colLo=297;state.colHi=301;selectTail();state.colorMode='region';state.scope='region';state.hidden.delete(8);}
    else if(name==='sss'){state.colLo=state.colHi=state.col=1;state.bin=100;state.includeSSS=true;}
    else{state.colLo=state.includeSSS?1:2;state.colHi=301;state.colorMode='region';}
    document.querySelectorAll('[data-preset]').forEach(b=>b.classList.toggle('active',b.dataset.preset===name));
    rasterDirty=true;render();
}
function selectTail(){const c=coord(D.regions.at(-1).start_r0);state.col=c.col;state.bin=c.bin;}
function renderInspector(){
    const c=info(state.col,state.bin),reg=c.region>=0?D.regions[c.region]:null;
    $('selectedTitle').textContent=c.kind;$('selectedSwatch').style.background=colorFor(c);$('selectedCol').value=state.col;
    const p=2*c.index,n=x=>Number(x).toFixed(3),facts=[['OFDM 列',c.col===1?'1 · SSS':`${c.col} · 数据列 ${c.col-1}`],['频率 bin / FFT行',`${c.bin} / ${c.row+1}`],
        ['q0 / r0',c.r<0?'—':`${c.q} / ${nf(c.r)}`],['去PN前 I + jQ',`${n(before[p])} + j(${n(before[p+1])})`],
        ['去PN后 I + jQ',c.col===1?'SSS 保持原观测':`${n(after[p])} + j(${n(after[p+1])})`]];
    if(reg)facts.push(['分配区间 r0',`${nf(reg.start_r0)}…${nf(reg.end_exclusive_r0-1)}`]);
    if(c.r>=0)facts.push(['边界标记',uncertain[c.r]?'待核验':'未落入分歧掩码']);
    $('resourceFacts').innerHTML=facts.map(([k,v])=>`<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('');
    let message=reg?reg.kind==='first_body'?'固定 Code5 H/P 支持这一段。下方码字卡片可进一步查看。':reg.kind.startsWith('header')?'这是 BCC 编码后的头部资源；下方位图展示译码后的保留位。':reg.kind==='tail'?'尾部按 ±1 二值模型解释，信息含义仍未确认。':'调制与长度是本公开采集的候选解释；高阶位映射和 FEC 尚未确认。':c.col===1?'SSS 是同步 / 信道参考列，不使用载荷 PN 去旋转。':fit.has(c.row)?'FIT 导频参与校准，不混入载荷星座样本。':evaluation.has(c.row)?'EVAL 导频仅用于评价，不用于相位 / 增益拟合。':'当前为未加载 bin，不混入载荷判决。';
    $('resourceMessage').textContent=message;
    $('focusRegion').disabled=c.region<0&&c.col!==1;
    if(state.scope!=='selection')$('selectionHint').textContent=c.r>=0&&uncertain[c.r]?'这个资源落在预测 / 信号边界的分歧区及附近。':'';
}
let currentSelection=[];
function selection(){
    let result=[];const sel=info(state.col,state.bin);
    if(state.scope==='selection'&&state.explicit.length)result=state.explicit.map(r=>coord(r).index);
    else if(state.scope==='region'&&sel.region>=0){const reg=D.regions[sel.region];for(let r=reg.start_r0;r<reg.end_exclusive_r0;r++)result.push(coord(r).index);}
    else if(state.scope==='view'){
        for(let c=state.colLo;c<=state.colHi;c++)for(const row of (c===1?D.loaded_rows0:D.payload_rows0)){const b=D.bins[row];if(b>=state.binLo&&b<=state.binHi)result.push((c-1)*1024+row);}
    }else result=(state.col===1?D.loaded_rows0:D.payload_rows0).map(row=>(state.col-1)*1024+row);
    return result.filter(i=>{const col=1+Math.floor(i/1024),q=qByRow[i%1024],r=col>1&&q>=0?(col-2)*1004+q:-1;return r<0||!state.hidden.has(regionIndex[r]-1);});
}
function drawScatter(canvas,indices,isAfter,limit){
    const{ctx,w,h}=canvasSetup(canvas),side=Math.min(w-65,h-53),l=(w-side)/2+8,t=10;
    const px=x=>l+(x/limit+1)*side/2,py=y=>t+(1-y/limit)*side/2;
    ctx.fillStyle='#fcfdfb';ctx.fillRect(l,t,side,side);ctx.lineWidth=.7;ctx.font='10px Consolas,monospace';ctx.fillStyle='#829081';
    const step=limit<=2?0.5:limit<=4?1:Math.ceil(limit/4);
    for(let v=Math.ceil(-limit/step)*step;v<=limit+1e-7;v+=step){ctx.strokeStyle=Math.abs(v)<1e-7?'#b6c7b6':'#e4eae1';ctx.beginPath();ctx.moveTo(px(v),t);ctx.lineTo(px(v),t+side);ctx.stroke();ctx.beginPath();ctx.moveTo(l,py(v));ctx.lineTo(l+side,py(v));ctx.stroke();ctx.textAlign='center';ctx.fillText(v.toFixed(step<1?1:0),px(v),t+side+16);ctx.textAlign='right';ctx.fillText(v.toFixed(step<1?1:0),l-7,py(v)+3);}
    ctx.strokeStyle='#c9d4c5';ctx.strokeRect(l,t,side,side);ctx.textAlign='center';ctx.fillText('I',l+side/2,h-3);ctx.save();ctx.translate(l-36,t+side/2);ctx.rotate(-Math.PI/2);ctx.fillText('Q',0,0);ctx.restore();
    const stride=Math.max(1,Math.ceil(indices.length/12000)),visible=[];for(let n=0;n<indices.length;n+=stride)visible.push(indices[n]);
    ctx.save();ctx.beginPath();ctx.rect(l,t,side,side);ctx.clip();
    const groups=new Map();
    for(const i of visible){const col=1+Math.floor(i/1024),row=i%1024,c=info(col,D.bins[row]),g=state.normalize?D.gain[col-1]:1;let x,y;
        if(isAfter&&state.decision&&c.r>=0){const r=D.regions[c.region],s=D.alphabets[r.alphabet][symbolIndex[c.r]-1];x=s[0]*(state.normalize?1:D.gain[col-1]);y=s[1]*(state.normalize?1:D.gain[col-1]);}
        else{const a=isAfter&&col>1?after:before;x=a[2*i]/g;y=a[2*i+1]/g;}
        const color=colorFor(c);if(!groups.has(color))groups.set(color,[]);groups.get(color).push([x,y]);}
    for(const[color,points]of groups){ctx.fillStyle=color;ctx.globalAlpha=state.decision&&isAfter?.48:.69;ctx.beginPath();for(const[x,y]of points){ctx.moveTo(px(x)+1.3,py(y));ctx.arc(px(x),py(y),1.3,0,Math.PI*2);}ctx.fill();}
    ctx.globalAlpha=1;
    const multipleColumns=indices.length>0&&Math.floor(indices[0]/1024)!==Math.floor(indices.at(-1)/1024);
    if(isAfter&&state.models&&!state.decision&&(state.normalize||!multipleColumns)){
        const regs=new Set(visible.map(i=>{const col=1+Math.floor(i/1024),q=qByRow[i%1024];return col>1&&q>=0?regionIndex[(col-2)*1004+q]-1:-1;}));
        for(const r of regs){if(r<0)continue;const model=D.alphabets[D.regions[r].alphabet],gain=state.normalize?1:D.gain[state.col-1];ctx.strokeStyle=state.colorMode==='modulation'?modulationColors[D.regions[r].alphabet]:colors[r];ctx.lineWidth=.85;
            for(const[x,y]of model){ctx.beginPath();ctx.arc(px(x*gain),py(y*gain),4,0,Math.PI*2);ctx.stroke();}}
    }
    const c=info(state.col,state.bin);if(indices.includes(c.index)){
        const a=isAfter&&state.col>1?after:before,g=state.normalize?D.gain[state.col-1]:1;
        // In decision view the selected ring follows the displayed ideal point.
        let x=a[2*c.index]/g,y=a[2*c.index+1]/g;
        if(isAfter&&state.decision&&c.r>=0){const s=D.alphabets[D.regions[c.region].alphabet][symbolIndex[c.r]-1];x=s[0]*(state.normalize?1:D.gain[state.col-1]);y=s[1]*(state.normalize?1:D.gain[state.col-1]);}
        ctx.beginPath();ctx.arc(px(x),py(y),5.5,0,Math.PI*2);ctx.strokeStyle='#172c36';ctx.lineWidth=1.5;ctx.stroke();
    }
    ctx.restore();return visible.length;
}
function renderScatter(){
    const indices=selection();currentSelection=indices;let max=1.3,unc=0;const regs=new Set();
    for(const i of indices){const col=1+Math.floor(i/1024),row=i%1024,g=state.normalize?D.gain[col-1]:1,a=col>1?after:before;
        max=Math.max(max,Math.abs(before[2*i]/g),Math.abs(before[2*i+1]/g),Math.abs(a[2*i]/g),Math.abs(a[2*i+1]/g));
        const q=qByRow[row],r=col>1&&q>=0?(col-2)*1004+q:-1;if(r>=0){regs.add(regionIndex[r]-1);unc+=uncertain[r];}}
    const limit=Math.ceil(max*1.12*4)/4,n=drawScatter($('beforeScatter'),indices,false,limit);drawScatter($('afterScatter'),indices,true,limit);
    const scopeText=state.scope==='column'?`OFDM 列 ${state.col}${state.col===1?' · SSS':' · 数据列 '+(state.col-1)}`:state.scope==='region'?'所选分配区域':state.scope==='view'?'当前网格范围':'所选字段 / 编码资源';
    $('scatterDescription').textContent=`${scopeText} · 两图使用相同资源和相同坐标尺度。点击图例可隐藏 / 恢复区域。`;
    $('pointCount').textContent=`绘图 ${nf(n)} / ${nf(indices.length)} 个资源${indices.length>12000?'（确定性抽样）':''} · ${nf(unc)} 个带边界标记`;
    $('scatterLegend').innerHTML=[...regs].sort((a,b)=>a-b).map(r=>`<span><i style="background:${state.colorMode==='modulation'?modulationColors[D.regions[r].alphabet]:colors[r]}"></i>${esc(regionNames[r])}</span>`).join('');
    $('afterTitle').textContent=state.col===1&&state.scope==='column'?'SSS 同一观测':state.decision?'条件几何判决':'去 PN 后';
    $('afterBadge').textContent=state.decision?'点编号尚未确认发射位映射':state.col===1&&state.scope==='column'?'不应用载荷 PN 去旋转':'可逆四相位参考去除';
    const multipleColumns=indices.length>0&&Math.floor(indices[0]/1024)!==Math.floor(indices.at(-1)/1024);
    $('afterNote').textContent=state.decision?'理想点整齐来自最近点判决；原接收观测仍保留，可切回右图真实接收点。':state.col===1&&state.scope==='column'?'SSS 是同步参考列，两图展示相同观测。':!state.normalize&&multipleColumns?'不同列的导频增益不同；跨列且未归一化时不叠加单一幅度的理想参考。':'只去掉固定参考相位，模长不变；空心圈是候选理想点。';
}
function renderLegend(){
    $('mapLegend').innerHTML=D.regions.map((r,i)=>`<button type="button" class="${state.hidden.has(i)?'dim':''}" data-region-toggle="${i}" aria-pressed="${!state.hidden.has(i)}"><i style="background:${state.colorMode==='modulation'?modulationColors[r.alphabet]:colors[i]}"></i>${esc(regionNames[i])}</button>`).join('')+
        '<span><i style="background:#39afb7"></i>FIT导频</span><span><i style="background:#77a9d1"></i>EVAL导频</span><span><i style="background:#e0e5de"></i>未加载</span><span>▨ 边界不确定</span>'+
        (state.colorMode==='header'?Object.entries(fieldNames).map(([key,name])=>`<span><i style="background:${fieldColors[key]}"></i>${esc(name)}</span>`).join(''):'');
}
function renderHeader(){
    const h=D.headers[state.header],N=h.block_count;
    document.querySelectorAll('[data-header]').forEach(b=>b.classList.toggle('active',+b.dataset.header===state.header));
    $('headerWords').textContent=h.words_hex.join(' · ');$('headerCoordinate').textContent=`r0 [${nf(h.start_r0)}, ${nf(h.end_r0+1)}) · ${114*N} 编码资源`;
    let html='';
    for(let word=0;word<N;word++){
        html+=`<div class="bit-row"><span class="word-label">W${word}</span>`;
        for(let j=0;j<32;j++){const b=word*32+j,f=bitField(h,b);html+=`<button class="bit-cell ${state.selectedBit===b?'selected':''}" style="--field:${fieldColors[f.type]}" data-bit="${b}" title="保留位 ${b}：${esc(f.name)}，值 ${h.retained_bits[b]}" aria-label="保留位${b}，${esc(f.name)}，值${h.retained_bits[b]}"><small>${j}</small>${h.retained_bits[b]}</button>`;}
        html+='</div>';
    }
    $('bitGrid').innerHTML=html;
    $('crcStatus').textContent=h.crc_pass?'通过 ✓':'未通过';$('crcObserved').textContent=hex(h.crc_observed);$('crcPredicted').textContent=hex(h.crc_predicted);
    const facts=[['BCC块数 N',N],['描述项数 D',h.fields.entry_count],['CRC 输入长度',`${h.retained_bits.length-8} 位`],['归零状态 / 尾位',h.termination_pass?'通过':'未通过'],['硬位重编码差异',`${h.hard_changes} 位`],['CRC 参数','0x4D · 初值 FF · MSB']];
    $('headerChecks').innerHTML=facts.map(([k,v])=>`<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('');
    $('codedGrid').innerHTML=h.blocks.map((block,bi)=>`<div class="coded-row"><span class="mono">B${bi+1}</span>`+block.hard_observed.map((v,k)=>{const inp=Math.floor(k/3),bit=inp<32?bi*32+inp:null,f=bit===null?{type:'tail',name:'归零尾'}:bitField(h,bit),r=h.start_r0+bi*114+k;return`<button class="coded-cell ${v?'one':''}" style="--field:${fieldColors[f.type]}" data-coded="${r}" title="r0=${r}；编码位=${v}；${esc(f.name)}" aria-label="编码资源${r}，值${v}"></button>`;}).join('')+'</div>').join('');
    let entries=h.fields.entries;if(!Array.isArray(entries))entries=[entries];
    const bodies=D.regions.map((r,i)=>({...r,region:i})).filter(r=>r.kind===(state.header===0?'first_body':'second_body'));
    $('allocationRows').innerHTML=entries.map((e,i)=>{const r=bodies[i];return`<tr><td>${i+1}</td><td><span class="mcs-pill">${e.index8}</span></td><td><b>${e.quantity}</b> 单位</td><td><i class="swatch" style="background:${colors[r.region]}"></i> ${esc(r.alphabet==='32cross'?'交叉32点':r.alphabet)}</td><td>${nf(r.resources_per_unit)}</td><td class="length-formula">${e.quantity} × ${nf(r.resources_per_unit)} = ${nf(r.resource_count)}</td><td class="mono">[${nf(r.start_r0)}, ${nf(r.end_exclusive_r0)})</td><td><button data-allocation="${r.region}">定位 ↗</button></td></tr>`;}).join('');
    renderBitDetail(h);
}
function renderBitDetail(h){
    const b=state.selectedBit;
    if(b===null||b<0||b>=h.retained_bits.length){$('bitDetail').textContent='点击一个位，查看其含义与对应的3个BCC输出资源。';return;}
    const block=Math.floor(b/32),input=b%32,first=h.start_r0+block*114+input*3,field=bitField(h,b);
    const group=state.scope==='selection'&&state.explicit.length===24&&field.type==='crc'&&state.explicit[0]===h.start_r0+(h.block_count-1)*114+72;
    $('bitDetail').innerHTML=group?`<b>PDU头 ${state.header+1} · CRC8 = ${hex(h.crc_observed)}</b><br>保留位 ${h.retained_bits.length-8}…${h.retained_bits.length-1} 的8个输入时刻，对应24个BCC输出：r0=${state.explicit[0]}…${state.explicit.at(-1)}；归零尾另计。`:
        `<b>PDU头 ${state.header+1} · 保留位 ${b} = ${h.retained_bits[b]}</b> · ${esc(field.name)}<br>第${block+1}块输入时刻${input}，对应输出 r0=${first} / ${first+1} / ${first+2}。每个输出也依赖前6位状态。`;
    $('bitDetail').insertAdjacentHTML('beforeend','<button id="goToSelected">带到上方网格 ↑</button>');
    $('goToSelected').onclick=()=>$('resourceSection').scrollIntoView({behavior:'smooth',block:'start'});
}
function selectBit(b){
    const h=D.headers[state.header];state.selectedBit=b;const block=Math.floor(b/32),input=b%32,first=h.start_r0+block*114+input*3,field=bitField(h,b);
    const list=[first,first+1,first+2];focusList(list,`保留位 ${b} 的输入时刻 → 三个BCC输出资源 ${list.join('、')}`);
}
function selectRegion(i){
    const r=D.regions[i],c=coord(r.start_r0);state.col=c.col;state.bin=c.bin;state.scope='region';state.explicit=[];state.selectedBit=null;
    state.colLo=Math.max(2,r.start_column-1);state.colHi=Math.min(301,r.last_column+1);state.binLo=-512;state.binHi=511;
    state.colorMode='region';state.hidden.delete(i);rasterDirty=true;render();
}
function renderBoundary(){
    const p=D.boundary.predicted_r0[0],s=D.boundary.signal_fit_r0[0],pc=coord(p),sc=coord(s),left=Math.min(pc.q,sc.q),right=Math.max(pc.q,sc.q);
    $('boundaryDiagram').innerHTML=[['头部推算',pc.q],['信号估计',sc.q]].map(([label,q])=>`<div class="boundary-row"><span>${label}</span><div class="boundary-bar"><div class="left16" style="width:${q/1004*100}%"></div><div class="dispute" style="left:${left/1004*100}%;width:${(right-left)/1004*100}%"></div></div></div>`).join('')+'<div class="boundary-labels"><span>q0 = 0</span><span>16QAM / 32点</span><span>1003</span></div>';
    $('boundaryFacts').innerHTML=`<div>头部预测<strong>列 ${pc.col} / q${pc.q}</strong><span class="mono">r0 ${p}</span></div><div>信号估计<strong>列 ${sc.col} / q${sc.q}</strong><span class="mono">r0 ${s}</span></div>`;
    $('inspectBoundary').onclick=()=>{state.col=pc.col;state.bin=(pc.bin+sc.bin)>>1;state.colLo=pc.col;state.colHi=pc.col;state.binLo=Math.max(-512,Math.min(pc.bin,sc.bin)-35);state.binHi=Math.min(511,Math.max(pc.bin,sc.bin)+35);state.scope='column';state.colorMode='region';rasterDirty=true;render();$('resourceSection').scrollIntoView({behavior:'smooth'});};
}
function renderCode5(){
    const c=D.code5;$('code5Status').textContent=`${c.words.filter(w=>w.converged).length}/${c.word_count} 字收敛`;
    $('code5Words').innerHTML=c.words.map((w,i)=>`<button class="code5-word" data-word="${i}"><strong>码字 ${i+1}<span>校验 ${w.initial_failed_checks} → ${w.final_failed_checks}</span></strong><small>硬位修改 ${w.decoder_hard_changes} · 重编码 ${w.reencode_matches_decoded_word?'一致':'不一致'}</small><small>奇偶重调制 NMSE ${w.parity_remodulation_nmse.toFixed(4)}</small><span class="mono">r0 ${w.start_r0}…${w.end_r0}</span></button>`).join('');
}
function render(){
    $('scope').value=state.scope;$('normalize').checked=state.normalize;$('showModels').checked=state.models;$('decisionView').value=state.decision?'decided':'observed';
    $('showSSS').checked=state.includeSSS;$('showUncertain').checked=state.showUncertain;$('colorMode').value=state.colorMode;
    renderLegend();drawMap();renderInspector();renderScatter();renderHeader();
}
$('resourceMap').addEventListener('pointerdown',e=>{const p=mapPosition(e);if(!p)return;drag={...p,lastX:p.x,lastY:p.y,moved:false};$('resourceMap').setPointerCapture(e.pointerId);$('mapTooltip').hidden=true;});
$('resourceMap').addEventListener('pointermove',e=>{const p=mapPosition(e);if(!p)return;if(drag){drag.lastX=p.x;drag.lastY=p.y;drag.moved=Math.hypot(p.x-drag.x,p.y-drag.y)>5;drawMap();return;}
    const c=info(p.col,p.bin);$('mapTooltip').textContent=`列 ${p.col} / bin ${p.bin} · ${c.kind}${c.r>=0?' · r0 '+c.r:''}`;
    $('mapTooltip').style.left=Math.min(p.x+12,$('resourceMap').clientWidth-245)+'px';$('mapTooltip').style.top=Math.max(2,p.y-42)+'px';$('mapTooltip').hidden=false;
});
$('resourceMap').addEventListener('pointerup',e=>{if(!drag)return;const p=mapPosition(e),d=drag;drag=null;if(!p){drawMap();return;}if(d.moved){state.colLo=Math.min(d.col,p.col);state.colHi=Math.max(d.col,p.col);state.binLo=Math.min(d.bin,p.bin);state.binHi=Math.max(d.bin,p.bin);drawMap();if(state.scope==='view')renderScatter();}else select(p.col,p.bin);});
$('resourceMap').addEventListener('pointercancel',()=>{drag=null;drawMap();});$('resourceMap').addEventListener('pointerleave',()=>$('mapTooltip').hidden=true);
$('resourceMap').addEventListener('dblclick',()=>preset('full'));
$('resourceMap').addEventListener('keydown',e=>{if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();select(state.col+(e.key==='ArrowRight'?1:-1),state.bin);}});
$('resourceMap').addEventListener('wheel',e=>{if(!e.ctrlKey)return;e.preventDefault();const p=mapPosition(e);if(!p)return;const span=int((state.colHi-state.colLo+1)*(e.deltaY>0?1.5:.67),1,301),start=int(p.col-span/2,state.includeSSS?1:2,Math.max(2,302-span));state.colLo=start;state.colHi=Math.min(301,start+span-1);drawMap();if(state.scope==='view')renderScatter();},{passive:false});
$('presets').addEventListener('click',e=>{const b=e.target.closest('[data-preset]');if(b)preset(b.dataset.preset);});
$('mapLegend').addEventListener('click',e=>{const b=e.target.closest('[data-region-toggle]');if(!b)return;const r=+b.dataset.regionToggle;state.hidden.has(r)?state.hidden.delete(r):state.hidden.add(r);rasterDirty=true;render();});
$('headerTabs').addEventListener('click',e=>{const b=e.target.closest('[data-header]');if(b){state.header=+b.dataset.header;state.selectedBit=null;renderHeader();$('bitDetail').textContent='点击一个位，查看其含义与对应的3个BCC输出资源。';}});
$('bitGrid').addEventListener('click',e=>{const b=e.target.closest('[data-bit]');if(b)selectBit(+b.dataset.bit);});
$('codedGrid').addEventListener('click',e=>{const b=e.target.closest('[data-coded]');if(b){focusList([+b.dataset.coded],'单个BCC接收编码资源');}});
$('allocationRows').addEventListener('click',e=>{const b=e.target.closest('[data-allocation]');if(b){selectRegion(+b.dataset.allocation);$('resourceSection').scrollIntoView({behavior:'smooth'});toast('已定位分配区域；星座同步切换为该区域。');}});
$('code5Words').addEventListener('click',e=>{const b=e.target.closest('[data-word]');if(b){const w=D.code5.words[+b.dataset.word];focusList(Array.from({length:2048},(_,i)=>w.start_r0+i),`Code5 码字 ${+b.dataset.word+1} 的2048个接收资源`);}});
$('locateCRC').onclick=()=>{const h=D.headers[state.header],start=h.start_r0+(h.block_count-1)*114+72;state.selectedBit=h.retained_bits.length-8;focusList(Array.from({length:24},(_,i)=>start+i),'CRC8 的8个输入时刻 → 24个BCC输出资源；归零尾另计。');toast('CRC对应24个BCC输出资源，已在网格和星座中联动定位。');};
$('focusRegion').onclick=()=>{const c=info(state.col,state.bin);if(c.region>=0)selectRegion(c.region);else{state.scope='column';render();}};
$('previousCol').onclick=()=>select(state.col-1,state.bin);$('nextCol').onclick=()=>select(state.col+1,state.bin);$('selectedCol').onchange=e=>select(e.target.value,state.bin);
$('scope').onchange=e=>{state.scope=e.target.value;if(state.scope==='selection'&&!state.explicit.length){const c=info(state.col,state.bin);if(c.r>=0)state.explicit=[c.r];else state.scope='column';}render();};
$('normalize').onchange=e=>{state.normalize=e.target.checked;renderScatter();};$('showModels').onchange=e=>{state.models=e.target.checked;renderScatter();};$('decisionView').onchange=e=>{state.decision=e.target.value==='decided';renderScatter();};
$('showSSS').onchange=e=>{state.includeSSS=e.target.checked;if(!state.includeSSS&&state.colLo===1)state.colLo=2;if(state.colHi<state.colLo)state.colHi=state.colLo;drawMap();};
$('colorMode').onchange=e=>{state.colorMode=e.target.value;rasterDirty=true;render();};$('showUncertain').onchange=e=>{state.showUncertain=e.target.checked;rasterDirty=true;drawMap();};
$('resetView').onclick=()=>preset('full');$('toggleRange').onclick=()=>$('rangeControls').hidden=!$('rangeControls').hidden;
$('applyRange').onclick=()=>{const a=int($('colLo').value,1,301),b=int($('colHi').value,1,301),x=int($('binLo').value,-512,511),y=int($('binHi').value,-512,511);state.colLo=Math.min(a,b);state.colHi=Math.max(a,b);state.binLo=Math.min(x,y);state.binHi=Math.max(x,y);state.includeSSS=state.colLo===1;render();};
document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>{const a=b.dataset.action;if(a==='pss')toast('PSS位于时域同步段，不在本次1024×301频域检查点中。SSS可直接点击查看。');else preset(a==='sss'?'sss':'full');});
$('downloadMeta').onclick=()=>download('frame1-summary.json',JSON.stringify({source:D.source,headers:D.headers.map(h=>({words_hex:h.words_hex,crc_pass:h.crc_pass,crc_observed:h.crc_observed,fields:h.fields})),regions:D.regions,boundary:D.boundary,code5:D.code5},null,2));
$('downloadCSV').onclick=()=>{let text='ofdm_column,fft_row_1based,bin,q0,r0,region,mcs_index,before_I,before_Q,after_I,after_Q,boundary_uncertain,geometric_symbol_index\n';
    for(const i of currentSelection){const col=1+Math.floor(i/1024),c=info(col,D.bins[i%1024]),reg=c.region>=0?D.regions[c.region]:null,a=col>1?after:before;text+=[col,c.row+1,c.bin,c.r>=0?c.q:'',c.r>=0?c.r:'',c.kind,reg?.id>=0?reg.id:'',before[2*i],before[2*i+1],a[2*i],a[2*i+1],c.r>=0?uncertain[c.r]:'',c.r>=0?symbolIndex[c.r]:''].join(',')+'\n';}
    download('frame1-selected-resources.csv','\uFEFF'+text,'text/csv;charset=utf-8');toast(`已导出${nf(currentSelection.length)}个资源，CSV为未作显示增益归一化的原坐标。`);};
$('sourceInfo').textContent=JSON.stringify(D.source,null,2);
renderBoundary();renderCode5();render();
let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{drawMap();renderScatter();},80);});
// Read-only data plus controlled actions, also used by browser regression checks.
window.FrameExplorer={getState:()=>({...state,hidden:[...state.hidden]}),getData:()=>D,getSelection:()=>currentSelection.slice(),
    info,preset,select,selectBit,selectRegion,header:i=>{state.header=i;state.selectedBit=null;renderHeader();},focusList,
    sourcePoint:(i,post=false)=>{const a=post?after:before;return[a[2*i],a[2*i+1]];},ready:true};
})();
