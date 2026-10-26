function d=ofdm_view_data(f,a)
% Reference-based diagnostics. No payload decisions, extra rotations or fits.
G={f.grid_before,f.grid_resampled,f.grid_equalized,f.grid_after};
for j=1:4
 assert(isequal(size(G{j}),[1024 301]),'view:Shape','Expected 1024 x 301 grid');
 if j<=2
  gain=sum(conj(a.sss_grid(a.active)).*G{j}(a.active,1))/sum(abs(a.sss_grid(a.active)).^2);
  assert(isfinite(gain) && abs(gain)>eps,'view:Gain','Invalid global SSS gain');
  G{j}=G{j}/gain;
 end
end
P=a.pilots(a.eval,2:end);assert(all(abs(P)>0,'all'));
d=struct('stage_names',{{'Coarse FFT / SSS scalar','CFO-SFO / SSS scalar','ZF equalized','Pilot tracked'}},...
 'stage_evm',zeros(1,4),'symbol_evm',zeros(4,300),'reference_rows',a.eval,...
 'selected_grid_columns',[2 51 101 151 201 251],'frequency_mhz',fftshift(a.freq)*240e6/1024/1e6);
d.derotated_pilots=cell(1,4);d.power_db=cell(1,4);
if isfield(f,'modulation') && isfield(f.modulation,'method_version') && strcmp(f.modulation.method_version,'author-ml-v1')
 d.stage_names{4}='ML residual synchronization';
end
for j=1:4
 error=G{j}(a.eval,2:end)-P;
 d.stage_evm(j)=sqrt(sum(abs(error).^2,'all')/sum(abs(P).^2,'all'));
 d.symbol_evm(j,:)=sqrt(sum(abs(error).^2,1)./sum(abs(P).^2,1));
 d.derotated_pilots{j}=G{j}(a.eval,2:end)./P;
 d.power_db{j}=10*log10(max(abs(fftshift(G{j},1)).^2,realmin));
end
d.heldout_error_magnitude=abs(G{4}(a.eval,2:end)-P);
d.heldout_phase_deg=zeros(4,2,300);
for j=1:4
 U=d.derotated_pilots{j};
 d.heldout_phase_deg(j,1,:)=angle(mean(U(1:4,:),1))*180/pi;
 d.heldout_phase_deg(j,2,:)=angle(mean(U(5:8,:),1))*180/pi;
end
d.payload_rows=setdiff(a.active,a.rows);
d.payload_points=f.grid_after(d.payload_rows,d.selected_grid_columns);
d.payload_frequency_sign=a.freq(d.payload_rows)>=0;
d.payload_mean_power=mean(abs(f.grid_after(d.payload_rows,2:end)).^2,1);
d.payload_fourth_moment=mean(abs(f.grid_after(d.payload_rows,2:end)).^4,1)./max(d.payload_mean_power.^2,eps);
d.scope='Heldout pilots support error metrics. Payload plots/moments are diagnostics only; modulation and business BER unknown.';
end
