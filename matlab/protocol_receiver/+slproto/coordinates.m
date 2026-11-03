function c = coordinates()
%COORDINATES r从0开始，先频率升序，再按时隙；从PN时钟中仅事后剔除导频。
c.bins=[0:511 -512:-1]';c.active=(3:1022)';
[~,j]=sort(c.bins(c.active));c.loaded_rows=c.active(j);
c.pilot_rows=[489:496 529:536]';c.fit_rows=[489 491 493 495 529 531 533 535]';
c.eval_rows=[490 492 494 496 530 532 534 536]';
c.payload_rows=setdiff(c.loaded_rows,c.pilot_rows,'stable');
assert(numel(c.loaded_rows)==1020&&numel(c.payload_rows)==1004);
c.payload_bins=c.bins(c.payload_rows);c.r0=(0:301199)';
c.slot=2+floor(c.r0/1004);c.q=mod(c.r0,1004);
c.fft_row=c.payload_rows(c.q+1);c.grid_column=c.slot;
end
