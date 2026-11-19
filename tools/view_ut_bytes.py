"""Export a UT archive frame as an offline hex viewer and a complete plain-text dump."""
import argparse
import base64
import json
from pathlib import Path

import numpy as np


def export(frame, archive_dir, output_dir):
    source = archive_dir / f"{frame:04}.npz"
    metadata = json.loads(source.with_suffix(".json").read_text(encoding="utf-8-sig"))
    allocations = []
    dump = [f"UT frame {frame} | decoded information bytes, including headers and padding",
            "Offsets are decimal, start at zero in each allocation; ?? = unverified codeword."]
    with np.load(source, allow_pickle=False) as archive:
        for i, info in enumerate(metadata["allocations"]):
            words = archive[f"part_{i}"]
            valid = [bool(v) for v in archive[f"valid_{i}"]]
            width = info["information_bytes_per_word"]
            assert words.shape == (info["quantity"], width) and words.dtype == np.uint8
            assert len(valid) == len(words) and sum(valid) == info["valid_words"]
            data = words.tobytes(order="C")
            allocations.append(dict(mcs=info["mcs"], size=len(data), width=width,
                                    valid=valid, bytes=base64.b64encode(data).decode("ascii")))
            dump.extend(("", f"part_{i} | MCS {info['mcs']} | {len(data)} bytes | valid words {sum(valid)}/{len(valid)}",
                         "  offset   +00 +01 +02 +03 +04 +05 +06 +07 +08 +09 +0A +0B +0C +0D +0E +0F"))
            for pos in range(0,len(data),16):
                cells = [f"{v:02X}" if valid[(pos+j)//width] else "??" for j,v in enumerate(data[pos:pos+16])]
                dump.append(f"{pos:8}   " + "  ".join(cells))
    total = sum(a["size"] for a in allocations)
    dump.insert(1, f"All allocations: {total:,} bytes")
    stem = f"ut_{frame:04}_bytes"
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir/f"{stem}.txt").write_text("\n".join(dump)+"\n", encoding="utf-8")
    data = dict(frame=frame,total=total,parts=allocations)
    html = TEMPLATE.replace("__FRAME__", str(frame)).replace("__DATA__", json.dumps(data,separators=(",",":")))
    (output_dir/f"{stem}.html").write_text(html,encoding="utf-8")
    print(f"{stem} | {len(allocations)} allocations | {total:,} bytes")


TEMPLATE = """<!DOCTYPE html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>UT 第 __FRAME__ 帧 · 字节查看器</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6f7;color:#132d39;font:16px "Source Sans 3","Microsoft YaHei",sans-serif}
main{max-width:1040px;margin:32px auto;padding:0 20px}h1{font-size:30px;margin:0 0 8px}p{line-height:1.55}
section{background:white;border:1px solid #cbd8dd;border-radius:8px;padding:18px;margin-top:16px}
form,nav,#jumps{display:flex;align-items:center;flex-wrap:wrap;gap:10px}label{display:flex;align-items:center;gap:6px}
button,select,input{font:inherit;padding:5px 8px;border:1px solid #a4b6bd;border-radius:4px;background:white;color:#173b48}
button{cursor:pointer}button:disabled{opacity:.45;cursor:default}button:hover:not(:disabled),button:focus-visible{border-color:#08796e}
input{width:112px}#jumps{margin-top:10px}#jumps:empty{display:none}#msg{color:#9c3617}
.scroll{overflow:auto}table{width:100%;border-collapse:collapse;font:16px Consolas,"Courier New",monospace;white-space:nowrap}
th,td{padding:4px 5px;text-align:center}thead th{color:#4d6772;background:#eaf1f3}tbody th{text-align:right;color:#506c76;padding-right:18px}
tbody tr:nth-child(even){background:#f5f8f9}td[data-pos]{cursor:pointer}td[data-pos]:hover{background:#cee8e2}
td.active{background:#006b60!important;color:white;font-weight:bold}nav{justify-content:space-between;margin-top:14px}
#selection{font-weight:600;color:#00645e}#summary,#meta{color:#48626e}
</style><main><h1>UT 第 __FRAME__ 帧</h1><p id="summary"></p><section>
<form id="go"><label>物理分配 <select id="part"></select></label>
<label>字节偏移 <input id="offset" aria-label="分配内字节偏移" placeholder="52 或 0x34"></label><button>跳转</button>
<span id="msg" role="status"></span></form><div id="jumps"></div><p id="meta"></p>
<div class="scroll"><table><thead id="cols"></thead><tbody id="grid"></tbody></table></div>
<nav><button id="prev">上一页</button><span id="page"></span><button id="next">下一页</button></nav>
<p id="selection" aria-live="polite"></p></section>
<p>左列是当前分配内的十进制偏移，顶行是十六进制列偏移。每格一个字节，未通过码字验证的位置显示 ??。</p>
</main><script id="data" type="application/json">__DATA__</script><script>
const data=JSON.parse(document.querySelector('#data').textContent);
const el=id=>document.getElementById(id);
const decoded=data.parts.map(p=>Uint8Array.from(atob(p.bytes),c=>c.charCodeAt(0)));
const hex=(v,n=2)=>v.toString(16).toUpperCase().padStart(n,'0');
let i=0,pos=0;const size=256;
el('summary').textContent=data.parts.length+' 个物理分配 · 共 '+data.total.toLocaleString()+' 个解调译码后的信息字节（含头部和填充）';
data.parts.forEach((p,i)=>el('part').add(new Option('分配 '+i+' · '+p.size.toLocaleString()+' 字节',i)));
el('cols').innerHTML='<tr><th>偏移</th>'+Array.from({length:16},(_,j)=>'<th>+'+hex(j)+'</th>').join('')+'</tr>';
function show(a,x){
  i=a;pos=x;const p=data.parts[i],buf=decoded[i],start=Math.floor(pos/size)*size,stop=Math.min(start+size,p.size);
  const value=k=>p.valid[Math.floor(k/p.width)]?hex(buf[k]):'??';
  el('msg').textContent='';el('part').value=i;el('offset').value=pos;
  el('meta').textContent='part_'+i+' · MCS '+p.mcs+' · '+p.valid.filter(Boolean).length+'/'+p.valid.length+' 个码字通过验证';
  let rows='';
  for(let k=start;k<stop;k+=16){rows+='<tr><th>'+k+'</th>';for(let j=k;j<k+16;j++){
    rows+=j<stop?'<td data-pos="'+j+'" class="'+(j===pos?'active':'')+'">'+value(j)+'</td>':'<td></td>';
  }rows+='</tr>'}el('grid').innerHTML=rows;
  el('selection').textContent='分配 '+i+' · 偏移 '+pos+'（0x'+hex(pos)+'） · 字节 '+value(pos);
  el('page').textContent=start+'–'+(stop-1)+' / '+p.size+' 字节';el('prev').disabled=start===0;el('next').disabled=stop===p.size;
}
el('part').onchange=e=>show(Number(e.target.value),0);
el('grid').onclick=e=>{if(e.target.dataset.pos!==undefined)show(i,Number(e.target.dataset.pos))};
el('go').onsubmit=e=>{e.preventDefault();const s=el('offset').value.trim(),v=Number(s);
  if(!/^(?:[0-9]+|0x[0-9a-f]+)$/i.test(s)||!Number.isSafeInteger(v)||v>=data.parts[i].size){
    el('msg').textContent='请输入 0 到 '+(data.parts[i].size-1)+' 的分配内偏移';return}show(i,v)};
el('prev').onclick=()=>show(i,Math.floor(pos/size)*size-size);
el('next').onclick=()=>show(i,Math.floor(pos/size)*size+size);
if(data.frame===1002){for(const [at,name] of [[52,'7EA · B8 头'],[989,'完整记录 · 9540'],[2507,'跨帧记录 · 94BD']]){
  const b=document.createElement('button');b.textContent=name+'  @ '+at;b.onclick=()=>show(1,at);el('jumps').appendChild(b)}}
show(data.frame===1002?1:0,data.frame===1002?52:0);
</script></html>"""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frame", type=int)
    parser.add_argument("--archive", type=Path, required=True, help="directory with decoded frame NPZ and JSON files")
    parser.add_argument("--output-dir", type=Path, required=True, help="directory for the generated local views")
    args = parser.parse_args()
    export(args.frame, args.archive, args.output_dir)
