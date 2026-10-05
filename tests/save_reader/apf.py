#!/usr/bin/env python3
"""Check the actual APF capture edge and a stricter 75-cycle derived deadline."""
import argparse,hashlib,json,pathlib,re,subprocess,time
R=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path,default=R/'build/save-reader-apf')
p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=R.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib')
a=p.parse_args();vendor=a.vendor_sim_dir/'altera_mf.v';o=a.output.resolve();o.mkdir(parents=True,exist_ok=True)
if (o/'summary.json').exists():p.error('Use fresh output')
files=[R/x for x in ('target/pocket/data_unloader.sv','rtl/upstream/bram.vhd','platform/pocket/io_bridge_peripheral.v','platform/pocket/common.v','tests/save_reader/tb_apf_reader.sv','tests/save_reader/tb_latch_pressure.sv','tests/save_reader/apf.py','target/pocket/mf_pllbase/mf_pllbase_0002.v','target/pocket/mf_pllbase_pal/mf_pllbase_pal_0002.v')]
def hashes():return {str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in files}
# Keep the fixture clocks bound to the production PLL source values.
for source,mhz in ((files[7],'21.477270'),(files[8],'21.281370')):
 assert re.search(r'\.output_clock_frequency1\("'+mhz+r' MHz"\)',source.read_text())
 assert '.reference_clock_frequency("74.25 MHz")' in source.read_text()
before=hashes();checks=[];measurements=[];complete=False
# Same source-derived production BRAM primitive as run.py, without test models.
bram=files[1].read_text();body=bram[bram.index('entity dpram_dif is'):bram.index('entity dpram_difclk is')]
gm=re.search(r'GENERIC MAP \((.*?)\n\s*\)\s*PORT MAP',body,re.S)[1]
pm=re.search(r'PORT MAP \((.*?)\n\s*\);',body,re.S)[1]
def mapping(m):return ',\n'.join('.'+k.strip()+'('+v.strip().replace(' and ',' && ')+')' for k,v in(item.split('=>')for item in m.split(',')))
ram=o/'ram.sv';ram.write_text('''module dpram_dif #(parameter addr_width_a=8,data_width_a=8,addr_width_b=8,data_width_b=8,parameter mem_init_file="")(
input wire clock,input wire[addr_width_a-1:0]address_a,input wire[data_width_a-1:0]data_a,input wire wren_a,output wire[data_width_a-1:0]q_a,
input wire[addr_width_b-1:0]address_b,input wire[data_width_b-1:0]data_b,input wire wren_b,output wire[data_width_b-1:0]q_b);
wire enable_a=1,enable_b=1,cs_a=1,cs_b=1;wire[data_width_a-1:0]q0;wire[data_width_b-1:0]q1;assign q_a=q0;assign q_b=q1;
altsyncram #(\n'''+mapping(gm)+') altsyncram_component (\n'+mapping(pm)+');\nendmodule\n')
# Quartus accepts procedural inout regs and omitted trailing positional ports;
# Icarus requires equivalent explicit wire/driver declarations and empty ports.
# Do not rewrite any APF state machine, receive logic, synchronization or delay.
s=files[2].read_text()
for sig in ('phy_spimosi','phy_spimiso','phy_spiclk'):
 old='inout   reg             '+sig
 assert s.count(old)==1
 s=s.replace(old,'inout   wire            '+sig)
 s,n=re.subn(r'\b'+sig+r'(\s*<=)',sig+'_drive'+r'\1',s);assert n>0
 s=s.replace('//\n// clock domain: clk',f'reg {sig}_drive;\nassign {sig} = {sig}_drive;\n\n//\n// clock domain: clk',1)
for old,new in [('s00(reset_n, reset_n_s, clk);','s00(reset_n, reset_n_s, clk,,);'),('s01(endian_little, endian_little_s, clk);','s01(endian_little, endian_little_s, clk,,);'),('s03(rx_byte_done, rx_byte_done_s, clk, rx_byte_done_r);','s03(rx_byte_done, rx_byte_done_s, clk, rx_byte_done_r,);')]:
 assert s.count(old)==1;s=s.replace(old,new)
