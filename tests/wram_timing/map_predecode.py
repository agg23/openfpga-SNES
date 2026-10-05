#!/usr/bin/env python3
"""Native Cyclone V map-only comparison of the exact-source read-decode tail.
Requires check_predecode.py output. No full-core build, fit or timing claim.
"""
import argparse,hashlib,json,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=pathlib.Path,required=True);p.add_argument('--proof',type=pathlib.Path,default=R/'build/wram-predecode-proof');p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-predecode-map');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True);Q=a.quartus_bin.resolve();proof=a.proof.resolve();results={}
manifest=json.loads((proof/'summary.json').read_text())
assert all(hashlib.sha256((R/f).read_bytes()).hexdigest()==h for f,h in manifest['sources_sha256'].items()),'proof sources changed'
assert hashlib.sha256((proof/'decode.vhd').read_bytes()).hexdigest()==manifest['extracted_model_sha256'],'proof model changed'
for mode in [0,1]:
 d=O/('baseline' if mode==0 else 'predecode');d.mkdir(exist_ok=True)
 (d/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
 (d/'unit.sv').write_text('''module unit(input clk,input [23:0] a,input [7:0] b,input [15:0] control,output reg [7:0] pa_out,output reg [1:0] strobe_out,output reg read_en);
 reg [23:0] ar;reg [7:0] br;reg [15:0] cr;
 always @(posedge clk)begin ar<=a;br<=b;cr<=control;end
 wire [7:0] pa;wire pr,pw,pred,oc,oo,nc,no,eq,se;
 WramReadDecode decode(.p65_a(ar),.dma_b(br),.en(cr[0]),.p65_en(cr[1]),.enable(cr[2]),.ramsel_n(cr[3]),.cpu_rd(cr[4]),.cpu_wr(cr[5]),
 .dma_b_rd(cr[6]),.dma_b_wr(cr[7]),.dma_a_rd(cr[8]),.dma_a_wr(cr[9]),.hdma_a_rd(cr[10]),.hdma_a_wr(cr[11]),.hdma_b_rd(cr[12]),.hdma_b_wr(cr[13]),.dma_transfer(cr[14]),.hdma_bus_active(cr[15]),
 .pa(pa),.pard_n(pr),.pawr_n(pw),.pa_wmdata(pred),.old_ce_n(oc),.old_oe_n(oo),.new_ce_n(nc),.new_oe_n(no),.equivalent(eq),.selected_eq(se));
 always @(posedge clk)begin pa_out<=pa;strobe_out<={pr,pw};read_en<=READ_EXPR;end
 endmodule
'''.replace('READ_EXPR','!oc&&!oo' if mode==0 else '!nc&&!no'))
 (d/'unit.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY unit
set_global_assignment -name SYSTEMVERILOG_FILE unit.sv
set_global_assignment -name VHDL_FILE "{proof/'decode.vhd'}"
set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_instance_assignment -name VIRTUAL_PIN ON -to *
''')
 for tool,args,label in [('quartus_map',['unit'],'map'),('quartus_eda',['unit','--simulation','--tool=modelsim','--format=verilog','--functional=on','--output_directory=functional'],'eda')]:
  q=subprocess.run([str(Q/tool),*args],cwd=d,text=True,capture_output=True,timeout=120);(d/(label+'.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout[-1500:]+q.stderr
 net=(d/'functional/unit.vo').read_text();rpt=(d/'output_files/unit.map.rpt').read_text()
 cells=[]
 for celltype,name,body in re.findall(r'\b(cyclonev_lcell_comb|dffeas)\s+(\\\S+|\w+)\s*\((.*?)\);',net,re.S):
  ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',body));cells.append(dict(type=celltype,name=name,ports=ports))
 (d/'cells.json').write_text(json.dumps(cells,indent=2)+'\n')
 def norm(net):return net.strip().lstrip('!').strip()
 drivers={norm(c['ports']['combout']):c for c in cells if c['type']=='cyclonev_lcell_comb'}
 def path(net,source):
  net=norm(net)
  if net==source:return []
  if net not in drivers:return None
  cell=drivers[net]
  found=[p+[cell['name']] for k,v in cell['ports'].items() if k.startswith('data') for p in [path(v,source)] if p is not None]
  return max(found,key=len) if found else None
 endpoint=next(c['ports']['d'] for c in cells if c['type']=='dffeas' and 'read_en' in c['name'])
 paths={source:path(endpoint,source) for source in ['ar[0]','br[0]']}
 assert all(paths.values()),'read cone missing'
 if mode:assert all(not any('PA[' in cell for cell in p) for p in paths.values()),'read decode still traverses PA mux'
 results[str(mode)]={'combinational_aluts':int(re.search(r'; Combinational ALUT usage for logic\s*;\s*(\d+)',rpt)[1]),'registers':sum(c['type']=='dffeas' for c in cells),'cells':len(cells),'read_cone_paths':paths,'read_cone_lut_levels':{src:len(p) for src,p in paths.items()},'netlist_sha256':hashlib.sha256(net.encode()).hexdigest()}
 print(d.name,results[str(mode)],flush=True)
(O/'summary.json').write_text(json.dumps({'results':results,'source_manifest':manifest,'scope':'Exact-source read-decode tail, native Cyclone V map only. No P65 address-generation cone, fitter, routed delay or full-core timing claim.'},indent=2)+'\n')
