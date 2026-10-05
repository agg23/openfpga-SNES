#!/usr/bin/env python3
"""Actual BSX mapper/flash integration plus immutable b63 legacy equivalence.
Only the synchronous dual-port RAM primitive is modeled; its original MIF bytes
are loaded exactly. No mapper, RTC, MCC or flash state machine is replaced.
"""
import pathlib,subprocess,tempfile,re,os,json,hashlib,argparse
ROOT=pathlib.Path(__file__).resolve().parents[1]
BASE='b63f8001856ec69d425d19eb110d2d208dea1243'
B=ROOT/'rtl/upstream/chip/BSX'
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--mutation',choices=['posted-order','posted-drain','snes-ready','cpu-credit','dma-credit']);args=ap.parse_args()
 with tempfile.TemporaryDirectory(prefix='bsx-map-') as d:
  w=pathlib.Path(d)
  def run(*p,ok=True):
   r=subprocess.run(['ghdl',*p[:1],'--std=08','-fsynopsys','--workdir='+d,*map(str,p[1:])],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
   if ok and r.returncode:raise RuntimeError(r.stdout)
   return r
  ram=(ROOT/'rtl/upstream/bram.vhd').read_text();a=ram.index('entity dpram is');b=ram.index('end entity;',a)+len('end entity;')
  vals=re.findall(r'^\s*([0-9A-F]+)\s*:\s*([0-9A-F]+);', (B/'bsx121-124.mif').read_text(),re.M)
  assert len(vals)==550
  init=',\n'.join(str(int(a,16))+'=>x"'+b+'"' for a,b in vals)+",others=>(others=>'0')"
  model='library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;\n'+ram[a:b]+'''
architecture simulation of dpram is
 type memory_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
 signal mem:memory_t := ('''+init+''');
 begin
 process(clock) begin if rising_edge(clock) then
 if enable_a='1' and cs_a='1' then if wren_a='1' then mem(to_integer(unsigned(address_a)))<=data_a;end if;q_a<=mem(to_integer(unsigned(address_a)));end if;
 if enable_b='1' and cs_b='1' then if wren_b='1' then mem(to_integer(unsigned(address_b)))<=data_b;end if;q_b<=mem(to_integer(unsigned(address_b)));end if;
 end if;end process;
end architecture;
'''
  (w/'ram.vhd').write_text(model)
  source=(B/'BSXMap.vhd').read_text()
  if args.mutation=='posted-order':source=source.replace('and not post_pending and not flush_i','and not flush_i').replace('(post_pending or not mem_ready(0))','(not mem_ready(0))')
  if args.mutation=='posted-drain':source=source.replace('mem_committed <= "0100"','mem_committed <= "0000"')
  if args.mutation=='snes-ready':source=source.replace('(post_pending or not mem_ready(0))',"(post_pending or '0')")
  if args.mutation=='cpu-credit':source=source.replace('DP_CREDIT_DATA => ROM_SNES_WRITE_DATA','DP_CREDIT_DATA => DI')
  if args.mutation=='dma-credit':source=source.replace("ROM_SNES_OWNER/=\"00\" and dp_busy='1'", 'false')
  (w/'BSXMap.vhd').write_text(source)
  run('-a',w/'ram.vhd',B/'BSX_BS.vhd',B/'BSX_MCC.vhd',B/'BSX_DP.vhd',B/'BSXMemoryBridge.vhd',w/'BSXMap.vhd',ROOT/'tests/memory_ready/tb_bsx_map_waits.vhd')
  r=run('-r','tb_bsx_map_waits','--assert-level=error','--ieee-asserts=disable',ok=not args.mutation)
  print(r.stdout.strip())
  if args.mutation:
   if not r.returncode:raise RuntimeError('Mutation survived')
   expected={'posted-order':'BSX read mismatch','posted-drain':'posted write incorrectly flush-acked','snes-ready':'BSX read mismatch','cpu-credit':'CPU_CREDIT','dma-credit':'DMA_CREDIT'}[args.mutation]
   if expected not in r.stdout:raise RuntimeError('Unrelated mutation failure')
   print('PASS mutation rejected:',args.mutation);return
  for latency in [0,1,31]:
   r=run('-r','tb_bsx_map_waits','-gLATENCY='+str(latency),'--assert-level=error','--ieee-asserts=disable');print(r.stdout.strip())
  # Analyze the exact original datapak and mapper under distinct entity names.
  for file,old,new in [('BSX_DP.vhd','DATAPAK','DATAPAK_REF'),('BSXMap.vhd','BSXMap','BSXMap_REF')]:
   text=subprocess.check_output(['git','show',BASE+':rtl/upstream/chip/BSX/'+file],cwd=ROOT,text=True)
   text=re.sub(r'\b'+old+r'\b',new,text)
   if file=='BSXMap.vhd':text=text.replace('work.DATAPAK','work.DATAPAK_REF')
   (w/(new+'.vhd')).write_text(text);run('-a',w/(new+'.vhd'))
  original=subprocess.check_output(['git','show',BASE+':rtl/upstream/chip/BSX/BSXMap.vhd'],cwd=ROOT,text=True)
  ports=re.findall(r'^\s*(\w+)\s*:\s*(in|out)\s+(std_logic(?:_vector\([^\n]+?\))?)',original.split('end BSXMap;')[0],re.M|re.I)
  decl=[];maps=[[],[]];assertions=[];inputs={}
  for name,direction,typ in ports:
   if direction=='in':
    init="(others=>'0')" if 'vector' in typ else "'0'"
    decl.append(f'signal {name}: {typ} := {init};');inputs[name]=typ
    for m in maps:m.append(name+'=>'+name)
   else:
    for i in range(2):decl.append(f'signal {name}_{i}: {typ};');maps[i].append(name+'=>'+name+'_'+str(i))
    assertions.append(f'assert {name}_0 = {name}_1 report "legacy mismatch {name}" severity failure;')
  tb='library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.env.all;\nentity tb_bsx_legacy is end;architecture test of tb_bsx_legacy is\n'+'\n'.join(decl)+'\nbegin\nMCLK<=not MCLK after 5 ns;\n'
  tb+='a:entity work.BSXMap port map('+','.join(maps[0])+');\n'
  tb+='b:entity work.BSXMap_REF port map('+','.join(maps[1])+');\n'
  tb+='''process variable x:unsigned(31 downto 0):=x"CAFEBABE"; begin
 MAP_CTRL<=x"30";ROM_MASK<=x"FFFFFF";BSRAM_MASK<=x"FFFFFF";
 wait for 30 ns;RST_N<='1';
 for n in 0 to 19999 loop
 wait until falling_edge(MCLK);
 x:=x(30 downto 0)&(x(31) xor x(21) xor x(1) xor x(0));
 CA<=std_logic_vector(x(23 downto 0));DI<=std_logic_vector(x(7 downto 0));ROM_Q<=std_logic_vector(x(23 downto 8));
 BSRAM_Q<=std_logic_vector(x(31 downto 24));ENABLE<=not x(5);CPURD_N<=x(0);CPUWR_N<=x(1);
 SYSCLKF_CE<=x(2);SYSCLKR_CE<=not x(2);PA<=std_logic_vector(x(15 downto 8));PARD_N<=x(3);PAWR_N<=x(4);
 if n mod 307=0 then RST_N<='0';else RST_N<='1';end if;
 wait until rising_edge(MCLK);wait for 1 ns;
 '''+'\n'.join(assertions)+'''
 end loop;report "PASS 20000-cycle BSX legacy-off exact output equivalence to b63";stop;end process;end;'''
  (w/'legacy.vhd').write_text(tb);run('-a',w/'legacy.vhd');r=run('-r','tb_bsx_legacy','--assert-level=error','--ieee-asserts=disable');print(r.stdout.strip())
  print('PASS actual BSX mapper wait suite')
if __name__=='__main__':main()
