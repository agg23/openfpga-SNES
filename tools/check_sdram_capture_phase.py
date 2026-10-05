#!/usr/bin/env python3
"""Exhaustive finite-state phase abstraction of Pocket-connected sdram.sv.
Assumes locked 4:1 clocks and rd0/wr0 changes only AFTER phase-0 edges.
Port1, SNI and rfs1 are tied off, matching MAIN_SNES. raw_req_test is deliberately
nondeterministic each edge (over-approximation). No claim of full-core formal proof.
State fields: phase, normal_age, st_num, read0, old_rd, old_wr, rd, wr, RD pipeline.
"""
from collections import deque
from itertools import product

def successors(s, allow_async_gate=False):
    phase,age,num,read,oldrd,oldwr,rd,wr,p0,p1,p2=s
    rr=rd and not oldrd; ww=wr and not oldwr
    # sdram.sv state[0] priority: rd0 edge, wr0 edge, then st_num cases.
    command=int(not rr and not (ww and not rd) and num%8==2 and read)
    for raw in (0,1):
        nnum=num+1 if num<8 else num
        nread=0 if num==3 else read
        # Original always-block ordering: regular wr0 before regular rd0.
        if ww:nnum,nread=5,0
        if rr:
            nread=raw
            if raw:nnum=1
        next_inputs=product((0,1),repeat=2) if phase==0 or allow_async_gate else [(rd,wr)]
        for nr,nw in next_inputs:
            yield ((phase+1)%4,min(8,age+1),nnum,nread,rd,wr,nr,nw,command,p0,p1),(raw,nr,nw)

# The first normal edge may see a pre-existing held request: old_rd/old_wr are
# not sampled in !init_done. Include all possible initial values/ending phases.
initial=[(p,0,8,0,od,ow,rd,wr,0,0,0) for p,od,ow,rd,wr in product(range(4),(0,1),(0,1),(0,1),(0,1))]
seen=set(initial);queue=deque(initial);pred={s:None for s in initial}
bad=[];edges=0
while queue:
    s=queue.popleft()
    if s[-1] and s[0]!=2:bad.append(s)
    for n,choice in successors(s):
        edges+=1
        if n not in seen:seen.add(n);queue.append(n);pred[n]=(s,choice)
assert bad, 'Expected startup counterexample missing'
max_bad_age=max(s[1] for s in bad)
assert max_bad_age==5,(max_bad_age,bad[:3])
assert not any(s[-1] and s[0]!=2 and s[1]>=6 for s in seen)
print(f'PASS exhaustive fixed-point check: {len(seen)} states, {edges} transitions')
print(f'PASS warm invariant: every data capture after >=6 completed normal edges is phase2')
print(f'Found {len(bad)} startup violating states; latest has normal_age={max_bad_age}')
s=next(s for s in bad if s[0]==1)
path=[]
while pred[s] is not None:
    path.append(s);s,_=pred[s]
path.append(s)
print('COUNTEREXAMPLE (held request when init_done became true):')
print('phase age st_num read oldrd oldwr rd wr pipe1 pipe2 pipe3')
for s in reversed(path):print(*s)
print('LIMIT: source changes at sys edge and reset/lock/consumer safety require whole-core proof.')

# Re-establishing a stable clock phase after a pause/relock is a different case:
# init_done may already be true, and pre-existing controller/pipeline state need
# not have the new phase. Over-approximate EVERY legal st_num value and pipeline
# bit combination, rather than assuming a fresh initialization. Illegal state
# corruption (e.g. st_num=10) is explicitly outside this functional model.
initial_any=[(p,0,num,r,od,ow,rd,wr,a,b,c)
             for p,num,r,od,ow,rd,wr,a,b,c in product(range(4),range(9),(0,1),(0,1),(0,1),(0,1),(0,1),(0,1),(0,1),(0,1))]
seen_any=set(initial_any);queue=deque(initial_any);edges_any=0
while queue:
    s=queue.popleft()
    for n,_ in successors(s):
        edges_any+=1
        if n not in seen_any:seen_any.add(n);queue.append(n)
bad_any=[s for s in seen_any if s[-1] and s[0]!=2]
max_any_age=max(s[1] for s in bad_any)
assert max_any_age==5,max_any_age
print(f'PASS arbitrary-legal-state fixed point: {len(seen_any)} states, {edges_any} transitions')
print('PASS phase2 capture after >=6 stable normal edges, even with old pipeline contents')
print('LIMIT: this does not prove consumers are held inactive for those six edges after relock.')

# Real top-level boundary: cart_download is driven by clk_74a, and directly
# gates rd0. Model ONE falling gate edge while a client/RFSH read is held high.
# The controller is already warm and idle; no init/reset exception is involved.
s=(0,8,8,0,0,0,0,0,0,0,0)
host_trace=[s]
download=1
for edge in range(12):
    if s[0]==1 and download:
        download=0  # asynchronous host-gate fall immediately after this edge
    desired_rd=1-download
    s=next(n for n,(raw,nr,nw) in successors(s,allow_async_gate=True)
           if raw==1 and nr==desired_rd and nw==0)
    host_trace.append(s)
    if s[-1]:break
assert s[1]==8 and s[0]==3,s
print('PASS warm host-gate counterexample: cart_download fall after phase1 gives phase3 capture')
print('phase age st_num read oldrd oldwr rd wr pipe1 pipe2 pipe3')
for s in host_trace:print(*s)
print('LIMIT: real top-level host gating violates the system-edge-only premise; reset/clearing masking is NOT proved.')
