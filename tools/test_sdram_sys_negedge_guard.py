#!/usr/bin/env python3
"""Exercise real optional SDRAM RTL and the real Pocket lifecycle guard.
Models arbitrary incoming DQ, not an external SDRAM electrical timing model.
"""
import argparse, pathlib, shutil, subprocess, sys
from test_sdram_early_equivalence import normalize_dq
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',default='build/sdram-sys-negedge-guard')
 p.add_argument('--negative-control',choices=['late-capture','miss-async-reset'])
 a=p.parse_args();out=(ROOT/a.output).resolve();out.mkdir(parents=True,exist_ok=True)
 if not shutil.which('verilator'):p.error('verilator is required')
 s=(ROOT/'rtl/upstream/sdram.sv').read_text()
 g=(ROOT/'target/pocket/pocket_sdram_lifecycle_guard.sv').read_text()
 if a.negative_control=='late-capture':
  old='if (early_bank0) sys_dq0 <= SDRAM_DQ;';assert s.count(old)==1
  s=s.replace(old,'if (early_bank0) sys_dq0 <= dout_buf[0];')
 if a.negative_control=='miss-async-reset':
  old='always @(posedge sys_clk or posedge reset_request)';assert g.count(old)==1
  g=g.replace(old,'always @(posedge sys_clk)')
 (out/'sdram.sv').write_text(normalize_dq(s));(out/'guard.sv').write_text(g)
 command=['verilator','--binary','--timing','--assert','-j','1','-Wno-fatal','--top-module','tb','--Mdir',str(out/'obj'),str(ROOT/'tests/timing/tb_sdram_sys_negedge_guard.sv'),str(out/'sdram.sv'),str(out/'guard.sv')]
 build=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (out/'compile.log').write_text(build.stdout)
 if build.returncode:print(build.stdout);return build.returncode
 run=subprocess.run([str(out/'obj/Vtb')],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
 (out/'simulation.log').write_text(run.stdout);print(run.stdout,end='')
 if a.negative_control:
  expected='earliest two-system-cycle result mismatch' if a.negative_control=='late-capture' else 'short pulse did not assert reset immediately'
  caught=run.returncode!=0 and expected in run.stdout
  print('PASS negative control rejected '+a.negative_control if caught else 'FAIL negative control assertion did not match')
  return 0 if caught else 1
 return run.returncode
if __name__=='__main__':sys.exit(main())
