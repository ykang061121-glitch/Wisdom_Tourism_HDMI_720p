"""Independent public-TMDS receiver. No access to protected core internals.
Checks complete frames after a bounded startup acquisition; logs startup
anomalies rather than treating arbitrary reset fragments as complete pulses.
"""
from pathlib import Path
from collections import Counter
import json,sys,hashlib
from functools import lru_cache
CTRL={0x354:0,0xab:1,0x154:2,0x2ab:3}
TERC={v:i for i,v in enumerate([0x29c,0x263,0x2e4,0x2e2,0x171,0x11e,0x18e,0x13c,0x2cc,0x139,0x19c,0x2c6,0x28e,0x271,0x163,0x2c3])}
def transition_minimized(value):
 invert=value.bit_count()>4 or (value.bit_count()==4 and not(value&1))
 q=value&1
 for bit in range(1,8):q|=(((q>>(bit-1))^(value>>bit)^invert)&1)<<bit
 return q,int(not invert),2*q.bit_count()-8
TMDS_LUT=[transition_minimized(v) for v in range(256)]
@lru_cache(maxsize=16384)
def encode(value,rd):
 q,x,b=TMDS_LUT[value]
 if rd==0 or b==0:return ((1-x)<<9)|(x<<8)|(q if x else q^255),rd+(b if x else -b)
 if (rd>0 and b>0) or (rd<0 and b<0):return 512|(x<<8)|(q^255),rd+2*x-b
 return (x<<8)|q,rd+b-2*(1-x)
def rgb_byte(symbol):
 q=(symbol&255)^(255 if symbol&512 else 0)
 return (q&1)|sum((((q>>i)^(q>>(i-1))^(0 if symbol&256 else 1))&1)<<i for i in range(1,8))
RGB_DECODE=[rgb_byte(i) for i in range(1024)]
def ecc(value,bits):
 parity=0
 for bit in range(bits):parity=(parity>>1)^(0x83 if ((parity^(value>>bit))&1) else 0)
 return parity
