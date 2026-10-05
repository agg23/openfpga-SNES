#!/usr/bin/env python3
"""Actual VHDL simulation/synthesis and focused BSX bridge negative controls.

Does not compile BSXMap/DP or assert whole-chip/integration/hardware validation.
Uses separate work libraries so mutations never modify production RTL.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess

ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--out',type=pathlib.Path,default=ROOT/'build/bsx-memory-bridge')
p.add_argument('--baseline',type=pathlib.Path,help='Optional pre-fix bridge to show the bench catches it')
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
if not shutil.which('ghdl'):raise SystemExit('NOT RUN: GHDL unavailable')
rtl=ROOT/'rtl/upstream/chip/BSX/BSXMemoryBridge.vhd'
bench=ROOT/'tests/memory_ready/tb_bsx_memory_bridge.vhd'
checks=[]
sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in (rtl,bench)}
def run(name,cmd,fail=False,signature=None,save=None):
    r=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,timeout=90)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    ok=(r.returncode!=0 if fail else r.returncode==0) and (signature is None or signature in r.stdout+r.stderr)
    checks.append(dict(name=name,passed=ok,command=list(map(str,cmd))))
    if save is not None:save.write_text(r.stdout)
    if not ok:raise RuntimeError(f'{name} failed; see {out/(name+".log")}')
    if signature:print(r.stdout.strip())
def simulate(name,source,fail=False,signature='PASS BSXMemoryBridge'):
    lib=out/name;lib.mkdir(exist_ok=True)
    common=['--std=08','--workdir='+str(lib)]
    run(name+'-analyze',['ghdl','-a',*common,source,bench])
    run(name+'-elaborate',['ghdl','-e',*common,'tb_bsx_memory_bridge'])
    run(name,['ghdl','-r',*common,'tb_bsx_memory_bridge','--assert-level=error'],fail=fail,signature=signature)
try:
    simulate('actual-rtl',rtl)
    run('synthesize-actual-bridge',['ghdl','--synth','--std=08','--out=verilog',rtl,'-e','BSXMemoryBridge'],save=out/'bridge-synth.v')
    if shutil.which('iverilog'):
        run('parse-synthesized-bridge',['iverilog','-g2012','-s','BSXMemoryBridge','-o',out/'bridge-synth',out/'bridge-synth.v'])
    text=rtl.read_text()
    mutations=[
        ('wrong-owner','RSP_OWNER=std_logic_vector(to_unsigned(held_owner,2))','true','IDENTITY_OWNER'),
        ('wrong-tag','RSP_TAG=held_tag','true','IDENTITY_TAG'),
        ('wrong-epoch','RSP_EPOCH=epochs(held_owner)','true','IDENTITY_EPOCH'),
        ('wrong-operation','RSP_WRITE=is_write(held_owner)','true','IDENTITY_OPERATION'),
        ('revoke-held-valid',"phase=OFFER and HARD_RESET_N='1' and", "phase=OFFER and HARD_RESET_N='1' and NEED(held_owner)='1' and",'HELD_VALID'),
        ('drop-committed-flush',"(FLUSH='0' or committed_write(held_owner)='1')", "(FLUSH='0')",'ARBITRATION expected offered owner 2'),
        ('lose-write-error',"if RSP_ERROR='1' then protocol_fault<='1'; end if;",'null;','ERROR_STICKY'),
        ('retire-disabled',"(ENABLE='1' or committed_write(i)='1') and",'','ENABLE_DISABLED'),
        ('dead-response-forward',"have(i)='1' and dead(i)='0' and", "have(i)='1' and",'DEAD_INFLIGHT'),
        ('no-immediate-response',"(phase=INFLIGHT or\n        (phase=OFFER and req_v='1' and REQ_READY='1'))",'(phase=INFLIGHT)','IMMEDIATE'),
        ('reuse-tag','next_tag<=next_tag+1','next_tag<=next_tag','TAG_SEQUENCE'),
        ('block-faulted-commit',"(fault_i='0' or (COMMITTED(i)='1' and WRITES(i)='1'))", "(fault_i='0')",'ARBITRATION expected offered owner 2'),
    ]
    for name,old,new,signature in mutations:
        if text.count(old)!=1:raise AssertionError('mutation target not unique: '+name)
        source=out/(name+'.vhd');source.write_text(text.replace(old,new))
        simulate(name,source,fail=True,signature=signature)
    if a.baseline:
        simulate('unfixed-baseline',a.baseline.resolve(),fail=True,signature='ENABLE_DISABLED')
finally:
    stable=sources=={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in (rtl,bench)}
    checks.append(dict(name='source-stable-during-run',passed=stable))
    (out/'summary.json').write_text(json.dumps(dict(checks=checks,sources_sha256=sources,
        boundaries=['Actual production VHDL bridge simulated with GHDL',
                    'GHDL synthesis and generated Verilog parsing are syntax/elaboration evidence, not native Quartus fit',
                    'Four-slot bridge only; BSXMap/DP/CPU/cart/CDC/engine and hardware require separate integration tests']),indent=2)+'\n')
    if not stable:raise RuntimeError('Bridge/bench changed during run; rerun required')
