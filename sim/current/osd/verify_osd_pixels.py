from pathlib import Path
import numpy as np,json,sys,hashlib
R=Path(__file__).resolve().parent;case=sys.argv[1];d=R/'runs'/case
# The reference is frozen A_ONLY, never edited DUT masks. Four relocated groups
# and brand recolor are calculated with fixed screen positions, not DUT internals.
cols=[(24,24,64,0x30D8FF),(208,144,48,0xFFD040),(400,256,48,0x00FF9A),(592,368,24,0xFFD040),(784,456,48,0x30D8FF)]
frames=12 if case=='actual' else 1
changed=0;allpixels=0;first=None
for f in range(frames):
 def rgb(t):
  p=d/f'RTL_OSD_{t}_f{f}.rgb';a=np.frombuffer(p.read_bytes(),np.uint8)
  assert len(a)==1280*720*3,(p,len(a))
  return a.reshape(720,1280,3)
 before=rgb('before');actual=rgb('after');under=rgb('under')
 mask=np.frombuffer((d/f'RTL_OSD_mask_f{f}.bin').read_bytes(),np.uint8).reshape(720,1280)
 expected=before.copy();expected[20:36,:,:]=under[20:36,:,:]
 for ox,nx,w,c in cols:
  m=mask[20:36,ox:ox+w+1]
  rect=expected[20:36,nx:nx+w+1]
  rect[m==1]=[(c>>16)&255,(c>>8)&255,c&255]
  rect[m==2]=[0x10,0x2C,0x48]
 bad=np.any(expected!=actual,axis=2);count=int(bad.sum())
 if count and first is None:
  y,x=map(int,np.argwhere(bad)[0]);first={'frame':f,'x':x,'y':y,'Got':actual[y,x].tolist(),'Expected':expected[y,x].tolist(),'MismatchPixels':count}
 changed+=int(np.any(before!=actual,axis=2).sum());allpixels+=1280*720
 negative=case!='actual'
 if count and not negative:break
pass_=first is None if not negative else first is not None
out={'Case':case,'Passed':pass_,'Negative':negative,'Frames':frames,'Pixels':allpixels,'ChangedPixels':changed,'FirstMismatch':first,
'Checker':'Independent old-to-new coordinate mapping + recolor using immutable A_ONLY font mask; original RGB outside top row exact; original preUI image under relocated text; metadata8cycle and all state counters asserted in SV',
'HDMIHardwareTest':False,'ControlledSpectrum':True}
(d/'result.json').write_text(json.dumps(out,indent=2),'utf-8')
print(json.dumps(out,indent=2));sys.exit(0 if pass_ else 1)
