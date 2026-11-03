function cal = resourceCalibration(grid,pilots)
%RESOURCECALIBRATION 幅度及似然尺度只使用FIT导频；不对每个载荷分段旋转。
c=slproto.coordinates();x=grid(c.fit_rows,2:301);p=pilots(c.fit_rows,2:301);
gain=mean(real(x.*conj(p)),1)./mean(abs(p).^2,1);
assert(all(gain>0),'slproto:Gain','Nonpositive pilot gain');
% 八复数观测扣除前级相位两参数和此处幅度一参数，13实自由度。
variance=max(sum(abs(x-gain.*p).^2,1)/6.5,.005);
eval=grid(c.eval_rows,2:301)-gain.*pilots(c.eval_rows,2:301);
cal=struct('gain_per_column',gain,'variance_per_column',variance,'FIT_rows',c.fit_rows, ...
    'EVAL_rows',c.eval_rows,'heldout_pilot_NMSE',sum(abs(eval).^2,'all')/sum(abs(gain.*pilots(c.eval_rows,2:301)).^2,'all'), ...
    'noise_scale_is_diagnostic',true,'payload_phase_fitted',false);
end
