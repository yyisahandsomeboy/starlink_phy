function runOne(cfg)
%RUNONE 在独立函数工作区执行同一个分节脚本，供批处理/多帧调用。
% 交互学习请直接打开START_HERE.m，变量会留在你的基础工作区。
% 这里不另写接收算法；脚本提前return只结束本帧，不打断外层多帧循环。

lesson_cfg = cfg; %#ok<NASGU>
script = fullfile(cfg.project_root,'matlab','learning_receiver','START_HERE.m');
run(script);
end
