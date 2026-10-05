#!/usr/bin/env python3
"""Actual-engine unit map/functional-netlist comparison of local OE control use.
No full-core fit, no production-file mutation, no timing/hardware claim.
"""
import argparse,hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=pathlib.Path,required=True)
p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--pack',action='store_true',help='Also fit ONLY the tiny unit to verify I/O packing; never a full core');a=p.parse_args();q=a.quartus_bin.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
records={}
for mode in ('baseline','local_no_sync_controls'):
 d=out/mode;d.mkdir();(d/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
 text=f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY standard_oe_map_unit
set_global_assignment -name SYSTEMVERILOG_FILE "{ROOT/'tests/timing/standard_oe_map_unit.sv'}"
set_global_assignment -name SYSTEMVERILOG_FILE "{ROOT/'rtl/memory_ready/sdram_single_request.sv'}"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_instance_assignment -name VIRTUAL_PIN ON -to *
'''
 if mode!='baseline':text+='set_instance_assignment -name ALLOW_SYNCH_CTRL_USAGE OFF -to "engine|dq_oe"\n'
 if a.pack:
  # Do not combine wildcard virtual pins with physical clock overrides: map
  # can lower the clock into a virtual combinational input before placement.
  text=text.replace('set_instance_assignment -name VIRTUAL_PIN ON -to *\n','')
  virtual=['reset_n','pll_locked','req_valid','req_write','rsp_ready','req_ready','rsp_valid','rsp_error','init_done']
  virtual += ['req_addr[%d]'%i for i in range(32)]+['req_wdata[%d]'%i for i in range(16)]+['req_wstrb[%d]'%i for i in range(2)]+['rsp_rdata[%d]'%i for i in range(16)]
  for port in virtual:text+=f'set_instance_assignment -name VIRTUAL_PIN ON -to {port}\n'
  pins={}
  for line in (ROOT/'platform/pocket/pocket.tcl').read_text().splitlines():
   m=re.match(r'set_location_assignment (\S+) -to (dram_\S+|clk_74a)$',line)
   if m:pins[m[2]]=m[1]
  ports=['dram_dq[%d]'%i for i in range(16)]+['dram_a[%d]'%i for i in range(13)]+['dram_ba[%d]'%i for i in range(2)]+['dram_dqm[%d]'%i for i in range(2)]+['dram_cke','dram_ras_n','dram_cas_n','dram_we_n']
  for port in ports:
   text+=f'set_instance_assignment -name VIRTUAL_PIN OFF -to {port}\nset_location_assignment {pins[port]} -to {port}\nset_instance_assignment -name IO_STANDARD "1.8 V" -to {port}\nset_instance_assignment -name FAST_OUTPUT_REGISTER ON -to {port}\n'
   if port.startswith('dram_dq['):text+=f'set_instance_assignment -name FAST_INPUT_REGISTER ON -to {port}\nset_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to {port}\n'
  text+=f'set_instance_assignment -name VIRTUAL_PIN OFF -to clk\nset_location_assignment {pins["clk_74a"]} -to clk\nset_instance_assignment -name IO_STANDARD "1.8 V" -to clk\nset_global_assignment -name SDC_FILE unit.sdc\nset_global_assignment -name FITTER_EFFORT "FAST FIT"\n'
  (d/'unit.sdc').write_text('create_clock -name unit_clk -period 9.312 [get_ports clk]\n')
 (d/'unit.qsf').write_text(text)
 (d/'map.tcl').write_text('load_package flow\nproject_open unit\nexecute_module -tool map\nproject_close\n')
 for tool,args,name in [('quartus_sh',['-t','map.tcl'],'map'),('quartus_eda',['unit','--simulation','--tool=modelsim','--format=verilog','--functional=on','--output_directory=functional'],'eda')]:
  r=subprocess.run([str(q/tool),*args],cwd=d,capture_output=True,text=True,timeout=120)
  (d/(name+'.log')).write_text(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError(mode+' '+name+' failed')
 net=next((d/'functional').glob('*.vo')).read_text(errors='replace')
 candidates=re.findall(r'dffeas\s+(\\[^\n]*dq_oe[^\n]*?)\s*\((.*?)\);',net,re.S)
 if not candidates:raise RuntimeError('OE primitive missing in exported actual-engine netlist')
 nodes=[]
 for node,body in candidates:
  nodes.append({'node':node,'ports':dict(re.findall(r'\.(\w+)\(([^)]*)\)',body))})
 if a.pack:
  (d/'fit.tcl').write_text('load_package flow\nproject_open unit\nexecute_module -tool fit\nproject_close\n')
  fit=subprocess.run([str(q/'quartus_sh'),'-t','fit.tcl'],cwd=d,capture_output=True,text=True,timeout=180)
  (d/'fit.log').write_text(fit.stdout+fit.stderr)
  if fit.returncode or 'invalid node name' in fit.stdout+fit.stderr:raise RuntimeError(mode+' unit fit failed or ignored an invalid fixture assignment')
 records[mode]={'unit_fit_performed':a.pack,'nodes':nodes,'engine_sha256':hashlib.sha256((ROOT/'rtl/memory_ready/sdram_single_request.sv').read_bytes()).hexdigest()}
 print(mode,json.dumps(nodes))
base=records['baseline']['nodes'][0]['ports'];fixed=records['local_no_sync_controls']['nodes'][0]['ports']
if base['sclr'].strip()=='gnd' or fixed['sclr'].strip()!='gnd':raise AssertionError('Expected local synchronous-clear removal missing')
for key in ('clk','clrn','ena','sload','aload','prn'):
 if base[key]!=fixed[key]:raise AssertionError('OE control semantics changed: '+key)
(out/'summary.json').write_text(json.dumps({'results':records,'scope':'actual-engine isolated unit map'+(' and tiny unit I/O packing fit' if a.pack else '')+'; no full-core fit, routed timing or hardware proof'},indent=2)+'\n')
