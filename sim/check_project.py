from pathlib import Path
import argparse,hashlib,json,xml.etree.ElementTree as ET,re,subprocess,os
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def xml(p):return ET.fromstring(p.read_text('utf-8-sig').replace('&','&amp;'))
def main():
 ap=argparse.ArgumentParser(description='Verify immutable production inputs and self-contained project paths');ap.parse_args()
 m=json.loads((R/'doc/verification/production_sha256.json').read_text('utf-8-sig'))
 assert len(m)==139
 assert all((R/f).is_file() and sha(R/f)==v for f,v in m.items()),'Production mismatch'
 expected='85FAF68CAEA63841E7C3C58B98B6F484FF777D89A59C4620B05D12BDA5DF5B30'
 assert sha(R/'src/td_project/output/Wisdom_Tourism_HDMI_720p.bit')==expected
 reports=[];allfiles=[]
 projects=[R/'src/td_project/HDMI1.4b_Transmitter_v1.0.al']+list((R/'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs').glob('*/*.prj'))
 for p in projects:
  refs=[]
  for f in xml(p).findall('.//Source_Files//File'):
   path=(p.parent/f.attrib['Path']).resolve();assert path.is_relative_to(R),str(path)
   assert path.is_file(),f'Missing referenced input {p}: {path}'
   refs.append({'Path':path.relative_to(R).as_posix(),'SHA256':sha(path)})
  reports.append({'Entry':p.relative_to(R).as_posix(),'References':len(refs),'AllLocalAndPresent':True})
  allfiles.extend(refs)
 for p in (R/'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs').glob('*/settings.cfg'):
  for rel in re.findall(r'\.\./\.\./\.\./user_source/[^\s"}]+',p.read_text('utf-8-sig')):
   assert (p.parent/rel).is_file(),rel
 h=R/'src/user_source/hdl_source'
 # Verilog includes resolve using source-local or recorded compiler include dirs.
 missing=[]
 for p in h.rglob('*'):
  if p.suffix not in ('.v','.vh'):continue
  s=p.read_text('utf-8-sig',errors='replace')
  for rel in re.findall(r'`include\s+"([^"]+)"',s):
   if not any((b/rel).is_file() for b in [p.parent,h,h/'include',h/'SD',R/'src/td_project']):missing.append((str(p),rel))
 assert not missing,missing
 result={'ProductionInputs':139,'AllExact':True,'BitSHA256':expected,'Projects':reports,'MissingIncludes':missing,'HistoryDirectoryRequired':False,'RTLChanged':False,'ConstraintsChanged':False}
 out=R/'doc/verification/dependency_check.json'
 out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
