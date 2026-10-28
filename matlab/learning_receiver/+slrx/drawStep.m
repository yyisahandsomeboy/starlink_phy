% 定义drawStep函数：圆括号内是输入，本函数不直接返回输出变量。
function drawStep(cfg, key, kind, data)
    %DRAWSTEP 只负责展示已算出的变量，不修改IQ、网格、分类或估计参数。
    % key决定文件名；kind对应学习步骤。重复的第二轮用相同画法但不同文件名。
    % 每张图只表达同一项物理量；信道幅度/相位、相位/时延、PSS/SSS分开。

    % 交互学习时显示图形窗口；批处理可转入不可见分支。
    if cfg.show_figures
        % 把图窗可见性设为'on'，交互学习时立即显示新建图。
        % 单引号里的文字是字符数据，不是同名变量。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        visibility = 'on';
    % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
    else
        % 把图窗可见性设为'off'，批处理仍可绘图并导出PNG。
        visibility = 'off';
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 在本次学习输出下建立figures子目录，避免图片散落到当前工作目录。
    folder = fullfile(cfg.run_dir, 'figures');

    % 路径/变量尚不存在时才创建，不覆盖已有运行或用户配置。
    if ~exist(folder, 'dir')
        % mkdir创建所需目录；已有原IQ与历史结果不因建目录而覆盖。
        mkdir(folder);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 根据kind选择一种绘图分支；每个case只展示当前处理步骤的结果。
    switch kind
        % kind等于1时执行本组绘图语句，其他case不会一起运行。
        case 1
            % 概览和32点离散I/Q局部使用同一批样本，不改原数值。
            fig = slrx.viz.plotSampleWindow(data.iq, data.fs_hz, '输入IQ采样', cfg.show_figures);
            store(fig, folder, [key '_iq.png'], cfg);

            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 频率Hz除1e6变成MHz；线性PSD取10*log10变成dB/Hz，画输入频谱。
            plot(data.psd_frequency_hz / 1e6, 10 * log10(data.psd_linear));

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('相对中心频率 / MHz');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('PSD / dB/Hz');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('输入频谱');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '_psd.png'], cfg);
        % kind等于2时执行本组绘图语句，其他case不会一起运行。
        case 2
            % 已保存重采样流：Fs取真实字段，局部显示离散采样。
            fig = slrx.viz.plotSampleWindow(data.iq, data.fs_hz, '名义重采样后的时域信号', cfg.show_figures);
            store(fig, folder, [key '.png'], cfg);
        % kind等于3时执行本组绘图语句，其他case不会一起运行。
        case 3
            % 全局抽取轨迹与精细局部相关分开；都明确原文件/模型坐标。
            fig = slrx.viz.plotGlobalSync(data, cfg, cfg.show_figures);
            slrx.viz.saveFigure(fig, folder, [key '_global.png'], cfg.show_figures);
            fig = slrx.viz.plotLocalSync(data, cfg, cfg.show_figures);
            slrx.viz.saveFigure(fig, folder, [key '_local.png'], cfg.show_figures);

        case 4
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 最多展示帧首2112点，即PSS+SSS同步部分，便于比较CFO补偿前后。
            n = min(2112, numel(data.time_raw));

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(real(data.time_raw(1:n)));

            % hold on保留当前图已有曲线，让后面的plot叠加用于前后对照。
            hold on;

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(real(data.time_cfo_compensated(1:n)));

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('帧内模型采样');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('I分量');

            % 添加曲线/散点图例，文字顺序与先前plot调用的绘图顺序一致。
            legend('CFO前', 'CFO后');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('帧首PSS/SSS的频偏补偿');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于5时执行本组绘图语句，其他case不会一起运行。
        case 5
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 横轴是普通OFDM列号，纵轴是CP与尾部的归一化相关幅度。
            plot(1:size(data.without_cp, 2), abs(data.cp_correlation), '.', 'MarkerSize', 6);

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('网格列，1为SSS');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('CP与符号尾部相关幅度');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('CP复制关系的观测');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于6时执行本组绘图语句，其他case不会一起运行。
        case 6
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % imagesc用颜色表达矩阵数值；行列坐标必须与对应数据顺序一致。
            imagesc(1:size(data.values, 2), fftshift(data.frequency_hz) / 1e6, ...
                20 * log10(max(abs(fftshift(data.values, 1)), 1e-12)));  % 续接同一调用的其余参数或表达式。

            % 设置坐标显示；equal使I/Q刻度等比例，xy使频率纵轴从下往上增加。
            axis xy;

            % 添加颜色与数值的对应刻度；颜色本身不能代替误差指标。
            colorbar;

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('网格列，1为SSS');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('相对中心频率 / MHz');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('FFT网格幅度，shift仅用于显示');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于7时执行本组绘图语句，其他case不会一起运行。
        case 7
            % 按物理频率排序，同时保留重排索引，画H时不能只重排横轴。
            % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
            [frequency, order] = sort(data.frequency_bins);

            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 按物理频率画H的幅度，abs把复响应转换成非负幅度。
            plot(frequency, abs(data.H(order)));

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('有符号FFT bin');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('|H|');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('SSS估计的信道幅度');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '_amplitude.png'], cfg);

            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 按物理频率画H相位；angle取弧度，unwrap去掉2π跳变。
            plot(frequency, unwrap(angle(data.H(order))));

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('有符号FFT bin');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('相位 / rad');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('SSS估计的信道相位');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '_phase.png'], cfg);
        % kind等于8时执行本组绘图语句，其他case不会一起运行。
        case 8
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 显示数据列时+1跳过第1列SSS；这里是FFT网格列号。
            c = cfg.display_data_column + 1;

            % 剔除4个gutter和16条导频，展示该列1004个实际载荷点。
            % 单独的'对复数做共轭转置，与.'不同。
            refs = slrx.references(cfg);
            rows = refs.payload_rows;

            % 按载荷行和选定列读取复数散点；实部画横轴，虚部画纵轴。
            z = data.values(rows, c);

            % 把这一列复数的实部I画在横轴、虚部Q画在纵轴；每个点对应一个载荷位置。
            plot(real(z), imag(z), '.');

            % 设置坐标显示；equal使I/Q刻度等比例，xy使频率纵轴从下往上增加。
            axis equal;

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('I');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('Q');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title(sprintf('均衡后：数据列%d，尚未完成跟踪', c - 1));

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于9时执行本组绘图语句，其他case不会一起运行。
        case 9
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.raw_phase_rad, '.', 'MarkerSize', 6);

            % hold on保留当前图已有曲线，让后面的plot叠加用于前后对照。
            hold on;

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.line_phase_rad);

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('数据OFDM列');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('相位 / rad');

            % 添加曲线/散点图例，文字顺序与先前plot调用的绘图顺序一致。
            legend('导频原始初值', '线性预览');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('FIT导频给出的相位观测');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于10时执行本组绘图语句，其他case不会一起运行。
        case 10
            % 离散候选的柱形得分与逐符号分类台阶；不连接候选K。
            fig = slrx.viz.plotCardinality(data, cfg);
            store(fig, folder, [key '.png'], cfg);
        % kind等于11时执行本组绘图语句，其他case不会一起运行。
        case 11
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.ml_phase_unwrapped_rad, '.');

            % hold on保留当前图已有曲线，让后面的plot叠加用于前后对照。
            hold on;

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.phase_line_rad);

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('数据OFDM列');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('相位 / rad');

            % 添加曲线/散点图例，文字顺序与先前plot调用的绘图顺序一致。
            legend('逐列ML', '整帧拟合');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('残余相位与整帧趋势');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '_phase.png'], cfg);

            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.ml_delay_samples, '.');

            % hold on保留当前图已有曲线，让后面的plot叠加用于前后对照。
            hold on;

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(data.delay_line_samples);

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('数据OFDM列');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('时延 / 模型采样');

            % 添加曲线/散点图例，文字顺序与先前plot调用的绘图顺序一致。
            legend('逐列ML', '整帧拟合');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('残余时延与整帧趋势');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '_delay.png'], cfg);
        % kind等于14时执行本组绘图语句，其他case不会一起运行。
        case 14
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % 判决矩阵已经不含SSS，因此直接使用display_data_column，不再+1。
            c = cfg.display_data_column;

            % 从1004×300判决前复数矩阵取这一列，与最近理想点对照。
            z = data.received(:, c);

            % 把这一列复数的实部I画在横轴、虚部Q画在纵轴；每个点对应一个载荷位置。
            plot(real(z), imag(z), '.');

            % hold on保留当前图已有曲线，让后面的plot叠加用于前后对照。
            hold on;

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(real(data.hard_symbols_observed_scale(:, c)), ...
                imag(data.hard_symbols_observed_scale(:, c)), 'ro');  % 续接同一调用的其余参数或表达式。

            % 设置坐标显示；equal使I/Q刻度等比例，xy使频率纵轴从下往上增加。
            axis equal;

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('I');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('Q');

            % 添加曲线/散点图例，文字顺序与先前plot调用的绘图顺序一致。
            legend('实际接收点', '最近理想点');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title(sprintf('数据列%d的条件符号判决，不是业务比特', c));

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
        % kind等于15时执行本组绘图语句，其他case不会一起运行。
        case 15
            % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
            fig = makeFigure(visibility);

            % plot画横纵坐标曲线；星座图中横轴取实部I、纵轴取虚部Q。
            plot(abs(data.samples));

            % 设置横轴名称和单位，避免把采样点、秒和FFT行号混在一起。
            xlabel('预测保护区内的原采样序号');

            % 设置纵轴名称和单位，读图时先确认它表示幅度、相位还是频率。
            ylabel('|IQ|');

            % 给当前图设置标题，明确阶段、列号和该图能说明的物理量。
            title('模型预测保护区的实测幅度，未独立检测噪声边缘');

            % 调用本文件后面的保存函数，将当前图按步骤key保存到figures。
            store(fig, folder, [key '.png'], cfg);
    % 结束按绘图类型选择的case分支。
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end

