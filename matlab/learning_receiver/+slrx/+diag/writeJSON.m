function writeJSON(file, value)
%WRITEJSON 小型诊断元数据，复数显式写成real/imag；不丢弃相位。
fid=fopen(file,'w','n','UTF-8');
assert(fid>=0,'slrx:DiagnosticOutput','无法创建%s',file);
closer=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(safe(value),'PrettyPrint',true));
end

function value=safe(value)
if isnumeric(value) && ~isreal(value)
    value=struct('real',real(value),'imag',imag(value));
elseif isstruct(value)
    names=fieldnames(value);
    for k=1:numel(value)
        for j=1:numel(names), value(k).(names{j})=safe(value(k).(names{j})); end
    end
elseif iscell(value)
    value=cellfun(@safe,value,'UniformOutput',false);
end
end
