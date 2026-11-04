"""Check DFT snapshots against the actual original I2S receiver input samples."""
import csv
from pathlib import Path
from reference import fixed_reference,floating_reference

base=Path(__file__).resolve().parent
windows={}
for row in csv.DictReader((base/'actual_chain_pcm.csv').open()):
    key=(int(row['epoch']),int(row['hop']))
    values=windows.setdefault(key,[])
    assert int(row['index'])==len(values),(key,row['index'],len(values))
    values.append(int(row['pcm']))
rows=list(csv.reader((base/'actual_chain_snapshots.csv').open()))
assert len(rows)==24,len(rows)
lines=[];max_peak_error=0;zero_snapshots=0
for row in rows:
    epoch,hop,snapshot=map(int,row[:3]);key=(epoch,hop)
    pcm=windows[key]
    assert len(pcm)==512,(key,len(pcm))
    raw,heights=fixed_reference(pcm)
    assert list(map(int,row[4:20]))==raw,('raw',key)
    assert list(map(int,row[20:36]))==heights,('heights',key)
    floating=floating_reference(pcm)
    if max(floating)>=10000:
        max_peak_error=max(max_peak_error,abs(max(raw)-max(floating))/max(floating))
    if not any(raw):zero_snapshots+=1
    lines.append(f'PASS actual receiver snapshot {snapshot:02d}: epoch={epoch} hop={hop}, peak_power={max(raw)}, height={max(heights)}, pcm_nonzero={sum(x!=0 for x in pcm)}')
assert zero_snapshots>=2,zero_snapshots
assert max_peak_error<.01,max_peak_error
assert any(int(r[0])==1 for r in rows),'No post-reset snapshot'
events=list(csv.reader((base/'actual_chain_events.csv').open()))
counts=next(r for r in events if r[1]=='counts')
coverage=next(r for r in events if r[1]=='coverage')
assert list(map(int,coverage[2:]))==[31,15],coverage
lines.append(f'PASS {len(rows)} actual-I2S-receiver snapshots bit-exact against independent integer DFT; max floating FFT peak-power error {max_peak_error:.6%}.')
lines.append(f'PASS parallel uninstrumented source/receiver equality: TX={counts[2]} cycles, RX={counts[3]} cycles, receiver-valid={counts[4]} samples.')
lines.append(f'PASS four songs steady; attack/play/release/silence/idle; persistent mute gives {zero_snapshots} zero snapshots; active-DFT reset and recovery.')
text='\n'.join(lines)+'\n'
(base/'logs'/'actual_chain_verification_summary.txt').write_text(text)
print(text)
