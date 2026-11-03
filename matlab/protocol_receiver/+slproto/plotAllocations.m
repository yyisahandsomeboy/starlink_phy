function files = plotAllocations(result,out,opt)
%PLOTALLOCATIONS 两幅新增图；使用真实接收点及离散资源坐标。
files={};if ~opt.make_plots||~isfield(result,'allocations')||~result.allocations.available,return;end
a=result.allocations;folder=fullfile(out,'figures');if ~isfolder(folder),mkdir(folder);end
visible='off';if opt.show_figures,visible='on';end
f=figure('Visible',visible,'Color','w','Position',[30 30 1450 1050]);t=tiledlayout(f,2,2,'TileSpacing','compact');
ax=nexttile(t);imagesc(ax,2:301,0:1003,reshape(a.region_index,1004,300));axis(ax,'xy');colorbar(ax);xlabel(ax,'OFDM列号（第1列SSS）');ylabel(ax,'非导频载荷序号q0');title(ax,'头部条件分配：一列内部允许出现不同区域');
r=a.plan.regions;body=r(strcmp({r.kind},'second_body'));
ax=nexttile(t);bar(ax,1:numel(body),[body.resource_count]);xticks(ax,1:numel(body));xticklabels(ax,compose('ID%d',[body.id]));ylabel(ax,'quantity × 每单位资源数');xlabel(ax,'第二头部描述项');grid(ax,'on');title(ax,'数量不是OFDM列数；同字母表的不同ID仍分段');
ax=nexttile(t);if a.boundaries.available
    d=a.boundaries.offset_resources;bar(ax,1:2,d);xticks(ax,1:2);xticklabels(ax,{'16→32','32→二值尾'});ylabel(ax,'信号拟合位置 − 头部模型位置 / 资源');grid(ax,'on');title(ax,'全域信号拟合未用数量限制搜索；保留偏差');
else,axis(ax,'off');text(ax,.05,.5,'此布局不能进行16→32→尾部边界检验');end
ax=nexttile(t);axis(ax,'off');text(ax,0,1,sprintf(['候选表：%s\n分配完整=%d；未解析资源=%d\n边界不确定资源=%d\n1004资源/列，r0=1004(col−2)+q0\n3277=ceil(16384/5)：每单位重新装箱\n高阶格式FEC、发射位映射仍未确认'],a.plan.profile,a.complete,a.unresolved_resource_count,a.uncertain_resource_count),'VerticalAlignment','top','FontSize',11,'Interpreter','none');
sgtitle(t,'19 从已解头部到资源分配：显式候选表、列内边界和反例');
notes=note('把MCS数量换算成资源位置，解释混合OFDM列','headers、allocation candidate JSON及固定PN后的payload_stream','L=C×ceil(Nc/b)，r0零基、右端开区间','比较头部预测与未受长度约束的信号边界',sprintf('完整条件分配=%d；不确定资源%d',a.complete,a.uncertain_resource_count),'候选表仅适用本公开采集；同字母表内部边界不能由点云证明；不是完整协议破解');
finish(f,'19_resource_allocations.png',notes);
if isempty(a.mixed_columns),return;end
chosen=1;
for j=1:numel(a.mixed_columns)
    ids=a.mixed_columns(j).region_indices;names={r(ids).alphabet};
    if any(strcmp(names,'16QAM'))&&any(strcmp(names,'32cross')),chosen=j;break;end
end
item=a.mixed_columns(chosen);col=item.column;ii=((col-2)*1004+(1:1004))';z=result.payload_stream(ii);ri=a.region_index(ii);groups=unique(ri);groups(groups==0)=[];
f=figure('Visible',visible,'Color','w','Position',[30 30 1450 1050]);t=tiledlayout(f,2,2,'TileSpacing','compact');
ax=nexttile(t);hold(ax,'on');labels=cell(1,numel(groups));
for j=1:numel(groups),k=double(groups(j));mask=ri==k;scatter(ax,real(z(mask)),imag(z(mask)),10,'.');labels{j}=sprintf('%s ID%d',r(k).alphabet,r(k).id);end
axis(ax,'equal');grid(ax,'on');xlabel(ax,'I / 原观测幅度');ylabel(ax,'Q / 原观测幅度');legend(ax,labels,'Location','best');title(ax,sprintf('同一OFDM列%d：真实观测按资源分组',col));
ax=nexttile(t);q=0:1003;scatter(ax,q,double(ri),9,'.');hold(ax,'on');unc=a.boundary_uncertain(ii);scatter(ax,q(unc),double(ri(unc)),15,'rx');yticks(ax,double(groups));xlim(ax,[0 1003]);ylim(ax,[double(min(groups))-.25 double(max(groups))+.25]);xlabel(ax,'本列q0');ylabel(ax,'区域编号（离散标签）');grid(ax,'on');title(ax,'边界可以穿过一列；红叉表示边界不确定区');
ax=nexttile(t);b=find(diff(ri)~=0,1);if isempty(b),b=500;end
window=max(1,b-20):min(1004,b+20);stem(ax,window-1,double(a.symbol_index(ii(window))),'.');xlabel(ax,'边界附近q0');ylabel(ax,'本区域字母表中的索引1..M');grid(ax,'on');title(ax,'逐资源条件几何索引：跨区域索引不能当统一位串');
ax=nexttile(t);values=[[a.mixed_columns.single_column_EVAL_NLL]' [a.mixed_columns.resource_model_EVAL_NLL]'];bar(ax,values);xticks(ax,1:numel(a.mixed_columns));xticklabels(ax,string([a.mixed_columns.column]));legend(ax,{'一列一个模型','头部分配模型'},'Location','best');xlabel(ax,'跨字母表的OFDM列');ylabel(ax,'同一留出资源平均NLL（越小越好）');grid(ax,'on');title(ax,'整列基线在r0偶数选模型，奇数评价；如实保留负收益');
sgtitle(t,'20 混合调制列的逐资源判决：接收点、几何索引和留出对照');
notes=note('说明一个OFDM符号如何同时含多种调制方式','同一列真实接收点、region_index、symbol_index和留出资源NLL','固定FIT导频幅度/尺度；min_s |z−gC_s|²；log-sum-exp混合似然','看资源边界、索引是否分区域解释和整列模型对照',sprintf('展示列%d；该列留出NLL改善%.4g',col,item.EVAL_NLL_improvement),'最近点没有真实业务SER/BER真值；高阶发射位映射未知；边界不确定资源需保留标记');
finish(f,'20_mixed_column_decisions.png',notes);
    function finish(fig,name,txt)
        slrx.viz.teachingNotes(fig,txt);exportgraphics(fig,fullfile(folder,name),'Resolution',120);files{end+1}=['figures/' name];if ~opt.show_figures,close(fig);end
    end
end
function n=note(p,s,f,o,v,l)
n=struct('purpose',p,'data_source',s,'calculation',f,'focus',o,'current_result',v,'limitations',l);
end
