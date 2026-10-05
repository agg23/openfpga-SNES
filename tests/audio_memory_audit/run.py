#!/usr/bin/env python3
"""Audio/memory isolation audit. New files/output stay in this audit directory."""
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess,tempfile,time
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[1]
def compact(s):return re.sub(r'\s','',re.sub(r'//[^\n]*','',s))
def source_contract():
 top=(ROOT/'target/pocket/core_top.sv').read_text();main=(ROOT/'rtl/upstream/main.v').read_text();wrapper=(ROOT/'rtl/mister_top/SNES.sv').read_text()
 pocket=(ROOT/'rtl/msu1/msu_pocket.sv').read_text();cart=(ROOT/'rtl/memory_ready/sdram_cart_port.sv').read_text();snes=(ROOT/'rtl/upstream/SNES.vhd').read_text()
 required=[(top,'.sys_clk(clk_sys_21_48),.host_clk(clk_74a),.reset(!pll_core_locked)'),
 (top,'.clk_74a(clk_74a),.clk_audio(clk_sys_21_48)'),
 (top,'.CLK_RATE(PAL_PLL ? 21281370 : 21477270)'),
 (top,'.ioctl_download(ioctl_image_busy)'),
 (top,'.core_reset(~pll_core_locked || reset_button_s || msu_init_busy || (USE_STANDARD_SDRAM && (!ioctl_config_valid || host_reset_s)))'),
 (wrapper,'.soft_reset(core_reset || save_busy || ram_clear_busy)'),
 (main,'.enable(1),.bus_wait(MSU_BUS_WAIT | CART_READ_WAIT)'),
 (pocket,'wire lifecycle_reset=soft_reset||init_busy;'),
 (pocket,'wire pcm_reset=sys_reset||lifecycle_reset||pcm_drain;'),
 (pocket,'.clk(sys_clk),.reset(pcm_reset)'),
 (wrapper,'assign msu_soft_reset = ~RESET_N;'),(wrapper,'.ACLK(clk_sys)'),
 (cart,'assign run_ready=!client_flush && !client_fault;'),
 (snes,'DSP_EN <= ENABLE and not (SS_BUSY and SPC_S0);')]
 for body,fragment in required:
  if compact(fragment) not in compact(body):raise AssertionError('Audio isolation wiring changed: '+fragment)
 guard=re.search(r'msu_init_guard\s+msu_bootstrap_guard\s*\((.*?)\);',top,re.S)
 if not guard or '.ioctl_download(ioctl_download)' not in compact(guard[1]):raise AssertionError('MSU bootstrap guard source clock domain changed')
 for name in ['msu_pocket.sv','msu_pcm_player.sv','msu_block_cdc.sv','msu_pocket_host.sv','msu_mount_cdc.sv']:
  path='rtl/msu1/'+name
  if (ROOT/path).read_bytes()!=subprocess.check_output(['git','show','b63f800:'+path],cwd=ROOT):raise AssertionError('MSU source changed from preserved prototype: '+path)
 for path in ['target/pocket/sound_i2s.sv','target/pocket/sync_fifo.sv']:
  if (ROOT/path).read_bytes()!=subprocess.check_output(['git','show','b63f800:'+path],cwd=ROOT):raise AssertionError('I2S path changed: '+path)
 for family in ['mf_pllbase','mf_pllbase_pal']:
  old=(ROOT/f'target/pocket/{family}/{family}_0002.v').read_text();new=(ROOT/f'target/pocket/{family}_sdram/{family}_sdram_0002.v').read_text()
  for index in range(4):
   pat=rf'\.output_clock_frequency{index}\("([^"]+)"\)'
   if re.search(pat,old)[1]!=re.search(pat,new)[1]:raise AssertionError('Base clock changed '+family+':'+str(index))
   for key in ['phase_shift','duty_cycle']:
    pat=rf'\.{key}{index}\(([^)]+)\)'
    if re.search(pat,old)[1]!=re.search(pat,new)[1]:raise AssertionError('Base clock phase/duty changed '+family+':'+str(index))
 flush=re.search(r'assign client_flush=(.*?);',cart,re.S)[1]
 if any(re.search(r'\b'+p+r'\b',flush) for p in ['req_valid','req_ready','bridge_req_ready','transport_idle','rsp_valid']):raise AssertionError('Ordinary transport backpressure leaks into lifecycle flush')
 # Extract balanced named-port expressions, then require the reviewed lifecycle
 # predicates exactly. Merely finding signal names would miss added wait terms.
 def port(text,name):
  hits=list(re.finditer(r'\.'+name+r'\s*\(',text))
  if len(hits)!=1:raise AssertionError('Expected exactly one source port '+name)
  start=hits[0].end();depth=1
  for end in range(start,len(text)):
   if text[end]=='(':depth+=1
   elif text[end]==')':
    depth-=1
    if depth==0:return text[start:end]
  raise AssertionError('Unbalanced source port '+name)
 body=re.search(r'  wire reset = core_reset.*?\n  end\n',wrapper,re.S)[0]
 reset_expr=re.search(r'wire reset\s*=([^;]+);',body)[1]
 expected='core_reset | cart_download | spc_download | bk_loading | ram_clear_busy | msu_data_download | (USE_STANDARD_SDRAM && save_busy) | (parser_delay != 0) | (USE_STANDARD_SDRAM && !standard_run_ready)'
 if compact(reset_expr)!=compact(expected):raise AssertionError('MAIN reset lifecycle predicate changed')
 main_instance=re.search(r'MAIN_SNES\s*#\(.*?\)\s+snes\s*\((.*?)\n  \);',top,re.S)[1]
 queue_instance=re.search(r'rom_download_queue\s+queue\s*\((.*?)\);',top,re.S)[1]
 if port(main_instance,'save_busy')!='queue_save_busy' or port(queue_instance,'save_busy')!='queue_save_busy':raise AssertionError('Queue to MAIN Save busy binding changed')
 core_input=port(main_instance,'core_reset')
 expected='~pll_core_locked || reset_button_s || msu_init_busy || (USE_STANDARD_SDRAM && (!ioctl_config_valid || host_reset_s))'
 if compact(core_input)!=compact(expected):raise AssertionError('core_top reset lifecycle predicate changed')
 cart_instance=re.search(r'sdram_cart_port\s+cart_memory\s*\((.*?)\);',wrapper,re.S)[1]
 cart_input=port(cart_instance,'soft_reset')
 if compact(cart_input)!='core_reset||save_busy||ram_clear_busy':raise AssertionError('Cart reset lifecycle predicate changed')
 host_guard=re.search(r'host_reset_guard\s+host_reset_sync\s*\((.*?)\);',top,re.S)
 if not host_guard or compact(host_guard[1])!='.clk_sys(clk_sys_21_48),.pll_locked(pll_core_locked),.host_reset_n(reset_n),.reset_hold(host_reset_s)':raise AssertionError('Host reset guard binding changed')
 # Only the existing FPGA power-up divider gets explicit four-state init.
 if body.count('reg [1:0] div;')!=1:raise AssertionError('MAIN reset divider extraction changed')
 body=body.replace('reg [1:0] div;', 'reg [1:0] div=0;')
 return '''module audio_core_reset_boundary(input wire clk_sys,core_reset,cart_download,standard_run_ready,cart_wait,save_busy,ram_clear_busy,output wire msu_soft_reset);
 localparam USE_STANDARD_SDRAM=1;
 wire spc_download=0,bk_loading=0,msu_data_download=0;
 wire[2:0]parser_delay=0;
'''+body+'''endmodule
module audio_core_reset_input(input wire clk_sys_21_48,reset,init_busy,config_valid,reset_n,output wire core_reset,host_reset_s);
 localparam USE_STANDARD_SDRAM=1;
 wire pll_core_locked=!reset,reset_button_s=0,msu_init_busy=init_busy,ioctl_config_valid=config_valid;
 host_reset_guard host_reset_sync('''+host_guard[1]+''');
 assign core_reset='''+core_input+''';
endmodule
module audio_cart_reset_input(input wire core_reset,save_busy,ram_clear_busy,output wire cart_core_reset);
 assign cart_core_reset='''+cart_input+''';
endmodule
'''

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--only',choices=['baseline','continuity','all'],default='all');ap.add_argument('--pal',choices=['0','1','both'],default='both');ap.add_argument('--mutation',choices=['wait-reset','wait-clock']);ap.add_argument('--vendor-sim-dir',type=pathlib.Path,default=pathlib.Path(os.environ.get('QUARTUS_SIM_LIB',str(ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib'))));ap.add_argument('--output',type=pathlib.Path,default=HERE/'results');args=ap.parse_args()
 out=(ROOT/args.output).resolve();out.mkdir(parents=True,exist_ok=True)
 manifest=out/('summary-'+args.only+'-'+args.pal+('-'+args.mutation if args.mutation else '')+'.json')
 manifest.write_text(json.dumps(dict(completed=False,passed=False,status='not_run_or_in_progress'),indent=2)+'\n')
 for name in ['iverilog','vvp']:
  if not shutil.which(name):raise SystemExit('NOT RUN: '+name+' missing')
 mf=args.vendor_sim_dir.resolve();mf=mf if mf.is_file() else mf/'altera_mf.v'
 if not mf.is_file():raise SystemExit('NOT RUN: installed Intel FIFO simulation library missing')
 boundary=''
 records=[]
 sources=list((ROOT/'rtl/msu1').glob('*.sv'))+list((ROOT/'rtl/memory_ready').glob('*.sv'))+[ROOT/'rtl/upstream/main.v',ROOT/'rtl/upstream/SNES.vhd',ROOT/'rtl/mister_top/SNES.sv',ROOT/'target/pocket/core_top.sv',ROOT/'target/pocket/sound_i2s.sv',ROOT/'target/pocket/sync_fifo.sv',HERE/'run.py',HERE/'tb_audio_memory_continuity.sv',HERE/'test_source_contract.py',ROOT/'target/pocket/host_reset_guard.sv',ROOT/'target/pocket/core_bridge_cmd.v',ROOT/'platform/pocket/common.v',ROOT/'tests/memory_ready/tb_host_reset_guard.sv',mf]
 sources+=list((ROOT/'tests/msu1').glob('tb_*.sv'))+[ROOT/'tests'/f'{n}.sv' for n in ['test_pcm_player','test_pcm_phase','test_pcm_rate']]
 sources+=list((ROOT/'target/pocket').glob('mf_pllbase*/**/*_0002.v'))
 def label(p):return str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)
 hashes={label(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 versions={n:subprocess.run([n,'-V'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT).stdout.splitlines()[0] for n in ['iverilog','vvp']}
 def run(name,cmd,expect='PASS',negative=False):
  t=time.monotonic();log=out/(name+'.log')
  with log.open('w') as stream:
   try:p=subprocess.run(list(map(str,cmd)),cwd=ROOT,text=True,stdout=stream,stderr=subprocess.STDOUT,timeout=480)
   except subprocess.TimeoutExpired:
    records.append(dict(name=name,passed=False,status='timed_out',seconds=round(time.monotonic()-t,3)))
    raise
  p.stdout=log.read_text()
  ok=(p.returncode!=0 if negative else p.returncode==0) and (not expect or expect in p.stdout)
  records.append(dict(name=name,passed=ok,expected_failure=negative,returncode=p.returncode,expected_marker=expect,seconds=round(time.monotonic()-t,3),log_sha256=hashlib.sha256(p.stdout.encode()).hexdigest()))
  if not ok:raise RuntimeError(name+' failed: '+p.stdout[-4000:])
  if expect:print(p.stdout.strip(),flush=True)
 def sim(name,bench,src,params=[],expect='PASS',negative=False):
  exe=out/(name+'.vvp');run(name+'-compile',['iverilog','-g2012','-s',bench,*params,'-o',exe,*src],expect=None)
  run(name,['vvp','-i',exe],expect,negative)
 msu=list((ROOT/'rtl/msu1').glob('*.sv'));integration=msu+[ROOT/'target/pocket/core_bridge_cmd.v',ROOT/'platform/pocket/common.v']
 completed=False;error=None
 try:
  boundary=source_contract();print('PASS source-bound clocks, host/Save/clear reset, SCPU-only waits and unchanged PCM/host RTL',flush=True)
  (out/'source-boundary.sv').write_text(boundary)
  run('source-contract-negative-tests',['python3',HERE/'test_source_contract.py'],expect='OK')
  if args.only in ['baseline','all'] and not args.mutation:
   sim('tb_host_reset_guard','tb_host_reset_guard',[ROOT/'tests/memory_ready/tb_host_reset_guard.sv',ROOT/'target/pocket/host_reset_guard.sv'])
   for name in ['test_pcm_player','test_pcm_phase','test_pcm_rate']:
    sizes=[4096,8192,16384] if name=='test_pcm_player' else [None]
    for size in sizes:sim(name+('-'+str(size) if size else ''),name,[ROOT/'tests'/f'{name}.sv',ROOT/'rtl/msu1/msu_pcm_player.sv'],[f'-P{name}.BUFFER_BYTES={size}'] if size else [])
   for name in ['tb_msu_pocket_host','tb_msu_transport','tb_msu_pocket_integration','tb_audit_bootstrap','tb_audit_soft_reset','tb_audit_reinit_mount','tb_audit_init_guard','tb_audit_mount_queue']:
    sim(name,name,[*integration,ROOT/'tests/msu1'/f'{name}.sv'])
  if args.only in ['continuity','all'] or args.mutation:
   with tempfile.TemporaryDirectory(prefix='audio-memory-audit-') as tmp:
    tmp=pathlib.Path(tmp);b=tmp/'boundary.sv'
    if args.mutation=='wait-reset':
     assert boundary.count('wire reset = core_reset |')==1
     boundary=boundary.replace('wire reset = core_reset |','wire reset = cart_wait | core_reset |')
    b.write_text(boundary)
    tb=(HERE/'tb_audio_memory_continuity.sv').read_text()
    if args.mutation=='wait-clock':
     assert tb.count('dut(.bridge_rd_data(wrapper_bridge_data),.*);')==1
     tb=tb.replace('dut(.bridge_rd_data(wrapper_bridge_data),.*);','dut(.sys_clk(sys_clk && !cart_wait),.bridge_rd_data(wrapper_bridge_data),.*);')
    (out/'effective-boundary.sv').write_text(boundary)
    (out/'effective-bench.sv').write_text(tb)
    t=tmp/'bench.sv';t.write_text(tb)
    memories=[ROOT/'rtl/memory_ready'/p for p in ['sdram_cart_port.sv','sdram_transaction_cdc.sv','sdram_single_request.sv','rom_download_queue.sv']]
    pals=['0','1'] if args.pal=='both' else [args.pal]
    for pal in pals:
     name='continuity-pal'+pal+('-'+args.mutation if args.mutation else '')
     expected='MEMORY_WAIT_RESET' if args.mutation=='wait-reset' else 'PCM_CADENCE: gated/missing clock tick' if args.mutation=='wait-clock' else 'PASS expected interruption: logical PLL reset'
     sim(name,'tb_audio_memory_continuity',[*integration,*memories,ROOT/'target/pocket/host_reset_guard.sv',ROOT/'target/pocket/sound_i2s.sv',ROOT/'target/pocket/sync_fifo.sv',b,t,mf],[f'-Ptb_audio_memory_continuity.PAL={pal}'],expected,bool(args.mutation))
  completed=True
 except BaseException as exc:
  error=type(exc).__name__+': '+str(exc)
  raise
 finally:
  now={label(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
  changed=[p for p in hashes if now.get(p)!=hashes[p]]
  manifest.write_text(json.dumps(dict(completed=completed,status='passed' if completed and error is None and not changed else 'failed',passed=completed and error is None and not changed and all(r['passed'] for r in records),error=error,checks=records,tool_versions=versions,source_hashes=hashes,reset_boundary_sha256=hashlib.sha256(boundary.encode()).hexdigest(),changed_during_run=changed,commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),limits=['Source-bound MAIN/core_top/cart reset fragments and real host_reset_guard; no complete mixed-language SNES top simulation','Clear busy and Save sink readiness are explicit behavioral lifecycle stimuli; no full physical RAM-clear or MAIN proof','Production cart/CDC/refresh/queue/MSU/APF/I2S with installed Intel FIFO model','Behavioral host file server and data-table RAM; constant SDRAM DQ','Logical PLL reset with simulated clocks continuing; not analogue PLL/relock/hardware evidence']),indent=2)+'\n')
  if changed:raise RuntimeError('Source changed during audit; rerun required: '+str(changed))
 print('PASS audio/memory audit selected checks')
if __name__=='__main__':main()
