function refs = references(cfg)
%REFERENCES 获取已公开的同步/导频序列，建立明确的频率与行号映射。
% 本函数只复用作者的参考序列，不调用旧接收机处理IQ。
% refs.pss/sss：1056×1时域参考；refs.sss_grid：1024×1频域SSS。
% refs.pilots：1024×301，列1对应SSS，列2:301对应数据列1:300。
% FIT八条导频用于估计；EVAL八条只评价。FFT行均为MATLAB一基、未shift。
% 作者包与仿真器有同名函数，因此临时添加精确目录，返回时恢复path。

oldPath = path;
restore = onCleanup(@() path(oldPath)); %#ok<NASGU>
base = fullfile(cfg.project_root, 'vendor', 'author_pilots');
addpath(fullfile(base, 'reference-template'), fullfile(base, 'utils', 'signalProcessing'), ...
    fullfile(base, 'utils', 'complexConstellations'));
refs.source_gen_pss = which('genPss');
refs.source_gen_sss = which('genSss');
assert(startsWith(refs.source_gen_pss, base), 'PSS函数路径不是预期的作者参考包');
refs.pss = genPss();
[refs.sss, refs.sss_grid] = genSss();
[pilotsWithPss, refs.pilot_rows] = genEdgePilots();
refs.pilots = pilotsWithPss(:, 2:302);
refs.fit_rows = [489 491 493 495 529 531 533 535];
refs.eval_rows = [490 492 494 496 530 532 534 536];
refs.frequency_bins = [0:511 -512:-1]';
refs.active_rows = (3:1022)';
refs.payload_rows = setdiff(refs.active_rows, refs.pilot_rows);
[~, order] = sort(refs.frequency_bins(refs.payload_rows));
refs.payload_rows_frequency_order = refs.payload_rows(order);
% 前两个四点星座按作者约定相差45°，几何编号不是商业位映射。
qpsk = genQPSKconst();
[~, order] = sort(mod(angle(qpsk), 2*pi));
qam4 = gen4QAMconst();
[~, order4] = sort(mod(angle(qam4), 2*pi));
[x, y] = meshgrid([-3 -1 1 3]);
qam16 = x(:) + 1j*y(:);
qam16 = qam16 / sqrt(mean(abs(qam16).^2));
[x, y] = meshgrid([-5 -3 -1 1 3 5]);
keep = ~(abs(x) == 5 & abs(y) == 5);
qam32 = x(keep) + 1j*y(keep);
qam32 = qam32 / sqrt(mean(abs(qam32).^2));
refs.constellations = {qpsk(order), qam4(order4), qam16, qam32};
refs.constellation_names = {'QPSK', '4QAM', '16QAM', 'cross32QAM'};
end
