#!/usr/bin/env python3
"""Actual DATAPAK RTL regressions; never shorten the production erase counters."""
import argparse,pathlib,re,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--mutation',choices=['read-ready','erase-ready','program-and','busy-guard','final-byte']);ap.add_argument('--scenario',type=int,choices=range(4));args=ap.parse_args()
 with tempfile.TemporaryDirectory(prefix='bsx-datapak-') as d:
  w=pathlib.Path(d)
  def run(action,*p,check=True):
   r=subprocess.run(['ghdl',action,'--std=08','--workdir='+str(w),*map(str,p)],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
   if check and r.returncode:raise RuntimeError(r.stdout)
   return r
  src=(ROOT/'rtl/upstream/chip/BSX/BSX_DP.vhd').read_text()
  if args.mutation=='read-ready':src=src.replace("(FS = FS_IDLE or MEM_READY = '1')", "(FS = FS_IDLE or FS = FS_READ or MEM_READY = '1')")
  if args.mutation=='erase-ready':src=src.replace("(FS = FS_IDLE or MEM_READY = '1')", "(FS = FS_IDLE or FS = FS_ERASE or MEM_READY = '1')")
  if args.mutation=='program-and':src=src.replace('WRITE_DATA <= WRITE_DATA and MEM_DI;','WRITE_DATA <= MEM_DI;')
  if args.mutation=='busy-guard':src=src.replace("(WRITE_PEND = '0' and CHIP_ERASE_PEND = '0')",'true')
  if args.mutation=='final-byte':src=src.replace('WRITE_ADDR(15 downto 0) = x"FFFF"','WRITE_ADDR(15 downto 0) = x"FFFE"')
  f=w/'BSX_DP.vhd';f.write_text(src);run('-a',f)
  ref=subprocess.check_output(['git','show','b63f800:rtl/upstream/chip/BSX/BSX_DP.vhd'],cwd=ROOT,text=True)
  f=w/'BSX_DP_ref.vhd';f.write_text(re.sub(r'\bDATAPAK\b','DATAPAK_REF',ref));run('-a',f)
  run('-a',ROOT/'tests/memory_ready/tb_bsx_datapak_waits.vhd',ROOT/'tests/memory_ready/tb_bsx_datapak_legacy.vhd')
  scenarios=[args.scenario] if args.scenario is not None else [0,1,2,3]
  for scenario in scenarios:
   name='tb_bsx_datapak_legacy' if scenario==3 else 'tb_bsx_datapak_waits'
   run('-e',name)
   opts=[] if scenario==3 else ['-gSCENARIO='+str(scenario)]
   r=run('-r',name,*opts,'--assert-level=error','--ieee-asserts=disable',check=not bool(args.mutation))
   print(r.stdout.strip(),flush=True)
   if args.mutation and r.returncode:
    expected={'read-ready':'DATAPAK request changed before matched completion',
              'erase-ready':'DATAPAK request changed before matched completion',
              'program-and':'DATAPAK program old AND new mismatch',
              'busy-guard':'DATAPAK request changed before matched completion',
              'final-byte':'DATAPAK erase ended before full length'}[args.mutation]
    if expected not in r.stdout:raise RuntimeError('Unexpected mutation failure: '+r.stdout)
    print('PASS mutation rejected:',args.mutation);return
   if 'PASS' not in r.stdout:raise RuntimeError('Missing PASS result')
  if args.mutation:raise RuntimeError('Mutation survived')
 print('PASS complete actual DATAPAK suite')
if __name__=='__main__':main()
