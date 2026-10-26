function test_author_receiver_dsp(root)
if nargin<1,root=fileparts(fileparts(fileparts(mfilename('fullpath'))));end
addpath(fullfile(root,'matlab','baseline'),fullfile(root,'matlab','visualization'));
C=payload_models();rng(20261014);k=[(2:487) (496:527) (536:1021)]';k(k>=512)=k(k>=512)-1024;
x=C{3}(randi(16,numel(k),1));theta=[.18;.21];y=x.*exp(1j*(theta(2)-2*pi*k/1024*theta(1)));
[v,g,H]=author_receiver_dsp('ml_cost',theta,y,k,C{3},.02);
for j=1:2
 step=zeros(2,1);step(j)=1e-6;
 vp=author_receiver_dsp('ml_cost',theta+step,y,k,C{3},.02);
 vm=author_receiver_dsp('ml_cost',theta-step,y,k,C{3},.02);
 assert(abs(g(j)-(vp-vm)/2e-6)<1e-6,'author:Gradient','Marginal likelihood gradient sign mismatch');
 [~,gp]=author_receiver_dsp('ml_cost',theta+step,y,k,C{3},.02);
 [~,gm]=author_receiver_dsp('ml_cost',theta-step,y,k,C{3},.02);
 assert(max(abs(H(:,j)-(gp-gm)/2e-6))<1e-5,'author:Hessian');
end
e=author_receiver_dsp('ml_symbol',y,k,C{3},.02,[0;0]);
assert(norm(e.theta-theta)<1e-4,'author:ML','Noiseless delay/phase recovery failed');
% Known pilots keep their public amplitude when payload gain is not one.
pk=[-495;-490;490;495];pc=exp(1j*pi/4)*ones(4,1);
py=pc.*exp(1j*(theta(2)-2*pi*pk/1024*theta(1)));
known=struct('y',py,'k',pk,'reference',pc,'variance',.02);
gain=1.52;scaled=known;scaled.y=py/gain;scaled.reference=pc/gain;scaled.variance=.02/gain^2;
[v1,g1,h1]=author_receiver_dsp('ml_cost',theta+[.02;-.03],y,k,C{3},.02,known);
[v2,g2,h2]=author_receiver_dsp('ml_cost',theta+[.02;-.03],y,k,C{3},.02,scaled);
assert(max(abs(g1-g2))<1e-10 && max(abs(h1-h2),[],'all')<1e-10,'author:PilotScale');
assert(abs((v2-v1)+2*log(gain)*4/(numel(y)+4))<1e-10,'author:PilotDensityScale');
q=author_receiver_dsp('cardinality',repmat(C{4},15,1)+.001*(randn(480,1)+1j*randn(480,1)),20,101);
assert(q.cardinality==32 && q.median_silhouette(q.selected_index)>.98,'author:Cardinality');
assert(abs(mean(abs(C{4}).^2)-1)<1e-12 && abs(max(abs(C{4}).^2)-34/20)<1e-12);
a=author_sequences(root);z=.12;h=.8*exp(1j*.4)*exp(-1j*2*pi*a.freq*z/1024);
Y=a.sss_grid.*h;
[combined,details]=author_receiver_dsp('channel',Y,a.sss_grid,a.freq,21,3);
assert(max(abs(combined(a.active)-h(a.active)))<1e-8,'author:Channel','SSS channel/delay gauge inconsistent');
assert(abs(details.sss_delay_samples-z)<1e-6);
fprintf('AUTHOR_RECEIVER_DSP_TEST_PASSED cost=%.6f\n',v);
end
