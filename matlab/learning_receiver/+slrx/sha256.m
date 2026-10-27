% 定义sha256函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function digest = sha256(filename)
    %SHA256 流式计算文件指纹；用于记录输入/代码，不参与DSP或模型推理。
    % 每次只读取1MiB，避免把大型IQ或MAT再复制一遍到内存。

    % 以二进制只读方式打开要算指纹的文件，返回文件编号。
    % 单引号里的文字是字符数据，不是同名变量。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    fid = fopen(filename, 'rb');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0, '无法读取要计算指纹的文件');

    % 无论正常返回还是报错，离开函数都自动关闭该文件。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    closer = onCleanup(@() fclose(fid));

    % 创建Java SHA-256摘要计算器；只用于文件身份，不参与信号DSP。
    md = java.security.MessageDigest.getInstance('SHA-256');

    % 只要文件尚未读到结尾就继续下面循环；~把feof的结果取反。
    while ~feof(fid)
        % 每次读取最多1MiB的uint8原始字节，避免整份大IQ再占一遍内存。
        bytes = fread(fid, 1048576, '*uint8');

        % 把本批原始字节累积到SHA-256计算器，不把大文件一次全部读进内存。
        md.update(bytes);
    % 回到while重新判断是否读完文件；条件不满足时结束循环。
    end

    % 将摘要结果按uint8解释为32个字节；typecast改变解释，不做数值缩放。
    bytes = typecast(md.digest(), 'uint8');

    % 每字节转两位十六进制，再按顺序拼成小写64字符SHA字符串。
    % .'只转置行列，不对复数取共轭。
    digest = lower(reshape(dec2hex(bytes, 2).', 1, []));
% 结束这个函数，输出变量按函数声明返回给调用者。
end
