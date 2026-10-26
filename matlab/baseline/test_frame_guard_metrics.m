function results = test_frame_guard_metrics
% Native MATLAB contract checks with independently derived sample coordinates.
assert(exist('frame_guard_metrics','file')==2, 'frame_guard_metrics:Missing', ...
    'Missing frame guard metric implementation');
test_zero_sfo_and_signal_windows;
test_positive_sfo;
test_negative_sfo;
test_nonconsecutive_detection_spacing;
test_truncated_tail;
test_unsupplied_signals;
test_empty_frames;
results=struct('passed',true,'test_count',7);
fprintf('frame_guard_metrics: 7 tests passed\n');
end

function test_zero_sfo_and_signal_windows
f=make_frame(1,1,0); f.original_interface=struct('value',17);
raw=repmat(3+4i,400000,1);
% At 250 MHz the predicted guard is [332201,333334+1/3).
raw(332201:333334)=1+2i;
nominal=complex(ones(330000,1),zeros(330000,1));
nominal(318913:320000)=2;
out=frame_guard_metrics(f,250e6,240e6,raw,nominal); g=out.frame_guard;
assert(isequal(out.original_interface,f.original_interface));
assert(out.start_sample_nominal==1 && out.start_sample_capture==1);
near(g.nominal_guard_model_samples,1088,1e-9);
near(g.nominal_guard_duration_s,4.533333333333333e-6,1e-15);
near(g.guard_start_sample_nominal,318913,1e-9);
near(g.guard_end_sample_nominal_exclusive,320001,1e-9);
near(g.guard_start_sample_capture,332201,1e-8);
near(g.guard_end_sample_capture_exclusive,333334+1/3,1e-8);
near(g.guard_start_time_s,332200/250e6,1e-15);
near(g.guard_end_time_s,(333333+1/3)/250e6,1e-15);
assert(g.raw_guard.in_capture && ~g.raw_guard.truncated);
assert(g.raw_guard.expected_integer_sample_count==1134);
assert(g.raw_guard.actual_integer_sample_count==1134);
assert(isequal(g.raw_guard.sample_indices,(332201:333334)'));
assert(isequal(g.raw_guard.samples,repmat(1+2i,1134,1)));
near(g.raw_guard.mean_power,5,1e-12); near(g.raw_guard.rms,sqrt(5),1e-12);
assert(g.raw_preguard.actual_integer_sample_count==1133);
assert(isequal(g.raw_preguard.sample_indices,(331068:332200)'));
near(g.raw_preguard.mean_power,25,1e-12);
near(g.raw_guard_to_preguard_power_ratio,0.2,1e-12);
near(g.raw_guard_to_preguard_power_db,-6.989700043360188,1e-12);
assert(isequal(g.nominal_guard.sample_indices,(318913:320000)'));
near(g.nominal_guard.mean_power,4,1e-12);
near(g.nominal_guard_to_preguard_power_ratio,4,1e-12);
assert(~g.edge_detection_performed);
assert(strcmp(g.endpoint_source,'model_predicted'));
assert(isnan(g.next_detected_start_interval_capture_samples));
assert(isnan(g.previous_detected_start_interval_capture_samples));
assert(isnan(g.gap_to_next_detected_frame_capture_samples));
end

function test_positive_sfo
% Manual +20 ppm calculation at st_model=25, st_capture=26.
out=frame_guard_metrics(make_frame(25,26,20),250e6,240e6,ones(400000,1));
g=out.frame_guard;
near(g.guard_start_sample_nominal,318930.6218875623,1e-7);
near(g.guard_end_sample_nominal_exclusive,320018.6001279974,1e-7);
near(g.guard_start_sample_capture,332219.3561328774,1e-7);
near(g.guard_end_sample_capture_exclusive,333352.6667999974,1e-7);
near(g.mapped_guard_model_samples,1087.9782404351913,1e-8);
assert(isequal(g.raw_guard.sample_indices,(332220:333352)'));
assert(g.raw_guard.actual_integer_sample_count==1133);
assert(g.mapped_guard_duration_s<g.nominal_guard_duration_s);
end

function test_negative_sfo
% Manual -20 ppm calculation at st_model=25, st_capture=26.
out=frame_guard_metrics(make_frame(25,26,-20),250e6,240e6,ones(400000,1));
g=out.frame_guard;
near(g.guard_start_sample_nominal,318943.3783675673,1e-7);
near(g.guard_end_sample_nominal_exclusive,320031.4001280026,1e-7);
near(g.guard_start_sample_capture,332232.6441328827,1e-7);
near(g.guard_end_sample_capture_exclusive,333366.0001333360,1e-7);
assert(isequal(g.raw_guard.sample_indices,(332233:333366)'));
assert(g.raw_guard.actual_integer_sample_count==1134);
assert(g.mapped_guard_duration_s>g.nominal_guard_duration_s);
end

function test_nonconsecutive_detection_spacing
% Detection spacings are two and three transmitter slots with 3 sample jitter.
% Deliberately unordered input verifies chronology without reordering frames.
f=[make_frame(640004,640004,0), make_frame(1,1,0), ...
    make_frame(1600001,1600001,0)];
out=frame_guard_metrics(f,240e6,240e6);
assert(out(1).start_sample_nominal==640004);
g=out(1).frame_guard; first=out(2).frame_guard; last=out(3).frame_guard;
near(g.previous_detected_start_interval_capture_samples,640003,1e-9);
assert(g.previous_estimated_slot_count==2);
near(g.previous_slot_interval_residual_capture_samples,3,1e-9);
near(g.previous_detected_start_interval_s,640003/240e6,1e-15);
assert(g.next_estimated_slot_count==3);
near(g.next_slot_interval_residual_capture_samples,-3,1e-9);
near(first.gap_to_next_detected_frame_capture_samples,321091,1e-9);
near(first.next_detected_start_interval_capture_samples,640003,1e-9);
assert(first.next_estimated_slot_count==2);
assert(isnan(first.previous_estimated_slot_count));
assert(isnan(last.next_estimated_slot_count));
assert(isnan(last.gap_to_next_detected_frame_capture_samples));
assert(strcmp(first.detected_gap_interpretation, ...
    'Gap to another detection; may include undetected slots or another beam'));
end

function test_truncated_tail
% Guard [318913,320001) but captured support only [1,319201).
out=frame_guard_metrics(make_frame(1,1,0),240e6,240e6,ones(319200,1));
g=out.frame_guard;
assert(~g.raw_guard.in_capture && g.raw_guard.truncated);
assert(~g.raw_guard.truncated_before && g.raw_guard.truncated_after);
assert(g.raw_guard.expected_integer_sample_count==1088);
assert(g.raw_guard.actual_integer_sample_count==288);
assert(g.raw_guard.missing_integer_sample_count==800);
near(g.raw_guard.truncated_after_samples,800,1e-9);
assert(isequal(g.raw_guard.sample_indices,(318913:319200)'));
assert(g.raw_preguard.in_capture);
near(g.raw_guard.rms,1,1e-12);
end

function test_unsupplied_signals
out=frame_guard_metrics(make_frame(1,1,10),250e6,240e6);
g=out.frame_guard;
assert(~g.raw_guard.signal_supplied && ~g.nominal_guard.signal_supplied);
assert(isnan(g.raw_guard.in_capture) && isnan(g.raw_guard.truncated));
assert(isnan(g.raw_guard.actual_integer_sample_count));
assert(isnan(g.raw_guard.mean_power));
assert(isempty(g.raw_guard.samples) && isempty(g.raw_guard.sample_indices));
assert(isnan(g.raw_guard_to_preguard_power_ratio));
end

function test_empty_frames
f=struct([]); out=frame_guard_metrics(f,250e6,240e6);
assert(isequal(f,out));
end

function f=make_frame(st_model,st_capture,sfo)
f=struct('start_sample_nominal',st_model,'start_sample_capture',st_capture, ...
    'sfo_ppm',sfo);
end

function near(actual,expected,tolerance)
assert(abs(actual-expected)<=tolerance, 'frame_guard_metrics:Value', ...
    'Expected %.16g, got %.16g (tolerance %.3g)',expected,actual,tolerance);
end
