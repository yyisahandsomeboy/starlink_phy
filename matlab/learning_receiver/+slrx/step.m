% 定义step函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function data = step(cfg, key, calculate, plotKind, plotContext)
    %STEP 学习流程的公共保存/恢复工具；数学处理在传入的具名函数里。
    % 示例：capture=slrx.step(cfg,'01_capture',@()slrx.readIQ(cfg),1)。
    % 第一次实际执行calculate，保存data到同名MAT；以后resume直接回读。
    % 小型JSON只包含data.summary，不把IQ/网格写成巨大JSON。
    % 异常写到单独error.json并停止，不让后续步骤使用不存在的结果。

    % 用运行目录和步骤key构造本步MAT文件路径。
    % 单引号里的文字是字符数据，不是同名变量。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    if nargin<5,plotContext=struct();end
    matFile = fullfile(cfg.run_dir, [key '.mat']);

    % 只有允许恢复且已有MAT时才回读，否则下面会实际计算本步。
    % &&要求两侧标量条件都为真，并按需计算右侧。
    if cfg.resume && exist(matFile, 'file')
        % load只回读MAT中的data变量，避免把文件里其他名字覆盖进当前函数。
        stored = load(matFile, 'data');

        % 从回读结构中取出真实步骤结果，返回主脚本的具名变量。
        data = stored.data;

        % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
        fprintf('回读 %s\n', key);
    % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
    else
        % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
        fprintf('执行 %s\n', key);

        % tic记录本步开始时刻，后面toc计算实际耗时。
        started = tic;

        % 进入可能失败的文件/计算操作；若报错转入下面catch记录原因。
        try
            % calculate是传入的函数句柄；加()才真正执行本步的DSP模块。
            data = calculate();

            % save把变量写进MAT；-v7.3可保存大数组，变量名data是统一回读入口。
            save(matFile, 'data', '-v7.3');

            % 记录步骤名、计算耗时、MAT位置、角色和小型数值摘要。
            % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
            summary = struct('key', key, 'elapsed_s', toc(started), 'mat_file', ...
                matFile, 'owner', 'codex_baseline', 'metrics', data.summary);  % 续接同一调用的其余参数或表达式。

            % 打开对应的JSON摘要文件；它不存整个IQ或1024×301复数组。
            fid = fopen(fullfile(cfg.run_dir, [key '.json']), 'w');

            % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
            assert(fid >= 0);

            % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
            fprintf(fid, '%s', jsonencode(summary, 'PrettyPrint', true));

            % 关闭这个文件编号，确保写入完成并释放文件句柄。
            fclose(fid);
        % 把异常接到ME结构里，里面含编号、消息、调用栈，下面会保存并继续抛出。
        catch ME
            % 把MATLAB异常的编号、消息和调用栈整理成可追查的错误记录。
            error = struct('key', key, 'identifier', ME.identifier, 'message', ...
                ME.message, 'stack', ME.stack);  % 续接同一调用的其余参数或表达式。

            % 创建本步骤专用的error.json文件，不伪造成功输出。
            fid = fopen(fullfile(cfg.run_dir, [key '_error.json']), 'w');

            % 只有成功打开错误记录文件时才写入；原错误仍会继续抛出。
            if fid >= 0
                % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
                fprintf(fid, '%s', jsonencode(error));

                % 关闭这个文件编号，确保写入完成并释放文件句柄。
                fclose(fid);
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 把原MATLAB异常重新抛出，保留错误位置，不把失败包装成成功。
            rethrow(ME);
        % 结束错误捕获块；正常时往下执行，异常已在catch记录并抛出。
        end
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 只有配置要求画图才调用展示函数，关闭画图不改变数值。
    if cfg.make_plots
        % 将已算出的data绘图并保存；它不回头改IQ、网格或估计参数。
        slrx.drawStep(cfg, key, plotKind, data, plotContext);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    if ~isfield(cfg,'diagnostics_enabled') || cfg.diagnostics_enabled
        slrx.diag.summarizeStep(cfg, key, data);
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end
