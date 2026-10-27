function saveFigure(fig, out, name, visible)
%SAVEFIGURE PNG固定导出；关闭时只关闭本函数接收的图窗。
if ~exist(out,'dir'), mkdir(out); end
axesHandles=findall(fig,'Type','axes');
for k=1:numel(axesHandles)
    try, axesHandles(k).Toolbar.Visible='off'; catch, end
end
layouts=findall(fig,'Type','tiledlayout');
if numel(layouts)==1,target=layouts(1);else,target=fig;end
exportgraphics(target,fullfile(out,name),'Resolution',120);
if ~visible, close(fig); end
end
