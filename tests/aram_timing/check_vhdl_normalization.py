#!/usr/bin/env python3
"""Simulate original VHDL, GHDL-only normalized VHDL and legacy-default candidate.
This independently checks that the mixed-language translation accommodations do
not change DSP behavior and the opt-out preserves original behavior.
"""
import pathlib,argparse,subprocess,re,os,json
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,default=R/'build/aram');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment()
def run(name,cmd):
 q=subprocess.run(list(map(str,cmd)),cwd=O,env=env,text=True,capture_output=True,timeout=180);(O/(name+'.log')).write_text(q.stdout+q.stderr)
 assert q.returncode==0,q.stdout+q.stderr
 return q.stdout
orig=subprocess.check_output(['git','show','982f103:rtl/upstream/DSP.vhd'],cwd=R,text=True);(O/'DSP-original.vhd').write_text(orig)
libs=[]
for lib,source in [('original',O/'DSP-original.vhd'),('normalized',O/'DSP-reference.vhd'),('legacy',R/'rtl/upstream/DSP.vhd')]:
 wd=O/lib;wd.mkdir(exist_ok=True);libs.append('-P'+str(wd))
 run('vhdl-'+lib,['ghdl','-a','--std=08','-fsynopsys','--work='+lib,'--workdir='+str(wd),O/'ram.vhd',R/'rtl/upstream/DSP_PKG.vhd',R/'rtl/upstream/CEGen.vhd',source])
ports=re.findall(r'^\s*(\w+)\s*:\s*(in|out)\s+(std_logic(?:_vector\([^\n]+?\))?)',orig.split('end DSP;')[0],re.M|re.I)
decl=[];maps=[[],[],[]];inputs=[];outputs=[]
for name,direction,typ in ports:
 if direction=='in':
  decl.append(f"signal {name}:{typ}:="+("(others=>'0')" if 'vector' in typ else "'0'")+";")
  for m in maps:m.append(name+'=>'+name)
 else:
  outputs.append(name)
  for j in range(3):
   decl.append(f'signal {name}_{j}:{typ};');maps[j].append(name+'=>'+name+'_'+str(j))
tb='library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;library original,normalized,legacy;\nentity tb_normalization is end;architecture test of tb_normalization is\n'+'\n'.join(decl)+'\nbegin\nCLK<=not CLK after 5 ns;\n'
for j,lib in enumerate(['original','normalized','legacy']):tb+=f'd{j}:entity {lib}.DSP port map('+','.join(maps[j])+');\n'
tb+='''process variable lfsr:unsigned(31 downto 0):=x"AC537B19"; begin
 for n in 0 to 79999 loop
  wait until falling_edge(CLK);
  lfsr:=lfsr(30 downto 0)&(lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
  if n mod 10000 < 3 then RST_N<='0';else RST_N<='1';end if;
  ENABLE<=not lfsr(0);PAL<=lfsr(5);FREQ<=lfsr(7);
  RAM_Q<=std_logic_vector(lfsr(7 downto 0));
  SMP_A<=std_logic_vector(lfsr(23 downto 8));SMP_DO<=std_logic_vector(lfsr(31 downto 24));SMP_WE<=lfsr(11);
  SS_ADDR<=std_logic_vector(to_unsigned(n mod 128,9));SS_DI<=std_logic_vector(lfsr(15 downto 8));
  if n mod 10000 < 128 then SS_WR<='1';SS_REGS_SEL<='1';else SS_WR<='0';SS_REGS_SEL<=lfsr(17);end if;
  wait until rising_edge(CLK);wait for 1 ns;
'''
for name in outputs:
 tb+=f'assert {name}_0={name}_1 report "NORMALIZATION {name}" severity failure;\n'
 tb+=f'assert {name}_0={name}_2 report "LEGACY_DEFAULT {name}" severity failure;\n'
tb+='end loop; report "PASS 80000 actual VHDL cycles: original=normalized=legacy-default, all DSP ports";stop;end process;end;\n'
(O/'normalization.vhd').write_text(tb)
run('vhdl-normalization-analyze',['ghdl','-a','--std=08','-fsynopsys',*libs,O/'normalization.vhd'])
out=run('vhdl-normalization',['ghdl','-r','--std=08','-fsynopsys',*libs,'tb_normalization','--assert-level=error','--ieee-asserts=disable']);print(out.strip())
