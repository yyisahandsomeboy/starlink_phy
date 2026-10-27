% 定义marginalNLL函数：圆括号内是输入，等号左边是返回变量；函数内部变量有独立作用域。
% 行尾...表示本条语句未结束，下一行仍属于这次计算/调用。
function [value, gradient, hessian] = marginalNLL(theta, received, bins, ...
    constellation, variance, known, nfft)  % 继续列出本函数的输入参数。
    %MARGINALNLL 未知载荷星座的高斯混合负对数似然，以及解析梯度/Hessian。
    % theta=[delay;phase]，delay是模型采样，phase是rad；bins是有符号FFT bin。
    % 前向模型 y=c*exp(j*phase-j*2*pi*bin*delay/N)+noise。
    % 将每个未知c在候选星座上求和，而不是先把所有点硬判成真值。
    % known为可选FIT导频结构(y/k/reference/variance)，不包含EVAL导频。
    % variance表示E|n|^2，已经按载荷幅度归一化；不是单独实部方差。
    % 先减去每行最大指数再求和，防止exp下溢。下面导数与旧接收机同式。

    % nargin是实际输入参数个数；少于6个时在下面补这个可选参数的默认值。
    if nargin < 6
        % 调用者没有传第6参数时，用空数组表示不加已知FIT导频项。
        % =先计算右边，再把结果放进左边变量；行末;不打印大数组。
        known = [];
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % nargin是实际输入参数个数；少于7个时在下面补这个可选参数的默认值。
    if nargin < 7
        % 未传第7参数时使用1024点FFT的模型约定。
        nfft = 1024;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % (:)把该数据列的接收复数统一成列向量。
    % (:)把全部元素按列顺序排成一列。
    % 冒号给出索引序列；单独:取整维全部位置。
    received = received(:);

    % 把与每个接收点对应的有符号FFT bin也统一成列向量。
    bins = bins(:);

    % (:).'先拉成列，再不共轭转成行；这样与接收列自动扩展成距离表。
    % .'只转置行列，不对复数取共轭。
    constellation = constellation(:).';

    % 把逐频点复噪声方差拉成列，并设1e-8数值下限。
    variance = max(variance(:), 1e-8);

    % assert检查括号内条件；若为false立即报错停止，不让错误输入继续传到下一步。
    assert(numel(received) == numel(bins));

    % 2πk/N给出时延每增加1采样时各频点应转动的角度。
    angularBins = 2 * pi * bins / nfft;

    % theta(1)是时延、theta(2)是相位；乘其反向模型得到当前对齐观测。
    % .*是对应元素相乘，不是矩阵乘法。
    % 1j是虚数单位；exp(1j*相位)表示复平面旋转。
    aligned = received .* exp(1j * (angularBins * theta(1) - theta(2)));

    % 每个对齐观测减去每个候选星座点，abs平方得到逐点候选误差。
    % .^是对各元素分别乘方。
    distance = abs(aligned - constellation) .^ 2;

    % 将负平方误差除噪声方差，得到高斯模型的对数权重。
    % ./是对应元素相除，列向量可自动扩展到各列。
    logWeight = -distance ./ variance;

    % max(...,[],2)逐行取最大对数权重，为稳定求指数作准备。
    largest = max(logWeight, [], 2);

    % 每行先减最大值再exp，避免极小概率全部下溢为0。
    weight = exp(logWeight - largest);

    % 沿第2维累加各候选权重，即每个观测的一行权重和。
    normalizer = sum(weight, 2);

    % 逐行归一化，使各候选的条件权重和为1。
    weight = weight ./ normalizer;

    % 利用log-sum-exp写法计算每个未知符号的负对数边缘似然。
    terms = log(pi * variance * numel(constellation)) - largest - log(normalizer);
    % 已知导频不需要对星座求和；其参考幅度必须与观测一起归一化。

    % 仅存在已知FIT导频时才计算它的高斯项；EVAL未放入known。
    if ~isempty(known)
        % 从known.k取FIT导频bin；(:)转列后变成角频率。
        pilotAngular = 2 * pi * known.k(:) / nfft;

        % 按同一时延/相位候选对齐已知导频观测。
        pilotAligned = known.y(:) .* exp(1j * (pilotAngular * theta(1) - theta(2)));

        % 把导频复噪声方差限制为正值，避免分母为0。
        pilotVariance = max(known.variance(:), 1e-8);

        % 对齐观测共轭乘已知参考，为后面的导数准备复内积。
        pilotProduct = conj(pilotAligned) .* known.reference(:);

        % 已知导频不需枚举星座，直接使用已知参考的高斯负对数似然。
        extra = log(pi * pilotVariance) + abs(pilotAligned ...
            - known.reference(:)) .^ 2 ./ pilotVariance;  % 续接同一调用的其余参数或表达式。
    % 上面的if/elseif条件都不成立时，执行下面这一组缩进语句。
    else
        % 没有FIT导频时使用0行列向量，使后面的求和自然等于0。
        extra = zeros(0, 1);

        % 没有导频时建立空角频率向量，使统一公式仍能使用。
        pilotAngular = zeros(0, 1);

        % 建立空复数导频内积，不伪造不存在的参考。
        pilotProduct = complex(zeros(0, 1));

        % 建立空方差向量，保持后续导数公式维度一致。
        pilotVariance = zeros(0, 1);
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 未知载荷点数加已知导频点数，作为平均代价的归一化分母。
    count = numel(received) + numel(extra);

    % 把载荷项和导频项相加再除点数，得到一个标量平均代价。
    value = (sum(terms) + sum(extra)) / count;

    % 调用者只取代价时提前返回，省去没有请求的梯度计算。
    if nargout < 2
        % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
        return;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 当前对齐观测共轭乘各候选星座，供解析梯度/Hessian计算。
    product = conj(aligned) .* constellation;

    % 取该复内积的虚部，它决定相位扰动的一阶变化。
    imaginary = imag(product);

    % 按各候选后验权重求虚部均值，避免先硬判未知发送符号。
    meanImaginary = sum(weight .* imaginary, 2);

    % 根据复高斯似然得到每个接收点的相位一阶导数因子。
    first = 2 * meanImaginary ./ variance;

    % 两列分别是时延和相位的链式求导系数[-2πk/N,1]。
    direction = [-angularBins ones(size(angularBins))];

    % 为已知FIT导频建立相同的两参数求导方向。
    pilotDirection = [-pilotAngular ones(size(pilotAngular))];

    % 把载荷和FIT导频的两参数一阶导数加总并平均，输出2×1梯度。
    gradient = (sum(first .* direction, ...
        1) + sum((2 * imag(pilotProduct) ./ pilotVariance) .* pilotDirection, ...  % 汇总载荷和FIT导频的一阶导数。
        1)).' / count;  % 汇总载荷和FIT导频的一阶导数。

    % 调用者没有请求Hessian时提前返回，节省二阶计算。
    if nargout < 3
        % 立即结束本次脚本/函数调用，不继续执行后面的步骤；已保存的MAT仍保留。
        return;
    % 结束这一组条件分支，之后接着执行同层的下一条语句。
    end

    % 计算逐点二阶导数因子，含候选权重随参数变化的校正项。
    second = 2 * sum(weight .* real(product), ...
        2) ./ variance - 4 * (sum(weight .* imaginary .^ 2, ...  % 继续计算同一负对数似然的二阶项。
        2) - meanImaginary .^ 2) ./ variance .^ 2;  % 继续计算同一负对数似然的二阶项。

    % 用链式方向组合载荷和FIT导频二阶项，得到2×2曲率矩阵。
    % 单独的'对复数做共轭转置，与.'不同。
    hessian = (direction' * (second .* direction) + pilotDirection' * ((2 ...
        * real(pilotProduct) ./ pilotVariance) .* pilotDirection)) / count;  % 继续计算同一负对数似然的二阶项。

    % 矩阵与转置取平均，去掉浮点舍入造成的微小非对称部分。
    hessian = (hessian + hessian') / 2;
% 结束这个函数，输出变量按函数声明返回给调用者。
end
