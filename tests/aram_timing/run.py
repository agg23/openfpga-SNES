#!/usr/bin/env python3
"""Actual SMP/SPC700 + DSP + PSRAM controller return-edge equivalence.
Only the FPGA dual-port primitive and external asynchronous PSRAM array are
modeled. CPU/DSP/control/PSRAM transaction state machines are repository RTL.
"""
import argparse,hashlib,json,os,pathlib,subprocess,time
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,default=R/'build/aram');p.add_argument('--build-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--quick',action='store_true');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment();env['TMPDIR']=str(O)
def run(name,cmd,timeout=240):
 t=time.monotonic();q=subprocess.run(list(map(str,cmd)),env=env,cwd=O,capture_output=True,text=True,timeout=timeout);(O/(name+'.log')).write_text(q.stdout+q.stderr)
 if q.returncode:raise RuntimeError(name+': '+(q.stdout+q.stderr)[-6000:])
 print(name,'PASS',round(time.monotonic()-t,2),flush=True);return q.stdout
sp=[R/'rtl/upstream/SPC700'/(n+'.vhd') for n in ['SPC700_pkg','AddrGen','AddSub','BCDAdj','ALU','MCode','MulDiv','SPC700']]+[R/'rtl/upstream/SMP.vhd']
# Avoid GHDL's generated instance-port net colliding with the upstream
# SPC700_D_OUT signal. Rename the instance label only in the simulation copy.
smp_normalized=O/'SMP-normalized.vhd';smp_normalized.write_text((R/'rtl/upstream/SMP.vhd').read_text().replace('SPC700: entity work.SPC700','CPUcore: entity work.SPC700'));sp[-1]=smp_normalized
(O/'program.hex').write_bytes((R/'tests/aram_timing/program.hex').read_bytes())
bram=(R/'rtl/upstream/bram.vhd').read_text();s=bram.index('entity dpram is');e=bram.index('end entity;',s)+len('end entity;')
# Exact production parameters: registered addresses, unregistered outputs,
# NEW_DATA_NO_NBE_READ and zero-initialized memory. Both ports share the clock.
for f in ['outdata_reg_a => "UNREGISTERED"','outdata_reg_b => "UNREGISTERED"','power_up_uninitialized => "FALSE"','read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ"','read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ"']:assert f in bram
ram=O/'ram.vhd';ram.write_text('library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;\n'+bram[s:e]+'''
architecture simulation of dpram is
 type memory_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
 signal mem:memory_t := (others=>(others=>'0'));
 signal aa,ab:unsigned(addr_width-1 downto 0):=(others=>'0');
 begin
 process(clock) begin if rising_edge(clock) then
 if enable_a='1' then aa<=unsigned(address_a);if wren_a='1' and cs_a='1' then mem(to_integer(unsigned(address_a)))<=data_a;end if;end if;
 if enable_b='1' then ab<=unsigned(address_b);if wren_b='1' and cs_b='1' then mem(to_integer(unsigned(address_b)))<=data_b;end if;end if;
 end if;end process;
 q_a<=mem(to_integer(aa)) when cs_a='1' else (others=>'1');
 q_b<=mem(to_integer(ab)) when cs_b='1' else (others=>'1');
end architecture;
''')
# GHDL cannot synthesize the upstream mixed combinational/clocked process
# variable LR. Its clocked use always assigns it before reading it; split only
# that local variable's name, preserving all statements and RTL expressions.
import re
def normalize_dsp(source):
 start=source.index('process(CLK, RST_N, RS, BRR_VOICE');end=source.index('end process;',start)
 chunk=source[start:end].replace('variable LR: integer range 0 to 1;', 'variable LR: integer range 0 to 1;\n variable LR_SEQ: integer range 0 to 1;')
 k=chunk.index("if RST_N = '0' then");chunk=chunk[:k]+re.sub(r'\bLR\b','LR_SEQ',chunk[k:])
 return source[:start]+chunk+source[end:]
dsp_normalized=O/'DSP-normalized.vhd';dsp_normalized.write_text(normalize_dsp((R/'rtl/upstream/DSP.vhd').read_text()))
ref_source=subprocess.check_output(['git','show','982f103:rtl/upstream/DSP.vhd'],cwd=R,text=True)
dsp_reference=O/'DSP-reference.vhd';dsp_reference.write_text(normalize_dsp(ref_source))
dsp=[ram,R/'rtl/upstream/DSP_PKG.vhd',R/'rtl/upstream/CEGen.vhd',dsp_normalized]
if not a.skip_build:
 for ent,src,label in [('SMP',sp,'SMP'),('DSP',dsp,'DSP'),('DSP',dsp[:-1]+[dsp_reference],'DSP_ref')]:
  v=run('synth-'+label,['ghdl','--synth','--std=08','-fsynopsys','--latches','--out=verilog',*(['-gARAM_RETURN_STAGE=true'] if label=='DSP' else []),*src,'-e',ent])
  if label=='DSP_ref':
   names=re.findall(r'^module (\w+)',v,re.M)
   for name in names:v=re.sub(r'\b'+name+r'\b',name+'_ref',v)
  (O/(label+'.v')).write_text(v)
 run('verilate',['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_aram_return','--Mdir',O/'obj','-j','1','-O1',O/'SMP.v',O/'DSP.v',O/'DSP_ref.v',R/'target/pocket/psram.sv',R/'tests/aram_timing/tb_aram_return.sv'],timeout=600)
if a.build_only:raise SystemExit(0)
records=[]
source_files=[*sp[:-1],R/'rtl/upstream/SMP.vhd',R/'rtl/upstream/DSP.vhd',*dsp[1:3],R/'rtl/upstream/bram.vhd',R/'rtl/upstream/SNES.vhd',R/'rtl/upstream/main.v',R/'target/pocket/psram.sv',R/'tests/aram_timing/tb_aram_return.sv',R/'tests/aram_timing/program.hex',R/'tests/aram_timing/run.py',R/'tests/tool_environment.py']
hashes={str(f.relative_to(R)):hashlib.sha256(f.read_bytes()).hexdigest() for f in source_files}
for pal in [0,1]:
 for freq in [0,1]:
  for phase in ([0] if a.quick else range(4)):
   name=f'pal{pal}-freq{freq}-phase{phase}'
   out=run(name,[O/'obj/Vtb_aram_return',f'+pal={pal}',f'+freq={freq}',f'+phase={phase}'],timeout=240);assert 'PASS ARAM_RETURN' in out
   records.append({'name':name,'output':out})
for mutation in [1,2]:
 q=subprocess.run([str(O/'obj/Vtb_aram_return'),f'+mutation={mutation}'],cwd=O,env=env,text=True,capture_output=True,timeout=240)
 (O/f'mutation{mutation}.log').write_text(q.stdout+q.stderr)
 assert q.returncode!=0 and 'ARAM_CONSUME_MISMATCH' in q.stdout,q.stdout+q.stderr
 print('PASS expected negative control',mutation,flush=True)
 records.append({'mutation':mutation,'detected':True,'returncode':q.returncode,'output':q.stdout})
assert hashes=={str(f.relative_to(R)):hashlib.sha256(f.read_bytes()).hexdigest() for f in source_files},'Sources changed during execution'
(O/'summary.json').write_text(json.dumps({'checks':records,'sources_sha256':hashes,'primitive_model_sha256':hashlib.sha256(ram.read_bytes()).hexdigest()},indent=2)+'\n')
