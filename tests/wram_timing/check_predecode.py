#!/usr/bin/env python3
"""Source-bound WRAM read-decode proof; no behavioral replacement CPU.

Binary SAT is unrestricted. Native VHDL tests std_logic 0/1/X/Z, including all
4^8 low-byte values and uncertain mux qualifiers. This does not assert hazard
or routed-delay equivalence. The real-CPU matrix lives in run.py.
"""
import argparse, hashlib, json, os, pathlib, re, subprocess
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
BASE='982f103a0d7fa39294b760738ceaed5bb88eddad'
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,default=R/'build/wram-predecode-proof');a=p.parse_args();O=a.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment()
checks=[]
def run(name,cmd,expected=None,negative=False):
 q=subprocess.run(list(map(str,cmd)),cwd=O,env=env,text=True,capture_output=True,timeout=180);log=q.stdout+q.stderr;(O/(name+'.log')).write_text(log)
 ok=(q.returncode!=0 if negative else q.returncode==0) and (expected is None or expected in log)
 checks.append(dict(name=name,passed=ok,negative=negative,command=list(map(str,cmd))));assert ok,log[-3000:];print('PASS '+name,flush=True);return log
paths=['rtl/upstream/CPU.vhd','rtl/upstream/SWRAM.vhd','rtl/upstream/SNES.vhd','rtl/upstream/main.v','rtl/mister_top/SNES.sv']
src={f:(R/f).read_text() for f in paths}
old={f:subprocess.check_output(['git','show',BASE+':'+f],cwd=R,text=True) for f in paths}
def extract(text,start,end=';'):
 assert text.count(start)==1,(start,text.count(start));i=text.index(start);return text[i:text.index(end,i)+len(end)]
select='process(P65_A, EN, CPU_RD, CPU_WR, DMA_B,'
cpuproc=extract(src[paths[0]],select,'end process;');assert cpuproc==extract(old[paths[0]],select,'end process;')
side=extract(src[paths[0]],'PA_WMDATA <=')
# Retain all production logic verbatim except the documented sideband and
# generic changes. This catches unrelated phase/state or legacy changes.
cpu=src[paths[0]];cpu=re.sub(r'        -- Parallel B-bus.*?PA_WMDATA.*?;\n','',cpu,flags=re.S)
cpu=re.sub(r'    -- Decode before the byte-wide.*?PA_WMDATA <=.*?;\n\n','',cpu,flags=re.S)
assert cpu==old[paths[0]],'SCPU contains an unproved change beyond the sideband'
for start in ['process( RST_N, CLK )','RAM_D <=','RAM_A','RAM_WE_N <=']:
 end='end process;' if start.startswith('process') else ';'
 # RAM_A's first occurrence is its port, so use the actual assignment anchor.
 if start=='RAM_A':start='RAM_A \t<='
 assert extract(src[paths[1]],start,end)==extract(old[paths[1]],start,end),start
snes=src[paths[2]]
for ent in ['SCPU','SWRAM']:
 block=extract(snes,'entity work.'+ent,'\n\t);')
 assert 'PA_WMDATA   => INT_PA_WMDATA,' in block
