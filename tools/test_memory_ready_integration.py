#!/usr/bin/env python3
"""Run new source-backed transaction integration evidence, separately from prototype tests."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--engine', type=pathlib.Path, default=ROOT/'rtl/memory_ready/sdram_single_request.sv')
parser.add_argument('--out', type=pathlib.Path, default=ROOT/'build/memory-ready-integration')
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
for tool in ['iverilog','vvp','ghdl']:
    if not shutil.which(tool):
        raise SystemExit(f'NOT RUN: required tool {tool} is unavailable')
if not args.engine.is_file():
    raise SystemExit('NOT RUN: engine source has not been integrated; supply --engine for an explicit source-only worker test')
checks=[]
def run(name, command, expected=None, stdout_path=None):
    result = subprocess.run(list(map(str,command)), cwd=ROOT, text=True, capture_output=True, timeout=120)
    (out/(name+'.log')).write_text(result.stdout+result.stderr)
    if stdout_path is not None:
        stdout_path.write_text(result.stdout)
    ok=result.returncode==0 and (expected is None or expected in result.stdout)
    checks.append({'name':name,'passed':ok,'command':list(map(str,command))})
    if not ok:
        raise RuntimeError(f'{name} failed; see {out/(name+".log")}')
    if expected: print(result.stdout.strip())
parts=['P65816_pkg','AddrGen','BCDAdder','AddSubBCD','ALU','MCode','P65C816']
scpu=[ROOT/'rtl/upstream/65C816'/(name+'.vhd') for name in parts]+[ROOT/'rtl/upstream/CPU.vhd']
rtl=[ROOT/'rtl/memory_ready/sdram_transaction_cdc.sv',ROOT/'rtl/memory_ready/sdram_cart_port.sv',args.engine.resolve()]
bench_names=['tb_sdram_cart_port','tb_sdram_cart_cache','tb_sdram_posted_drain','tb_sdram_client_fault','tb_sdram_download_throughput','tb_scpu_rom_transaction','tb_scpu_rom_chain']
try:
    run('synthesize-actual-scpu',['ghdl','--synth','--std=08','-fsynopsys','--latches','--out=verilog',*scpu,'-e','SCPU'],stdout_path=out/'scpu.v')
    for name in bench_names:
        bench=ROOT/'tests/memory_ready'/(name+'.sv')
        sources=rtl if not name.startswith('tb_scpu_') else [out/'scpu.v',ROOT/'rtl/memory_ready/snes_rom_client.sv'] + (rtl if name=='tb_scpu_rom_chain' else [])
        run('compile-'+name,['iverilog','-g2012','-s',name,'-o',out/name,*sources,bench])
        run('simulate-'+name,['vvp',out/name],expected='PASS')
        if name=='tb_scpu_rom_chain':
            for suffix,parameters in [
                ('immediate-rom',['USE_TRANSPORT=0']),
                ('uncached-unforwarded',['READ_CACHE=0','FORWARD_RESPONSE=0']),
                ('uncached-forwarded',['READ_CACHE=0'])]:
                binary=out/(name+'-'+suffix)
                run('compile-'+name+'-'+suffix,['iverilog','-g2012','-s',name,
                    *['-P'+name+'.'+p for p in parameters],'-o',binary,*sources,bench])
                run('simulate-'+name+'-'+suffix,['vvp',binary],expected='PASS')
finally:
    sources=list(dict.fromkeys(scpu+rtl+[ROOT/'rtl/memory_ready/snes_rom_client.sv']+
                               [ROOT/'tests/memory_ready'/(name+'.sv') for name in bench_names]))
    manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources if p.is_file()}
    (out/'summary.json').write_text(json.dumps({'checks':checks,'sources_sha256':manifest,
      'boundaries':['Actual production SCPU translated by GHDL, --latches retains pre-existing inferred latches',
                    'Actual new SDRAM engine and CDC/cart-port tested together with behavioral DQ source',
                    'SCPU test uses a variable-latency tagged memory responder',
                    'Full mixed-language SNES/chip integration, synthesis/fit/STA and Pocket hardware NOT RUN here']},indent=2)+'\n')
