#!/usr/bin/env python3
"""Conventional AR latency model, not a claim about existing client retirement.
Source-derived normal pipeline: ACT=request+1, READ=ACT+2, DQ=ACT+6.
CL3 5:1 output samples on sys falling; consume at next sys rising.
All-bank idle conservatively follows ACT+6(tRAS)+2(tRP). RFC=9 fast clocks.
"""
import math,json

def consume(act):
    capture=act+6
    # Sys falling is at 2.5 modulo5; DQ capture is an integer mem edge.
    falling=5*math.floor((capture+2)/5)+2.5
    assert falling>capture
    return int(falling+2.5)

def isolated(batch=1):
    rows=[]
    for ar in range(-1,2):
        # Previous miss: request=-10, ACT=-9, AP completion=-1.
        assert ar>=-1
        act=max(1,ar+9*batch)
        extra=(consume(act)-10)//5
        rows.append(dict(ar=ar,batch=batch,act=act,read=act+2,
                         capture=act+6,consume=consume(act),extra_sys=extra))
    return rows

def continuous(period,ar_count=256):
    cycle=0;last_ar=-9;deadline=last_ar+period;bank_until=0;rfc_until=0
    pending=dict(request=0,act=None);retire=None;events={};waits=[];ars=[];trace=[]
    while len(ars)<ar_count:
        if retire==cycle:
            wait=(cycle-(pending['request']+10))//5
            waits.append(wait)
            pending=dict(request=cycle,act=None);retire=None
        command=events.pop(cycle,None)
        want_ar=cycle>=deadline-8
        if command:
            assert cycle>=rfc_until,('command during tRFC',cycle,rfc_until)
            assert command=='READ'
        elif want_ar and cycle>=bank_until and cycle>=rfc_until:
            assert cycle<=deadline,('refresh deadline missed',cycle,deadline)
            command='AR';ars.append(cycle);rfc_until=cycle+9
            last_ar=cycle;deadline=last_ar+period
        elif pending['act'] is None and cycle>=pending['request']+1 and not want_ar and cycle>=bank_until and cycle>=rfc_until:
            command='ACT';pending['act']=cycle;bank_until=cycle+8
            events[cycle+2]='READ';retire=consume(cycle)
        if len(ars)<2 and command:trace.append((cycle,command))
        cycle+=1
        assert cycle<ar_count*(period+100)
    assert max(waits)==2,(period,max(waits))
    assert set(waits)<=set([0,2]),set(waits)
    gaps=[b-a for a,b in zip(ars,ars[1:])]
    assert max(gaps)<=period
    return dict(period=period,cycles=cycle,reads_retired=len(waits),refreshes=len(ars),
        extra_sys_values=sorted(set(waits)),max_extra_sys=max(waits),
        ar_gap_min=min(gaps),ar_gap_max=max(gaps),first_ar=ars[:4])

def scpu_restart(period,fall,ready_at=3.5):
    # Replay CPU.vhd's WAIT_CYCLE recurrence, preserving old FF values at edges.
    wait_cycle=0
    for sys in range(1,period*3):
        read_wait=sys<ready_at
        rising=(sys%period)==0
        falling=(sys-fall)%period==0
        if falling and not read_wait and not wait_cycle:
            return dict(period_sys=period,normal_fall=fall,retire=sys,extra_sys=sys-fall)
        if read_wait:wait_cycle=1
        elif rising:wait_cycle=0
    raise AssertionError('restart did not retire')

def main():
    counter=isolated()[0]
    assert counter['consume']==20 and counter['extra_sys']==2
    assert counter['capture']>10  # old no-wait deadline reads stale data
    print('PASS no-wait counterexample:',json.dumps(counter))
    batches={k:isolated(k)for k in range(1,5)}
    assert all(r['extra_sys']==2 for r in batches[1])
    assert all(r['extra_sys']==4 for r in batches[2])
    sparse=[]
    for start in range(-20,2):
        act=max(1,start+9)
        sparse.append((consume(act)-10)//5)
    assert sorted(set(sparse))==[0,1,2]
    result={
      'continuous_ntsc':continuous(838),'continuous_pal':continuous(831),
      'sparse_single_ar_extra_sys':sorted(set(sparse)),
      'consecutive_ar_bounds':{k:[min(r['extra_sys']for r in v),max(r['extra_sys']for r in v)]for k,v in batches.items()},
      'existing_scpu_wait_restart_examples':[scpu_restart(p,d)for p,d in [(4,2),(6,3),(8,5),(12,9),(8,4)]],
      'limits':'memory availability only; real clients require request ownership and an approved wait contract. SCPU examples assume an early wait request, not arbitrary instruction/IRQ/HDMA behavior.'}
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
