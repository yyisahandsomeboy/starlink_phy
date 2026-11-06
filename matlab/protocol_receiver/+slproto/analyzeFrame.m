function result = analyzeFrame(grid,pilots,opt)
%ANALYZEFRAME 共享纯后处理：原网格→FIT校准→固定PN→BCC/CRC→条件资源→code5。
if nargin<3,opt=slproto.defaultOptions();end
assert(isequal(size(grid),[1024 301])&&all(isfinite(grid),'all'));
[calibrated,calibration]=slproto.calibrateGrid(grid,pilots);
[R,pn]=slproto.pnReference(opt.pn_model);after=calibrated.*conj(R);c=slproto.coordinates();
values=after(c.payload_rows,2:301);stream=values(:);
headers=slproto.findHeaders(stream,opt);coding=slproto.analyzeCode5(stream,headers,opt);
result=slproto.finishFrame(grid,calibrated,R,calibration,pn,headers,coding,opt);
if opt.enable_allocations
    result.allocations=slproto.analyzeAllocations(stream,headers,calibrated,pilots);
end
if isfield(opt,'enable_mcs66')&&opt.enable_mcs66
    gainCalibration=slproto.resourceCalibration(calibrated,pilots);
    result.mcs66=slproto.analyzeMCS66(stream,headers,gainCalibration,opt);
end
if isfield(opt,'enable_mcs70')&&opt.enable_mcs70
    gainCalibration=slproto.resourceCalibration(calibrated,pilots);
    result.mcs70=slproto.analyzeMCS70(stream,headers,gainCalibration,opt);
end
end
