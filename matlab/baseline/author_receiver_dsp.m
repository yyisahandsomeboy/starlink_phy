function varargout=author_receiver_dsp(action,varargin)
% Native implementation of Qin journal VI-B/D and PLANS2025 V-D/F.
% Forward model: y=A*c*exp(j*phi-j*2*pi*d*delay/N)+noise.
switch action
 case 'ml_cost',[varargout{1:nargout}]=ml_cost(varargin{:});
 case 'ml_symbol',varargout{1}=ml_symbol(varargin{:});
 case 'cardinality',varargout{1}=cardinality(varargin{:});
 case 'channel',[varargout{1:nargout}]=channel(varargin{:});
 case 'frame_ml',[varargout{1:nargout}]=frame_ml(varargin{:});
 case 'extract_grid',[varargout{1:nargout}]=extract_grid(varargin{:});
 otherwise,error('author:Action','Unknown author DSP action');
end
end

function [value,gradient,hessian]=ml_cost(theta,y,k,C,variance,known)
y=y(:);k=k(:);C=C(:).';variance=max(variance(:),1e-8);
assert(numel(y)==numel(k) && (isscalar(variance)||numel(variance)==numel(y)));
a=2*pi*k/1024;rot=y.*exp(1j*(a*theta(1)-theta(2)));
distance=abs(rot-C).^2;Q=-distance./variance;largest=max(Q,[],2);
W=exp(Q-largest);normalizer=sum(W,2);W=W./normalizer;
terms=log(pi*variance*numel(C))-largest-log(normalizer);
if nargin>=6 && ~isempty(known)
 ka=2*pi*known.k(:)/1024;kr=known.y(:).*exp(1j*(ka*theta(1)-theta(2)));
 kv=max(known.variance(:),1e-8);kt=conj(kr).*known.reference(:);
 extra=log(pi*kv)+abs(kr-known.reference(:)).^2./kv;
