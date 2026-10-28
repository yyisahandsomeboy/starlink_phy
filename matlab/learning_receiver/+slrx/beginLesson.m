% 定义beginLesson函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function cfg = beginLesson(cfg)
    %BEGINLESSON 创建/恢复一次学习目录，保存固定配置和源码快照。
    % 不覆盖旧接收结果。恢复时DSP参数和学习代码必须与本次起点一致。
    % 可改变stop_after、是否显示/画图及显示列，这些选项不改变数值处理。
    % 若想修改算法或DSP参数，请清空cfg.run_dir建立新目录，保留旧记录比较。

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    % 单引号里的文字是字符数据，不是同名变量。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    assert(strcmp(cfg.channel_mode, 'frame_local'), ...
        '当前学习入口仅支持frame_local；共享信道属于原多帧参考模式');  % 继续同一检查条件/失败时的说明。

    % 未指定输出目录时才自动生成新的时间目录。
    if isempty(cfg.run_dir)
        % 把当前时间格式化成目录名；日期时间字符串只用于区分学习运行。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        stamp = char(datetime('now', 'Format', 'yyyyMMdd-HHmmss-SSS'));

        % 在工程runs下创建本次独立目录名，避免覆盖旧实验。
        cfg.run_dir = fullfile(cfg.project_root, 'runs', ['codex-learning-' stamp]);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 路径/变量尚不存在时才创建，不覆盖已有运行或用户配置。
    if ~exist(cfg.run_dir, 'dir')
        % mkdir创建所需目录；已有原IQ与历史结果不因建目录而覆盖。
        mkdir(cfg.run_dir);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 定位当前学习源码目录，后面只记录该目录下的MATLAB文件。
    learningRoot = fullfile(cfg.project_root, 'matlab', 'learning_receiver');

    % dir递归列出全部.m源码；**表示包含子目录。
    files = dir(fullfile(learningRoot, '**', '*.m'));

    % 创建含path和sha256两个字段的空结构数组，准备逐文件登记。
    % {编号}取得cell格子内部的数据，()则取得格子外壳。
    code = struct('path', {}, 'sha256', {});

    % 逐个处理当前列表中的元素，k是从1开始的整数索引；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for k = 1:numel(files)
        % 拼接第k个源码文件的绝对路径。
        source = fullfile(files(k).folder, files(k).name);

        % 去掉公共目录前缀，只存相对源码路径，便于快照目录重建。
        code(k).path = erase(source, [learningRoot filesep]);

        % 计算源文件的SHA-256，恢复旧运行时用它识别代码是否变化。
        code(k).sha256 = slrx.sha256(source);
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 本次运行固定配置的MAT路径，MAT能直接保留结构类型。
    configFile = fullfile(cfg.run_dir, 'lesson_config.mat');

    % 这些是显示/停止选项；恢复时允许变化，DSP参数仍必须完全一致。
    % 花括号创建cell，可放不同尺寸或类型的数据。
    ignored = {'run_dir', 'stop_after', 'resume', 'show_figures', 'make_plots', ...
        'display_data_column', 'diagnostics_enabled', 'debug_plots'};  % 续接同一调用的其余参数或表达式。

    % 已有固定配置时走恢复核验；新运行会进入else记录初始身份。
    if exist(configFile, 'file')
        % load读取固定配置和原代码指纹，返回一个包含这两个变量的结构。
        saved = load(configFile, 'frozenConfig', 'code');

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(isequaln(rmfield(cfg, intersect(fieldnames(cfg), ignored)), ...
            rmfield(saved.frozenConfig, intersect(fieldnames(saved.frozenConfig), ignored))), 'DSP参数已变化，请使用新学习目录，避免混合旧中间变量');  % 继续同一检查条件/失败时的说明。

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(isequaln(code, saved.code), '学习代码已变化，请新建学习目录；旧MAT仍可直接读取');
    % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
    else
        % 复制本次配置作为冻结记录；不把后续显示选项变化当成算法更新。
        frozenConfig = cfg;

        % save把变量写进MAT；-v7.3可保存大数组，变量名data是统一回读入口。
        save(configFile, 'frozenConfig', 'code');

        % 逐个处理当前列表中的元素，k是从1开始的整数索引；for后面的=给出本轮编号序列。
        for k = 1:numel(code)
            % 拼接第k个源码文件的绝对路径。
            source = fullfile(learningRoot, code(k).path);

            % 为当前源码构造本次运行的source_code快照位置。
            target = fullfile(cfg.run_dir, 'source_code', code(k).path);

            % fileparts取目标文件的父目录，复制前保证它存在。
            parent = fileparts(target);

            % 路径/变量尚不存在时才创建，不覆盖已有运行或用户配置。
            if ~exist(parent, 'dir')
                % mkdir创建所需目录；已有原IQ与历史结果不因建目录而覆盖。
                mkdir(parent);
            % 结束这一组条件分支，之后接着执行同层的下一条语句。
            end

            % 把当前源码复制进本次运行的快照目录，保留以后回查的版本。
            copyfile(source, target);
        % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
        end

        % 只在新运行里创建JSON摘要文件；'w'表示写入模式。
        fid = fopen(fullfile(cfg.run_dir, 'lesson_config.json'), 'w');

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(fid >= 0);

        % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
        fprintf(fid, '%s', jsonencode(cfg, 'PrettyPrint', true));

        % 关闭这个文件编号，确保写入完成并释放文件句柄。
        fclose(fid);

        % 记录角色、代码指纹、输入SHA与原评价器锁SHA，明确未使用作者TOA。
        record = struct('role', 'codex_baseline', 'version', cfg.version, ...
            'code', code, 'input_sha256', slrx.sha256(cfg.input_file), ...  % 后续字段/选项名称及对应取值。
            'original_evaluator_lock_sha256', ...  % 后续字段/选项名称及对应取值。
            slrx.sha256(fullfile(cfg.project_root, 'config', ...  % 续接同一调用的其余参数或表达式。
            'evaluator_lock.json')), ...  % 续接同一调用的其余参数或表达式。
            'author_TOAs_used_for_detection', false, ...  % 后续字段/选项名称及对应取值。
            'online_model_calls', 0);  % 后续字段/选项名称及对应取值。

        % 只在新运行里创建JSON摘要文件；'w'表示写入模式。
        fid = fopen(fullfile(cfg.run_dir, 'lesson_lock.json'), 'w');

        % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
        assert(fid >= 0);

        % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
        fprintf(fid, '%s', jsonencode(record, 'PrettyPrint', true));

        % 关闭这个文件编号，确保写入完成并释放文件句柄。
        fclose(fid);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
    fprintf('学习目录：%s\n', cfg.run_dir);
% 结束这个函数，输出变量按函数声明返回给调用者。
end
