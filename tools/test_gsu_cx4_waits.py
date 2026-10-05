#!/usr/bin/env python3
"""Compile actual GSU/CX4 RTL with probe-only ports and behavioral RAM primitives.
No chip datapath/FSM is replaced. Shared transport pinned from sibling dependency
commit only if this independent worktree has not yet integrated that commit.
"""
import argparse, pathlib, re, subprocess, tempfile, os
ROOT=pathlib.Path(__file__).resolve().parents[1]
HELPER='116961d3329e94661caecb46d760456acedd4444'
PROBES={
'GSU': {
 'p_state':('std_logic_vector(2 downto 0)','ROMST'),
 'p_count':('std_logic_vector(2 downto 0)','std_logic_vector(ROM_ACCESS_CNT)'),
 'p_load':('std_logic','ROM_LOAD_END'),
 'p_fetch':('std_logic','ROM_FETCH_END'),
 'p_cachewe':('std_logic','BRAM_CACHE_WE_B'),
 'p_cacheaddr':('std_logic_vector(8 downto 0)','BRAM_CACHE_ADDR_B'),
 'p_cachedata':('std_logic_vector(7 downto 0)','BRAM_CACHE_DI_B'),
 'p_romdr':('std_logic_vector(7 downto 0)','ROMDR'),
 'p_rombuf':('std_logic_vector(7 downto 0)','ROM_BUF'),
 'p_cpu':('std_logic','CPU_EN'),
 'p_r15':('std_logic_vector(15 downto 0)','R(15)'),
 'p_en':('std_logic','EN'),
},
'CX4': {
 'p_cachecount':('std_logic_vector(2 downto 0)','std_logic_vector(CACHE_WAIT_CNT)'),
 'p_cachewe':('std_logic','CACHE_WE'),
 'p_cacheaddr':('std_logic_vector(9 downto 0)','CACHE_ADDR_WR'),
 'p_cachedata':('std_logic_vector(7 downto 0)','CACHE_DI'),
 'p_cacherun':('std_logic','CACHE_RUN'),
 'p_dmacount':('std_logic_vector(15 downto 0)','std_logic_vector(DMA_CNT)'),
 'p_dmastate':('std_logic','DMA_STATE'),
 'p_dmarun':('std_logic','DMA_RUN'),
 'p_dmawait':('std_logic_vector(2 downto 0)','std_logic_vector(DMA_WAIT_CNT)'),
 'p_dmaaddr':('std_logic_vector(23 downto 0)','DMA_SRC_ADDR'),
 'p_ramwe':('std_logic','DATA_RAM_WE_A'),
 'p_ramaddr':('std_logic_vector(11 downto 0)','DATA_RAM_ADDR_A'),
 'p_ramdata':('std_logic_vector(7 downto 0)','DATA_RAM_DI_A'),
 'p_extcount':('std_logic_vector(2 downto 0)','std_logic_vector(BUS_ACCESS_CNT)'),
 'p_ext':('std_logic','ROM_ACCESS'),
 'p_mbr':('std_logic_vector(7 downto 0)','MBR'),
 'p_pc':('std_logic_vector(7 downto 0)','PC'),
 'p_cpu':('std_logic','CPU_EN'),
}}
def instrument(s,chip,name):
 s=re.sub(r'\b'+chip+r'\b',name,s)
 s=s.replace('\tport(', '\tport(\n'+''.join(f'  {n}:out {t};\n' for n,(t,e) in PROBES[chip].items()),1)
 p=s.index('\nbegin\n')+len('\nbegin\n')
 return s[:p]+''.join(f' {n} <= {e};\n' for n,(t,e) in PROBES[chip].items())+s[p:]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--mutation',choices=['gsu-ready','cx4-cache-ready','cx4-finext-ready','cx4-dma-ready']);ap.add_argument('--keep',action='store_true');args=ap.parse_args()
 tmp=tempfile.TemporaryDirectory(prefix='gsu-cx4-waits-');w=pathlib.Path(tmp.name)
 if args.keep:tmp._finalizer.detach();print('workdir',w)
 def ghdl(action,*p,ok=True):
  r=subprocess.run(['ghdl',action,'--std=08','-fsynopsys','--workdir='+str(w),*map(str,p)],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
  if r.returncode and ok:raise RuntimeError(r.stdout)
  return r
 helper=ROOT/'rtl/upstream/chip/SA1/SA1RomBridge.vhd'
 if not helper.exists():
  helper=w/'SA1RomBridge.vhd';helper.write_bytes(subprocess.check_output(['git','show',HELPER+':rtl/upstream/chip/SA1/SA1RomBridge.vhd'],cwd=ROOT))
 ghdl('-a',ROOT/'tests/memory_ready/gsu_cx4_ram_models.vhd',helper,ROOT/'rtl/upstream/chip/GSU/GSU_PKG.vhd')
 for chip in ['GSU','CX4']:
  s=(ROOT/f'rtl/upstream/chip/{chip}/{chip}.vhd').read_text()
  if args.mutation=='gsu-ready' and chip=='GSU':s=s.replace("ROM_ACCESS_CNT = 0 and TX_READY(1)='1'",'ROM_ACCESS_CNT = 0')
  if args.mutation=='cx4-cache-ready' and chip=='CX4':s=s.replace(" and TX_READY(1)='1'",'')
  if args.mutation=='cx4-finext-ready' and chip=='CX4':s=s.replace("or TX_READY(3)='1'","or true")
  if args.mutation=='cx4-dma-ready' and chip=='CX4':s=s.replace("or TX_READY(2)='1'","or true")
  p=w/(chip+'_PROBE.vhd');p.write_text(instrument(s,chip,chip+'_PROBE'));ghdl('-a',p)
  base=subprocess.check_output(['git','show','b63f800:'+f'rtl/upstream/chip/{chip}/{chip}.vhd'],cwd=ROOT,text=True)
  p=w/(chip+'_REF.vhd');p.write_text(instrument(base,chip,chip+'_REF'));ghdl('-a',p)
 # Compile the untouched production entities and mapper wrappers as well;
 # probe-only analysis is not a substitute for verifying the public boundary.
 ghdl('-a',ROOT/'rtl/upstream/CEGen.vhd',ROOT/'rtl/upstream/chip/GSU/GSU.vhd',
      ROOT/'rtl/upstream/chip/CX4/CX4.vhd',ROOT/'rtl/upstream/chip/GSU/GSUMap.vhd',
      ROOT/'rtl/upstream/chip/CX4/CX4Map.vhd')
 ghdl('-e','GSUMap');ghdl('-e','CX4Map')
 for chip in ['gsu','cx4']:
  name='tb_'+chip+'_transaction_waits';source=ROOT/'tests/memory_ready'/f'{name}.vhd'
  if not source.exists():continue
  ghdl('-a',source);ghdl('-e',name)
  r=ghdl('-r',name,'--assert-level=error','--ieee-asserts=disable',ok=not bool(args.mutation))
  print(r.stdout.strip(),flush=True)
  if args.mutation and r.returncode:
   expected={'gsu-ready':'GSU LOAD retired/underflowed without result',
             'cx4-cache-ready':'CX4 cache wrote/advanced before matched data',
             'cx4-finext-ready':'CX4 FINEXT advanced before response',
             'cx4-dma-ready':'CX4 DMA advanced/wrote before matching source'}[args.mutation]
   if expected not in r.stdout:raise RuntimeError('Mutation failed for an unrelated reason: '+r.stdout)
   print('PASS mutation rejected:',args.mutation);return
  if not args.mutation and 'PASS' not in r.stdout:raise RuntimeError('No PASS marker')
 if args.mutation:raise RuntimeError('Mutation survived')
 for chip in ['gsu','cx4']:
  name='tb_'+chip+'_zero_wait_equivalence';ghdl('-a',ROOT/'tests/memory_ready'/f'{name}.vhd');ghdl('-e',name)
  for handshake, latency in [('false',0),('true',0),('true',1),('true',7),('true',31)]:
   r=ghdl('-r',name,'-gHANDSHAKE='+handshake,'-gLATENCY='+str(latency),'--assert-level=error','--ieee-asserts=disable');print(r.stdout.strip(),flush=True)
   if 'PASS' not in r.stdout:raise RuntimeError('No equivalence PASS marker')
 print('PASS actual GSU/CX4 RTL transaction suite')
if __name__=='__main__':main()
