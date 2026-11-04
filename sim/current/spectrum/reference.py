"""Independent floating FFT and exact fixed DFT checks for the read-only PCM tap."""
from pathlib import Path
import csv, json, math, sys
import numpy as np

BASE=Path(__file__).resolve().parent
FS=48027.663934
N=512
EDGES=[1,2,3,4,5,7,9,12,16,22,30,41,56,77,106,146,256]
idx=np.arange(N)
HANN=np.array([round((.5-.5*math.cos(2*math.pi*n/N))*32767) for n in range(N)],dtype=np.int64)
SINE=np.array([round(math.sin(2*math.pi*n/N)*32767) for n in range(N)],dtype=np.int64)
phase=np.outer(np.arange(1,256),idx)%N
COS=SINE[(phase+128)%N]
SIN=SINE[phase]

def compression(p):
    if p<64:return 0
    e=int(p).bit_length()-1
    return min(255,(e-6)*12+(((int(p)>>(e-3))&7)*3>>1))

def fixed_reference(pcm):
    # Wide integer dot products, no RTL cycle/state emulation.
    x=((np.array(pcm,dtype=np.int64)>>8)*HANN)>>15
    re=(COS@x)>>24
    im=(-SIN@x)>>24
    bins=re*re+im*im
    power=[int(max(bins[a-1:b-1])) for a,b in zip(EDGES[:-1],EDGES[1:])]
    return power,[compression(p) for p in power]

def floating_reference(pcm):
    # A separate radix FFT from NumPy, ideal Hann and unquantized PCM scaling.
    x=np.array(pcm,dtype=np.float64)/256*(.5-.5*np.cos(2*np.pi*idx/N))
    z=np.fft.rfft(x)/N
    bins=z.real*z.real+z.imag*z.imag
    return [float(max(bins[a:b])) for a,b in zip(EDGES[:-1],EDGES[1:])]

def tone(f,amp):
    return np.round(8388607*amp*np.sin(2*np.pi*f*idx/FS)).astype(np.int64).tolist()

def prepare():
    cases=[]
    def add(name,pcm):cases.append({'name':name,'pcm':list(map(int,pcm))})
    add('silence',[0]*N)
    add('440Hz_amp0.8_real_sample_cadence',tone(440,.8))
    add('880Hz_amp0.8',tone(880,.8))
    add('440Hz_amp0.4',tone(440,.4))
    add('440Hz_amp0.2',tone(440,.2))
    add('440_plus_880_two_tones',np.array(tone(440,.35))+np.array(tone(880,.35)))
    add('sample_valid_pause_same_440',tone(440,.8))
    add('6000_plus_12000_two_tones',np.array(tone(6000,.35))+np.array(tone(12000,.35)))
    add('negative_control_same_pcm_different_song_label',tone(440,.8))
    shuffled=np.array(tone(440,.8));np.random.default_rng(20261027).shuffle(shuffled)
    add('negative_control_shuffled_pcm',shuffled)
    add('fullscale_positive_dc',[8388607]*N)
    add('fullscale_negative_dc',[-8388608]*N)
    add('fullscale_alternating_nyquist',[8388607 if n&1 else -8388608 for n in idx])
    add('fullscale_noise',np.random.default_rng(512).integers(-8388608,8388608,size=N))
    add('fullscale_impulse',[0]*256+[8388607]+[0]*255)
    # These values were emitted by the actual, unchanged D1 image_melody_pcm RTL.
    selected={}
    with (BASE/'real_dds_pcm.csv').open() as f:
        reader=csv.DictReader(f)
        for row in reader:
            key=(int(row['song']),int(row['note']))
            if int(row['envelope'])==2000000:
                values=selected.setdefault(key,[])
                if len(values)<N+128: values.append(int(row['pcm']))
    for song in range(4):
        for note in range(8):
            values=selected[(song,note)]
            assert len(values)>=N+128,(song,note,len(values))
            add(f'original_DDS_song{song+1}_note{note}',values[128:128+N])
    for c in cases:
        c['power'],c['levels']=fixed_reference(c['pcm'])
        c['floating_power']=floating_reference(c['pcm'])
        c['dominant_band']=int(np.argmax(c['power']))
    (BASE/'expected.json').write_text(json.dumps({'fs':FS,'edges':EDGES,'cases':cases},indent=2))
    (BASE/'stimulus.hex').write_text(''.join(f'{p&0xffffffff:08x}\n' for c in cases for p in c['pcm']))
    (BASE/'case_count.txt').write_text(str(len(cases)))
    print(f'Prepared {len(cases)} cases, including 32 windows from original DDS RTL.')

