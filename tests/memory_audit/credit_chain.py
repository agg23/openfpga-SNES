#!/usr/bin/env python3
import argparse,pathlib,tempfile,subprocess,re,os,json,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--bsx-root',type=pathlib.Path,default=ROOT);p.add_argument('--output',type=pathlib.Path);a=p.parse_args();B=a.bsx_root/'rtl/upstream/chip/BSX';results=[]
env=os.environ.copy();env['PATH']='/tmp/msu1-tools/bin:'+env.get('PATH','')
with tempfile.TemporaryDirectory(prefix='credit-chain-') as tmp:
 w=pathlib.Path(tmp)
 ram=(ROOT/'rtl/upstream/bram.vhd').read_text();i=ram.index('entity dpram is');j=ram.index('end entity;',i)+len('end entity;')
 vals=re.findall(r'^\s*([0-9A-F]+)\s*:\s*([0-9A-F]+);',(B/'bsx121-124.mif').read_text(),re.M)
 assert len(vals)==550
 init=',\n'.join(str(int(i,16))+'=>x"'+v+'"' for i,v in vals)+",others=>(others=>'0')"
 (w/'ram.vhd').write_text('library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;\n'+ram[i:j]+'''
architecture simulation of dpram is
 type memory_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
 signal mem:memory_t := ('''+init+'''); begin
 process(clock) begin if rising_edge(clock) then
 if enable_a='1' and cs_a='1' then if wren_a='1' then mem(to_integer(unsigned(address_a)))<=data_a;end if;q_a<=mem(to_integer(unsigned(address_a)));end if;
 if enable_b='1' and cs_b='1' then if wren_b='1' then mem(to_integer(unsigned(address_b)))<=data_b;end if;q_b<=mem(to_integer(unsigned(address_b)));end if;
 end if;end process;end;
''')
 sources=[ROOT/'rtl/upstream/65C816'/(x+'.vhd') for x in ['P65816_pkg','AddrGen','BCDAdder','AddSubBCD','ALU','MCode','P65C816']]
 sources += [ROOT/'rtl/upstream/CPU.vhd',w/'ram.vhd']+[B/(x+'.vhd') for x in ['BSX_BS','BSX_MCC','BSX_DP','BSXMemoryBridge','BSXMap']]+[ROOT/'tests/memory_audit/tb_scpu_bsx_credit_chain.vhd']
 def call(action,*args):return subprocess.run(['ghdl',action,'--std=08','-fsynopsys','--workdir='+str(w),*map(str,args)],env=env,cwd=ROOT,text=True,capture_output=True,timeout=120)
 r=call('-a',*sources);assert r.returncode==0,r.stdout+r.stderr
 for mutated in [False,True]:
  r=call('-r','tb_scpu_bsx_credit_chain','-gMISWIRE='+str(mutated).lower(),'--assert-level=error','--ieee-asserts=disable')
  print(r.stdout+r.stderr)
  results.append({'stale_MDR_mutation':mutated,'returncode':r.returncode,'output':r.stdout+r.stderr})
  assert (r.returncode!=0 and 'LOOKAHEAD_CREDIT' in r.stdout) if mutated else (r.returncode==0 and 'PASS actual SCPU' in r.stdout)
 if a.output:a.output.write_text(json.dumps({'sources_sha256':{str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources if x!=w/'ram.vhd'},'bsx_mif_sha256':hashlib.sha256((B/'bsx121-124.mif').read_bytes()).hexdigest(),'results':results},indent=2)+'\n')
 print('PASS real SCPU→BSX chain and stale-MDR wiring mutation')
