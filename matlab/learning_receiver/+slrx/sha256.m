function digest = sha256(filename)
%SHA256 流式计算文件指纹；用于记录输入/代码，不参与DSP或模型推理。
% 每次只读取1MiB，避免把大型IQ或MAT再复制一遍到内存。

fid = fopen(filename,'rb');
assert(fid>=0,'无法读取要计算指纹的文件');
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
md = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes = fread(fid,1048576,'*uint8');
    md.update(bytes);
end
bytes = typecast(md.digest(),'uint8');
digest = lower(reshape(dec2hex(bytes,2).',1,[]));
end
