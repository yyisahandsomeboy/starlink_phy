function result = decodeMCS35(calibratedSymbols)
%DECODEMCS35 Decode calibrated eight-point units with the verified MCS 35 H.
% Input is 5462-by-N, with one complete unit per column, in air order after
% PN removal and gain normalization. The first column can begin a MAC
% allocation. For a mid-allocation input, use the word results only.
validateattributes(calibratedSymbols,{'single','double'}, ...
    {'2d','nrows',5462,'nonempty','finite'},mfilename,'calibratedSymbols');
model = effectiveModel();
numWords = size(calibratedSymbols,2);
information = false(model.K,numWords);
receivedBits = false(model.N,numWords);
template = struct('passed',false,'initial_failed_checks',0,'final_failed_checks',0, ...
    'iterations',0,'noise_scale',NaN,'observed_trailing_slots',false(2,1));
words = repmat(template,1,numWords);
for i = 1:numWords
    z = double(calibratedSymbols(:,i));
    power = mean(abs(z).^2);
    if power==0 || ~isfinite(power)
        error('slproto:InvalidMCS35UnitPower','MCS 35 unit %d needs finite nonzero power.',i);
    end
    z = z/sqrt(power);
    for pass = 1:3
        [~,point] = min(abs(z-model.points.').^2,[],2);
        ideal = model.points(point);
        gain = (ideal'*z)/(ideal'*ideal);
        if abs(gain)<eps,break;end
        z = z/gain;
    end
    best = [];
    for scale = [.04 .025 .08 .015]
        serial = likelihood(z,model,scale);
        decoded = slproto.minsumGrouped(serial(1:model.N),model.groups,.8,90);
        if isempty(best) || decoded.final_failed_checks<best.final_failed_checks
            best = decoded;
            words(i) = struct('passed',decoded.converged, ...
                'initial_failed_checks',decoded.initial_failed_checks, ...
                'final_failed_checks',decoded.final_failed_checks,'iterations',decoded.iterations, ...
                'noise_scale',scale,'observed_trailing_slots',serial(model.N+1:end)<0);
        end
        if decoded.converged,break;end
    end
    if words(i).passed
        receivedBits(:,i) = best.bits;
        information(:,i) = best.bits(1:model.K);
    end
end

firstFailed = find(~[words.passed],1);
prefixWords = numWords;
if ~isempty(firstFailed),prefixWords=firstFailed-1;end
mac = slproto.verifyPayloadHeaderCrc(information(:,1:prefixWords));
result = struct('N',model.N,'K',model.K,'words',words, ...
    'information_bits',information,'codeword_bits',receivedBits,'mac',mac);
end

function serial = likelihood(z,model,scale)
distance = abs(z-model.points.').^2/scale;
values = zeros(numel(z),3);
for i = 1:3
    a = distance(:,~model.labels(:,i));
    b = distance(:,model.labels(:,i));
    lo = min(a,[],2);
    hi = min(b,[],2);
    values(:,i) = hi-lo+log(sum(exp(lo-a),2))-log(sum(exp(hi-b),2));
end
serial = reshape(values.',[],1);
end

function model = effectiveModel()
persistent loaded
if isempty(loaded)
    root = fileparts(fileparts(mfilename('fullpath')));
    source = jsondecode(fileread(fullfile(root,'models','mcs35_complete_16384_model.json')));
    checks = source.H_support_0based;
    assert(iscell(checks) && numel(checks)==source.N-source.K);
    degrees = cellfun(@numel,checks);
    values = unique(degrees);
    groups = cell(1,numel(values));
    for i = 1:numel(values)
        selected = checks(degrees==values(i));
        groups{i} = cell2mat(cellfun(@(row)row(:).'+1,selected(:),'UniformOutput',false));
    end
    coordinates = source.alphabet_scaled_by_sqrt10;
    points = complex(coordinates(:,1),coordinates(:,2))/sqrt(10);
    loaded = struct('N',source.N,'K',source.K,'groups',{groups}, ...
        'points',points,'labels',logical(source.bit_labels));
end
model = loaded;
end
