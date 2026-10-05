#!/usr/bin/env python3
"""Prove a universal binary transition/output miter of actual mapped PSRAMs.

The exported native LUT masks and connections are retained. Register Qs are
matched by their exact stable native names and universally quantified. The
DFFEAS transition is modeled only after rejecting unsupported async controls
or priority modes. All pad-driver data AND output-enables are compared;
external DQ input is a common unconstrained value, leaving bus resolution to
an identical environment. The original vendor atoms also run in pin simulation.
"""
import argparse,hashlib,json,os,pathlib,re,subprocess
R=pathlib.Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=pathlib.Path,required=True);p.add_argument('--map',type=pathlib.Path,default=R/'build/wram-state-map');p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-state-proof');a=p.parse_args();M=a.map.resolve();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env['PATH']='/tmp/msu1-tools/bin:'+env.get('PATH','');lib=a.quartus_bin.resolve().parent/'eda/sim_lib'
# Independently validate the supported FF transition abstraction against the
# installed official sequential atom for both Q values and all 32 controls.
for label,cmd in [('dffeas-compile',['iverilog','-g2012','-s','tb_wram_state_dffeas','-o',O/'dffeas',lib/'altera_primitives.v',R/'tests/timing/tb_wram_state_dffeas.sv']),('dffeas-exhaustive',['vvp',O/'dffeas'])]:
 r=subprocess.run(list(map(str,cmd)),cwd=R,env=env,text=True,capture_output=True,timeout=30);(O/(label+'.log')).write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
 if label=='dffeas-exhaustive':assert 'PASS official DFFEAS 64' in r.stdout
records={m:json.loads((M/m/'cells.json').read_text()) for m in ['baseline','state_data_only']}
regs={m:{c['name']:c for c in cs if c['type']=='dffeas'} for m,cs in records.items()};names=sorted(regs['baseline']);assert names==sorted(regs['state_data_only'])
for n in names:
 b,c=(regs[m][n] for m in regs);assert b['params']==c['params'],('initialization/priority mismatch',n)
 for cell in [b,c]:
  ports=cell['ports'];assert all(ports[x].strip()==v for x,v in [('aload','gnd'),('clrn','vcc'),('prn','vcc'),('devclrn','devclrn'),('devpor','devpor')]),cell
  assert cell['params'].get('sclr_over_ena','"false"')=='"false"',cell
  assert ports['clk'].strip()=='\\clk~input1',('unexpected register clock',cell)
  assert cell['params'].get('power_up') in ['"low"','"high"'],('unspecified initialization',cell)
obs={m:{c['name']:c for c in cs if c['type']=='cyclonev_io_obuf'} for m,cs in records.items()};pads=sorted(obs['baseline']);assert pads==sorted(obs['state_data_only'])
# Reuse the exact official combinational primitive rather than invent LUT masks.
vendor=(lib/'cyclonev_atoms.v').read_text();start=vendor.index('module cyclonev_lcell_comb (');stop=vendor.index('endmodule',start)+len('endmodule');lut=vendor[start:stop];(O/'vendor_lut.v').write_text(lut+'\n')
pat=r'\b(cyclonev_lcell_comb|dffeas|cyclonev_io_ibuf|cyclonev_io_obuf)\s+(\\\S+|\w+)\s*\((.*?)\);'
input_names=['clk','bank_sel','write_en','write_high_byte','write_low_byte','read_en','addr','data_in','cram_dq','cram_wait']
widths={'clk':1,'bank_sel':2,'write_en':2,'write_high_byte':2,'write_low_byte':2,'read_en':2,'addr':44,'data_in':32,'cram_dq':32,'cram_wait':2}
for mode in records:
 raw=(M/mode/'functional/unit.vo').read_text();text=raw.replace('module psram_state_map_unit (','module '+mode+' (',1);text=text.replace('\n\tcram_a);','\n\tcram_a,qstate,next_state,pad_data,pad_oe);',1)
 pos=text.index('input \tclk;');text=text[:pos]+f'input [{len(names)-1}:0] qstate;output [{len(names)-1}:0] next_state;output [{len(pads)-1}:0] pad_data,pad_oe;\n'+text[pos:]
 text=re.sub(r'\binout(\s+\[31:0\]\s+cram_dq;)','input'+r'\1',text)
 text=re.sub(r'assign cram_dq\[\d+\]\s*=.*?;','',text)
 def replace(m):
  typ,n,body=m.groups();ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',body));ps={k:v.strip()+' ' for k,v in ports.items()}
  if typ=='cyclonev_lcell_comb':return m[0]
  if typ=='dffeas':
   i=names.index(n);return f'assign {ps["q"]}=qstate[{i}];\nassign next_state[{i}]={ps["ena"]}? ({ps["sclr"]}?1\'b0:({ps["sload"]}?{ps["asdata"]}:{ps["d"]})):qstate[{i}];'
  if typ=='cyclonev_io_ibuf':
   assert ports['ibar'].strip()=='gnd';return f'assign {ps["o"]}={ps["i"]};'
  if typ=='cyclonev_io_obuf':
   cell=obs[mode][n];assert cell['params']['open_drain_output']=='"false"' and cell['params']['bus_hold']=='"false"';i=pads.index(n)
   return f'assign {ps["o"]}={ps["i"]};\nassign pad_data[{i}]={ps["i"]};assign pad_oe[{i}]={ps["oe"]};'
 text=re.sub(pat,replace,text,flags=re.S)
 # Removed cells no longer have instance parameters. Preserve every native LUT parameter.
 removed={c['name'] for c in records[mode] if c['type']!='cyclonev_lcell_comb'}
 text=re.sub(r'defparam\s+(\\\S+|\w+)\s+\.(\w+)\s*=\s*([^;]+);',lambda m:'' if m[1] in removed else m[0],text)
 # Native EDA defparams are inside simulation-only translate comments. Formal
 # must retain those actual LUT masks, never accept the primitive defaults.
 text=text.replace('// synopsys translate_off','').replace('// synopsys translate_on','')
 text=text.replace('tri1 devclrn;','wire devclrn=1\'b1;').replace('tri1 devpor;','wire devpor=1\'b1;').replace('tri1 devoe;','wire devoe=1\'b1;')
 (O/(mode+'.v')).write_text(text)
