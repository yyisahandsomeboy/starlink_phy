function plan = planAllocations(headers,registry,total)
%PLANALLOCATIONS r0零基、右端开区间。未知ID立即停止推算后续位置。
if nargin<2,registry=slproto.allocationRegistry();end
if nargin<3,total=301200;end
plan=struct('available',false,'complete',false,'reason','','profile',registry.version, ...
    'conditional',true,'regions',struct([]),'predicted_tail_start_r0',NaN,'unknown_id',[], ...
    'full_payload_FEC_supported',false,'transmitter_bit_mapping_verified',false);
if ~headers.first.accepted||~headers.second_unique||~headers.first_body_length_agrees
    plan.reason='Need two unique accepted headers and verified first body endpoint';return;
end
h=headers.first;s=headers.second_candidates;
plan.regions=region('header1',-1,0,0,h.end_r0+1,1,'BPSK',0,0,true);
e=h.fields.entries;
if numel(e)~=1||e.index8~=5,plan.reason='First body is not verified Code5';return;end
a=h.end_r0+1;b=s.start_r0;
plan.regions(end+1)=region('first_body',5,e.quantity,a,b,1,'BPSK',2048,2048,true);
plan.regions(end+1)=region('header2',-1,0,s.start_r0,s.end_r0+1,1,'BPSK',0,0,true);
cursor=s.end_r0+1;entries=s.fields.entries;plan.available=true;
for j=1:numel(entries)
    e=entries(j);k=find([registry.profiles.id]==e.index8);
    if numel(k)~=1
        plan.unknown_id=e.index8;plan.reason='Unknown ID: downstream positions remain unresolved';return;
    end
    p=registry.profiles(k);last=cursor+e.quantity*p.resources_per_unit;
    if e.quantity<1||last>total,plan.reason='Allocation exceeds frame or has zero quantity';return;end
    plan.regions(end+1)=region('second_body',e.index8,e.quantity,cursor,last,p.bits_per_symbol,p.alphabet,p.resources_per_unit,p.coded_bits_hypothesis,p.FEC_verified); %#ok<AGROW>
    cursor=last;
end
plan.predicted_tail_start_r0=cursor;
if cursor<total,plan.regions(end+1)=region('tail',-2,0,cursor,total,1,'BPSK',0,0,false);end
plan.complete=true;plan.reason='Conditional resource allocation; higher-order FEC and bit mappings remain unresolved';
end
function r=region(kind,id,count,a,b,bits,alphabet,q,nc,fec)
r=struct('kind',kind,'id',id,'quantity',count,'start_r0',a,'end_exclusive_r0',b, ...
    'resource_count',b-a,'bits_per_symbol',bits,'alphabet',alphabet,'resources_per_unit',q, ...
    'coded_bits_hypothesis',nc,'FEC_verified',fec,'start_column',2+floor(a/1004), ...
    'start_q0',mod(a,1004),'last_column',2+floor((b-1)/1004),'same_alphabet_boundary_signal_identifiable',false);
end
