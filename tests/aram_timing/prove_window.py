#!/usr/bin/env python3
"""Bound every legal residual physical PSRAM state at an ARAM address change.
The state counts are computed from the exact source macros, not a proposed
external latency. This checks window sufficiency, not CPU/DSP equivalence.
"""
import math,pathlib,re,json,argparse,os,subprocess
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
def ceil_macro(x):
 # Verilog rtoi(integer) rounds input on conversion, then CEIL handles either
 # side; equals mathematical ceil for the nonintegral production values.
 return math.ceil(x)
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path);a=p.parse_args()
 ps=(R/'target/pocket/psram.sv').read_text();dsp=(R/'rtl/upstream/DSP_PKG.vhd').read_text()
 assert 'STATE_READ_DATA_RECEIVED = READ_INITIAL_COUNT + TOTAL_READ_CYCLE_COUNT' in ps
 assert 'state <= STATE_NONE;' in ps and 'data_out <= cram_dq;' in ps
 assert 'parameter MAX_ACCESS_TIME_FROM_ADV = 70' in ps
 assert 'parameter MIN_WRITE_TIME_FROM_ADV = 70' in ps
 top=(R/'rtl/mister_top/SNES.sv').read_text()
 speed=float(re.search(r'psram #\(\s*\.CLOCK_SPEED\(([\d.]+)\)\s*\) aram',top)[1])
 out=a.output.resolve().parent if a.output else R/'build/aram';out.mkdir(parents=True,exist_ok=True)
 env=tool_environment()
 commands=[['iverilog','-g2012','-s','tb_psram_constants','-Ptb_psram_constants.CLOCK_SPEED='+str(speed),'-o',str(out/'constants.vvp'),str(R/'target/pocket/psram.sv'),str(R/'tests/aram_timing/tb_psram_constants.sv')],['vvp',str(out/'constants.vvp')]]
 for index,command in enumerate(commands):
  q=subprocess.run(command,cwd=R,env=env,text=True,capture_output=True,timeout=30);(out/f'constants-{index}.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout+q.stderr
 values=dict((key,int(value)) for key,value in re.findall(r'(\w+)=(\d+)',next(line for line in q.stdout.splitlines() if line.startswith('PSRAM_CONSTANTS'))))
 ret=values['read_gap'];write_ret=values['write_gap']
 assert ret==1+values['read_total'] and write_ret==1+values['write_total']
 assert ret==1+ceil_macro(float(re.search(r'parameter MAX_ACCESS_TIME_FROM_ADV = ([\d.]+)',ps)[1])/(1000/speed))
 assert values['accept_interval']==ret+1 and ret==8 and write_ret==8
 # t=0 is the sys rising edge at which the address changes. A coincident
 # controller edge can still accept the old bus. Take that as the worst case.
 rows=[]
 def rate_constant(name):return int(re.search(r'constant\s+'+name+r'\s*:\s*integer\s*:=\s*(\d+)',dsp)[1])
 for region,rate in [('NTSC',rate_constant('MCLK_NTSC_FREQ')),('PAL',rate_constant('MCLK_PAL_FREQ'))]:
  for freq in [rate_constant('ACLK_TYPE_FREQ'),rate_constant('ACLK_REAL_FREQ')]:
   min_sys=rate//freq;capture_mem=4*min_sys-2
   assert min_sys==5
   for kind in ['idle','read','write']:
    for remaining in ([0] if kind=='idle' else range(1,(write_ret if kind=='write' else ret)+1)):
     # Idle on the coincident launch edge may accept OLD: include that path.
     old_remaining=ret if kind=='idle' else remaining
     # On completion the state becomes idle, accepting new on next edge.
     first_new=old_remaining+1+ret
     slack=capture_mem-first_new
     assert slack>=1,(region,freq,kind,remaining,first_new,capture_mem)
     rows.append(dict(region=region,apu_hz=freq,old_kind=kind,old_remaining_mem=remaining,
       new_return_mem=first_new,stage_mem=capture_mem,margin_mem=slack))
 result={'passed':True,'cases':len(rows),'min_stage_margin_mem':min(r['margin_mem'] for r in rows),
 'production_constant_probe':values,'psram_clock_speed_parameter_mhz':speed,'read_accept_to_return_mem':ret,'minimum_CE_interval_sys':5,'stage_before_consume_sys':0.5,
 'current_profile_structural_guards':['Pocket spc_download=0 makes IO_WR=0',
 'USE_SS defaults false and core_top does not override it; DSP/SMP restore selects are zero',
 'Standard main reset directly includes ram_clear_busy/reset; no consume during clearing',
 'CEGen reset is RST_N AND ENABLE, including during disabled restore tests'],
 'environment_assumptions':['Any separate caller enabling the stage with live IO_WR or selected SS_WR must hold reset/disable until restore finishes; not proved for arbitrary enabled injection',
 'Memory contents are changed only by the actual PSRAM controller transaction writes',
 'sys and mem4x retain the same PLL relationship and duty cycles',
 'CEGen has been held reset while disabled; first re-enabled CE cannot arrive earlier than five sys cycles'],
 'cases_detail':rows}
 if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n')
 print('PASS ARAM window',len(rows),'legal residual-state/frequency cases; worst target return t=17, sample t=18, consume t=20 mem edges')
if __name__=='__main__':main()
