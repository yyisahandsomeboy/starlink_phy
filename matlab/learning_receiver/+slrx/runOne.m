% 定义runOne函数：圆括号内是输入，本函数不直接返回输出变量。
function runOne(cfg)
    %RUNONE 在独立函数工作区执行同一个分节脚本，供批处理/多帧调用。
    % 交互学习请直接打开START_HERE.m，变量会留在你的基础工作区。
    % 这里不另写接收算法；脚本提前return只结束本帧，不打断外层多帧循环。

    % 把函数参数命名成主脚本期待的lesson_cfg，变量位于本函数独立工作区。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    lesson_cfg = cfg;

    % 构造START_HERE.m的路径；该脚本就是交互和批处理共用的顺序主线。
    % 单引号里的文字是字符数据，不是同名变量。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    script = fullfile(cfg.project_root, 'matlab', 'learning_receiver', ...
        'START_HERE.m');  % 续接同一调用的其余参数或表达式。

    % 在当前函数工作区执行START_HERE脚本；交互学习时可在编辑器按节直接执行它。
    run(script);
% 结束这个函数，输出变量按函数声明返回给调用者。
end
