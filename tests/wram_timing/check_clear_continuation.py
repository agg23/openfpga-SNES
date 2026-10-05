#!/usr/bin/env python3
"""Pinned production clear barrier + real CPU/C0/C1/WRAM/ARAM pin-level proof."""
import argparse, pathlib, subprocess, os, json, hashlib, re, resource, itertools
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--source-ref',default='1ea7ab129e8f601b3abfa2b79557fec3ae59e723');p.add_argument('--out',type=pathlib.Path,default=R/'build/clear-continuation');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment();resource.setrlimit(resource.RLIMIT_CORE,(0,0));checks=[];matrix=[];hashes={};completed=False
def source(path):
 b=subprocess.check_output(['git','show',a.source_ref+':'+path],cwd=R);hashes[path]=hashlib.sha256(b).hexdigest();return b.decode()
def run(name,cmd,marker=None,negative=False):
 q=subprocess.run(list(map(str,cmd)),cwd=R,env=env,capture_output=True,text=True,timeout=150);log=q.stdout+q.stderr;(O/(name+'.log')).write_text(log)
 good=q.returncode!=0 and marker in log if negative else q.returncode==0 and (marker is None or marker in log)
 row={'name':name,'passed':good,'negative':negative,'returncode':q.returncode}
 if negative:row['failure']=next((l for l in log.splitlines() if marker in l),'')
 if 'PASS CLEAR' in log or 'PASS CPU CLEAR' in log:
  line=next(l for l in log.splitlines() if l.startswith(('PASS CLEAR','PASS CPU CLEAR')));row['metrics']=dict(re.findall(r'(\w+)=([^\s]+)',line));matrix.append(row)
 checks.append(row)
 if not good:raise AssertionError(name+'\n'+log[-3000:])
 if len(checks)%100==0 or negative or not row.get('metrics'):print('PASS',name,flush=True)
 return row
