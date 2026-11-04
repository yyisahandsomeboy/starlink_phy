function files = plotFrame(result,out,opt)
%PLOTFRAME 三幅教学图分别解释旋转、头部编码和独立奇偶约束。
if nargin<3,opt=slproto.defaultOptions();end
files={};if ~opt.make_plots,return;end
folder=fullfile(out,'figures');if ~isfolder(folder),mkdir(folder);end
visible='off';if opt.show_figures,visible='on';end
c=slproto.coordinates();r=result;notes=struct('purpose','','source','','formula','','observe','','fact','','limit','');
f=figure('Visible',visible,'Color','w','Position',[30 30 1450 1000]);t=tiledlayout(f,2,2,'TileSpacing','compact');
first=r.calibrated_grid(c.payload_rows,2:301);after=r.payload_stream;n=228;selection=first(1:n);
limit=1.08*max(abs([selection(:);after(1:n)]));
ax=nexttile(t);scatter(ax,real(first(1:n)),imag(first(1:n)),12,'.');axis(ax,'equal');xlim(ax,[-limit limit]);ylim(ax,[-limit limit]);grid(ax,'on');xlabel(ax,'I / 接收机幅度');ylabel(ax,'Q / 接收机幅度');title(ax,'同一228个实际头部资源：去PN前');
ax=nexttile(t);scatter(ax,real(after(1:n)),imag(after(1:n)),12,'.');axis(ax,'equal');xlim(ax,[-limit limit]);ylim(ax,[-limit limit]);grid(ax,'on');xlabel(ax,'I / 接收机幅度');ylabel(ax,'Q / 接收机幅度');title(ax,'去PN后：BPSK两点不是把观测替换成理想点');
ax=nexttile(t);k=1:24;stem(ax,k,angle(r.reference_grid(c.payload_rows(k),2)),'filled');grid(ax,'on');xlabel(ax,'slot2的非导频序号q+1');ylabel(ax,'已知参考相位 / rad');title(ax,'少量资源的固定四相位参考；时钟仍经过导频');
ax=nexttile(t);axis(ax,'off');text(ax,0,1,sprintf(['实轴能量：前%.4f → 后%.4f\n错误参考对照：%.4f\n留出导频EVM：%.4f%%\nPN往返相对误差：%.3g\n状态锚点：名义SSS首载波\n物理burst复位状态仍未知'],r.axis_energy_before,r.axis_energy_after,r.wrong_reference_axis_energy,100*r.calibration.heldout_pilot_evm,r.rotation_roundtrip_relative_error),'VerticalAlignment','top','FontSize',12);
sgtitle(t,'16 去PN：四相位参考 × 二值符号 → 去参考后的两点观测');
notes=contract('解释旧QPSK→BPSK记忆对应的可逆去旋转','calibrated_grid、reference_grid及payload_stream','z_after=z_before*conj(R)，|R|=1','只比较相同资源；导频FIT与EVAL分离',sprintf('模长不变；实轴能量%.4f',r.axis_energy_after),'两点形状不能证明BCC/CRC、业务内容或PN物理复位种子');finish(f,'16_pn_bpsk.png',notes);

