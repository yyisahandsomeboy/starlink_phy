function a = author_sequences(root)
% Only sequence generators and their direct utilities enter the MATLAB path.
p=fullfile(root,'vendor','author_pilots');
addpath(fullfile(p,'reference-template'),fullfile(p,'utils','signalProcessing'));
a.pss=genPss(); [a.sss,a.sss_grid]=genSss(); [e,a.rows]=genEdgePilots();
a.pilots=e(:,2:302); a.fit=[489 491 493 495 529 531 533 535];
a.eval=[490 492 494 496 530 532 534 536];
a.freq=[0:511 -512:-1]'; a.active=3:1022;
end
