% 定义references函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
function refs = references(cfg)
    %REFERENCES 获取已公开的同步/导频序列，建立明确的频率与行号映射。
    % 本函数只复用作者的参考序列，不调用旧接收机处理IQ。
    % refs.pss/sss：1056×1时域参考；refs.sss_grid：1024×1频域SSS。
    % refs.pilots：1024×301，列1对应SSS，列2:301对应数据列1:300。
    % FIT八条导频用于估计；EVAL八条只评价。FFT行均为MATLAB一基、未shift。
    % 作者包与仿真器有同名函数，因此临时添加精确目录，返回时恢复path。

    % 保存当前MATLAB搜索路径，避免作者参考包影响其他同名函数。
    % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
    oldPath = path;

    % 函数结束时自动恢复原搜索路径；onCleanup会在正常退出和报错时执行。
    % @定义函数句柄，保存任务，之后加()才实际调用。
    restore = onCleanup(@() path(oldPath));

    % fullfile按系统规则拼接作者参考包的目录名，返回路径字符串。
    % 单引号里的文字是字符数据，不是同名变量。
    base = fullfile(cfg.project_root, 'vendor', 'author_pilots');

    % 把指定目录加入MATLAB搜索路径，使其中函数可以按名字调用；+slrx包只加父目录。
    % 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
    addpath(fullfile(base, 'reference-template'), fullfile(base, 'utils', ...
        'signalProcessing'), fullfile(base, 'utils', 'complexConstellations'));  % 续接同一调用的其余参数或表达式。

    % which返回实际将调用的genPss文件位置，作为来源记录。
    refs.source_gen_pss = which('genPss');

    % 同样记录SSS生成函数的真实位置，便于排查同名覆盖。
    refs.source_gen_sss = which('genSss');

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(startsWith(refs.source_gen_pss, base), 'PSS函数路径不是预期的作者参考包');

    % 调用作者函数生成1056×1的PSS时域参考。
    refs.pss = genPss();

    % 同时取得SSS时域参考和1024×1频域参考。
    % 等号左侧[...]同时接收多个输出，~丢弃对应输出。
    [refs.sss, refs.sss_grid] = genSss();

    % 取得含PSS列的公开导频模板，以及导频的MATLAB行号。
    [pilotsWithPss, refs.pilot_rows] = genEdgePilots();

    % 保留模板第2:302列，形成SSS+300列数据的1024×301参考。
    % 冒号给出索引序列；单独:取整维全部位置。
    refs.pilots = pilotsWithPss(:, 2:302);

    % 方括号建立8条用于估计的导频行列表；这里是MATLAB一基行号。
    refs.fit_rows = [489 491 493 495 529 531 533 535];

    % 另8条交错导频只评价，不参与后面的ML拟合。
    refs.eval_rows = [490 492 494 496 530 532 534 536];

    % 拼接未shift的FFT有符号bin，并转成1024×1列向量。
    % 单独的'对复数做共轭转置，与.'不同。
    refs.frequency_bins = [0:511 -512:-1]';

    % 3:1022是排除4个gutter后的1020行；'在实数上只做转置。
    refs.active_rows = (3:1022)';

    % setdiff从有效行剔除16条导频，留下1004个载荷位置。
    refs.payload_rows = setdiff(refs.active_rows, refs.pilot_rows);

    % sort排序频率；~丢弃不需要的第一个输出，order保留原行的排列。
    [~, order] = sort(refs.frequency_bins(refs.payload_rows));

    % 按物理频率排列载荷行；原FFT行号仍保留用于回查。
    refs.payload_rows_frequency_order = refs.payload_rows(order);
    % 前两个四点星座按作者约定相差45°，几何编号不是商业位映射。

    % 直接调用作者的QPSK几何函数，不自行假设商业比特标签。
    qpsk = genQPSKconst();

    % 按QPSK点相位排序，固定该几何在本代码中的内部点序。
    [~, order] = sort(mod(angle(qpsk), 2 * pi));

    % 直接调用作者4QAM几何；它与这里的QPSK相差45度。
    qam4 = gen4QAMconst();

    % 按相位排序4QAM点，固定本代码的内部点序。
    [~, order4] = sort(mod(angle(qam4), 2 * pi));

    % meshgrid把给定横纵坐标展开成二维网格，用它组合QAM复数候选点。
    [x, y] = meshgrid([-3 -1 1 3]);

    % 把4×4的横纵坐标拉直组合成16个复数候选点；(:)表示全部元素排成一列。
    % (:)把全部元素按列顺序排成一列。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    qam16 = x(:) + 1j * y(:);

    % 除以平均能量的平方根，将这一组候选星座归一化到单位平均功率。
    % .^是对各元素分别乘方。
    qam16 = qam16 / sqrt(mean(abs(qam16) .^ 2));

    % meshgrid把给定横纵坐标展开成二维网格，用它组合QAM复数候选点。
    [x, y] = meshgrid([-5 -3 -1 1 3 5]);

    % ~表示取反；去掉6×6网格中横纵坐标绝对值都等于5的四个角点。
    % &对数组各元素分别取逻辑“并且”。
    keep = ~(abs(x) == 5 & abs(y) == 5);

    % 先选出非角点，再把横纵坐标组合成32个复数候选点。
    qam32 = x(keep) + 1j * y(keep);

    % 除以平均能量的平方根，将这一组候选星座归一化到单位平均功率。
    qam32 = qam32 / sqrt(mean(abs(qam32) .^ 2));

    % 花括号建立cell容器，存放长度不同的四组星座点。
    % 花括号创建cell，可放不同尺寸或类型的数据。
    refs.constellations = {qpsk(order), qam4(order4), qam16, qam32};

    % cell中的四个名称与上行四组几何一一对应，不是MCS编号。
    refs.constellation_names = {'QPSK', '4QAM', '16QAM', 'cross32QAM'};
% 结束这个函数，输出变量按函数声明返回给调用者。
end
