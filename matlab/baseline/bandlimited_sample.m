function out=bandlimited_sample(x,positions)
% Windowed sinc interpolation, 256 taps; preserves the ~115MHz edge pilots.
% positions are MATLAB 1-based fractional input sample coordinates.
x=x(:); positions=positions(:); out=zeros(size(positions),'like',x); offsets=-127:128;
for start=1:2048:numel(positions)
 last=min(numel(positions),start+2047); p=positions(start:last);
 center=floor(p); index=center+offsets; distance=p-index;
 weights=sinc(distance).*(.5+.5*cos(pi*distance/128)); weights(abs(distance)>=128)=0;
 valid=index>=1 & index<=numel(x); index=max(1,min(numel(x),index)); weights=weights.*valid;
 out(start:last)=sum(x(index).*weights,2);
end
end
