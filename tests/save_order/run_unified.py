#!/usr/bin/env python3
"""Independent full-depth Intel Save RAM qualification for unified transport.
Historical known-bad RTL is an obligatory expected-corruption control in --case all.
"""
import argparse,concurrent.futures,hashlib,json,pathlib,re,shutil,subprocess,time
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[1]
def compact(s):return re.sub(r'\s','',re.sub(r'//[^\n]*','',s))
def need(text,fragment,label):
 if compact(fragment) not in compact(text):raise AssertionError(label+': '+fragment)
def ram_wrapper(bram):
 body=bram[bram.index('entity dpram_dif is'):bram.index('entity dpram_difclk is')]
 gm=re.search(r'GENERIC MAP \((.*?)\n\s*\)\s*PORT MAP',body,re.S)[1];pm=re.search(r'PORT MAP \((.*?)\n\s*\);',body,re.S)[1]
 def mapping(m):return ',\n'.join('.'+k.strip()+'('+v.strip().replace(' and ',' && ')+')' for k,v in (item.split('=>') for item in m.split(',')))
 return '''module dpram_dif #(parameter addr_width_a=8,data_width_a=8,addr_width_b=8,data_width_b=8,parameter mem_init_file=" ")(
input wire clock,input wire[addr_width_a-1:0]address_a,input wire[data_width_a-1:0]data_a,input wire wren_a,output wire[data_width_a-1:0]q_a,
input wire[addr_width_b-1:0]address_b,input wire[data_width_b-1:0]data_b,input wire wren_b,output wire[data_width_b-1:0]q_b);
wire enable_a=1'b1,enable_b=1'b1,cs_a=1'b1,cs_b=1'b1;
wire[data_width_a-1:0]q0;wire[data_width_b-1:0]q1;assign q_a=q0;assign q_b=q1;
altsyncram #(\n'''+mapping(gm)+') altsyncram_component (\n'+mapping(pm)+');\nendmodule\n'
def make_boundary(top,snes,bram):
 need(snes,'localparam BSRAM_BITS = 17;','physical Save geometry')
 helper=re.search(r'ram_clear_frontier\s*#\(\.BSRAM_BITS\(BSRAM_BITS\)\)\s+clear_frontier\s*\(.*?\);',snes,re.S)
 ready=re.search(r'assign save_write_ready\s*=\s*frontier_credit.*?;',snes,re.S)
 ram=re.search(r'  dpram_dif #\(BSRAM_BITS, 8, BSRAM_BITS - 1, 16\) bsram \(.*?\n  \);',snes,re.S)
 mux=re.search(r'wire\s*\[15:0\]\s*sd_buff_addr\s*=.*?;',top,re.S)
 if not all((helper,ready,ram,mux)):raise AssertionError('MAIN helper/ready/RAM or top backup address mux missing')
 for f in ('.image_begin(ioctl_image_begin)','.save_byte_addr(save_write_addr)'):need(helper[0],f,'frontier binding')
 for f in ('frontier_credit','standard_host_quiescent','!ioctl_image_begin','!ioctl_fault','!sd_rd'):need(ready[0],f,'Save credit')
 need(mux[0],'sd_wr ? sd_buff_addr_in[16:1] : sd_buff_addr_out[16:1]','independent backup address mux')
 main=re.search(r'MAIN_SNES.*?\)\s+snes\s*\((.*?)\n\s*\);',top,re.S)[1]
 for f in ('.ioctl_download(ioctl_image_busy)','.ioctl_image_begin(ioctl_image_begin)','.save_busy(queue_save_busy)',
           '.save_write_addr(sd_buff_addr_in)','.save_write_ready(queue_save_ready)','.sd_wr(sd_wr)',
           '.rom_type(ioctl_config[7:0])','.rom_size(ioctl_config[11:8])','.ram_size(ioctl_config[15:12])','.PAL(ioctl_config[16])'):
  need(main,f,'MAIN binding')
 need(snes,'.soft_reset(core_reset || save_busy || ram_clear_busy)','cart host flush')
 need(snes,'.host_quiescent(standard_host_quiescent)','cart credit binding')
 queue=re.search(r'rom_download_queue\s+queue\s*\((.*?)\);',top,re.S)[1]
 for f in ('.save_valid(queue_save_valid)','.save_ready(queue_save_ready)','.save_en(sd_wr)',
           '.save_addr(sd_buff_addr_in)','.save_data(sd_buff_dout)','.save_busy(queue_save_busy)'):
  need(queue,f,'queue Save binding')
 need(top,'generate if (!USE_STANDARD_SDRAM) begin : g_legacy_save_download','legacy loader exclusion')
 reader=re.search(r'data_unloader\s*#\(.*?\)\s+data_unloader\s*\(.*?\n\s*\);',top,re.S)
 if not reader:raise AssertionError('Actual backup unloader instance missing')
 reader_module='''
module save_backup_reader_boundary(input wire clk_74a,clk_sys_21_48,pll_core_locked,bridge_rd,bridge_endian_little,
input wire[31:0]bridge_addr,input wire[15:0]read_data,output wire[31:0]bridge_rd_data,output wire read_en,output wire[16:0]read_addr);
localparam USE_STANDARD_SDRAM=1;
wire[31:0]sd_read_data;wire sd_rd;wire[16:0]sd_buff_addr_out;wire[15:0]sd_buff_din=read_data;
assign bridge_rd_data=sd_read_data;assign read_en=sd_rd;assign read_addr=sd_buff_addr_out;
'''+reader[0]+'\nendmodule\n'
 module='''`timescale 1ns/1ps
module unified_clear_boundary(input wire clk_sys,pll_locked,core_reset,cart_download,image_begin,save_busy,host_quiescent,save_valid,save_en,qfault,sd_rd,
input wire[16:0]save_addr,read_addr,backup_addr,input wire[15:0]save_data,
output wire save_ready,output wire[7:0]read_q,output wire[15:0]backup_q,port_b_addr,output wire clearing,clear_pending,clear_busy,backup_ready,output wire[16:0]clear_addr);
localparam BSRAM_BITS=17;
wire ioctl_image_begin=image_begin,ioctl_fault=qfault,standard_host_quiescent=host_quiescent;
wire[16:0]save_write_addr=save_addr;wire[16:0]mem_fill_addr;
wire frontier_credit,save_write_ready,clearing_ram,ram_clear_busy;
wire wram_psram_busy=0,aram_psram_busy=0;
wire sd_wr=save_en;wire[16:0]sd_buff_addr_in=save_addr,sd_buff_addr_out=backup_addr;
wire[15:0]sd_buff_dout=save_data;wire[15:0]sd_buff_din;wire[19:0]BSRAM_ADDR={3'b0,read_addr};
wire[7:0]BSRAM_D=0;wire[7:0]BSRAM_Q;wire BSRAM_CE_N=1,BSRAM_WE_N=1;
assign save_ready=save_write_ready;assign read_q=BSRAM_Q;assign backup_q=sd_buff_din;
assign port_b_addr=sd_buff_addr;assign clearing=clearing_ram;assign clear_addr=mem_fill_addr;
// The RAM-only content test supplies idle PSRAMs; actual controller-drain
// qualification is separate. Keep the production pending barrier intact.
assign clear_pending=clear_frontier.pending;assign clear_busy=ram_clear_busy;
'''+mux[0]+'\n'+helper[0]+'\n'+ready[0]+'\n'+(('wire save_backup_ready;\n'+re.search(r'assign save_backup_ready\s*=.*?;',snes,re.S)[0]+'\nassign backup_ready=save_backup_ready;') if 'assign save_backup_ready' in snes else "assign backup_ready=1'b0;")+'\n'+ram[0]+'\nendmodule\n'+ram_wrapper(bram)
 admission=''
 if 'read_fence_issued' in top:
  need(re.search(r'\.core_reset\((.*?)\),',main,re.S)[1],'host_reset_s','MAIN APF soft reset')
  for f in ('.source_ready(queue_source_ready)','.save_read_request(queue_save_read_request)','.save_read_ready(queue_save_read_ready)','.save_read_quiescent(save_backup_ready)'):
   need(queue,f,'ordered backup fence binding')
  need(main,'.save_backup_ready(save_backup_ready)','MAIN backup credit binding')
  frag=top[top.index('  reg queue_save_read_request'):top.index('  wire host_reset_s;')]
  frag=frag.replace('queue_save_read_request','request_reg')
  guard=re.search(r'host_reset_guard\s+host_reset_sync\s*\(.*?\);',top,re.S)[0]
  admission='''
module save_backup_admission_boundary(input wire clk_74a,clk_sys_21_48,pll_core_locked,reset_n,dataslot_requestread,queue_source_ready,queue_save_read_ready,
input wire[15:0]dataslot_requestread_id,output wire queue_save_read_request,dataslot_requestread_ack,host_reset_s);
localparam USE_STANDARD_SDRAM=1;
'''+frag+'\nassign queue_save_read_request=request_reg;\n'+guard+'\nendmodule\n'
 return module+reader_module+admission