assert 'generic map (WMDATA_PREDECODE => WRAM_PREDECODE)' in snes
# The independent APU return-stage generic shares this declaration/instance.
# Still require the exact WRAM default and exact standard-only selector.
generic=re.search(r'entity\s+SNES\s+is\s+generic\s*\((.*?)\);',snes,re.S)
assert generic and re.search(r'\bWRAM_PREDECODE\s*:\s*boolean\s*:=\s*false\s*(?:;|$)',generic[1])
instance=re.search(r'SNES\s*#\s*\((.*?)\)\s*SNES\s*\(',src[paths[3]],re.S)
assert instance and len(re.findall(r'\.WRAM_PREDECODE\s*\(',instance[1]))==1
assert re.search(r'\.WRAM_PREDECODE\s*\(\s*USE_STANDARD_SDRAM\s*\?\s*"TRUE"\s*:\s*"FALSE"\s*\)',instance[1])
assert '.read_en (clearing_ram || block_ram_clients ? 1\'b0 : ~WRAM_CE_N & ~WRAM_OE_N)' in src[paths[4]]
checks.append(dict(name='source_binding_and_unchanged_phases',passed=True))
header='''library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;
entity WramReadDecode is port(
 P65_A:in std_logic_vector(23 downto 0);DMA_B:in std_logic_vector(7 downto 0);
 EN,P65_EN,ENABLE,RAMSEL_N,CPU_RD,CPU_WR:in std_logic;
 DMA_B_RD,DMA_B_WR,DMA_A_RD,DMA_A_WR,HDMA_A_RD,HDMA_A_WR,HDMA_B_RD,HDMA_B_WR,DMA_TRANSFER,HDMA_BUS_ACTIVE:in std_logic;
 PA:out std_logic_vector(7 downto 0);PARD_N,PAWR_N,PA_WMDATA:out std_logic;
 OLD_CE_N,OLD_OE_N,NEW_CE_N,NEW_OE_N:out std_logic;EQUIVALENT,SELECTED_EQ:out std_logic);
end;architecture extracted of WramReadDecode is
 signal INT_CPURD_N,INT_CPUWR_N:std_logic;
 alias CPURD_N:std_logic is INT_CPURD_N;
 constant WMDATA_PREDECODE:boolean:=true;
 signal WMDATA_SEL:std_logic;
begin
'''
body=[cpuproc,side,extract(src[paths[1]],'WMDATA_SEL <=')]
for prefix,s in [('OLD',old[paths[1]]),('NEW',src[paths[1]])]:
 for sig in ['CE','OE']:body.append(extract(s,'RAM_'+sig+'_N <=').replace('RAM_'+sig+'_N',prefix+'_'+sig+'_N'))
body+=['EQUIVALENT <= \'1\' when OLD_CE_N=NEW_CE_N and OLD_OE_N=NEW_OE_N else \'0\';', 'SELECTED_EQ <= \'1\' when (PA=x"80")=(PA_WMDATA=\'1\') else \'0\';']
model=header+'\n'.join(body)+'\nend;\n';(O/'decode.vhd').write_text(model)
try:
 v=run('synthesize_decode',['ghdl','--synth','--std=08','--out=verilog','decode.vhd','-e','WramReadDecode']);(O/'decode.v').write_text(v)
 script='read_verilog decode.v\nprep -top WramReadDecode -flatten\nsat -prove EQUIVALENT 1 -prove SELECTED_EQ 1 -verify\n';(O/'proof.ys').write_text(script)
 run('binary_unrestricted_sat',['yosys','-Q','-s','proof.ys'],'SAT proof finished - no model found: SUCCESS!')
 run('analyze_4state',['ghdl','-a','--std=08','decode.vhd',R/'tests/wram_timing/tb_predecode_4state.vhd'])
 run('four_state_native',['ghdl','-r','--std=08','tb_predecode_4state','--assert-level=error'],'PASS native VHDL four-state')
 # Drop DMA selection while preserving the CPU term: the proof must detect it.
 mutant=model.replace('DMA_B = x"80"','DMA_B = x"81"');assert mutant!=model
 (O/'mutant.vhd').write_text(mutant)
 v=run('synthesize_mutant',['ghdl','--synth','--std=08','--out=verilog','mutant.vhd','-e','WramReadDecode']);(O/'decode.v').write_text(v)
 run('wrong_dma_byte_negative',['yosys','-Q','-s','proof.ys'],'proof did fail',negative=True)
 (O/'decode.v').write_text((O/'synthesize_decode.log').read_text())
finally:
 (O/'summary.json').write_text(json.dumps(dict(baseline=BASE,checks=checks,sources_sha256={f:hashlib.sha256((R/f).read_bytes()).hexdigest() for f in paths},extracted_model_sha256=hashlib.sha256(model.encode()).hexdigest(),limits=['Unrestricted binary combinational SAT; native VHDL four-state finite enumeration','No analog hazards, full console/game, routed timing, board or hardware signoff']),indent=2)+'\n')
