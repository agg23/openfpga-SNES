#!/usr/bin/env python3
"""Map the REAL old/new wrapper QIPs and audit all five counters plus normal SDC.

Unit Analysis & Synthesis, functional technology-netlist export, and post-map
TimeQuest only. No fitter, assembler, commercial ROM or live project mutation.
Output must be new; all native logs and generated inputs are preserved.
"""
import argparse
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def require(test, message):
    if not test: raise RuntimeError(message)

def parse_counter_netlist(text):
    counters={}
    for idx,attribute,value in re.findall(r'defparam \\[^\n ]*general\[(\d+)\]\.gpll~PLL_OUTPUT_COUNTER \.([a-z0-9_]+) = ([^;]+);',text):
        counters.setdefault(int(idx),{})[attribute]=value.strip('"')
    vcos=re.findall(r'defparam \\[^\n ]*FRACTIONAL_PLL \.output_clock_frequency = "([0-9.]+) mhz";',text)
    require(len(vcos)==1,'Expected exactly one native VCO')
    pll=dict(re.findall(r'FRACTIONAL_PLL \.([a-z0-9_]+) = ([^;]+);',text))
    m=int(pll['pll_m_cnt_hi_div'])+int(pll['pll_m_cnt_lo_div'])
    k=int(pll['pll_fractional_division']) % (2**32)
    n=1 if pll['pll_n_cnt_bypass_en']=='"true"' else int(pll['pll_n_cnt_hi_div'])+int(pll['pll_n_cnt_lo_div'])
    physical_vco=Fraction('74.25')*(m+Fraction(k,2**32))/n
    for index,counter in counters.items():
        hi=int(counter['dprio0_cnt_hi_div']); lo=int(counter['dprio0_cnt_lo_div'])
        counter['divisor']=hi+lo
        counter['physical_frequency_at_ideal_reference_mhz']=float(physical_vco/(hi+lo))
        require(counter['duty_cycle']=='50','Non-50% native output')
        require(hi==lo or (hi==lo+1 and counter['dprio0_cnt_odd_div_even_duty_en']=='true'), 'Physical divider does not implement 50% duty')
        require(counter['dprio0_cnt_bypass_en']=='false','Unexpected divider bypass')
        require(counter['cnt_fpll_src']=='fpll_0' and counter['c_cnt_in_src']=='ph_mux_clk','Wrong physical source')
        require(counter['c_cnt_ph_mux_prst']=='0','Unexpected fine phase tap')
        require(counter['c_cnt_coarse_dly']=='0 ps' and counter['c_cnt_fine_dly']=='0 ps','Unexpected additional phase delay')
        if index != 3:
            require(counter['phase_shift']=='0 ps' and counter['c_cnt_prst']=='1','Nonzero zero-phase counter reset')
        else:
            require(int(counter['c_cnt_prst'])-1==(hi+lo)//4,'Video native phase no longer one-quarter period')
    return {'vco_mhz':float(vcos[0]),'physical_vco_at_ideal_reference_mhz':float(physical_vco),
            'physical_fractional_divider':{'M':m,'K_unsigned':k,'fraction_denominator':2**32,'N':n},'counters':counters}

def run(qb, exe, args, cwd, log):
    result=subprocess.run([str(qb/exe),*args],cwd=cwd,env=os.environ,capture_output=True,text=True)
    log.write_text(result.stdout+result.stderr)
    require(result.returncode==0,f'{exe} failed: {log}')
    return result.stdout+result.stderr

def clocks_tsv(path):
    out={}
    for line in path.read_text().splitlines():
        name,attr,value=line.split('\t',2)
        out.setdefault(name,{})[attr]=value
    return out

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--quartus-bin',type=Path,required=True)
    p.add_argument('--output',type=Path,default=Path('build/standard-pll-clocks'))
    a=p.parse_args();qb=a.quartus_bin.resolve();out=a.output.resolve()
    require(not out.exists(),'Refusing to replace existing evidence')
    out.mkdir(parents=True);records={}
    for region in ['ntsc','pal']:
      for standard in [False,True]:
        name=f'{region}-'+('standard' if standard else 'legacy')
        d=out/name;d.mkdir()
        old='mf_pllbase'+('_pal' if region=='pal' else '')
        wrapper=old+('_sdram' if standard else '')
        fifth=', .outclk_4(clocks[4])' if standard else ''
        assign='' if standard else 'assign clocks[4]=clocks[0];'
        source=f'''module pll_clock_unit(input wire clk_74a,clk_74b,bridge_spiclk,rst,seed,output wire [4:0] clocks,output wire locked,output wire [7:0] observed);
clock_unit_core ic(.*);
endmodule
module clock_unit_core(input wire clk_74a,clk_74b,bridge_spiclk,rst,seed,output wire [4:0] clocks,output wire locked,output wire [7:0] observed);
{wrapper} mp1(.refclk(clk_74a),.rst(rst),.outclk_0(clocks[0]),.outclk_1(clocks[1]),.outclk_2(clocks[2]),.outclk_3(clocks[3]){fifth},.locked(locked));
{assign}
(* preserve *) reg [7:0] q=8'h00;
always @(posedge clocks[0]) begin q[0]<=q[2]^seed; q[1]<=q[4]^seed; end
always @(posedge clocks[1]) begin q[2]<=q[0]^seed; q[3]<=q[4]^seed; end
always @(posedge clocks[4]) begin q[4]<=q[0]^seed; q[5]<=q[2]^seed; end
always @(posedge clk_74b) q[6]<=seed;
always @(posedge bridge_spiclk) q[7]<=seed;
assign observed=q;
endmodule
'''
        (d/'pll_clock_unit.sv').write_text(source)
        (d/'pll_clock_unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "pll_clock_unit"\n')
        # A snapshot-only SDC records derived clocks at their normal position;
        # no replacement clocks or source routes are inserted by the probe.
        (d/'snapshot.sdc').write_text('if {[llength [info commands pocket_unit_dump_clocks]]} {pocket_unit_dump_clocks original.tsv}\n')
        (d/'premap-audit.sdc').write_text('''# Unit-only evidence: reaches this include only after the production helper/groups.
if {$::quartus(nameofexecutable) eq "quartus_map"} {
    set premap_out [open premap-native.tsv w]
    foreach_in_collection premap_clock [get_clocks *] {
        foreach premap_attr {type period waveform master_clock master_clock_pin divide_by multiply_by phase offset duty_cycle edges edge_shifts is_inverted} {
            puts $premap_out "[get_clock_info -name $premap_clock]\\t$premap_attr\\t[get_clock_info -$premap_attr $premap_clock]"
        }
    }
    close $premap_out
}
''')
        (d/'pll_clock_unit.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY pll_clock_unit
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name SYSTEMVERILOG_FILE pll_clock_unit.sv
set_global_assignment -name SYNTH_PROTECT_SDC_CONSTRAINT ON
set_global_assignment -name QIP_FILE {ROOT}/target/pocket/{wrapper}.qip
set_global_assignment -name SDC_FILE {ROOT}/platform/pocket/apf_constraints.sdc
set_global_assignment -name SDC_FILE snapshot.sdc
set_global_assignment -name SDC_FILE {ROOT}/target/pocket/core_constraints.sdc
set_global_assignment -name SDC_FILE premap-audit.sdc
''')
        mapping=run(qb,'quartus_map',['pll_clock_unit','--read_settings_files=on','--write_settings_files=off'],d,d/'map.log')
        require('Warning (330000)' not in mapping,'Pre-map helper disabled timing-driven synthesis')
        require((d/'premap-native.tsv').exists(),'Production SDC did not complete in native pre-map context')
        run(qb,'quartus_eda',['pll_clock_unit','--simulation','--tool=modelsim','--format=verilog','--functional=on','--output_directory=functional'],d,d/'eda.log')
        net=(d/'functional/pll_clock_unit.vo').read_text()
        native=parse_counter_netlist(net)
        require(len(native['counters'])==(5 if standard else 4),'Wrong number of physical counters')
        report=(d/'output_files/pll_clock_unit.map.rpt').read_text()
        require(re.search(r'; Total PLLs\s*; 1\s*;',report),'Not exactly one PLL in map report')
        expected=[10,40,80,80,8] if standard else ([7,28,56,56] if region=='ntsc' else [8,32,64,64])
        require([native['counters'][i]['divisor'] for i in range(len(expected))]==expected,'Unexpected mapped divisors')
        sta=run(qb,'quartus_sta',['-t',str(ROOT/'tools/validate_standard_sdram_clocks.tcl'),str(d),str(int(standard))],d,d/'sta.log')
        require('STANDARD_CLOCK_UNIT_PASS' in sta,'Missing native STA completion marker')
        require('Warning (332088)' not in sta,'Generated-clock source lost actual source latency')
        require('Critical Warning (332199)' not in sta,'Post-map request used a fitted DB')
        require(sta.count('POCKET_COUNTER_EDGES name=')==(3 if standard else 2),'Wrong replacement count')
        before=clocks_tsv(d/'original.tsv'); after=clocks_tsv(d/'aligned.tsv')
        native['model_rounding']={}
        for idx in [0,1]+([4] if standard else []):
            target=next(n for n in after if f'general[{idx}].gpll~PLL_OUTPUT_COUNTER|divclk' in n)
            ideal=1000/float(native['counters'][idx]['output_clock_frequency'].split()[0])
            native['model_rounding'][idx]={'ideal_period_ns':ideal,'original_period_ns':float(before[target]['period']),
                'aligned_period_ns':float(after[target]['period']),'aligned_minus_ideal_ps':1000*(float(after[target]['period'])-ideal),
                'edges':after[target]['edges'],'master':after[target]['master_clock']}
        native['map_only']=True;native['source_wrapper']=wrapper
        native['premap_native_clocks']=clocks_tsv(d/'premap-native.tsv')
        native['netlist_sha256']=hashlib.sha256(net.encode()).hexdigest()
        records[name]=native
        print(f'PASS {name}: one physical PLL, counters={expected}, normal post-map SDC',flush=True)
      legacy=records[region+'-legacy']; standard=records[region+'-standard']
      for i in range(4):
        for attr in ['output_clock_frequency','phase_shift','duty_cycle']:
            require(legacy['counters'][i][attr]==standard['counters'][i][attr],f'{region} output {i} changed {attr}')
        # Different legal VCOs quantize the fractional M word differently.
        # Keep the actual, sub-Hz change visible instead of claiming exact analog equality.
        delta=1e6*(standard['counters'][i]['physical_frequency_at_ideal_reference_mhz']-legacy['counters'][i]['physical_frequency_at_ideal_reference_mhz'])
        standard['counters'][i]['physical_frequency_change_from_legacy_hz']=delta
        require(abs(delta)<0.2,'Unexpected fractional-M frequency drift')
      require(Decimal(standard['counters'][4]['output_clock_frequency'].split()[0])==5*Decimal(standard['counters'][1]['output_clock_frequency'].split()[0]),'Not exactly 5x nominal sys')
    (out/'summary.json').write_text(json.dumps({'status':'PASS','results':records,
        'limits':'Unit map and post-map normal read_sdc only. No physical clock routing, board delay, fitted timing, hardware or ROM compatibility result.'},indent=2)+'\n')
    print('PASS original four native frequency/phase/duty attributes unchanged in both regions')

if __name__=='__main__':main()