def check(folder,mode,external,fault='NONE',expected_file=None):
 folder=Path(folder);W,H,HT,VT,HS,VS,VIC=(1280,720,1650,750,40,5,4) if mode else (640,480,800,525,96,2,1)
 expected_rgb=Path(expected_file).read_bytes() if expected_file else None
 if expected_rgb is not None:assert len(expected_rgb)==W*H*3
 packet_records=[];guard_like_video=0;first_guard_like_video=None
 state='CONTROL';guard=0;pre=None;prelen=0;h=v=None;last_h_fall=last_h_rise=last_v_fall=None
 locked=False;lock_cycle=None;startup_rows=0;video_x=video_y=0;rows=pixels=frames=avi=packets=0
 header=0;sub=[0]*4;packet_index=0;island_pixels=0;video_lines=Counter();preambles=Counter();startup=[];frame_hash=hashlib.sha256();hashes=[]
 frame_bytes=bytearray();last_cycle=0;injected=False;disparity=[set(range(-16,17)) for _ in range(3)];encoded_checks=0
 def fail(why,**values):
  data={'passed':False,'fault':fault,'mode':mode,'external':external,'cycle':last_cycle,'state':state,'x':video_x,'y':video_y,'reason':why,**values}
  (folder/f'checker_{fault}.json').write_text(json.dumps(data,indent=2));print('HDMI_RECEIVER_REJECT',json.dumps(data));raise AssertionError(why)
 def parse_packet():
  nonlocal packets,avi,header,sub
  hb=[(header>>(8*i))&255 for i in range(4)]
  if ecc(header&0xffffff,24)!=hb[3]:fail('header BCH',header=hb)
  for s in sub:
   if ecc(s&((1<<56)-1),56)!=(s>>56):fail('subpacket BCH',subpacket=hex(s))
  payload=[(s>>(8*i))&255 for s in sub for i in range(7)]
  packets+=1
  packet_records.append({'cycle':last_cycle,'header':hb,'sub':sub.copy()})
  if hb[0]==0x82:
   if hb[1:3]!=[2,13]:fail('AVI header',header=hb)
   if (sum(hb[:3])+sum(payload[:14]))&255:fail('AVI checksum')
   if fault=='VIC':
    previous=payload[4];payload[4]^=1;payload[0]=(payload[0]+previous-payload[4])&255
   expected_vic=VIC
   if payload[4]&127!=expected_vic:fail('AVI VIC',expected=expected_vic,actual=payload[4]&127)
   if (payload[1]>>5)&3:fail('AVI not RGB')
   avi+=1
  header=0;sub=[0]*4
 try:
  for line in (folder/'symbols.txt').open():
   fields=line.split();last_cycle=int(fields[0])
   if last_cycle<100:continue
   try:b,g,r,k=(int(i,16) for i in fields[1:])
   except ValueError:
    if last_cycle>20000:fail('unknown symbol')
    continue
   if k not in [0x1f,0x3e0]:
    if last_cycle>20000:fail('clock word',word=k)
    continue
   control=b in CTRL and g in CTRL and r in CTRL
   if state=='VIDEO' and ((b,g,r)==(0x2cc,0x133,0x2cc) or (g==r==0x133 and b in TERC)):
    guard_like_video+=1
    if first_guard_like_video is None:first_guard_like_video=last_cycle
   hv=None
   if control:
    if state=='VIDEO':
     video_lines[video_x]+=1;startup_rows+=1
     if locked:
      if video_x!=W:fail('active line width',actual=video_x,expected=W)
      rows+=1
     state='CONTROL'
    if state=='ISLAND' and island_pixels%32:fail('island packet length',length=island_pixels)
    state='CONTROL';guard=0;hv=CTRL[b]
    tag='VIDEO' if g==0xab and r==0x354 else 'ISLAND' if g==r==0xab else None
    if pre==tag:prelen+=1
    else:
     if pre:preambles[(pre,prelen)]+=1
     pre=tag;prelen=1
   elif (b,g,r)==(0x2cc,0x133,0x2cc) and state in ['CONTROL','VIDEO_GUARD']:
    if guard==0:
     if locked and (pre!='VIDEO' or prelen!=8):fail('video preamble',tag=pre,length=prelen)
     if pre:preambles[(pre,prelen)]+=1
     pre=None;prelen=0
    guard+=1;state='VIDEO_GUARD'
    continue
   elif g==r==0x133 and b in TERC and state in ['CONTROL','ISLAND','ISLAND_GUARD']:
    if state not in ['ISLAND','ISLAND_GUARD']:
     if locked and (pre!='ISLAND' or prelen!=8):fail('island preamble',tag=pre,length=prelen)
     if pre:preambles[(pre,prelen)]+=1
     pre=None;prelen=0;island_pixels=0
    state='ISLAND_GUARD';hv=TERC[b]&3
   elif state in ['ISLAND_GUARD','ISLAND'] and b in TERC and g in TERC and r in TERC:
    state='ISLAND';hv=TERC[b]&3
    header|=((TERC[b]>>2)&1)<<packet_index
    for i in range(4):sub[i]|=(((TERC[g]>>i)&1)<<(2*packet_index))|(((TERC[r]>>i)&1)<<(2*packet_index+1))
    packet_index+=1;island_pixels+=1
    if packet_index==32:
     if fault=='DATAISLAND' and locked and not injected:header^=1;injected=True
     parse_packet();packet_index=0
   else:
    if state=='VIDEO_GUARD':
     if guard!=2:fail('video guard length',length=guard)
     state='VIDEO';guard=0;video_x=0;disparity=[set(range(-16,17)) for _ in range(3)]
    if state=='VIDEO':
     if locked:
      # Alternative polarity preserves the decoded byte, but is illegal for
      # the already-acquired running disparity. This negative must exercise
      # the encoder checker, not merely the external RGB checker.
      if fault=='TMDS' and not injected and video_x==33 and rows==11:r^=0x2ff;injected=True
      values=(RGB_DECODE[r],RGB_DECODE[g],RGB_DECODE[b])
      for channel,(value,word) in enumerate(zip(values,(r,g,b))):
       candidates={nxt for rd in disparity[channel] for candidate,nxt in [encode(value,rd)] if candidate==word}
       if not candidates:fail('TMDS encoding/disparity',channel=channel,actual=hex(word),previous_RD=sorted(disparity[channel]))
       disparity[channel]=candidates
       encoded_checks+=1
      if fault=='CHANNEL':values=(values[2],values[1],values[0])
      if fault=='RGB' and not injected and video_x==33 and rows==11:values=(values[0]^1,*values[1:]);injected=True
      if external:
       expected=tuple(expected_rgb[(rows*W+video_x)*3:(rows*W+video_x)*3+3]) if expected_rgb is not None else (video_x&255,rows&255,(video_x^rows)&255)
       if values!=expected:fail('RGB mismatch',expected=expected,actual=values)
      frame_hash.update(bytes(values));frame_bytes.extend(values);pixels+=1
     video_x+=1
    elif locked:fail('unexpected symbol state',symbols=[b,g,r])
   if hv is not None:
    if fault=='SYNC' and locked and not injected:hv^=1;injected=True
    nh,nv=hv&1,(hv>>1)&1
    if nh!=h:
     if nh==0:
      if locked and last_h_fall is not None and last_cycle-last_h_fall!=HT:fail('H total',actual=last_cycle-last_h_fall,expected=HT)
      last_h_fall=last_cycle
     elif last_h_fall is not None:
      width=last_cycle-last_h_fall
      if locked and width!=HS:fail('HS width',actual=width,expected=HS)
     h=nh
    if nv!=v:
     if nv==0:
      if locked:
       if last_cycle-last_v_fall!=HT*VT:fail('V total',actual=last_cycle-last_v_fall)
       if rows!=H or pixels!=W*H:fail('frame active area',rows=rows,pixels=pixels)
       hashes.append(frame_hash.hexdigest());frames+=1
       if frames==1:
        (folder/'rtl_decoded_frame.ppm').write_bytes(f'P6\n{W} {H}\n255\n'.encode()+frame_bytes)
       frame_bytes=bytearray();frame_hash=hashlib.sha256();rows=pixels=0
      elif startup_rows>=H:
       locked=True;lock_cycle=last_cycle;rows=pixels=0;frame_bytes=bytearray();frame_hash=hashlib.sha256()
      last_v_fall=last_cycle
     elif locked and last_v_fall is not None and last_cycle-last_v_fall!=VS*HT:fail('VS width',actual=last_cycle-last_v_fall)
     v=nv
   if not locked and last_cycle>2*HT*VT+20000:fail('bounded acquisition timeout')
  if frames<2:fail('fewer than two full locked frames',frames=frames)
  if avi<2:fail('AVI packets not observed',avi=avi)
  data={'passed':True,'mode':mode,'external':external,'frames':frames,'pixel_checks':frames*W*H,'lock_cycle':lock_cycle,'packets':packets,'AVI':avi,
   'HTOTAL':HT,'VTOTAL':VT,'active':[W,H],'HS_LOW':HS,'VS_LOW':VS,'TMDS_encoding_checks':encoded_checks,'frame_SHA256':hashes,'video_line_lengths':dict(video_lines),'preambles':{str(k):v for k,v in preambles.items()}}
  data['VideoDataGuardLikeTriples']=guard_like_video;data['FirstVideoDataGuardLikeCycle']=first_guard_like_video
  (folder/f'checker_{fault}.json').write_text(json.dumps(data,indent=2))
  if fault=='NONE':(folder/'decoded_packets.json').write_text(json.dumps(packet_records))
  print('HDMI_RECEIVER_TEST_PASS',json.dumps(data));return True
 except AssertionError:return False
if __name__=='__main__':
 ok=check(sys.argv[1],int(sys.argv[2]),bool(int(sys.argv[3])),sys.argv[4] if len(sys.argv)>4 else 'NONE',sys.argv[5] if len(sys.argv)>5 else None)
 sys.exit(0 if ok else 1)
