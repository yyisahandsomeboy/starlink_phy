function export_ut_mcs92_symbols(source,repo,pairs)
% Export calibrated, de-rotated resources and CRC-accepted PHY allocations.
addpath(fullfile(repo,'matlab','protocol_receiver'),fullfile(repo,'matlab','learning_receiver'));
maxNumCompThreads(2);
refs = slrx.references(slrx.defaultConfig(repo));
options = slproto.defaultOptions();
[pn,~] = slproto.pnReference();
coordinates = slproto.coordinates();
registry = slproto.allocationRegistry();
models = jsondecode(fileread(fullfile(repo,'matlab','protocol_receiver','models','ar4ja_observed_mcs.json')));
for model = models.formats(:).'
    index = find([registry.profiles.id] == model.mcs);
    if isempty(index)
        index = numel(registry.profiles)+1;
        registry.profiles(index) = registry.profiles(1);
    end
    registry.profiles(index).id = model.mcs;
    registry.profiles(index).resources_per_unit = model.resources_per_unit;
    registry.profiles(index).coded_bits_hypothesis = model.N;
    registry.profiles(index).bits_per_symbol = ceil(model.N/model.resources_per_unit);
    registry.profiles(index).alphabet = model.modulation;
    registry.profiles(index).FEC_verified = true;
end
if nargin < 3
    pairs = [455 466;455 467;481 482];
end
for pair = pairs.'
    block = pair(1);
    frame = pair(2);
    final = fullfile(source,sprintf('mac_trace_symbols_%04d.mat',frame));
    if isfile(final),continue;end
    input = fullfile(source,sprintf('length_grid_%04d.h5',block));
    ids = double(h5read(input,'/frame0'));
    j = find(ids==frame);
    assert(isscalar(j));
    grid = complex(h5read(input,'/grid_real',[1 1 j],[1024 301 1]), ...
                   h5read(input,'/grid_imag',[1 1 j],[1024 301 1]));
    original = slproto.calibrateGrid(grid,refs.pilots);
    after = original.*conj(pn);
    points = reshape(after(coordinates.payload_rows,2:301),[],1);
    headers = slproto.findHeaders(points,options);
    if ~(headers.first.accepted && headers.second_unique && headers.first_body_length_agrees)
        fprintf('FRAME %d skipped, PHY headers unavailable\n',frame);
        continue;
    end
    plan = slproto.planAllocations(headers,registry,numel(points));
    if ~plan.complete
        fprintf('FRAME %d skipped, incomplete allocation plan\n',frame);
        continue;
    end
    gain = slproto.resourceCalibration(original,refs.pilots);
    points = points./repelem(gain.gain_per_column(:),numel(coordinates.payload_rows));
    points = single(points);
    rows = plan.regions;
    ranges = [[rows.id];[rows.quantity];[rows.start_r0]; ...
              [rows.end_exclusive_r0];[rows.resources_per_unit]];
    save(final,'points','ranges','-v7.3');
    fprintf('FRAME %d complete PHY plan, %d regions, tail starts %d\n', ...
        frame,numel(rows),plan.predicted_tail_start_r0);
end
end
