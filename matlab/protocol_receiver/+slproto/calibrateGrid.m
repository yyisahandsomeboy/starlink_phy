function [z,info] = calibrateGrid(grid,pilots)
%CALIBRATEGRID 与旧PN实验一致的只读FIT导频校准；EVAL只评价。
c=slproto.coordinates();assert(isequal(size(grid),[1024 301])&&isequal(size(pilots),[1024 301]));
[~,j]=sort(c.bins(c.fit_rows));fit=c.fit_rows(j);
phase=unwrap(angle(grid(fit,2:301).*conj(pilots(fit,2:301))),[],1);
beta=[ones(8,1) c.bins(fit)]\phase;
z=grid;z(:,2:301)=grid(:,2:301).*exp(-1j*(ones(1024,1)*beta(1,:)+c.bins*beta(2,:)));
err=z(c.eval_rows,2:301)-pilots(c.eval_rows,2:301);
info=struct('phase_intercept_rad',beta(1,:),'phase_slope_rad_per_bin',beta(2,:), ...
    'fit_rows',fit,'eval_rows',c.eval_rows,'heldout_pilot_evm',sqrt(sum(abs(err).^2,'all')/sum(abs(pilots(c.eval_rows,2:301)).^2,'all')), ...
    'policy','Only FIT pilots estimate phase/slope; no header or payload phase fitting; original grid unchanged');
end
