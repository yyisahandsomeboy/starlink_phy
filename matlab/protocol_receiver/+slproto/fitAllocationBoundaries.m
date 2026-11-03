function check = fitAllocationBoundaries(stream,plan,g,v)
%FITALLOCATIONBOUNDARIES 固定16→交叉32→二值尾的顺序；全域搜索，不用数量限制候选。
check=struct('available',false,'reason','Requires complete 16QAM then 32cross profile', ...
    'uses_header_quantities_to_restrict_search',false,'uses_header_end_as_anchor',true,'fit_parity_r0',0);
if ~plan.complete,return;end
r=plan.regions;body=r(strcmp({r.kind},'second_body'));names={body.alphabet};
k=find(strcmp(names,'32cross'),1);
if isempty(k)||k==1||~all(strcmp(names(1:k-1),'16QAM'))||~all(strcmp(names(k:end),'32cross')),return;end
start=body(1).start_r0;z=stream(start+1:end);gg=g(start+1:end);vv=v(start+1:end);
A=slproto.symbolLikelihood(z,slproto.alphabet('16QAM'),gg,vv);
B=slproto.symbolLikelihood(z,slproto.alphabet('32cross'),gg,vv);
C=slproto.symbolLikelihood(z,slproto.alphabet('BPSK'),gg,vv);
train=mod((start:numel(stream)-1)',2)==0;
a=[0;cumsum(A.*train)];b=[0;cumsum(B.*train)];c=[0;cumsum(C.*train)];N=numel(z);m=96;
diffAB=a-b;diffAB(1:m)=Inf;best=cummin(diffAB);
fresh=[true;diff(best)<0];bestIndex=cummax((1:numel(best))'.*fresh);
t=(2*m:N-m)';cost=b(t+1)-c(t+1)+best(t-m+1)+c(end);
[minimum,j]=min(cost);end32=t(j);end16=bestIndex(end32-m+1)-1;
pred=[body(k).start_r0 plan.predicted_tail_start_r0];measured=start+[end16 end32];
% 留出资源仅评价固定边界。+/-1资源在隔点拟合中可不唯一。
p=pred-start;allTrain=score(A,B,C,train,p);signalTrain=score(A,B,C,train,[end16 end32]);
evalPred=score(A,B,C,~train,p);evalSignal=score(A,B,C,~train,[end16 end32]);
check=struct('available',true,'reason','Ordered mixture change-point, not a confidence interval or truth', ...
    'uses_header_quantities_to_restrict_search',false,'uses_header_end_as_anchor',true,'fit_parity_r0',0, ...
    'predicted_r0',pred,'signal_fit_r0',measured,'offset_resources',measured-pred, ...
    'predicted_minus_signal_fit_NLL_fit',allTrain-signalTrain, ...
    'predicted_minus_signal_fit_NLL_EVAL',evalPred-evalSignal,'fit_minimum_NLL',minimum, ...
    'internal_same_alphabet_boundaries_identifiable',false);
end
function s=score(A,B,C,mask,p)
n=numel(A);s=sum(A(1:p(1)).*mask(1:p(1)))+sum(B(p(1)+1:p(2)).*mask(p(1)+1:p(2)))+sum(C(p(2)+1:n).*mask(p(2)+1:n));
end