try:
 helper=source('target/pocket/ram_clear_frontier.sv');(O/'ram_clear_frontier.sv').write_text(helper)
 main=source('rtl/mister_top/SNES.sv');n=re.sub(r'\s+','',main)
 anchors=['.RESET_N(USE_STANDARD_SDRAM?(RESET_N&&standard_run_ready&&!reset):RESET_N)',
 '.quiescent(standard_host_quiescent&&!wram_psram_busy&&!aram_psram_busy)',
 'wireblock_ram_clients=USE_STANDARD_SDRAM&&ram_clear_busy;',
 '.soft_reset(core_reset||save_busy||ram_clear_busy)',
 '.write_en(clearing_ram?1\'b1:block_ram_clients?1\'b0:wram_write)',
 '.read_en(clearing_ram||block_ram_clients?1\'b0:~WRAM_CE_N&~WRAM_OE_N)',
 '.write_en(clearing_ram?1\'b1:block_ram_clients?1\'b0:~ARAM_CE_N&~ARAM_WE_N)',
 '.busy(wram_psram_busy)','.busy(aram_psram_busy)']
 for text in anchors:assert text in n,text
 for path in ['target/pocket/psram.sv','target/pocket/wram_write_stage.sv','target/pocket/wram_read_stage.sv','rtl/upstream/CPU.vhd','rtl/upstream/SWRAM.vhd','rtl/upstream/SNES.vhd']:
  b=source(path);assert (R/path).read_text()==b,path+' differs from pinned integration'
 cart=source('rtl/memory_ready/sdram_cart_port.sv');assert 'assign run_ready=!client_flush && !client_fault;' in cart and 'client_flush=soft_reset || download_active' in cart
 checks.append({'name':'pinned_production_wiring','passed':True,'anchors':anchors})
 # Exhaust the 17 real FSM states and every possible old idle offer. BEGIN
 # closes admission after edge zero; pending sees its registered pulse at +4T.
 bounds=[]
 for state0,offer,host_sys in itertools.product(list(range(9))+list(range(20,28)),range(3),range(9)):
  state=state0;busy=state!=0;pending=False;begin=True;finish=-1;start=None
  for t in range(80):
   pre_busy=busy
   if t>=4 and t%4==0:
    if begin:pending=True;begin=False
    elif pending and not pre_busy and t>host_sys*4:start=t;break
   if state==0:
    if t==0 and offer:state=1 if offer==1 else 20;busy=True
    else:busy=False
   elif state in [8,27]:state=0;busy=False;finish=t
   else:state+=1;busy=True
  assert start is not None and start>=8 and finish<=8
  assert start<=max(12,host_sys*4+4),(state0,offer,host_sys,start)
  bounds.append((state0,offer,host_sys,finish,start))
 total=131072*16;last_accept=1+9*((total-1)//9);last_complete=last_accept+8
 assert last_complete-total==1
 # Each byte has an acceptance within 9T of its address becoming visible,
 # completes within 17T; the final barrier keeps clients blocked through +4T.
 max_byte_lateness=max((1+9*((byte*16-1)//9+1)+8)-(byte+1)*16 for byte in range(131072))
 assert max_byte_lateness==1
 bound_result={'states':17,'finite_cases':len(bounds),'old_finish_max_T':max(v[3] for v in bounds),'local_start_max_T':max(v[4] for v in bounds if v[2]==0),'first_clear_accept_T':1,'first_clear_finish_T':9,'full_clear_active_T':total,'last_accept_T':last_accept,'last_complete_T':last_complete,'physical_tail_T':1,'busy_tail_T':4,'maximum_per_byte_lateness_T':max_byte_lateness,'assumptions':['unchanged 8T PSRAM completion, 9T acceptance spacing','coherent running phase-zero 4:1 clocks','standard immediate run_ready reset plus busy admission gates','host_quiescent eventually true; its unbounded wait is not assigned a latency guarantee','no PLL loss, frozen clocks or device/pin fault']}
 (O/'bounds.json').write_text(json.dumps(bound_result,indent=2)+'\n');checks.append({'name':'finite_phase_bounds','passed':True,**bound_result})
 run('actual_vhdl',['python3',R/'tests/wram_timing/trace_cpu.py','--out',O])
 common=[R/'target/pocket/psram.sv',R/'target/pocket/wram_write_stage.sv',R/'target/pocket/wram_read_stage.sv',R/'tests/wram_timing/tb_wram_cpu.sv',O/'ram_clear_frontier.sv']
 for pal in [0,1]:
  exe=O/f'sweep{pal}';cpu=O/f'cpu{pal}'
  run(f'compile_sweep{pal}',['iverilog','-g2012','-s','tb_clear_continuation',f'-Ptb_clear_continuation.PAL={pal}','-o',exe,R/'tests/wram_timing/tb_clear_continuation.sv',*common])
  run(f'compile_cpu{pal}',['iverilog','-g2012','-s','tb_clear_cpu',f'-Ptb_clear_cpu.PAL={pal}','-o',cpu,R/'tests/wram_timing/tb_clear_cpu.sv',*[O/(m+'.v') for m in ['SCPU','SWRAM','WramMux']],*common])
  for kind,akind,phase,alead in itertools.product(range(3),range(3),range(9),range(9)):
   run(f'p{pal}_pair_{kind}_{akind}_{phase}_{alead}',['vvp',exe,f'+kind={kind}',f'+akind={akind}',f'+phase={phase}',f'+alead={alead}'],'PASS CLEAR')
  for phase,addr,delay in itertools.product(range(9),[0,1,256,257],[0,1,3,8]):
   run(f'p{pal}_packet_{phase}_{addr}_{delay}',['vvp',exe,f'+phase={phase}',f'+old_addr={addr}',f'+host_delay={delay}','+akind=2','+alead=4'],'PASS CLEAR')
  for restart in range(1,10):run(f'p{pal}_restart_{restart}',['vvp',exe,f'+restart={restart}','+phase=6','+akind=1','+alead=4'],'PASS CLEAR')
  for turbo,target,cut in itertools.product(range(2),[256,257,4352,4353],[0,1,100]):
   run(f'p{pal}_cpu_{turbo}_{target}_{cut}',['vvp',cpu,f'+turbo={turbo}',f'+target={target}',f'+cut={cut}'],'PASS CPU CLEAR')
  for mode in range(4):
   run(f'p{pal}_full_{mode}',['vvp',exe,'+phase=6','+old_addr=1','+akind=2','+alead=4','+host_delay=7','+full=1',f'+fillmode={mode}',f'+restart={5 if mode>=2 else 0}'],'PASS CLEAR')
 # Mutations preserve the real PSRAM engine and addresses. A failure identifies
 # the missing production obligation, not a substitute CPU or expected stream.
 variants=[('no_tail',helper.replace(' || draining;',';'),['+full=1'],'CLEAR BARRIER RELEASED BEFORE PHYSICAL TAIL'),
 ('ignore_quiescent',helper.replace('if (quiescent) begin clearing','if (1\'b1) begin clearing'),['+host_delay=8'],'CLEAR START WITHOUT HOST QUIESCENT'),
 ('one_sys_zero',helper.replace('clear_addr <= 0; divider <= 0;\n        end else if (pending)', 'clear_addr <= 0; divider <= 3;\n        end else if (pending)'),[],'ZERO BYTE DEADLINE')]
 for name,text,opts,error in variants:
  assert text!=helper,name
  mutated=O/(name+'.sv');mutated.write_text(text);exe=O/name
  run(name+'_compile',['iverilog','-g2012','-s','tb_clear_continuation','-o',exe,R/'tests/wram_timing/tb_clear_continuation.sv',*common[:-1],mutated])
  run(name,['vvp',exe,*opts],error,negative=True)
 text=(R/'tests/wram_timing/tb_clear_continuation.sv').read_text();anchor='wire write_en=active||(staged_write&&!barrier_busy);';assert text.count(anchor)==1
 mutated=O/'ungated_c0.sv';mutated.write_text(text.replace(anchor,'wire write_en=active||staged_write;'));exe=O/'ungated_c0'
 run('ungated_c0_compile',['iverilog','-g2012','-s','tb_clear_continuation','-o',exe,mutated,*common])
 run('ungated_c0',['vvp',exe,'+phase=6'],'OLD ADMISSION TOO LATE',negative=True)
 completed=True
finally:
 paths=['tests/tool_environment.py','tests/wram_timing/check_clear_continuation.py','tests/wram_timing/tb_clear_continuation.sv','tests/wram_timing/tb_clear_cpu.sv','tests/wram_timing/tb_wram_cpu.sv','tests/wram_timing/trace_cpu.py']
 local={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in paths}
 (O/'matrix.json').write_text(json.dumps(matrix,separators=(',',':'))+'\n')
 states=lambda key:sorted({int(r['metrics'][key]) for r in matrix if key in r['metrics']})
 summary={'source_ref':a.source_ref,'production_sha256':hashes,'test_sha256':local,'checks':len(checks),'passed':completed and all(c['passed'] for c in checks),'positive_simulations':len(matrix),'wram_begin_states':states('begin_state'),'aram_begin_states':states('arbegin_state'),'negative_controls':[c for c in checks if c.get('negative')],'matrix_sha256':hashlib.sha256((O/'matrix.json').read_bytes()).hexdigest(),'limits':['actual SCPU/SWRAM use four-state GHDL-to-Icarus; CPU tests cover direct and WMDATA writes, not full console','two actual PSRAM controllers and C0/C1 modules; pin memory is an asynchronous fixture with 70ns read access','global SDRAM host_quiescent modeled by a delayed externally proven signal; no claim of cart/BSX drain reproof','all 128KiB WRAM and aliased 64KiB ARAM bytes checked after each full pass','phase proof assumes clocks continue running at related 4:1; no arbitrary PLL-loss safety','Save credit is synchronous BRAM progress, not PSRAM completion; PSRAM completion is guarded by busy tail']}
 (O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2),flush=True)
