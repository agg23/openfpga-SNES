#!/usr/bin/env python3
"""Native five-output PLL unit synthesis only; never fits or edits the core project."""
from pathlib import Path
import argparse,subprocess,os,re,json
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--quartus-bin',type=Path,required=True);p.add_argument('--output',default='build/pll5x-unit');a=p.parse_args()
qb=a.quartus_bin.resolve();out=(ROOT/a.output).resolve();records=[]
for region,freqs,mode,shift in [('ntsc',(85.909080,21.477270,10.738635,107.386350),'normal',23280),('pal',(85.125480,21.281370,10.640685,106.406850),'direct',23495)]:
 d=out/region;d.mkdir(parents=True,exist_ok=True)
 params=[('fractional_vco_multiplier','"true"'),('reference_clock_frequency','"74.25 MHz"'),('operation_mode','"'+mode+'"'),('number_of_clocks','5')]
 for i,f in enumerate([freqs[0],freqs[1],freqs[2],freqs[2],freqs[3]]):
  params += [(f'output_clock_frequency{i}',f'"{f:.6f} MHz"'),(f'phase_shift{i}',f'"{shift if i==3 else 0} ps"'),(f'duty_cycle{i}','50')]
 params += [('pll_type','"General"'),('pll_subtype','"General"')]
 source='module pll5x_unit(input wire refclk,rst,output wire [4:0] clocks,output wire locked);\n altera_pll #(\n'+',\n'.join(' .'+k+'('+v+')'for k,v in params)+') pll(.refclk(refclk),.rst(rst),.outclk(clocks),.locked(locked),.fbclk(1\'b0),.fboutclk());\nendmodule\n'
 (d/'pll5x_unit.sv').write_text(source)
 (d/'pll5x_unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "pll5x_unit"\n')
 (d/'pll5x_unit.qsf').write_text('''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY pll5x_unit
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name SYSTEMVERILOG_FILE pll5x_unit.sv
''')
 for exe,args,log in [('quartus_map',['pll5x_unit','--read_settings_files=on','--write_settings_files=off'],'map.log'),('quartus_eda',['pll5x_unit','--simulation','--tool=modelsim','--format=verilog','--functional=on','--output_directory=functional'],'eda.log')]:
  r=subprocess.run([str(qb/exe),*args],cwd=d,capture_output=True,text=True);(d/log).write_text(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError(str(d/log)+' failed')
 net=(d/'functional/pll5x_unit.vo').read_text();divs={i:0 for i in range(5)}
 for idx,side,v in re.findall(r'general\[(\d+)\]\.gpll~PLL_OUTPUT_COUNTER \.dprio0_cnt_(hi|lo)_div = (\d+);',net):divs[int(idx)]+=int(v)
 assert list(divs.values())==[10,40,80,80,8],divs
 report=(d/'output_files/pll5x_unit.map.rpt').read_text();assert re.search(r'; Total PLLs\s*; 1\s*;',report)
 vco=re.search(r'FRACTIONAL_PLL \.output_clock_frequency = "([0-9.]+) mhz"',net).group(1)
 record={'region':region,'passed':True,'physical_plls_in_map_summary':1,'divisors':divs,'vco_mhz':vco,'limits':'unit map/netlist only, no fitted clock insertion/phase or board timing claim'}
 records.append(record);print(record)
(out/'summary.json').write_text(json.dumps(records,indent=2)+'\n')
