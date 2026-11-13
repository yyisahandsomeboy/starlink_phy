function paths = EXPORT_MCS35_REPLAY(source,outputDir,root)
%EXPORT_MCS35_REPLAY Export the verified replay coordinates from UT soft grids.
% source is the public decodedExemplarFrames_20251019T2214.mat, or a folder
% with length_grid_XXXX.h5 extracts using the published yDataSoft convention.
% The result contains at most the first three units of each MCS 35 allocation.
if nargin<3
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
addpath(fullfile(root,'matlab','learning_receiver'));
if ~isfolder(outputDir),mkdir(outputDir);end
fromExtracts = isfolder(source);
if ~fromExtracts
    archive = matfile(source);
    dims = size(archive,'yDataSoft');
    assert(isequal(dims,[1024 301 1009]),'Expected the published UT yDataSoft array.');
end
refs = slrx.references(slrx.defaultConfig(root));
options = slproto.defaultOptions();
[pn,~] = slproto.pnReference();
coordinates = slproto.coordinates();
blocks = [455 468 481 494];
Q = 5462;
paths = strings(1,numel(blocks));
for i = 1:numel(blocks)
    block = blocks(i);
    mcs35Points = complex(zeros(Q,0));
    mcs35Meta = zeros(4,0);
    if fromExtracts
        input = fullfile(source,sprintf('length_grid_%04d.h5',block));
        frames = double(h5read(input,'/frame0'));
        assert(isequal(frames(:),(block:block+12).'));
    end
    for j = 1:13
        frame = block+j-1;
        if fromExtracts
            grid = complex(h5read(input,'/grid_real',[1 1 j],[1024 301 1]), ...
                           h5read(input,'/grid_imag',[1 1 j],[1024 301 1]));
        else
            grid = archive.yDataSoft(:,:,frame+1);
        end
        calibrated = slproto.calibrateGrid(grid,refs.pilots);
        after = calibrated.*conj(pn);
        points = reshape(after(coordinates.payload_rows,2:301),[],1);
        headers = slproto.findHeaders(points,options);
        if ~headers.first.accepted || ~headers.second_unique || ~headers.first_body_length_agrees
            continue;
        end
        second = headers.second_candidates;
        entry = second.fields.entries(1);
        if entry.index8~=35,continue;end
        gain = slproto.resourceCalibration(calibrated,refs.pilots);
        points = points./repelem(gain.gain_per_column(:),1004);
        for word = 1:min(entry.quantity,3)
            start = second.end_r0+1+(word-1)*Q;
            if start+Q>numel(points),break;end
            mcs35Points(:,end+1) = points(start+(1:Q)); %#ok<AGROW>
            mcs35Meta(:,end+1) = [frame;start;word;entry.quantity]; %#ok<AGROW>
        end
    end
    path = fullfile(outputDir,sprintf('record80_geo_words_%04d.mat',block));
    save(path,'mcs35Points','mcs35Meta','-v7.3');
    paths(i) = string(path);
end
end
