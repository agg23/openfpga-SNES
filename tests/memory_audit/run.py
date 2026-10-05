#!/usr/bin/env python3
"""Independent lifecycle/cache/refresh audit. Does not edit production files.

The END/error fixture intentionally pins the original permissive queue so later
source bounds checks cannot hide a cart lifecycle regression. Other DUT modules
are snapshots of the current checkout. Intel dcfifo is the actual vendor model.
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
HISTORY='3ddde3f'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path)
p.add_argument('--vendor',type=pathlib.Path,default=ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib/altera_mf.v')
a=p.parse_args()
env=os.environ.copy();env['PATH']='/tmp/msu1-tools/bin:'+env.get('PATH','')
results=[]
def cmd(args):
 return subprocess.run(list(map(str,args)),cwd=ROOT,env=env,text=True,capture_output=True,timeout=120)
def git_file(path):
 r=cmd(['git','show',HISTORY+':'+path]);assert r.returncode==0,r.stderr;return r.stdout
with tempfile.TemporaryDirectory(prefix='memory-audit-') as name:
 d=pathlib.Path(name)
 current={}
 hashes={}
 for f in ['sdram_cart_port','sdram_transaction_cdc','sdram_single_request']:
  path=ROOT/'rtl/memory_ready'/f'{f}.sv';text=path.read_text()
  current[f]=d/path.name;current[f].write_text(text)
  hashes[str(path.relative_to(ROOT))]=hashlib.sha256(text.encode()).hexdigest()
 old_cart=d/'old_cart.sv';old_cart.write_text(git_file('rtl/memory_ready/sdram_cart_port.sv'))
 queue=d/'original_queue.sv';queue.write_text(git_file('rtl/memory_ready/rom_download_queue.sv'))
 def sim(top,*,old=False,queue_needed=False,hz=None):
  source=[current['sdram_single_request']]
  if top!='tb_refresh_under_held_response':source += [current['sdram_transaction_cdc'],old_cart if old else current['sdram_cart_port']]
  if queue_needed: source += [queue,a.vendor]
  out=d/(top+str(hz)+str(old))
  compile_args=['iverilog','-g2012','-s',top,'-o',out]
  if hz:compile_args += ['-P'+top+'.PHYSICAL_CLK_HZ='+str(hz)]
  c=cmd(compile_args+source+[ROOT/'tests/memory_audit'/f'{top}.sv'])
  assert c.returncode==0,c.stdout+c.stderr
  r=cmd(['vvp',out]);log=r.stdout+r.stderr
  expect=(r.returncode!=0 and 'AUDIT_REPRO' in log) if old else (r.returncode==0 and 'PASS' in log)
  assert expect,log
  result={'test':top,'historical_negative':old,'physical_hz':hz,'passed':True,'output':log.strip()}
  results.append(result);print(('NEGATIVE DETECTED ' if old else '')+log.strip(),flush=True)
 sim('tb_client_fault_drain_gap',old=True)
 sim('tb_download_error_empty_save',old=True,queue_needed=True)
 sim('tb_client_fault_drain_gap')
 sim('tb_download_error_empty_save',queue_needed=True)
 sim('tb_cache_write_data_audit')
 for hz in (107386350,106406850):sim('tb_refresh_under_held_response',hz=hz)
 evidence={'production_source_sha256':hashes,'pinned_queue_commit':HISTORY,'results':results}
 if a.output:a.output.write_text(json.dumps(evidence,indent=2)+'\n')
print('PASS independent memory audit')