% 定义makeFigure函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function fig = makeFigure(visibility)
    %MAKEFIGURE 新建学习图；不关闭用户的其他figure。

    % 新建一个本学习步骤的图窗，返回图形对象供后面保存。
    fig = figure('Visible', visibility, 'Color', 'w', 'Position', [50 50 1050 650]);

    % 设置当前坐标轴字体；gca表示当前坐标轴对象，不是信号数组。
    set(gca, 'FontName', 'Noto Sans CJK SC');

    % grid on显示读图辅助网格，不改变任何DSP数值。
    grid on;
% 结束这个函数，输出变量按函数声明返回给调用者。
end

% 定义store函数：圆括号内是输入，本函数不直接返回输出变量。
function store(fig, folder, filename, cfg)
    %STORE 保存PNG。批处理时关闭本图；交互模式保留窗口供检查。

    % 把当前图导出成120dpi PNG，方便关闭MATLAB后仍能阅读。
    exportgraphics(fig, fullfile(folder, filename), 'Resolution', 120);

    % 批处理时只关闭本函数创建的图，不关闭用户其他图窗。
    if ~cfg.show_figures
        % 只关闭这个图窗对象，释放图形资源；不执行close all影响用户其他图。
        close(fig);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end
% 结束这个函数，输出变量按函数声明返回给调用者。
end