else,extra=zeros(0,1);ka=zeros(0,1);kt=complex(zeros(0,1));kv=zeros(0,1);
end
count=numel(y)+numel(extra);value=(sum(terms)+sum(extra))/count;
if nargout<2,return;end
t=conj(rot).*C;imaginary=imag(t);eimag=sum(W.*imaginary,2);
first=2*eimag./variance;b=[-a ones(size(a))];
kb=[-ka ones(size(ka))];gradient=(sum(first.*b,1)+sum((2*imag(kt)./kv).*kb,1)).'/count;
if nargout<3,return;end
second=2*sum(W.*real(t),2)./variance-4*(sum(W.*imaginary.^2,2)-eimag.^2)./variance.^2;
hessian=(b'*(second.*b)+kb'*((2*real(kt)./kv).*kb))/count;hessian=(hessian+hessian')/2;
end

function r=ml_symbol(y,k,C,variance,seed,known)
% Local multistart Newton search after coarse acquisition/delay compensation.
if nargin<6,known=[];end
seed=seed(:);initial=zeros(2,9);scores=zeros(1,9);j=0;
for z=[-.15 0 .15]
 for phase=[-pi/4 0 pi/4]
  j=j+1;initial(:,j)=seed+[z;phase];scores(j)=ml_cost(initial(:,j),y,k,C,variance,known);
 end
end
[~,order]=sort(scores);best=Inf;best_theta=seed;best_iter=0;
for start=order(1:2)
 theta=initial(:,start);
 for iteration=1:30
  [value,g,H]=ml_cost(theta,y,k,C,variance,known);
  eigenvalue=min(eig(H));H=H+eye(2)*max(0,1e-5-eigenvalue);
  delta=-H\g;delta=delta/max([1 abs(delta(1))/.2 abs(delta(2))/.3]);
  accepted=false;
  for scale=2.^-(0:10)
   proposal=theta+scale*delta;
   if abs(proposal(1)-seed(1))>2,continue;end
   next=ml_cost(proposal,y,k,C,variance,known);
   if next<=value-1e-4*scale*max(0,-g'*delta),accepted=true;break;end
  end
  if ~accepted || norm(scale*delta)<1e-7,break;end
  theta=proposal;
 end
 value=ml_cost(theta,y,k,C,variance,known);
 if value<best,best=value;best_theta=theta;best_iter=iteration;end
end
[~,gradient,H]=ml_cost(best_theta,y,k,C,variance,known);
r=struct('theta',best_theta,'negative_log_likelihood',best,'initial_negative_log_likelihood',ml_cost(seed,y,k,C,variance,known),...
 'gradient',gradient,'hessian',H,'iterations',best_iter,'seed',seed,'finite',all(isfinite(best_theta)) && isfinite(best));
end

function r=cardinality(z,replicates,seed)
% PLANS V-D: K=4,8,16,32; maximum median pointwise silhouette.
z=z(:);X=[real(z) imag(z)];counts=[4 8 16 32];scores=zeros(1,4);
old=rng;clean=onCleanup(@()rng(old));rng(seed,'twister'); %#ok<NASGU>
D=sqrt(max(abs(z).^2+abs(z).'.^2-2*real(z*z'),0));
labels=cell(1,4);centers=cell(1,4);silhouettes=cell(1,4);sse=zeros(1,4);
for j=1:4
 [ids,centroid,sumd]=kmeans(X,counts(j),'Replicates',replicates,'MaxIter',100,'Display','off','EmptyAction','singleton');
 membership=sparse(1:numel(z),ids,1,numel(z),counts(j));sizes=full(sum(membership,1));
 mean_distance=(D*membership)./sizes;
 within=sum(mean_distance.*full(membership),2).*sizes(ids).'./max(sizes(ids).'-1,1);
 singleton=sizes(ids).'==1;
 mean_distance(sub2ind(size(mean_distance),(1:numel(z))',ids))=Inf;
 other=min(mean_distance,[],2);s=(other-within)./max(other,within);s(singleton)=0;
 scores(j)=median(s);labels{j}=ids;centers{j}=centroid(:,1)+1j*centroid(:,2);silhouettes{j}=s;sse(j)=sum(sumd);
end
[~,chosen]=max(scores);
r=struct('candidate_cardinalities',counts,'median_silhouette',scores,'within_cluster_sum_squares',sse,...
 'selected_index',chosen,'cardinality',counts(chosen),'labels',labels{chosen},'centroids',centers{chosen},...
 'silhouette',silhouettes{chosen},'replicates',replicates,'seed',seed,...
 'source','Qin PLANS2025 V-D; median pointwise Euclidean silhouette; kmeans20replicates');
end

function [combined,d]=channel(y,reference,k,window,degree,shared)
active=find(abs(reference)>eps);freq=k(active);[freq,order]=sort(freq);rows=active(order);
q=y(rows)./reference(rows);a=2*pi*freq/1024;
trials=-2:.02:2;profile=abs(sum(q.*exp(1j*a*trials),1)).^2;
[~,peak]=max(profile);lower=max(-2,trials(peak)-.04);upper=min(2,trials(peak)+.04);
delay=fminbnd(@(z)-abs(sum(q.*exp(1j*a*z)))^2,lower,upper,optimset('TolX',1e-10,'Display','off'));
deramped=q.*exp(1j*a*delay);smoothed=sgolayfilt(deramped,degree,window);
zero=interp1(freq,smoothed,0,'linear');assert(abs(zero)>1e-10,'author:ChannelZero');
normalized=smoothed/zero;
shared_used=nargin>=6 && ~isempty(shared);
if shared_used,normalized=shared(rows);normalized=normalized/interp1(freq,normalized,0,'linear');end
gain=sqrt(mean(abs((y(rows).*exp(1j*a*delay))./normalized).^2));
phase=angle(sum((y(rows).*exp(1j*a*delay)./normalized).*conj(reference(rows))));
frame_gain=gain*exp(1j*phase);
combined=zeros(1024,1);combined(rows)=frame_gain*normalized.*exp(-1j*a*delay);
combined([1 2])=combined(3);combined([1023 1024])=combined(1022);
floor_amplitude=max(median(abs(combined(active)))*1e-3,realmin);
small=abs(combined)<floor_amplitude;combined(small)=floor_amplitude*exp(1j*angle(combined(small)));
residual=y(rows)-combined(rows).*reference(rows);
noise_power=max(median(abs(residual).^2)/log(2),1e-12);
normalized_full=zeros(1024,1);normalized_full(rows)=normalized;
d=struct('frequency_order_rows',rows,'sss_ls_frequency_order',q,'sss_deramped_ls',deramped,...
 'channel_smoothed_frequency_order',smoothed,'channel_normalized',normalized_full,...
 'frame_complex_gain',frame_gain,'sss_delay_samples',delay,'sss_delay_s',delay/240e6,...
 'sss_delay_trial_samples',trials,'sss_delay_profile',profile,'sss_residual_frequency_order',residual,...
 'noise_power_before_equalization',noise_power,'noise_variance_equalized',noise_power./max(abs(combined).^2,eps),...
 'smoothing_window',window,'smoothing_degree',degree,'shared_channel_used',shared_used,...
 'delay_channel_gauge','SSS profile delay removed before smoothing and restored in combined H');
end

function [corrected,tracking,d]=frame_ml(grid,a,channel_info,opt,seed)
rows=setdiff(a.active,a.rows);C=payload_models();deltas=nan(1,300);phases=deltas;gains=deltas;types=zeros(1,300);
q=grid(a.fit,2:301)./a.pilots(a.fit,2:301);
left=unwrap(angle(mean(q(1:4,:),1)));right=unwrap(angle(mean(q(5:8,:),1)));
kl=mean(a.freq(a.fit(1:4)));kr=mean(a.freq(a.fit(5:8)));
pilot_slope=(right-left)/(kr-kl);pilot_phase=(left*kr-right*kl)/(kr-kl);
pilot_delay=-pilot_slope*1024/(2*pi);
records=cell(1,300);costs=nan(1,300);iterations=zeros(1,300);silhouette_scores=zeros(4,300);
for j=1:300
 z=grid(rows,j+1);c=cardinality(z,opt.kmeans_replicates,seed+j);silhouette_scores(:,j)=c.median_silhouette;
 if c.cardinality==8
  c.geometry_id=0;c.status='composite_cardinality_8';records{j}=c;continue;
 end
 if c.cardinality==4,m=1;elseif c.cardinality==16,m=3;else,m=4;end
 gain=max(sqrt(mean(abs(c.centroids).^2)),.05);yn=z/gain;
 noise=max(channel_info.noise_variance_equalized(rows)/gain^2,opt.noise_variance_floor);
 e=ml_symbol(yn,a.freq(rows),C{m},noise,[pilot_delay(j);pilot_phase(j)]);
 phase=e.theta(2);
 if m==1
  delta=wrap90(phase-pilot_phase(j));
  if abs(delta)>pi/8,m=2;phase=phase-sign(delta)*pi/4;end
 end
 phase=pilot_phase(j)+wrap90(phase-pilot_phase(j));
 known_pilots=struct('y',grid(a.fit,j+1)/gain,'k',a.freq(a.fit),...
  'reference',a.pilots(a.fit,j+1)/gain,'variance',max(channel_info.noise_variance_equalized(a.fit)/gain^2,opt.noise_variance_floor/gain^2));
 e=ml_symbol(yn,a.freq(rows),C{m},noise,[e.theta(1);phase],known_pilots);
 phase=pilot_phase(j)+wrap90(e.theta(2)-pilot_phase(j));
 aligned=yn.*exp(1j*(2*pi*a.freq(rows)/1024*e.theta(1)-phase));
 [~,ids]=min(abs(aligned-C{m}.').^2,[],2);
 point=C{m}(ids);updated_gain=max(real(sum(conj(point).*aligned))*gain/sum(abs(point).^2),.05);
 types(j)=m;deltas(j)=e.theta(1);phases(j)=phase;gains(j)=updated_gain;costs(j)=e.negative_log_likelihood;iterations(j)=e.iterations;
 c.geometry_id=m;c.status='author_simple_constellation';c.ml=e;c.gain=updated_gain;records{j}=c;
 if mod(j,50)==0,fprintf('AUTHOR_ML %d/300\n',j);end
end
known=types>0 & isfinite(deltas) & isfinite(phases);index=1:300;
assert(nnz(known)>=opt.minimum_simple_symbols,'author:InsufficientSimpleSymbols');
inliers=ransac_line(index,deltas,known,opt.ransac_delay_threshold_samples,seed);
% Fit wrapped phase with SSS absolute reference and pilot-seeded branch continuity.
phase_unwrapped=nan(size(phases));phase_unwrapped(known)=unwrap(4*phases(known))/4;
phase_unwrapped(known)=phase_unwrapped(known)+round((pilot_phase(known)-phase_unwrapped(known))/(pi/2))*(pi/2);
delay_fit=polyfit(index(inliers),deltas(inliers),1);phase_fit=polyfit(index(inliers),phase_unwrapped(inliers),1);
delay_line=polyval(delay_fit,index);phase_line=polyval(phase_fit,index);
corrected=grid;corrected(:,2:301)=grid(:,2:301).*exp(1j*(2*pi*a.freq/1024*delay_line-ones(1024,1)*phase_line));
% Frame gain remains referenced to known SSS/pilots; payload gains are used only for decisions/display.
tracking=struct('symbol_index',2:301,'phase_intercept_rad',phase_line,...
 'phase_slope_rad_per_bin',-2*pi*delay_line/1024,'residual_delay_s',delay_line/240e6,...
 'fit_amplitude',1,'fit_rows',a.fit,'evaluation_rows',a.eval,...
 'method','Author per-symbol marginalized ML; delay RANSAC; 90degree unwrap; joint affine fit',...
 'ml_delay_samples',deltas,'ml_phase_rad',phases,'ml_phase_unwrapped_rad',phase_unwrapped,...
 'ml_inlier_mask',inliers,'ml_delay_residual_samples',deltas-delay_line,...
 'ml_phase_residual_rad',phase_unwrapped-phase_line,'delay_line_coefficients',delay_fit,...
 'phase_line_coefficients',phase_fit,'pilot_seed_phase_rad',pilot_phase,'pilot_seed_delay_samples',pilot_delay);
d=struct('method_version','author-ml-v1','geometry_id_per_data_symbol',types,'gain_per_data_symbol',gains,...
 'cardinality_scores',silhouette_scores,'cardinality_candidate_sizes',[4 8 16 32],...
 'records',{records},'ml_negative_log_likelihood',costs,'ml_iterations',iterations,...
 'simple_symbol_mask',known,'training_reference_rows',a.fit,'heldout_rows_excluded',a.eval);
end

function inliers=ransac_line(x,y,valid,threshold,seed)
old=rng;cleanup=onCleanup(@()rng(old));rng(seed,'twister'); %#ok<NASGU>
ids=find(valid);best=0;best_error=Inf;inliers=valid;
for trial=1:150
 pair=ids(randperm(numel(ids),2));p=polyfit(x(pair),y(pair),1);residual=abs(y-polyval(p,x));mask=valid & residual<=threshold;
 count=nnz(mask);err=sum(residual(mask).^2);
 if count>best || (count==best && err<best_error),best=count;best_error=err;inliers=mask;end
end
if nnz(inliers)<2,inliers=valid;end
end
function value=wrap90(value)
value=mod(value+pi/4,pi/2)-pi/4;
end
function [grid,d]=extract_grid(v,start,cfo,sfo)
offset=(0:302*1056-1)'/(1+sfo*1e-6);positions=start+offset;
w=bandlimited_sample(v,positions);compensated=w.*exp(-1j*2*pi*cfo*offset/240e6);
blocks=reshape(compensated,1056,302);without_cp=blocks(33:end,2:end);
grid=fft(without_cp,[],1)/32;
d=struct('frame_time_raw',w,'frame_time_cfo_compensated',compensated,...
 'cp_samples',blocks(1:32,2:end),'time_without_cp',without_cp,...
 'sample_position_start',start,'sample_position_step',1/(1+sfo*1e-6),...
 'cp_tail_normalized_correlation',sum(blocks(1025:1056,2:end).*conj(blocks(1:32,2:end)),1)./...
 max(sqrt(sum(abs(blocks(1025:1056,2:end)).^2,1).*sum(abs(blocks(1:32,2:end)).^2,1)),eps));
end
