#!/usr/bin/env python3
"""Source-bound actual SCPU/SWRAM/MSU to physical-pin PSRAM write/read staging checks."""
import argparse,pathlib,os,subprocess,json,hashlib,re,resource
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-read-stage');p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=pathlib.Path(os.environ.get('QUARTUS_SIM_LIB',R.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib')));p.add_argument('--icarus-only',action='store_true',help='Run the four-state CPU/DMA matrix and negative controls without compiling Verilator/HDMA');args=p.parse_args();args.vendor_sim_dir=args.vendor_sim_dir.resolve();O=args.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment();resource.setrlimit(resource.RLIMIT_CORE,(0,0));checks=[]
def run(name,cmd,expect='PASS',negative=False,pair=None):
 q=subprocess.run(list(map(str,cmd)),cwd=R,env=env,text=True,capture_output=True,timeout=180);log=q.stdout+q.stderr;(O/(name+'.log')).write_text(log)
 passed=(q.returncode!=0 and expect in log) if negative else (q.returncode==0 and (expect is None or expect in log))
 row={'name':name,'passed':passed,'negative_control':negative,'returncode':q.returncode,'command':list(map(str,cmd))}
 if 'PASS CPU WRAM' in log:
  row['metrics']=dict(re.findall(r'(\w+)=([^\s]+)',next(l for l in log.splitlines() if l.startswith('PASS CPU WRAM'))))
  row['pin_minimums']=next(l for l in log.splitlines() if l.startswith('PIN '))
 if negative:row['detected_failure']=next((l for l in log.splitlines() if expect in l),'')
 if pair:row['pair']=pair
 checks.append(row);print(('PASS ' if passed else 'FAIL ')+name,flush=True);assert passed,log[-3000:]
 return log
sources=[O/(x+'.v') for x in ['SCPU','SWRAM','SWRAM_PREDECODE','WramMux']]+[R/'target/pocket/psram.sv',R/'target/pocket/wram_write_stage.sv',R/'target/pocket/wram_read_stage.sv',R/'rtl/upstream/chip/MSU1/MSU.sv',R/'tests/wram_timing/tb_wram_cpu.sv']
scenarios=[('normal',[]),('turbo',['+turbo']),('pause',['+inject=1']),('reset_before_stage',['+inject=2']),('reset_after_stage',['+inject=3'])]
try:
 run('source_bound_predecode',['python3',R/'tests/wram_timing/check_predecode.py','--out',O/'predecode-proof'])
 run('synthesize_exact_vhdl',['python3',R/'tests/wram_timing/trace_cpu.py','--out',O],expect=None)
 # Original 42-check coverage is retained; new reverse/phase cases run through
 # the same actual CPU. Each baseline/candidate pair must have equal cycles.
 for pal in [0,1]:
  prefix='pal' if pal else 'ntsc'
  for mode in [0,2]:
   binary=O/(prefix+f'-mode{mode}')
   run(prefix+f'-compile-mode{mode}',['iverilog','-g2012','-s','tb_wram_cpu',f'-Ptb_wram_cpu.MODE={mode}',f'-Ptb_wram_cpu.PAL={pal}','-Ptb_wram_cpu.HAS_HDMA=0','-o',binary,*sources],expect=None)
   cpu_cases=scenarios+[(n+'_reverse',opts+['+reverse']) for n,opts in scenarios]
   cpu_cases += [(f'read_pause_{ticks}', ['+reverse','+turbo','+inject=4',f'+read_pause_ticks={ticks}']) for ticks in range(8,41,4)]
   for name,opts in cpu_cases:run(prefix+f'-4state-mode{mode}-'+name,['vvp',binary,*opts],pair=prefix+'-4state-'+name)
   if not args.icarus_only:
    obj=O/(prefix+f'-obj{mode}');binary=obj/'sim'
    run(prefix+f'-verilator-build-mode{mode}',['verilator','--binary','-j','1','--timing','-Wno-fatal','--top-module','tb_wram_cpu',f'-GMODE={mode}',f'-GPAL={pal}','--Mdir',obj,'-o','sim',*sources],expect=None)
    hdma_cases=scenarios+[('hdma_msu',['+hdma_source=1']),('hdma_wram',['+hdma_source=2']),('hdma_msu_turbo',['+hdma_source=1','+turbo']),('hdma_wram_turbo',['+hdma_source=2','+turbo'])]
    for source in [3,4]:
     for name,opts in scenarios+[('read_pause',['+turbo','+inject=4','+read_pause_ticks=8'])]:
      hdma_cases.append((f'reverse_hdma{source}_'+name,opts+['+reverse',f'+hdma_source={source}']))
    for name,opts in hdma_cases:run(prefix+f'-actual-hdma-mode{mode}-'+name,[binary,*opts],pair=prefix+'-hdma-'+name)
 # Equality of real consuming input values is checked in every simulation.
 # This additional run-level comparison checks no effective-cycle change.
 pairs={}
 for row in checks:
  if 'pair' in row:pairs.setdefault(row['pair'],{})[row['metrics']['mode']]=row['metrics']
 equal_fields=['cycles','r_phases','f_phases','writes','dma','reads','refresh','msu_reads','hdma','reverse_dma','reverse_hdma','read_even','read_odd']
 for name,values in pairs.items():
  assert set(values)=={'0','2'},name
  for key in equal_fields:assert values['0'][key]==values['2'][key],(name,key,values)
 checks.append({'name':'zero_effective_cycle_delta','passed':True,'pairs':len(pairs),'fields':equal_fields})
 print('PASS zero_effective_cycle_delta',flush=True)
 for name,mode,mutate,failure in [('data_only_register',1,False,'WRITE RETIRE DEADLINE'),('unheld_write_address',2,True,'MEMORY MISMATCH')]:
  inputs=sources.copy()
  if mutate:
   text=(R/'target/pocket/wram_write_stage.sv').read_text();anchor='memory_write ? write_address : address';assert text.count(anchor)==1
   mutant=O/'unheld_address.sv';mutant.write_text(text.replace(anchor,'address'));inputs[5]=mutant
  binary=O/name;run(name+'-compile',['iverilog','-g2012','-s','tb_wram_cpu',f'-Ptb_wram_cpu.MODE={mode}','-Ptb_wram_cpu.HAS_HDMA=0','-o',binary,*inputs],expect=None)
  run(name,['vvp',binary],expect=failure,negative=True)
 for name,old,new,failure in [('rising_read_stage','negedge clk_sys','posedge clk_sys','CART B TO A PHASE MISMATCH'),('wrong_read_lane','read_lane <= byte_lane','read_lane <= ~byte_lane','READ RETURN ADDRESS/LANE MISMATCH')]:
  inputs=sources.copy();text=(R/'target/pocket/wram_read_stage.sv').read_text();assert text.count(old)==1
  mutant=O/(name+'.sv');mutant.write_text(text.replace(old,new));inputs[6]=mutant
  binary=O/name;run(name+'-compile',['iverilog','-g2012','-s','tb_wram_cpu','-Ptb_wram_cpu.MODE=2','-Ptb_wram_cpu.HAS_HDMA=0','-o',binary,*inputs],expect=None)
  run(name,['vvp',binary,'+reverse'],expect=failure,negative=True)
 # A severed sideband must be visible to the real-CPU dual-SWRAM check.
 text=(R/'tests/wram_timing/tb_wram_cpu.sv').read_text();start=text.index('SWRAM_PREDECODE predecoded_swram');end=text.index(';',start)
 block=text[start:end];old='.PA_WMDATA(pa_wmdata)';assert block.count(old)==1
 mutant=O/'disconnected_predecode.sv';mutant.write_text(text[:start]+block.replace(old,".PA_WMDATA(1'b0)")+text[end:]);inputs=sources[:-1]+[mutant];binary=O/'disconnected_predecode'
 run('disconnected_predecode-compile',['iverilog','-g2012','-s','tb_wram_cpu','-Ptb_wram_cpu.MODE=2','-Ptb_wram_cpu.HAS_HDMA=0','-o',binary,*inputs],expect=None)
 run('disconnected_predecode',['vvp',binary],expect='SWRAM PREDECODE MISMATCH',negative=True)
 run('spc_half_edge',['python3',R/'tests/wram_timing/check_spc_half_edge.py','--out',O/'spc-phase','--vendor-sim-dir',args.vendor_sim_dir])
