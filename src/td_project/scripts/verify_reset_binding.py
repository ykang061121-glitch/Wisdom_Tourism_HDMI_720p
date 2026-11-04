from pathlib import Path
import re,json,hashlib,sys
p=Path(__file__).resolve().parents[3];r=p/'doc/verification';r.mkdir(exist_ok=True,parents=True)
n=p/'src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/diagnostic_route_before_hold.v'
s=n.read_text('utf-8-sig')
# Flattening can choose a module input as the common clock NET name. Prove the
# clock by its actual PLL output, not by the spelling of the old top-level net.
pll_blocks=[b for b in s.split(');') if re.search(r'\\video_pll_m0/candidate/pll_inst\s+\(',b)]
assert len(pll_blocks)==1 and 'EG_PHY_PLL' in pll_blocks[0]
pll_port=re.search(r'\.clkc\((.*?)\)',pll_blocks[0],re.S)
assert pll_port and pll_port[1].strip().startswith('{')
pll_outputs=[v.strip() for v in pll_port[1].strip()[1:-1].split(',')]
assert len(pll_outputs)==5
video_clock_net=pll_outputs[-2].strip().lstrip('\\').strip()
clock_evidence={'PLL':'video_pll_m0/candidate/pll_inst','Output':'clkc[1]',
                'Net':video_clock_net,'Port':pll_port[1]}
first='frame_read_write_m0/read_buf/asy_r_rst0'
second='frame_read_write_m0/read_buf/ram_inst/rstb'
cells=[]
for block in s.split(');'):
 q=re.search(r'\.q\((.*?)\)',block,re.S)
 if not q:continue
 nets=re.findall(r'\\([^\s,{}()]+)',q[1])
 if not {first,second}&set(nets):continue
 names=re.findall(r'\\([^\s]+)\s+\(',block)
 clock_pin=re.search(r'\.clk\((.*?)\)',block,re.S)
 assert names and 'SRMODE("ASYNC")' in block and clock_pin
 assert clock_pin[1].strip().lstrip('\\').strip()==video_clock_net,'Reset FF is not on the proven video PLL output'
 assert all(x in {first,second} for x in nets),'Other live Q shares SR'
 sr=re.search(r'\.sr\((.*?)\)',block,re.S);mi=re.search(r'\.mi\((.*?)\)',block,re.S)
 original_clear = sr and 'frame_read_write_m0/frame_fifo_read_m0/fifo_aclr_holdbuf' in sr[1]
 segmented_clear=False
 if sr and 'frame_read_write_m0/frame_fifo_read_m0/fifo_clear_holdbuf' in sr[1]:
  wrapper=(p/'src/user_source/hdl_source/SD/slide_frame_read_write.v').read_text('utf-8-sig')
  top=(p/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text('utf-8-sig')
  assert 'slide_frame_read_write #(' in top
  assert re.search(r'\.rst\s*\(read_fifo_aclr\s*\)',wrapper)
  assert '.fifo_clear(read_fifo_aclr)' in wrapper
  assert 'segmented_frame_reader #(' in wrapper
  segmented_clear=True
 diagnostic_alias = sr and p.name=='D3_F1_startup_status' and 'frame_read_write_m0/diagnostic_read_clear_holdbuf' in sr[1]
 if diagnostic_alias:
  rtl=(p/'src/user_source/hdl_source/SD/frame_read_write.v').read_text('utf-8-sig')
  assert 'assign diagnostic_read_clear=read_fifo_aclr;'in rtl
  assert re.search(r'\.fifo_aclr\s*\(read_fifo_aclr\s*\)',rtl)
 assert original_clear or segmented_clear or diagnostic_alias, 'Unproven logical reset source'
 if second in nets:assert mi and first in mi[1]
 cells.append({'Cell':names[-1],'Q':q[1],'MI':mi[1]if mi else None,'SR':sr[1],'Snippet':block[-2400:]+');'})
assert len(cells)in (1,2)
assert sum(first in c['Q']for c in cells)==1 and sum(second in c['Q']for c in cells)==1
result={'Netlist':str(n),'SHA256':hashlib.sha256(n.read_bytes()).hexdigest().upper(),'VideoClockProof':clock_evidence,'LogicalResetFFs':[first,second],'Cells':cells}
(r/'rebuild_reset_binding.json').write_text(json.dumps(result,indent=2),'utf-8')
lines=['# Same audited logical reset boundary, mapped by current Q/MI connectivity.']
for i,c in enumerate(cells):
 lines += [f'set reset_entry_{i} [get_pins {{{c["Cell"]}.sr}}]',f'if {{[llength $reset_entry_{i}] != 1}} {{error "Reset entry mismatch; stop"}}',f'set_false_path -from [get_clocks ext_mem_clk] -to $reset_entry_{i}']
expected=(p/'src/user_source/constraints_source/postroute_reset.sdc').read_text('utf-8-sig')
assert all(c['Cell']+'.sr' in expected for c in cells), 'Physical reset name changed; stop. Do not reuse or silently rewrite the exception.'
print(json.dumps(result,indent=2))