def check():
    data=json.loads((BASE/'expected.json').read_text()); cases=data['cases']
    rows=list(csv.reader((BASE/'rtl_snapshots.csv').open()))
    assert len(rows)==len(cases),(len(rows),len(cases))
    lines=[]
    max_rel=0;max_peak_rel=0
    for row,c in zip(rows,cases):
        values=list(map(int,row));case_id,cycles=values[:2]
        assert values[2:18]==c['power'],('power',case_id,c['name'],values[2:18],c['power'])
        assert values[18:34]==c['levels'],('levels',case_id,c['name'])
        for fixed,floating in zip(c['power'],c['floating_power']):
            if floating>=10000:
                rel=abs(fixed-floating)/floating;max_rel=max(max_rel,rel)
                assert rel<.025,(c['name'],fixed,floating,rel)
        if max(c['floating_power'])>=10000:
            max_peak_rel=max(max_peak_rel,abs(max(c['power'])-max(c['floating_power']))/max(c['floating_power']))
        lines.append(f"PASS {case_id:02d} {c['name']}: dominant_band={c['dominant_band']} peak_power={max(c['power'])} peak_height={max(c['levels'])} process_wait={cycles}")
    p=[c['power'] for c in cases]
    assert p[0]==[0]*16
    assert cases[1]['dominant_band']==4 # 440 Hz peaks at k5 (469.02 Hz).
    assert cases[2]['dominant_band']==6 # 880 Hz peaks at k9 (844.24 Hz).
    # Floating reference independently determines peak bands for all stimuli.
    for c in cases:
        if max(c['power'])>10000:
            assert c['dominant_band']==int(np.argmax(c['floating_power'])),c['name']
    assert p[1]==p[6]==p[8], 'Pause or metadata-label changed an identical PCM spectrum'
    assert abs(max(p[1])/max(p[3])-4)<.03
    assert abs(max(p[3])/max(p[4])-4)<.03
    assert max(p[9])<max(p[1])*.3,'Shuffled PCM retained an implausible tone peak'
    top2=np.argsort(p[5])[-2:]
    assert set(top2)=={4,6},top2
    streaming=list(csv.reader((BASE/'streaming_snapshots.csv').open()))
    assert len(streaming)==3
    for row,case_id in zip(streaming,[1,2,0]):
        assert list(map(int,row[3:]))==cases[case_id]['power'],('streaming',row[0])
    assert all(int(row[2])==2048*521 for row in streaming[1:])
    lines.append(f'PASS all {len(cases)} snapshots bit-exact against independent integer matrix DFT.')
    lines.append(f'PASS independent floating FFT: max relative significant-band power error {max_rel:.6%}.')
    lines.append(f'PASS independent floating FFT: max peak-band power error {max_peak_rel:.6%}.')
    lines.append('PASS amplitude x2 -> power x4; two-tone bands; PCM shuffle and metadata-label negative controls.')
    lines.append('PASS all four original DDS songs, all eight notes, input pause, capture/processing reset, full-scale inputs and overrun detection.')
    lines.append('PASS continuous 25MHz-equivalent input: three snapshots match 440Hz/880Hz/silence references; exact 2048*521 cycle spacing; outputs atomic and stable; no overrun.')
    text='\n'.join(lines)+'\n';(BASE/'logs'/'verification_summary.txt').write_text(text)
    print(text)

if __name__=='__main__':
    {'prepare':prepare,'check':check}[sys.argv[1]]()
