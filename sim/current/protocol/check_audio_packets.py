"""Independent packet interpretation, not access to protected IP internals.

Wire format cross-reference (primary implementation, HDMI section citations):
https://github.com/hdl-util/hdmi/blob/master/src/audio_sample_packet.sv
https://github.com/hdl-util/hdmi/blob/master/src/audio_clock_regeneration_packet.sv
No third-party RTL is incorporated in the FPGA.
"""
from pathlib import Path
import json,sys,collections
root=Path(__file__).resolve().parent;folder=root/(sys.argv[2] if len(sys.argv)>2 else'protocol_final')
fault=sys.argv[1] if len(sys.argv)>1 else'NONE'
packets=json.loads((folder/'decoded_packets.json').read_text())
pcm=[(int(v[0]),int(v[1],16),int(v[2],16),int(v[3]),int(v[4])) for line in (folder/'pcm_input.txt').read_text().splitlines() if (v:=line.split())]
acr_in=[list(map(int,line.split())) for line in (folder/'acr_input.txt').read_text().splitlines()]
stereo=[];acr=[];counts=collections.Counter();modified=False;parity_checks=0
try:
    for p in packets:
        hb=p['header'];counts[hb[0]]+=1
        if hb[0]==1:
            values=[]
            for s in p['sub']:
                b=[(s>>(8*i))&255 for i in range(7)]
                values.append((((b[4]&15)<<16)|(b[5]<<8)|b[6],((b[1]&15)<<16)|(b[2]<<8)|b[3]))
            assert len(set(values))==1,'ACR subpackets inconsistent'
            n,cts=values[0]
            if fault=='CTS'and not modified and cts:
                cts+=200;modified=True
            assert n==6144 and 74205<=cts<=74210,('ACR N/CTS',n,cts,p['cycle'])
            acr.append((p['cycle'],n,cts))
        elif hb[0]==2:
            assert not(hb[1]&16),'unsupported audio layout1'
            for i,s in enumerate(p['sub']):
                if hb[1]&(1<<i):
                    meta=(s>>48)&255
                    assert ((s&0xffffff).bit_count()+(meta&7).bit_count())%2==((meta>>3)&1),'left IEC60958 parity'
                    assert (((s>>24)&0xffffff).bit_count()+((meta>>4)&7).bit_count())%2==((meta>>7)&1),'right IEC60958 parity'
                    parity_checks+=2
                    pair=(s&0xffffff,(s>>24)&0xffffff)
                    if fault=='PCM'and not modified and len(stereo)>100:
                        pair=(pair[0]^1,pair[1]);modified=True
                    stereo.append(pair)
    assert len(acr)>40 and len(stereo)>3000,('packet coverage',len(acr),len(stereo))
    expected=[(p[1],p[2])for p in pcm]
    offsets=[i for i in range(65)if i+len(stereo)<=len(expected) and stereo==expected[i:i+len(stereo)]]
    if not offsets:
        candidates=[i for i in range(65)if stereo[:16]==expected[i:i+16]]
        best=min(candidates,key=lambda i:sum(a!=b for a,b in zip(stereo,expected[i:])))if candidates else 0
        mismatch=next(((j,a,b)for j,(a,b)in enumerate(zip(stereo,expected[best:]))if a!=b),None)
        raise AssertionError(('HDMI PCM ordering/value',len(stereo),len(expected),best,mismatch))
    offset=offsets[0];tail=len(expected)-offset-len(stereo)
    assert tail<64,('undrained PCM tail',tail)
    songs={p[3]for p in pcm};assert songs=={0,1,2,3},('melody transport coverage',songs)
    periods=[pcm[i+1][0]-pcm[i][0]for i in range(20,len(pcm)-1)]
    mean_period=sum(periods)/len(periods);fs_input=74_250_000/mean_period
    mean_cts=sum(v[2]for v in acr)/len(acr);fs_reconstructed=74_250_000*6144/(128*mean_cts)
    assert abs(fs_input-fs_reconstructed)/fs_input<0.00005,('ACR reconstructed rate',fs_input,fs_reconstructed)
    result={'Passed':True,'PacketTypes':dict(counts),'AudioSamples':len(stereo),'InputPCM':len(pcm),
        'StartupDiscard':offset,'TailPending':tail,'ACRPackets':len(acr),'N':6144,'CTSRange':[min(v[2]for v in acr),max(v[2]for v in acr)],
        'InputSampleRateHz':fs_input,'ReconstructedSampleRateHz':fs_reconstructed,'OriginalPLLSampleRateHz':750_000_000/(61*256),
        'Nominal48kErrorPPM':(fs_input/48000-1)*1e6,'AllFourMelodiesTransported':True,'IEC60958ParityChecks':parity_checks}
    if fault!='NONE':raise AssertionError('fault checker incorrectly accepted')
    (folder/'audio_checker_NONE.json').write_text(json.dumps(result,indent=2));print('AUDIO720_PACKET_TEST_PASS',json.dumps(result))
except AssertionError as ex:
    result={'Passed':False,'Fault':fault,'Reason':str(ex),'Modified':modified,'PacketTypes':dict(counts)}
    (folder/f'audio_checker_{fault}.json').write_text(json.dumps(result,indent=2))
    print('AUDIO720_PACKET_CHECKER_REJECT',str(ex))
    if fault=='NONE' or not modified:raise SystemExit(1)
