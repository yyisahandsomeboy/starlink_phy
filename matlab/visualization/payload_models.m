function C=payload_models()
% Geometric candidates. Point order is internal, never a Starlink bit map.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'vendor','author_pilots','utils','complexConstellations'));
q=genQPSKconst();[~,order]=sort(mod(angle(q),2*pi));q=q(order);
q4=gen4QAMconst();[~,order]=sort(mod(angle(q4),2*pi));q4=q4(order);
[x,y]=meshgrid([-3 -1 1 3]);
c16=x(:)+1j*y(:);c16=c16/sqrt(mean(abs(c16).^2));
[x,y]=meshgrid([-5 -3 -1 1 3 5]);keep=~(abs(x)==5 & abs(y)==5);
c32=x(keep)+1j*y(keep);c32=c32/sqrt(mean(abs(c32).^2));
C={q,q4,c16,c32};
end
