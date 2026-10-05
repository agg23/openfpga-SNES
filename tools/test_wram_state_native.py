#!/usr/bin/env python3
"""Compare actual Intel native functional atoms with each other and PSRAM RTL."""
import argparse,hashlib,json,os,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=pathlib.Path,required=True);p.add_argument('--map',type=pathlib.Path,default=R/'build/wram-state-map');p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-state-native');a=p.parse_args();M=a.map.resolve();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True);lib=a.quartus_bin.resolve().parent/'eda/sim_lib';env=os.environ.copy();env['PATH']='/tmp/msu1-tools/bin:'+env.get('PATH','');checks=[]
def run(name,command,negative=False):
 q=subprocess.run(list(map(str,command)),cwd=R,env=env,text=True,capture_output=True,timeout=120);log=q.stdout+q.stderr;(O/(name+'.log')).write_text(log)
 ok=q.returncode!=0 and 'NATIVE PIN EDGE MISMATCH' in log if negative else q.returncode==0
 checks.append(dict(name=name,passed=ok,negative=negative,command=list(map(str,command))));assert ok,log[-3000:];print('PASS '+name,flush=True);return log
cells={m:json.loads((M/m/'cells.json').read_text()) for m in ['baseline','state_data_only']}
for mode,label in [('baseline','baseline'),('state_data_only','candidate')]:
 src=(M/mode/'functional/unit.vo').read_text();assert src.count('module psram_state_map_unit (')==1
 (O/(label+'.v')).write_text(src.replace('module psram_state_map_unit (','module native_'+label+' ('))
q=[]
for mode,inst,signal in [('baseline','b','qb'),('state_data_only','c','qc')]:
 regs=sorted((c for c in cells[mode] if c['type']=='dffeas'),key=lambda c:c['name'])
 q.append('wire ['+str(len(regs)-1)+':0] '+signal+'={'+','.join(inst+'.'+c['ports']['q']+' ' for c in regs)+'};')
bench=(R/'tests/timing/tb_wram_state_native.sv').read_text();assert bench.count(' // NATIVE_Q_WIRES\n')==1
(O/'tb.sv').write_text(bench.replace(' // NATIVE_Q_WIRES\n','\n'.join(q)+'\n'))
inputs=[O/'baseline.v',O/'candidate.v',lib/'altera_primitives.v',lib/'cyclonev_atoms.v',R/'target/pocket/psram.sv',R/'tests/timing/psram_state_map_unit.sv',O/'tb.sv']
for region,period in [('ntsc','11.640'),('pal','11.747')]:
 binary=O/region;run(region+'-compile',['iverilog','-g2012','-s','tb_wram_state_native','-Ptb_wram_state_native.T='+period,'-o',binary,*inputs]);log=run(region,['vvp',binary]);assert 'PASS native PSRAM sequential/pin equivalence' in log
src=(O/'candidate.v').read_text();anchor='.i(read_en[0]),';assert src.count(anchor)==1;(O/'candidate.v').write_text(src.replace(anchor,'.i(~read_en[0]),'))
binary=O/'negative';run('corrupted_read-compile',['iverilog','-g2012','-s','tb_wram_state_native','-o',binary,*inputs]);run('corrupted_read',['vvp',binary],True);(O/'candidate.v').write_text(src)
(O/'summary.json').write_text(json.dumps({'checks':checks,'native_netlist_hashes':{m:hashlib.sha256((M/m/'functional/unit.vo').read_bytes()).hexdigest() for m in cells},'source_hashes':{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [R/'target/pocket/psram.sv',R/'tests/timing/psram_state_map_unit.sv',R/'tests/timing/tb_wram_state_native.sv']},'vendor_atom_hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [lib/'altera_primitives.v',lib/'cyclonev_atoms.v']},'scope':'Actual zero-delay Intel atoms vs each other and unchanged RTL, NTSC/PAL pin sequences; no SDF, routed, glitch, PCB or hardware proof'},indent=2)+'\n')
