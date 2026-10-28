function teachingNotes(fig,note)
%TEACHINGNOTES 六项说明共用页脚；保留既有UserData，不改变信号数据。
layouts=findall(fig,'Type','tiledlayout');
if numel(layouts)==1,layouts(1).OuterPosition=[0 .19 1 .73];end
result=note.current_result;if strlength(string(result))>190,result=[result(1:190) '…（完整值见步骤JSON）'];end
textLines={['目的：' note.purpose],['来源：' note.data_source],['计算：' note.calculation], ...
    ['观察：' note.focus],['结果：' result],['局限：' note.limitations]};
annotation(fig,'textbox',[.025 .005 .95 .17],'String',textLines,'Interpreter','none', ...
    'EdgeColor',[.8 .85 .9],'BackgroundColor',[.97 .98 1],'FontSize',9,'FitBoxToText','off','Tag','slrx-teaching-notes');
if ~isstruct(fig.UserData),fig.UserData=struct();end
fig.UserData.teaching_notes=note;
end
