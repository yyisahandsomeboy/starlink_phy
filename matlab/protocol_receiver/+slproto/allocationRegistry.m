function registry = allocationRegistry()
%ALLOCATIONREGISTRY 本地采集的显式候选表；不是商业标准MCS表。
base=fileparts(fileparts(mfilename('fullpath')));
registry=jsondecode(fileread(fullfile(base,'models','utexas_allocation_candidate_v1.json')));
for j=1:numel(registry.profiles)
    p=registry.profiles(j);assert(p.resources_per_unit==ceil(p.coded_bits_hypothesis/p.bits_per_symbol));
end
end
