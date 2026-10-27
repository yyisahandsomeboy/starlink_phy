function fig = plotFFTGrid(context, options)
%PLOTFFTGRID 排序仅用于显示，原FFT行号与bin映射保存在UserData。
fig=slrx.viz.newFigure('FFT资源网格：行号、signed bin与频率',options.show_figures);
layout=tiledlayout(fig,1,2,'TileSpacing','compact');layout.OuterPosition=[0 .02 1 .92];
cfg=context.cfg;refs=context.refs;columns=options.grid_columns;
assert(isscalar(columns)||all(diff(columns)==1),'slrx:DiagnosticSelection','FFT图列范围必须连续');
[bins,order]=sort(refs.frequency_bins);freq=slrx.diag.coordinates('bin_to_mhz',bins,cfg);
keep=freq>=options.frequency_band_mhz(1)&freq<=options.frequency_band_mhz(2);order=order(keep);bins=bins(keep);freq=freq(keep);
assert(~isempty(order),'slrx:DiagnosticSelection','FFT图所选频率区间为空');
axesList=gobjects(1,2);images=gobjects(1,2);markers=cell(1,2);fields={'fft1','fft2'};limits=[Inf -Inf];
for pass=1:2
    field=fields{pass};ax=nexttile(layout);axesList(pass)=ax;markers{pass}=struct('handle',{},'bin',{});
    if ~isfield(context,field),axis(ax,'off');text(ax,.1,.5,sprintf('第%d轮FFT未执行',pass));continue;end
    z=20*log10(max(abs(context.(field).values(order,columns)),1e-12));
    limits=[min(limits(1),min(z,[],'all')),max(limits(2),max(z,[],'all'))];
    images(pass)=imagesc(ax,columns,freq,z);axis(ax,'xy');colorbar(ax);hold(ax,'on');
    groups={refs.fit_rows(:),refs.eval_rows(:),setdiff((1:cfg.nfft)',refs.active_rows(:))};
    colors={[.95 .4 .12],[.1 .8 .9],[.65 .65 .65]};styles={'--',':',':'};
    for group=1:3
        rows=intersect(groups{group},order);
        for j=1:numel(rows)
            bin=refs.frequency_bins(rows(j));h=yline(ax,slrx.diag.coordinates('bin_to_mhz',bin,cfg),styles{group},'Color',colors{group},'LineWidth',.5);
            markers{pass}(end+1)=struct('handle',h,'bin',bin); %#ok<AGROW>
        end
    end
    if ismember(1,columns),xline(ax,1.5,'w--','SSS | 数据1起');end
    xlabel(ax,'FFT网格列：1=SSS，2..301=数据符号1..300');
    title(ax,sprintf('第%d轮FFT（均衡前）；颜色=20log10|Y|',pass));
end
if all(isfinite(limits))&&limits(2)>limits(1)
    for pass=1:2,if isgraphics(images(pass)),clim(axesList(pass),limits);end;end
end
menu=uicontrol(fig,'Style','popupmenu','Units','normalized','Position',[.03 .955 .4 .03], ...
    'String',{'基带频率/MHz','signed FFT bin'},'Tag','slrx-grid-coordinate','Callback',@changeAxis);
sgtitle(layout,'同一原FFT行映射；橙FIT导频、青EVAL导频、灰空载波；频率重排仅显示，不改DSP矩阵','FontSize',11);
fig.UserData=struct('diagnostic','fft_grid','matlab_row_order',order,'signed_bins',bins,'frequency_mhz',freq,'grid_columns',columns);
changeAxis(menu,[]);
    function changeAxis(control,~)
        for roundIndex=1:2
            if ~isgraphics(images(roundIndex)),continue;end
            if control.Value==1,y=freq;label='基带频率 / MHz';else,y=bins;label='有符号FFT bin（不是MATLAB行号）';end
            images(roundIndex).YData=y;
            for n=1:numel(markers{roundIndex})
                b=markers{roundIndex}(n).bin;
                if control.Value==1,markers{roundIndex}(n).handle.Value=slrx.diag.coordinates('bin_to_mhz',b,cfg);
                else,markers{roundIndex}(n).handle.Value=b;end
            end
            ylabel(axesList(roundIndex),label);ylim(axesList(roundIndex),[min(y)-eps max(y)+eps]);
        end
        state=fig.UserData;state.coordinate_mode=control.Value;fig.UserData=state;
    end
end
