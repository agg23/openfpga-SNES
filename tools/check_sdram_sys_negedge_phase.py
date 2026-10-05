#!/usr/bin/env python3
"""Exhaustive phase/output abstraction; not a whole-core formal proof.

Start from every legal st_num / pending read / RD pipeline / stale-output state.
After a lifecycle event settles, rd0/wr0 may change after sys rising edges only.
DQ equality is nondeterministic at every capture, so no data coincidence can hide
an output-latency failure. See docs/SDRAM-sys-negedge-capture-experiment.md.
"""
from collections import deque
from itertools import product

def successors(s):
    phase, age, num, read, oldrd, oldwr, rd, wr, p0, p1, p2, differs = s
    rr=rd and not oldrd; ww=wr and not oldwr
    command=int(not rr and not(ww and not rd) and num%8==2 and read)
    for raw in (0,1):
        nnum=num+1 if num<8 else num
        nread=0 if num==3 else read
        if ww:nnum,nread=5,0
        if rr:
            nread=raw
            if raw:nnum=1
        inputs=product((0,1),repeat=2) if phase==0 else [(rd,wr)]
        # Actual candidate captures current DQ at phase2, otherwise mem buffer.
        ndiff=(0,) if phase==2 else (0,1) if p2 else (differs,)
        for (nr,nw),d in product(inputs,ndiff):
            yield ((phase+1)%4,min(16,age+1),nnum,nread,rd,wr,nr,nw,command,p0,p1,d)

initial=[(p,0,num,r,od,ow,rd,wr,a,b,c,d)
    for p,num,r,od,ow,rd,wr,a,b,c,d in
    product(range(4),range(9),*((0,1),)*9)]
seen=set(initial);queue=deque(initial);edges=0
while queue:
    s=queue.popleft()
    for n in successors(s):
        edges+=1
        if n not in seen:seen.add(n);queue.append(n)
bad_capture=[s for s in seen if s[-2] and s[0]!=2]
bad_live=[s for s in seen if s[0]==0 and s[-1]]
assert max(s[1] for s in bad_capture)==5
last_bad=max(s[1] for s in bad_live)
assert last_bad < 12, last_bad
assert not any(s[0]==0 and s[1]>=12 and s[-1] for s in seen)
print(f'PASS arbitrary-legal-state fixed point: {len(seen)} states, {edges} transitions')
print('PASS capture phase2 after >=6 stable normal memory edges')
print(f'PASS sys-edge output equality after >=12 stable normal edges; last potential mismatch age={last_bad}')
print('Guard actual RTL includes 2-domain reset release, 6mem warm, 2sys ready sync, 4sys release')
print('LIMIT: legal locked 4:1 clock relationship and source-event coverage are premises; no analog/SDRAM-content proof')