apf=o/'apf-iverilog.v';apf.write_text(s)
def run(name,cmd,expect=None,reject=False):
 t=time.monotonic();r=subprocess.run(list(map(str,cmd)),cwd=R,capture_output=True,text=True,timeout=120);txt=r.stdout+r.stderr
 (o/(name+'.log')).write_text(txt)
 ok=(r.returncode!=0 if reject else r.returncode==0)and(expect is None or expect in txt)
 checks.append(dict(name=name,passed=ok,command=list(map(str,cmd)),returncode=r.returncode,seconds=round(time.monotonic()-t,3)))
 if not ok:raise RuntimeError(name+' failed: '+txt[-2000:])
 for line in txt.splitlines():
  if line.startswith('PASS '):measurements.append(dict(test=line.split()[1],**dict(f.split('=')for f in line.split()[2:])))
def compile_case(name,top,tb,delay=2,reader=None):
 exe=o/(name+'.vvp')
 run(name+'-compile',['iverilog','-g2012','-s',top,f'-P{top}.DELAY={delay}','-o',exe,reader or files[0],tb,ram,apf,files[3],a.vendor_sim_dir/'altera_mf.v'])
 return exe
try:
 actual=compile_case('actual','tb_apf_reader',files[4])
 pressure=compile_case('pressure','tb_latch_pressure',files[5])
 for pal in (0,1):
  for phase in range(16):
   run(f'actual-{pal}-{phase}',['vvp',actual,f'+pal={pal}',f'+phase={phase}','+ss_high_cycles=1'],'PASS APF_READER')
   run(f'pressure-{pal}-{phase}',['vvp',pressure,f'+pal={pal}',f'+phase={phase}','+little=0','+interval=75','+reset_case=1'],'PASS LATCH_PRESSURE')
 late=compile_case('actual-delay7','tb_apf_reader',files[4],7)
 run('actual-delay7-negative',['vvp',late,'+ss_high_cycles=1'], 'APF_LATCH_DEADLINE',True)
 run('pressure-too-fast-negative',['vvp',pressure,'+interval=60'],'APF_EARLY_LATCH_DEADLINE',True)
 # Capture-edge discrimination: make a known correct word available one clk74
 # after APF captures it, still before the next consumer sees its read strobe.
 # The actual latch checker must reject it, even though a strobe-only oracle
 # would see correct data. This is a bench mutation, not a production repair.
 late_tb=o/'tb_late_capture.sv'
 s=files[4].read_text().replace('wire[31:0]addr,result;','wire[31:0]addr;wire[31:0]result;wire[31:0]raw_result;')
 s=s.replace('.bridge_addr(addr),.bridge_rd_data(result)', '.bridge_addr(addr),.bridge_rd_data(raw_result)')
 s=s.replace('integer cycle=0', '''reg[31:0]delayed_result=0;
 assign result=delayed_result;
 always @(posedge src)if(apf.state==apf.ST_READ_1)delayed_result<=raw_result;
 integer cycle=0''')
 late_tb.write_text(s)
 ex=compile_case('one-edge-late','tb_apf_reader',late_tb)
 run('one-edge-late-negative',['vvp',ex,'+ss_high_cycles=1'],'APF_LATCH_DEADLINE',True)
 complete=True
finally:
 stable=before==hashes()
 summary=dict(completed=complete,source_stable=stable,passed=complete and stable and all(x['passed'] for x in checks),source_sha256=before,vendor_model_sha256=hashlib.sha256(vendor.read_bytes()).hexdigest(),generated_sha256={x.name:hashlib.sha256(x.read_bytes()).hexdigest()for x in(ram,apf)},checks=checks,measurements=measurements,limits=['Actual APF state machine, synch_3 and serial stimulus; mechanical Icarus port syntax adapter only','75-cycle direct-strobe pressure captures two consumer clocks early, corroborated against actual APF','SPI stimulus pacing is a reproducible stress condition, not measured firmware or official minimum','No whole-console simulation, fit, CDC physical timing or hardware claim'])
 (o/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
if not summary['passed']:raise SystemExit(1)
print('PASS APF Save reader qualification',len(checks),'checks')
