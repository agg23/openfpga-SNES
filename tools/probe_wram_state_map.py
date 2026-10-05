#!/usr/bin/env python3
"""Map the actual dual PSRAM under one precise standard-only synthesis control.
No fit, STA, timing exceptions, source RTL changes, or functional replacement.
"""
import argparse,hashlib,json,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-state-map');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True);Q=a.quartus_bin.resolve();results={}
srcs=['target/pocket/psram.sv','tests/timing/psram_state_map_unit.sv','target/pocket/standard_wram_state.tcl']
hashes={s:hashlib.sha256((R/s).read_bytes()).hexdigest() for s in srcs}
for mode in ['baseline','state_data_only']:
 d=O/mode;d.mkdir(exist_ok=True);(d/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
 (d/'unit.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY psram_state_map_unit
set_global_assignment -name SYSTEMVERILOG_FILE "{R/'tests/timing/psram_state_map_unit.sv'}"
set_global_assignment -name SYSTEMVERILOG_FILE "{R/'target/pocket/psram.sv'}"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_instance_assignment -name VIRTUAL_PIN ON -to *
''')
 (d/'map.tcl').write_text('load_package flow\nproject_open unit\nsource {'+str(R/'target/pocket/standard_wram_state.tcl')+'}\nconfigure_standard_wram_state '+str(int(mode!='baseline'))+'\nexport_assignments\nexecute_module -tool map\nproject_close\n')
 for tool,args,name in [('quartus_sh',['-t','map.tcl'],'map'),('quartus_eda',['unit','--simulation','--tool=modelsim','--format=verilog','--functional=on','--output_directory=functional'],'eda')]:
  q=subprocess.run([str(Q/tool),*args],cwd=d,text=True,capture_output=True,timeout=120);(d/(name+'.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,(mode,name,q.stdout[-2000:]+q.stderr)
 net=(d/'functional/unit.vo').read_text();cells=[]
 for typ,name,body in re.findall(r'\b(cyclonev_lcell_comb|dffeas|cyclonev_io_ibuf|cyclonev_io_obuf)\s+(\\\S+|\w+)\s*\((.*?)\);',net,re.S):
  ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',body));params=dict(re.findall(r'defparam\s+'+re.escape(name)+r'\s+\.(\w+)\s*=\s*([^;]+);',net));cells.append(dict(type=typ,name=name,ports=ports,params=params))
 (d/'cells.json').write_text(json.dumps(cells,indent=2)+'\n')
 w=[c for c in cells if c['type']=='dffeas' and '|wram|state[' in c['name']];ar=[c for c in cells if c['type']=='dffeas' and '|aram|state[' in c['name']]
 assert len(w)==8 and len(ar)==8,(len(w),len(ar))
 def controls(cs):return {c['name']:{k:c['ports'][k].strip() for k in ['d','ena','sclr','sload','asdata','aload','clrn','prn']} for c in cs}
 if mode=='baseline':assert any(c['ports']['sclr'].strip()!='gnd' for c in w),'baseline unexpectedly has no state SCLR'
 else:
  assert all(c['ports']['sclr'].strip()==c['ports']['sload'].strip()=='gnd' for c in w),'WRAM synchronous controls remain'
  assert any(c['ports']['sclr'].strip()!='gnd' for c in ar),'ARAM state control was inadvertently disabled'
 rpt=(d/'output_files/unit.map.rpt').read_text()
 results[mode]={'combinational_aluts':int(re.search(r'; Combinational ALUT usage for logic\s*;\s*(\d+)',rpt)[1]),'registers':sum(c['type']=='dffeas' for c in cells),'wram_state_controls':controls(w),'aram_state_controls':controls(ar),'netlist_sha256':hashlib.sha256(net.encode()).hexdigest()}
 print(mode,results[mode]['combinational_aluts'],results[mode]['registers'],'WRAM sclr',[c['ports']['sclr'] for c in w],flush=True)
assert hashes=={s:hashlib.sha256((R/s).read_bytes()).hexdigest() for s in srcs},'source drift'
(O/'summary.json').write_text(json.dumps({'results':results,'sources_sha256':hashes,'scope':'Actual dual PSRAM, exact standard-only WRAM state targets, native unit map and functional netlist export only; no fit or timing closure claim'},indent=2)+'\n')
