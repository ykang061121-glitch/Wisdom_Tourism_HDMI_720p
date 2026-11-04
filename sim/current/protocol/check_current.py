from pathlib import Path
import argparse,hashlib,json,subprocess,sys
from check_protocol import check
a=argparse.ArgumentParser();a.add_argument('--folder',type=Path,required=True);a.add_argument('--rgb',type=Path,required=True);x=a.parse_args()
results=[]
for fault in ['NONE','TMDS','DATAISLAND','VIC','SYNC','RGB','CHANNEL']:
 passed=check(x.folder,1,True,fault,str(x.rgb))
 assert passed if fault=='NONE' else not passed, fault
 results.append({'Name':'Video '+fault,'Passed':True,'Negative':fault!='NONE'})
for fault in ['NONE','CTS','PCM']:
 p=subprocess.run([sys.executable,str(Path(__file__).with_name('check_audio_packets.py')),fault,str(x.folder.resolve())],capture_output=True,text=True)
 print(p.stdout,p.stderr)
 assert p.returncode==0,fault
 results.append({'Name':'Audio '+fault,'Passed':True,'Negative':fault!='NONE'})
out={'Results':results,'RGB':str(x.rgb),'RGBSHA256':hashlib.sha256(x.rgb.read_bytes()).hexdigest().upper(),'AllPassed':True,'HardwareTested':False}
(x.folder/'results.json').write_text(json.dumps(out,indent=2),'utf-8')
print('CURRENT_HDMI_AUDIO_PROTOCOL_ALL_PASS')
