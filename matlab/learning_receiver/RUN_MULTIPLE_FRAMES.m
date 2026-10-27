% 定义RUN_MULTIPLE_FRAMES函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function batchDir = RUN_MULTIPLE_FRAMES(frameCount, throughStep)
    %RUN_MULTIPLE_FRAMES 学完一帧后，用同一套模块顺序检查多帧。
    % 直接运行默认只取前2个独立检测合格帧，先做到第8步，避免一上来很耗时。
    % RUN_MULTIPLE_FRAMES(3,14)可处理3帧完整链路，耗时相应增加。
    % 每帧独立SSS估计，不自动开启旧接收机的跨帧共享信道假设。
    % 每帧都建立独立目录，主脚本不复制；这里为易读重复读50ms而不引入缓存服务。

    % nargin是实际输入参数个数；少于1个时在下面补这个可选参数的默认值。
    if nargin < 1
        % 没有传第1参数时默认检查2帧，不是一上来处理所有候选。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        frameCount = 2;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % nargin是实际输入参数个数；少于2个时在下面补这个可选参数的默认值。
    if nargin < 2
        % 没有传第2参数时默认只到第8步，先检查同步、FFT和均衡。
        throughStep = 8;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % mfilename找当前文件，fileparts取其目录，定位学习代码入口。
    % 单引号里的文字是字符数据，不是同名变量。
    learningRoot = fileparts(mfilename('fullpath'));

    % 学习目录向上两层就是工程根，避免写死Windows或其他机器路径。
    projectRoot = fileparts(fileparts(learningRoot));

    % 把指定目录加入MATLAB搜索路径，使其中函数可以按名字调用；+slrx包只加父目录。
    addpath(learningRoot);

    % 用当前时间为本次多帧检查生成独立批次名称。
    stamp = char(datetime('now', 'Format', 'yyyyMMdd-HHmmss-SSS'));

    % 拼出本次批次总目录，每帧在其中有自己的子目录。
    batchDir = fullfile(projectRoot, 'runs', ['codex-learning-batch-' stamp]);

    % mkdir创建所需目录；已有原IQ与历史结果不因建目录而覆盖。
    mkdir(batchDir);

    % 为每帧准备一个cell，分别保存独立检查结果。
    records = cell(1, frameCount);

    % 依时间序号逐帧处理，当前帧使用独立输出目录；for后面的=给出本轮编号序列。
    % 冒号给出索引序列；单独:取整维全部位置。
    for rank = 1:frameCount
        % 为当前帧重新创建配置，不复用上一帧的H和临时变量。
        cfg = slrx.defaultConfig(projectRoot);

        % 每帧从50ms窗口独立检测；这里为易读不引入共享缓存。
        cfg.read_duration_s = 0.05;

        % 按独立合格检测的时间顺序选择当前第rank帧，不是作者标注帧号。
        cfg.frame_rank = rank;

        % 让单帧脚本执行到调用者指定的步骤。
        cfg.stop_after = throughStep;

        % 多帧时不弹出窗口，PNG仍可保存，避免一次打开许多图。
        cfg.show_figures = false;

        % sprintf生成frame_01等目录名，让各帧结果互不覆盖。
        cfg.run_dir = fullfile(batchDir, sprintf('frame_%02d', rank));

        % 在独立函数工作区运行同一份单帧主脚本，不影响外层多帧循环。
        slrx.runOne(cfg);

        % 回读并独立检查这帧已运行步骤，把结果存入第rank个cell。
        % {编号}取得cell格子内部的数据，()则取得格子外壳。
        records{rank} = slrx.validateRun(cfg.run_dir);
    % 结束循环体；还有下一个编号时回到for继续，否则往下执行。
    end

    % 为整个批次写JSON检查索引；它不包含大复数数组。
    fid = fopen(fullfile(batchDir, 'batch_validation.json'), 'w');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(fid >= 0);

    % 把内容写到fid指定的文件；jsonencode把结构转成JSON文本，%s表示原样写入字符串。
    fprintf(fid, '%s', jsonencode(records, 'PrettyPrint', true));

    % 关闭这个文件编号，确保写入完成并释放文件句柄。
    fclose(fid);

    % fprintf按格式输出文字；%s放字符串、%d放整数，表示换行。
    fprintf('多帧学习结果：%s\n', batchDir);
% 结束这个函数，输出变量按函数声明返回给调用者。
end
