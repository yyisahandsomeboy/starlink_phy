function fig = newFigure(name, visible)
%NEWFIGURE 只设置本图，不改变groot或用户其他图窗。
if visible, state='on'; else, state='off'; end
fig=figure('Name',name,'NumberTitle','off','Visible',state,'Color','w', ...
    'Position',[40 40 1400 900],'Tag','slrx-visual-diagnostics');
if ispc, font='Microsoft YaHei'; else, font='Noto Sans CJK SC'; end
set(fig,'DefaultAxesFontName',font,'DefaultTextFontName',font,'DefaultAxesFontSize',10, ...
    'DefaultTextInterpreter','none','DefaultLegendInterpreter','none');
end
