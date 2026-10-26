function check=test_payload_artifacts(root,run_dir,out)
% Independently check current author-method payload export against saved grids.
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
check=test_author_payload_artifacts(root,run_dir,out);
end
