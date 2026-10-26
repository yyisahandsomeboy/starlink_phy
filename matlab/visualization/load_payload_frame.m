function f=load_payload_frame(run_dir,index)
% Read an author frame checkpoint without loading the full multi-frame MAT.
% Python orchestration verifies every consumed checkpoint against run_manifest.
% Parent result adds frame_guard only; payload arrays are the saved checkpoint.
summary_path=fullfile(run_dir,'result.json');manifest_path=fullfile(run_dir,'run_manifest.json');
if exist(summary_path,'file') && exist(manifest_path,'file')
 s=jsondecode(fileread(summary_path));
 if isfield(s,'receiver_version') && strcmp(s.receiver_version,'author-ml-v1')
  assert(index>=1 && index<=s.frame_count,'payload:FrameIndex');
  expected=s.estimates(index).start_sample_capture;
  files=dir(fullfile(run_dir,'frame_candidate_*.mat'));found='';
  for j=1:numel(files)
   p=fullfile(run_dir,files(j).name);position=h5read(p,'/completed_frame/start_sample_capture');
   if abs(double(position)-expected)<1e-6
    assert(isempty(found),'payload:CheckpointAmbiguous');found=p;
   end
  end
  assert(~isempty(found),'payload:CheckpointMissing');
  d=load(found,'completed_frame');f=d.completed_frame;
  assert(abs(f.start_sample_capture-expected)<1e-6 && strcmp(f.modulation.method_version,'author-ml-v1'));
  return;
 end
end
d=load(fullfile(run_dir,'result.mat'),'result');
assert(index>=1 && index<=numel(d.result.frames),'payload:FrameIndex');
f=d.result.frames(index);
end
