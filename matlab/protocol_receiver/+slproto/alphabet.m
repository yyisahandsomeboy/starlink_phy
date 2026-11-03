function C = alphabet(name)
%ALPHABET 单位平均功率点集；顺序仅为索引，未假定发射Gray/自然位映射。
switch name
    case 'BPSK',C=[-1;1];return;
    case 'QPSKaxes',C=[1;1j;-1;-1j];return;
    case 'QPSKdiag',C=exp(1j*pi/4)*[1;1j;-1;-1j];return;
    case '16QAM',a=-3:2:3;
    case '32cross',a=-5:2:5;
    case '64QAM',a=-7:2:7;
    otherwise,error('slproto:UnknownAlphabet','Unknown alphabet %s',name);
end
[x,y]=meshgrid(a,a);keep=true(size(x));if strcmp(name,'32cross'),keep=~(abs(x)==5&abs(y)==5);end
C=x(keep)+1j*y(keep);C=C/sqrt(mean(abs(C).^2));
end
