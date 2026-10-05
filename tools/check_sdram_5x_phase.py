#!/usr/bin/env python3
"""5:1 CL3 phase abstraction, starting from all legal old controller states.
No whole-core, analog, initialization-sequence or retention claim.
"""
from collections import deque
from itertools import product

def successors(s):
 phase,age,num,read,od,ow,rd,wr,a,b,c,d,diff=s
 rr=rd and not od;ww=wr and not ow
 command=int(not rr and not(ww and not rd) and num%8==2 and read)
 for raw in (0,1):
  nn=num+1 if num<8 else num;nr=0 if num==3 else read
  if ww:nn,nr=5,0
  if rr:
   nr=raw
   if raw:nn=1
  inputs=product((0,1),repeat=2)if phase==0 else [(rd,wr)]
  # At phase2, capture on mem rising, then copy on sys falling half a mem later.
  diffs=(0,)if phase==2 else (0,1)if d else (diff,)
  for (r,w),df in product(inputs,diffs):
   yield ((phase+1)%5,min(16,age+1),nn,nr,rd,wr,r,w,command,a,b,c,df)
initial=[(p,0,n,r,od,ow,rd,wr,a,b,c,d,df)
 for p,n,r,od,ow,rd,wr,a,b,c,d,df in product(range(5),range(9),*((0,1),)*10)]
seen=set(initial);queue=deque(initial);edges=0
while queue:
 s=queue.popleft()
 for n in successors(s):
  edges+=1
  if n not in seen:seen.add(n);queue.append(n)
bad_capture=[s for s in seen if s[-2]and s[0]!=2]
bad_q=[s for s in seen if s[-1]and s[0]==0]
assert max(s[1]for s in bad_capture)==6
assert max(s[1]for s in bad_q)==8
assert not any(s[0]==0 and s[-1] and s[1]>=12 for s in seen)
print(f'PASS 5x CL3 fixed point: {len(seen)} states, {edges} transitions')
print('PASS normal capture phase after >=7 stable mem edges; consuming sys equality after >=12')
print('LIMIT: sys-edge-only requests after lifecycle settles and legal old state are premises')