f=figure('Visible',visible,'Color','w','Position',[30 30 1450 1000]);t=tiledlayout(f,2,2,'TileSpacing','compact');h=r.headers.first;
ax=nexttile(t);b=h.blocks(1);stem(ax,0:113,double(b.hard_observed),'.','DisplayName','接收硬位');hold(ax,'on');plot(ax,0:113,double(b.reencoded),'o','MarkerSize',3,'DisplayName','Viterbi后重编码');ylim(ax,[-.2 1.2]);grid(ax,'on');legend(ax);xlabel(ax,'114位编码资源内的零基编号');ylabel(ax,'条件编码位');title(ax,sprintf('第一块重编码差异%d位',b.hard_changes));
ax=nexttile(t);imagesc(ax,0:37,1:numel(h.blocks),double(reshape([h.blocks.inputs],38,[]).'));colorbar(ax);xline(ax,31.5,'r--');xlabel(ax,'输入位：0..31信息字，32..37归零尾');ylabel(ax,'独立编码块');title(ax,'每块32+6输入 → 114输出；CRC在去尾后的整组上检查');
ax=nexttile(t);axis(ax,'off');lines={sprintf('BCC八进制(155,123,137)，K=7，rate=1/3'),sprintf('第一头部CRC：%02X / 接收%02X；通过=%d',h.crc_predicted,h.crc_observed,h.crc_pass),sprintf('第一头部字：%s',strjoin(h.words_hex,' ')),sprintf('第二头部CRC候选数=%d；扫描候选=%d',numel(r.headers.second_candidates),r.headers.scan_prefix_candidates)};
if r.headers.second_unique,lines{end+1}=sprintf('第二头部r0=%d；首分配长度一致=%d',r.headers.signal_found_second_start_r0,r.headers.first_body_length_agrees);else,lines{end+1}='第二头部未唯一验证；保留失败/歧义状态';end
text(ax,0,1,strjoin(lines,newline),'VerticalAlignment','top','FontSize',11,'Interpreter','none');
ax=nexttile(t);entries=h.fields.entries;if ~isempty(entries),bar(ax,[entries.quantity]);xlabel(ax,'条件描述项编号');ylabel(ax,'12位候选数量');title(ax,sprintf('首项条件格式编号=%d；19/20位布局均保留',entries(1).index8));else,axis(ax,'off');end
sgtitle(t,'17 从BPSK编码位到BCC、归零尾、组CRC和条件资源字段');
notes=contract('逐层验证编码关系，不靠常量位或星座外观推断成功','payload_stream、headers.blocks与CRC','38×3=114；(32N−8)位做CRC8(0x4D,FF)','看重编码、尾状态、CRC及第二头部是否同时支持',sprintf('第一组CRC=%d；硬位改变%d',h.crc_pass,h.hard_changes),'CRC不认证发射方；布局和MCS语义有条件；头部解出不等于业务载荷解码');finish(f,'17_bcc_crc.png',notes);

f=figure('Visible',visible,'Color','w','Position',[30 30 1450 1000]);t=tiledlayout(f,2,2,'TileSpacing','compact');code=r.code5;
if code.available
    words=code.words;ax=nexttile(t);values=[[words.initial_failed_checks]' [words.final_failed_checks]'];bar(ax,values);markZeros(ax,values);legend(ax,{'软译码前','译码后'});xlabel(ax,'2048位码字编号');ylabel(ax,'非零校验方程数');title(ax,'固定稀疏H的校验结果；0以数字标出');grid(ax,'on');
    ax=nexttile(t);values=[[words.raw_parity_prediction_errors]' [words.decoder_hard_changes]'];bar(ax,values);markZeros(ax,values);legend(ax,{'原信息位预测奇偶的差异','译码改变硬位'});xlabel(ax,'码字编号');ylabel(ax,'位数');title(ax,'保留实际错误和修改，不把收敛当业务正确');grid(ax,'on');
    ax=nexttile(t);semilogy(ax,1:numel(words),[words.parity_remodulation_nmse],'o',1:numel(words),[words.parity_flip_control_nmse],'x');xticks(ax,1:numel(words));legend(ax,{'固定模型预测','翻转奇偶位对照'});xlabel(ax,'码字编号');ylabel(ax,'同一奇偶资源NMSE');title(ax,'输入资源固定，仅比较预测的奇偶符号');grid(ax,'on');
    ax=nexttile(t);axis(ax,'off');text(ax,0,1,sprintf(['Code5条件模型：N=2048，K=1024，QC128\nH秩=%d；GH^T=0：%d\n逐字译码收敛=%s\n重编码等于译码字=%s\n信息位只导出为不透明编码器输入\n其余未识别格式/完整明文仍未知'],code.H_rank,code.GH_orthogonal,mat2str([words.converged]),mat2str([words.reencode_matches_decoded_word])),'VerticalAlignment','top','FontSize',12);
else,ax=nexttile(t);axis(ax,'off');text(ax,.1,.5,code.reason);end
sgtitle(t,'18 Code5：冻结QC关系 → 稀疏校验 → 软译码 → 奇偶重调制对照');
notes=contract('验证新增FEC关系及纠错；区分编码器输入和应用明文','固定code5模型、第一头部支持的实际资源','Hc^T=0；p=uP；LLR=4Re(z)/sigma²；normalized min-sum eta=0.8','看真实非零校验、重编码和翻转奇偶对照',sprintf('Code5可用=%d；码字数=%d',code.available,code.word_count),'同一旧采集条件模型；无业务真值；未识别格式不套用Code5');finish(f,'18_code5_fec.png',notes);
    function finish(fig,name,txt)
        slrx.viz.teachingNotes(fig,txt);file=fullfile(folder,name);exportgraphics(fig,file,'Resolution',120);files{end+1}=['figures/' name];if ~opt.show_figures,close(fig);end
    end
end
function markZeros(ax,values)
xticks(ax,1:size(values,1));ylim(ax,[0 max(1,1.25*max(values,[],'all'))]);
for j=1:size(values,1)
    if all(values(j,:)==0),text(ax,j,.04,'0 / 0','HorizontalAlignment','center','FontSize',11,'HandleVisibility','off');end
end
end
function n=contract(p,s,f,o,v,l)
% 共享旧教学六项说明结构，兼容统一页脚。
n=struct('purpose',p,'data_source',s,'calculation',f,'focus',o,'current_result',v,'limitations',l);
end