def main():
 p=argparse.ArgumentParser();p.add_argument('--integration-root',type=pathlib.Path,default=ROOT);p.add_argument('--queue-root',type=pathlib.Path,default=ROOT)
 p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib');p.add_argument('--out',type=pathlib.Path,default=HERE/'results-unified')
 p.add_argument('--pal',choices=['0','1','both'],default='both');p.add_argument('--case',choices=['primary','remount','lifecycle','reset','phase','backup','backup-negative','all'],default='all');p.add_argument('--jobs',type=int,default=2)
 a=p.parse_args();i=a.integration_root.resolve();q=a.queue_root.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);manifest=out/'summary.json'
 manifest.write_text(json.dumps(dict(completed=False,passed=False,status='in_progress'),indent=2)+'\n')
 for t in ('iverilog','vvp'):
  if not shutil.which(t):raise SystemExit('NOT RUN: '+t+' unavailable')
 vendor=a.vendor_sim_dir.resolve()/'altera_mf.v'
 if not vendor.is_file():raise SystemExit('NOT RUN: installed Intel altera_mf.v missing')
 selected={'queue.sv':q/'rtl/memory_ready/rom_download_queue.sv','cart.sv':i/'rtl/memory_ready/sdram_cart_port.sv',
 'cdc.sv':i/'rtl/memory_ready/sdram_transaction_cdc.sv','engine.sv':i/'rtl/memory_ready/sdram_single_request.sv',
 'frontier.sv':i/'target/pocket/ram_clear_frontier.sv','unloader.sv':i/'target/pocket/data_unloader.sv',
 'SNES.sv.txt':i/'rtl/mister_top/SNES.sv','core_top.sv.txt':i/'target/pocket/core_top.sv','bram.vhd.txt':i/'rtl/upstream/bram.vhd',
 'bench.sv':HERE/'tb_unified_save_contents.sv','backup_program.svh':HERE/'backup_program.svh','runner.py':pathlib.Path(__file__).resolve()}
 if (i/'target/pocket/host_reset_guard.sv').is_file():selected['host_reset.sv']=i/'target/pocket/host_reset_guard.sv'
 if a.case in ('backup','backup-negative','all'):
  selected.update({'bridge_cmd.v':i/'target/pocket/core_bridge_cmd.v','platform_common.v':i/'platform/pocket/common.v','datatable.v':i/'platform/pocket/mf_datatable.v'})
 snapshot=out/'source_snapshot';snapshot.mkdir(exist_ok=True)
 hashes={};origin={}
 for name,path in selected.items():
  content=path.read_bytes();(snapshot/name).write_bytes(content);hashes[str(path)]=hashlib.sha256(content).hexdigest();origin[name]=str(path)
 hashes[str(vendor)]=hashlib.sha256(vendor.read_bytes()).hexdigest()
 boundary=snapshot/'boundary.sv';boundary.write_text(make_boundary((snapshot/'core_top.sv.txt').read_text(),(snapshot/'SNES.sv.txt').read_text(),(snapshot/'bram.vhd.txt').read_text()))
 hashes[str(boundary)]=hashlib.sha256(boundary.read_bytes()).hexdigest()
 sources=[snapshot/n for n in ('queue.sv','cart.sv','cdc.sv','engine.sv','frontier.sv','unloader.sv','bench.sv')]+[boundary,vendor]
 if 'host_reset.sv' in selected:sources.append(snapshot/'host_reset.sv')
 if a.case in ('backup','backup-negative','all'):
  text=(snapshot/'bench.sv').read_text();marker=text.index(' integer i,before_begins,before_saves;')
  text=text[:marker]+(snapshot/'backup_program.svh').read_text()
  text=text.replace('module tb_unified_save_contents;','module tb_unified_backup;')
  text=text.replace('.save_read_request(1\'b0),.save_read_ready(),.save_read_quiescent(1\'b1)', '.source_ready(source_ready),.save_read_request(fence_request),.save_read_ready(fence_ready),.save_read_quiescent(backup_ready)')
  text=text.replace('.soft_reset(soft_reset||save_busy||clear_busy)', '.soft_reset(soft_reset||host_reset_hold||save_busy||clear_busy)')
  text=text.replace('.core_reset(soft_reset)', '.core_reset(soft_reset||host_reset_hold)')
  text=text.replace('.clear_busy(clear_busy),.clear_addr(clear_addr)', '.clear_busy(clear_busy),.backup_ready(backup_ready),.clear_addr(clear_addr)')
  (snapshot/'backup_bench.sv').write_text(text)
 cases=[];pals=[0,1]if a.pal=='both'else[int(a.pal)]
 for pal in pals:
  for case in ([0,1,2,3,5] if a.case=='all' else [] if a.case in ('phase','backup-negative') else [{'primary':0,'remount':1,'lifecycle':2,'reset':3,'backup':5}[a.case]]):
   for burst in ([0,1] if case==0 else [1]):cases.append((f'pal{pal}-case{case}-burst{burst}',pal,case,burst,0))
  if a.case in ('all','phase'):
   # Clock phase sweep retains full-depth hardware; each focused probe checks
   # early restore/frontier, not a completed 24-ms sweep.
   for phase in range(0,47,5):cases.append((f'pal{pal}-phase{phase}',pal,4,1,phase))
 if a.case in ('all','backup-negative'):
  text=boundary.read_text()
  mutations={
   'stale-ready':('read_fence_issued && read_fence_saw_clear && queue_save_read_ready','queue_save_read_ready','BACKUP_ACK_BEFORE_ORDERED_DRAIN'),
   'stale-slot-id':("dataslot_requestread && (dataslot_requestread_id != 16'd10 ||","(dataslot_requestread_id != 16'd10 ||",'SLOT10_ADMISSION')}
  for key,(old,new,signature) in mutations.items():
   if old not in text:raise AssertionError('Command mutation target missing: '+key)
   target=snapshot/('boundary-negative-'+key+'.sv');target.write_text(text.replace(old,new))
   hashes[str(target)]=hashlib.sha256(target.read_bytes()).hexdigest()
   cases.append(('negative-'+key,pals[0],5,1,0))
 records=[];completed=False;error=None
 def run_case(job):
  name,pal,case,burst,phase=job;negative=name.startswith('negative-');top='tb_unified_backup'if case==5 else 'tb_unified_save_contents';src=[p for p in sources if case!=5 or p.name!='bench.sv'];src+=([snapshot/n for n in ('backup_bench.sv','bridge_cmd.v','platform_common.v','datatable.v')]if case==5 else []);exe=out/(name+'.vvp');
  if negative:src=[snapshot/('boundary-'+name+'.sv')if p==boundary else p for p in src]
  started=time.monotonic();oracle=out/(name+'-oracle');oracle.mkdir(exist_ok=True)
  compile_cmd=['iverilog','-g2012',*(['-DHAS_READ_FENCE']if 'save_read_request' in (snapshot/'queue.sv').read_text() else []),'-s',top,f'-P{top}.PAL={pal}',f'-P{top}.CASE={case}',f'-P{top}.BURST={burst}',f'-P{top}.PHASE_NS={phase}','-o',str(exe),*map(str,src)]
  with (out/(name+'-compile.log')).open('w') as log:r=subprocess.run(compile_cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=90)
  if r.returncode:return dict(name=name,passed=False,stage='compile',seconds=time.monotonic()-started)
  with (out/(name+'.log')).open('w') as log:r=subprocess.run(['vvp','-i',str(exe),'+ORACLE_DIR='+str(oracle)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=1200)
  txt=(out/(name+'.log')).read_text();signature=mutations[name[len('negative-'):]][2]if negative else 'PASS UNIFIED_SAVE_CONTENTS';ok=(r.returncode!=0 if negative else r.returncode==0)and signature in txt
  checks=[dict(label=int(m),bytes_compared=131072,bad_bytes=0)for m in re.findall(r'PASS FULL_RAM label=(\d+)',txt)]
  pairs=[]
  for actual in sorted(oracle.glob('label-*-actual.hex')):
   gold=actual.with_name(actual.name.replace('-actual.hex','-expected.hex'))
   av=re.sub(r'//[^\n]*','',actual.read_text()).split();gv=re.sub(r'//[^\n]*','',gold.read_text()).split()
   same=len(av)==131072 and len(gv)==131072 and av==gv
   pairs.append(dict(label=int(re.search(r'label-(\d+)',actual.name)[1]),bytes_compared=len(av),bad_bytes=sum(x!=y for x,y in zip(av,gv)),equal=same,actual=str(actual),expected=str(gold),actual_sha256=hashlib.sha256(actual.read_bytes()).hexdigest(),expected_sha256=hashlib.sha256(gold.read_bytes()).hexdigest()))
  if not negative and case!=4 and (not pairs or not all(x['equal']for x in pairs)):ok=False
  first=re.search(r'RAM_BAD label=(\d+) addr=(\d+) got=(\w+) expected=(\w+)',txt)
  return dict(name=name,passed=ok,expected_failure=negative,expected_signature=signature,stage='complete'if ok else 'simulation',exit_code=r.returncode,full_ram_checks=checks,byte_oracles=pairs,first_mismatch=first.groups()if first else None,phase_frontier_bytes=256 if case==4 and ok else 0,log=str(out/(name+'.log')),seconds=round(time.monotonic()-started,3))
 def historical(pal):
  # Preserve the original counterexample code and oracle exactly. Its success
  # means the old RTL exhibits expected byte corruption, not that old RTL passed.
  old=out/'historical';old.mkdir(exist_ok=True);paths={
   'queue.sv':('26a37e7','rtl/memory_ready/rom_download_queue.sv'),'cart.sv':('26a37e7','rtl/memory_ready/sdram_cart_port.sv'),
   'cdc.sv':('26a37e7','rtl/memory_ready/sdram_transaction_cdc.sv'),'engine.sv':('26a37e7','rtl/memory_ready/sdram_single_request.sv'),
   'loader.sv':('26a37e7','target/pocket/data_loader.sv'),'bench.sv':('3401c9c','tests/save_order/tb_save_order.sv'),
   'boundary.sv':('3401c9c','tests/save_order/evidence/ntsc-burst/source_boundary.sv')}
  for name,(rev,path) in paths.items():
   content=subprocess.check_output(['git','show',rev+':'+path],cwd=ROOT);(old/name).write_bytes(content);hashes['git:'+rev+':'+path]=hashlib.sha256(content).hexdigest()
  name=f'historical-pal{pal}-expected-corruption';exe=old/(name+'.vvp');cmd=['iverilog','-g2012','-s','tb_save_order',f'-Ptb_save_order.PAL={pal}','-Ptb_save_order.BURST=1','-o',str(exe),*[str(old/n)for n in paths],str(vendor)]
  with (out/(name+'-compile.log')).open('w')as log:r=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=90)
  if r.returncode:return dict(name=name,passed=False,stage='compile',expected_failure=True)
  with (out/(name+'.log')).open('w')as log:r=subprocess.run(['vvp','-i',str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=1200)
  txt=(out/(name+'.log')).read_text();m=re.search(r'baseline_bad=(\d+) queued_bad=(\d+) first_bad=(-?\d+) last_bad=(-?\d+)',txt)
  ok=r.returncode==0 and 'PASS SAVE_ORDER' in txt and m and tuple(map(int,m.groups()))==((0,1246,0,1247)if pal else(0,1204,0,1203))
  return dict(name=name,passed=bool(ok),expected_failure=True,observed='old RTL corrupts save'if ok else 'unexpected',byte_counts=list(map(int,m.groups()))if m else None,log=str(out/(name+'.log')))
 try:
  with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,a.jobs))as pool:
   futures={pool.submit(run_case,c):c[0]for c in cases}
   for future in concurrent.futures.as_completed(futures):
    result=future.result();records.append(result);print(json.dumps(result),flush=True)
  if a.case=='all':
   for pal in pals:records.append(historical(pal));print(json.dumps(records[-1]),flush=True)
  completed=True
  if not all(x['passed']for x in records):error='one or more checks failed'
 except BaseException as exc:error=type(exc).__name__+': '+str(exc);raise
 finally:
  changed=[str(path)for path in selected.values()if hashes[str(path)]!=hashlib.sha256(path.read_bytes()).hexdigest()]
  manifest.write_text(json.dumps(dict(completed=completed,passed=completed and not error and not changed,status='passed'if completed and not error and not changed else 'failed',error=error,checks=records,source_hashes=hashes,source_origins=origin,source_changed=changed,integration_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=i,text=True).strip(),queue_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=q,text=True).strip(),limits=['Full physical128KiB Intel BSRAM model and production FIFO/cart/CDC/engine/helper; source-extracted MAIN credit and backup mux','Source-side byte oracle; no real user save or commercial ROM','Not complete mixed-language MAIN/CPU/WRAM execution or board/analogue CDC proof','Phase probes retain full clear hardware but stop after checking256-byte frontier','Historical controls require unchanged counterexamples to reproduce known byte corruption']),indent=2)+'\n')
 if error:raise SystemExit(error)
 if changed:raise SystemExit('Source changed during run; snapshot result is not final current-source qualification')
if __name__=='__main__':
 try:main()
 except BaseException as exc:
  # Setup/elaboration failures must also leave a terminal manifest.
  import sys
  dest=pathlib.Path(sys.argv[sys.argv.index('--out')+1]).resolve() if '--out' in sys.argv else HERE/'results-unified'
  dest.mkdir(parents=True,exist_ok=True);f=dest/'summary.json'
  saved=json.loads(f.read_text()) if f.exists() else {}
  if saved.get('status')=='in_progress' or not saved:
   saved.update(completed=False,passed=False,status='failed',error=type(exc).__name__+': '+str(exc));f.write_text(json.dumps(saved,indent=2)+'\n')
  raise
