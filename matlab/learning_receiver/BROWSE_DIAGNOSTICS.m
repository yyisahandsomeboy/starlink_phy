function controller = BROWSE_DIAGNOSTICS(runDirs, varargin)
%BROWSE_DIAGNOSTICS 原生MATLAB轻量浏览器，缓存已选帧的MAT，不重新执行DSP。
p=inputParser;addParameter(p,'Visible',true,@islogical);parse(p,varargin{:});
if ischar(runDirs)||isstring(runDirs),runDirs=cellstr(runDirs);end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
controller=slrx.viz.exploreRun(runDirs,root,p.Results.Visible);
end
