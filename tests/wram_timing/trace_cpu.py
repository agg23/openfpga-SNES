import pathlib,subprocess,os,argparse
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,default=pathlib.Path('/tmp/wram-timing'));args=p.parse_args();O=args.out.resolve();O.mkdir(parents=True,exist_ok=True)
env=tool_environment()
parts=[str(R/'rtl/upstream/65C816'/(n+'.vhd')) for n in ['P65816_pkg','AddrGen','BCDAdder','AddSubBCD','ALU','MCode','P65C816']]+[str(R/'rtl/upstream/CPU.vhd'),str(R/'rtl/upstream/SWRAM.vhd')]
for ent, module, generics in [('SCPU','SCPU',[]),('SWRAM','SWRAM',[]),('SWRAM','SWRAM_PREDECODE',['-gWMDATA_PREDECODE=true'])]:
 p=subprocess.run(['ghdl','--synth','--std=08','-fsynopsys','--latches','--out=verilog',*generics,*parts,'-e',ent],env=env,cwd=O,capture_output=True,text=True);assert p.returncode==0,p.stderr
 assert p.stdout.count('module '+ent+'\n')==1
 (O/(module+'.v')).write_text(p.stdout.replace('module '+ent+'\n','module '+module+'\n',1))
snes=(R/'rtl/upstream/SNES.vhd').read_text()
ins={'INT_CA':24,'INT_PA':8,'DI':8,'PPU_DO':8,'SMP_CPU_DO':8,'WRAM_DO':8,'CPU_DO':8,'INT_RAMSEL_N':1,'INT_PARD_N':1}
outs={'CPU_DI':8,'WRAM_DI':8,'CART_DO':8}
ports=[]
for mode,d in [('in',ins),('out',outs)]:
 for n,w in d.items():ports.append(n+':'+mode+' '+('std_logic' if w==1 else f'std_logic_vector({w-1} downto 0)'))
body=[]
for n in ['BUSA_SEL','BUSA_DO','BUSB_SEL','BUSB_DO','CPU_DI','WRAM_DI']:
 a=snes.index(n+' <=');body.append(snes[a:snes.index(';',a)+1])
a=snes.index('\n\tDO <=');body.append(snes[a:snes.index(';',a)+1].replace('DO <=','CART_DO <=',1))
v='library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;\nentity WramMux is port('+ ';'.join(ports)+');end;\narchitecture exact of WramMux is\nsignal BUSA_SEL,BUSB_SEL:std_logic;signal BUSA_DO,BUSB_DO:std_logic_vector(7 downto 0);\nbegin\n'+'\n'.join(body)+'\nend;'
(O/'mux.vhd').write_text(v)
p=subprocess.run(['ghdl','--synth','--std=08','--out=verilog',str(O/'mux.vhd'),'-e','WramMux'],env=env,cwd=O,capture_output=True,text=True);assert p.returncode==0,p.stderr;(O/'WramMux.v').write_text(p.stdout)
