function coded = encodeMCS70(u,model)
%ENCODEMCS70 复用QC逆编码算法，N/K/H与逆矩阵均由70模型提供。
if nargin<2,model=slproto.mcs70Model();end
coded=slproto.encodeMCS66(u,model);
end