ports=','.join(('input '+(f'[{widths[n]-1}:0] ' if widths[n]>1 else '')+n) for n in input_names)
ports+=f',input [{len(names)-1}:0] qstate,output equivalent,output states_equal,output pins_equal'
body=[f'module miter({ports});',f'wire [{len(names)-1}:0] bn,cn;wire [{len(pads)-1}:0] bd,cd,be,ce;']
conn=','.join('.'+n+'('+n+')' for n in input_names)+',.qstate(qstate)'
for mode,prefix in [('baseline','b'),('state_data_only','c')]:body.append(f'{mode} {prefix}({conn},.next_state({prefix}n),.pad_data({prefix}d),.pad_oe({prefix}e));')
body+=['assign states_equal=bn==cn;assign pins_equal=(bd==cd)&&(be==ce);assign equivalent=states_equal&&pins_equal;endmodule']
(O/'miter.v').write_text('\n'.join(body)+'\n')
script='read_verilog -sv vendor_lut.v baseline.v state_data_only.v miter.v\nprep -top miter -flatten\nsat -prove equivalent 1 -prove states_equal 1 -prove pins_equal 1 -verify -show-inputs -show-outputs\n';(O/'proof.ys').write_text(script)
q=subprocess.run(['yosys','-Q','-s','proof.ys'],cwd=O,env=env,text=True,capture_output=True,timeout=120);(O/'proof.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout[-4000:]+q.stderr
assert 'SAT proof finished - no model found: SUCCESS!' in q.stdout
# Corrupt exactly one native state next-bit. The same all-state miter must fail.
original=(O/'state_data_only.v').read_text();state_bit=names.index('\\ic|snes|wram|state[0]')
pattern=r'(assign next_state\['+str(state_bit)+r'\]=)(.*?);'
mutant,count=re.subn(pattern,lambda m:m[1]+'~('+m[2]+');',original);assert count==1
(O/'state_data_only.v').write_text(mutant)
q=subprocess.run(['yosys','-Q','-s','proof.ys'],cwd=O,env=env,text=True,capture_output=True,timeout=120);(O/'corrupt-state-negative.log').write_text(q.stdout+q.stderr)
(O/'state_data_only.v').write_text(original)
assert q.returncode!=0 and 'proof did fail' in q.stdout+q.stderr,'corruption was not detected'
summary={'passed':True,'official_dffeas_exhaustive_transitions':64,'corrupt_state_negative_detected':True,'matched_registers':len(names),'matched_pad_drivers':len(pads),'inductive_scope':'All binary register valuations and all binary inputs; equal per-register power-up parameters plus equal next-state and pad data/OE functions imply unbounded sequential equivalence under the same clock and DQ environment','register_names':names,'pad_names':pads,'native_netlists_sha256':{m:hashlib.sha256((M/m/'functional/unit.vo').read_bytes()).hexdigest() for m in records},'vendor_lut_sha256':hashlib.sha256(lut.encode()).hexdigest(),'limits':['Not arbitrary X-pessimism or SDF/glitch/analog equivalence','No reset port exists in PSRAM; all externally driven request/quiesce/clear sequences are unrestricted binary inputs','Unit synthesis model; later full-core fit must verify assignment binding and routed timing']}
(O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print('PASS universal mapped transition/output equivalence:',len(names),'registers;',len(pads),'pin drivers')
