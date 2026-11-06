function s = smallSummary(result)
%SMALLSUMMARY 数值数组留MAT；JSON不塞整网格或恢复的信息位。
s=rmfield(result,{'calibrated_grid','derotated_grid','payload_stream','reference_grid'});
s.calibration=rmfield(s.calibration,{'phase_intercept_rad','phase_slope_rad_per_bin'});
if s.code5.available
    s.code5.words=rmfield(s.code5.words,{'information_bits','decoded_codeword'});
end
if isfield(s,'allocations')&&s.allocations.available
    s.allocations=rmfield(s.allocations,{'region_index','symbol_index','decided_symbol','boundary_uncertain'});
    s.allocations.calibration=rmfield(s.allocations.calibration,{'gain_per_column','variance_per_column'});
end
if isfield(s,'mcs66')&&s.mcs66.available
    s.mcs66.words=rmfield(s.mcs66.words,{'information_bits','decoded_codeword'});
end
if isfield(s,'mcs70')&&s.mcs70.available
    s.mcs70.words=rmfield(s.mcs70.words,{'information_bits','decoded_codeword'});
end
s.headers.first=smallHeader(s.headers.first);
if ~isempty(s.headers.second_candidates)
    s.headers.second_candidates=arrayfun(@smallHeader,s.headers.second_candidates);
end
end
function h=smallHeader(h)
if ~h.available,return;end
h=rmfield(h,{'word_bits'});h.blocks=rmfield(h.blocks,{'inputs','word_bits','tail_bits','reencoded','hard_observed'});
end
