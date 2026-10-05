#!/usr/bin/env python3
"""Command-slot feasibility only, not a DRAM cell-retention/physical RTL proof.
Foreground: 5:1 aligned strobes, min 2sys between requests, arbitrary bank/row.
Background: ACT at phase4 every 10mem; bank-specific PRE six edges later.
Copy flips occur at sys boundaries only when every physical bank is idle.
"""
import argparse,random,json

def simulate(rows=8192,epochs=4,pattern='continuous0-bank0',negative=None):
    actbg_phase=3 if negative=='collision' else 4
    ras_bg=5 if negative=='short-ras' else 6
    busy=[0]*4;opened=[None]*4;lastact=[-100]*4;last_global=-100
    lastpre=[-100]*4;pending={};restored={};latest={};maxgap=0
    copy=0;bgindex=0;scan_done=False;flips=0;last_req=-100;reads=0
    events=[];rng=random.Random(971);cycle=0
    while flips<epochs:
        commands=[]
        if cycle%5==0:
            if scan_done and max(busy)<=cycle and all(x is None for x in opened):
                copy ^= 1;bgindex=0;scan_done=False;flips+=1
                events.append(('flip',cycle,copy))
            sys=cycle//5
            request=(sys%2==0 if pattern.startswith('continuous0') else sys%2==1 if pattern.startswith('continuous1') else rng.randrange(3)!=0)
            if request and cycle-last_req>=10:
                bank=copy*2+(int(pattern[-1]) if pattern!='random' else rng.randrange(2))
                row=(reads*941)%rows
                pending.setdefault(cycle+1,[]).append(('ACT',bank,row,'foreground'))
                pending.setdefault(cycle+3,[]).append(('READ_AP',bank,row,'foreground'))
                last_req=cycle;reads+=1
        commands+=pending.pop(cycle,[])
        if cycle%10==actbg_phase and not scan_done:
            bank=(1-copy)*2+(bgindex//rows);row=bgindex%rows
            commands.append(('ACT',bank,row,'background'))
            pending.setdefault(cycle+ras_bg,[]).append(('PRE',bank,row,'background'))
            bgindex+=1
            if bgindex==rows*2:scan_done=True
        assert len(commands)<=1,('command collision',cycle,commands)
        for cmd,b,r,who in commands:
            if cmd=='ACT':
                assert busy[b]<=cycle and opened[b] is None,('bank not idle',cycle,b,busy,opened)
                assert cycle-last_global>=2,('tRRD',cycle,last_global)
                assert cycle-lastact[b]>=7,('tRC',cycle,lastact[b])
                assert cycle-lastpre[b]>=2,('tRP',cycle,lastpre[b])
                lastact[b]=last_global=cycle;opened[b]=(r,who);busy[b]=cycle+8
            elif cmd=='READ_AP':
                assert opened[b]==(r,'foreground')
                assert cycle-lastact[b]>=2,('tRCD',cycle,lastact[b])
                # Conservative integer-cycle auto-precharge completion:
                # ACT + ceil(48ns/T)=6 + ceil(18ns/T)=2.
                pending.setdefault(lastact[b]+6,[]).append(('AUTO_PRE',b,r,who))
            elif cmd in ('PRE','AUTO_PRE'):
                assert opened[b] is not None
                assert cycle-lastact[b]>=6,('tRAS',cycle,lastact[b])
                # AUTO_PRE is internal, not an external command-bus consumer.
                opened[b]=None;lastpre[b]=cycle;busy[b]=cycle+2
                if who=='background':
                    key=(b,r);restored[key]=restored.get(key,0)+1
                    if key in latest:maxgap=max(maxgap,cycle-latest[key])
                    latest[key]=cycle
        cycle+=1
        # Internal AP event must not occupy an external command slot.
        internal=[e for e in pending.get(cycle,[]) if e[0]=='AUTO_PRE']
        if internal:
            pending[cycle]=[e for e in pending[cycle] if e[0]!='AUTO_PRE']
            for _,b,r,who in internal:
                assert opened[b]==(r,who)
                assert cycle-lastact[b]>=6
                opened[b]=None;lastpre[b]=cycle;busy[b]=cycle+2
        assert cycle<epochs*(rows*2*10+100),('progress timeout',cycle)
    assert len(restored)==4*rows,('row coverage',len(restored),rows)
    return dict(pattern=pattern,cycles=cycle,reads=reads,role_flips=flips,
                restored_rows=len(restored),max_observed_row_gap_cycles=maxgap,
                last_flips=events[-4:],ntsc_runtime_ms=cycle*9.312170494667154/1e6,
                pal_runtime_ms=cycle*9.397891207192018/1e6)

def main():
    p=argparse.ArgumentParser();p.add_argument('--rows',type=int,default=8192);a=p.parse_args()
    results=[simulate(a.rows,pattern=k)for k in ['continuous0-bank0','continuous0-bank1','continuous1-bank0','continuous1-bank1','random']]
    for mut,expected in [('collision','command collision'),('short-ras','tRAS')]:
        try:simulate(4,pattern='continuous0-bank0',negative=mut)
        except AssertionError as e:
            assert expected in str(e),(mut,e)
            print('PASS negative',mut,str(e))
        else:raise AssertionError('negative escaped '+mut)
    print(json.dumps(results,indent=2))
    print('LIMIT: ACT/PRE retention equivalence on AS4C32M16MSA is not guaranteed by this scheduling model')
if __name__=='__main__':main()