finally:
 paths=[R/'rtl/upstream/65C816'/(n+'.vhd') for n in ['P65816_pkg','AddrGen','BCDAdder','AddSubBCD','ALU','MCode','P65C816']]
 paths += [R/p for p in ['rtl/upstream/CPU.vhd','rtl/upstream/SWRAM.vhd','rtl/upstream/SNES.vhd','rtl/upstream/main.v','rtl/mister_top/SNES.sv','target/pocket/psram.sv','target/pocket/wram_write_stage.sv','target/pocket/wram_read_stage.sv','target/pocket/core.qip','rtl/upstream/chip/MSU1/MSU.sv','tests/wram_timing/tb_wram_cpu.sv','tests/wram_timing/trace_cpu.py','tests/wram_timing/check_spc_half_edge.py','tests/wram_timing/run.py','tests/tool_environment.py','tests/wram_timing/check_predecode.py','tests/wram_timing/tb_predecode_4state.vhd']]
 summary={'checks':checks,'sources_sha256':{str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths},'limits':['Native SCPU/SWRAM VHDL translated by GHDL; no replacement CPU',('HDMA matrix NOT RUN (--icarus-only)' if args.icarus_only else 'Verilator HDMA matrix is two-state; four-state Icarus covers CPU/DMA/MSU without HDMA (upstream unreset HDMA flags propagate X after translation)'),'Exact source-extracted SNES selectors, fixture ROM/PPU/SMP inputs, real MSU and psram RTL','Restricted asynchronous pin memory with 70ns access; not vendor model/PCB/PVT or metastability proof','CPU inputs compared at each enabled F phase; exact global cartridge DO at every enabled sys rising edge while B read is active; independently checked reverse WRAM DMA and direct/indirect HDMA; physical repeated-write counts can differ during asynchronous pause/reset, final 128KiB memories and retired bytes match','No complete console/game/hardware run or post-fit timing claim']}
 (O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
