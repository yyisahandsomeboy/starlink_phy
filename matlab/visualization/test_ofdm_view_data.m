function test_ofdm_view_data(root)
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
a=author_sequences(root);
f=struct('grid_before',a.pilots,'grid_resampled',a.pilots,...
 'grid_equalized',a.pilots,'grid_after',a.pilots,'start_sample_capture',125001);
f.grid_before(:,1)=a.sss_grid;f.grid_resampled(:,1)=a.sss_grid;
f.grid_after(a.eval,2:end)=1.2*a.pilots(a.eval,2:end);
% Fitting rows are deliberately wrong: diagnostic EVM must use heldout rows.
f.grid_after(a.fit,2:end)=5*a.pilots(a.fit,2:end);
payload=setdiff(a.active,a.rows);
for col=[2 51 101 151 201 251]
 f.grid_after(payload,col)=exp(1j*(col/100))*ones(numel(payload),1);
end
f.grid_after(1:2,:)=99; % Gutters must never enter payload scatter.
d=ofdm_view_data(f,a);
assert(abs(d.stage_evm(4)-.2)<1e-12,'view:Heldout','EVM used wrong references');
assert(all(abs(d.symbol_evm(4,:)-.2)<1e-12),'view:TimeEVM','Incorrect time EVM');
assert(max(abs(d.derotated_pilots{4}-1.2),[],'all')<1e-12,'view:Derotate','Pilot de-rotation wrong');
assert(isequal(d.selected_grid_columns,[2 51 101 151 201 251]),'view:Selection','Symbol selection must be fixed, not selected for prettiness');
assert(isequal(size(d.payload_points),[numel(payload) 6]),'view:Payload','Payload points pooled across symbols');
for j=1:6
 assert(max(abs(d.payload_points(:,j)-exp(1j*(d.selected_grid_columns(j)/100))))<1e-12,...
  'view:NoRefit','Payload points rotated/scaled or mixed');
end
assert(all(diff(d.frequency_mhz)>0) && numel(d.frequency_mhz)==1024,'view:Axis','FFT frequency order wrong');
fprintf('OFDM_VIEW_DATA_TEST_PASSED\n');
end
