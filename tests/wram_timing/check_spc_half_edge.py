#!/usr/bin/env python3
"""Run actual SPC7110 mapper with the proposed negative-edge capture observation.
This is a mapper output phase check, not a second model of the decompressor.
"""
import pathlib,subprocess,tempfile,os,json,argparse,hashlib
R=pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0,str(R/'tests'))
from tool_environment import tool_environment
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=pathlib.Path(os.environ.get('QUARTUS_SIM_LIB',R.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib')));a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
env=tool_environment()
D=R/'rtl/upstream/chip/SPC7110';vendor=a.vendor_sim_dir.resolve();checks=[]
missing=[f for f in ['220pack.vhd','220model.vhd','altera_mf_components.vhd','altera_mf.vhd'] if not (vendor/f).is_file()]
if missing:p.error('NOT RUN: approved Quartus vendor models absent; pass --vendor-sim-dir or set QUARTUS_SIM_LIB (missing: '+', '.join(missing)+')')
with tempfile.TemporaryDirectory(prefix='wram-spc-phase-') as td:
 w=pathlib.Path(td);flags=['--std=08','-fsynopsys','--workdir='+str(w)]
 def run(name,cmd):
  q=subprocess.run(cmd,cwd=R,env=env,text=True,capture_output=True,timeout=120);(a.out/(name+'.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout+q.stderr;return q.stdout
 for lib,files in [('lpm',['220pack.vhd','220model.vhd']),('altera_mf',['altera_mf_components.vhd','altera_mf.vhd'])]:
  wd=w/lib;wd.mkdir();run(lib,['ghdl','-a','--std=08','-fsynopsys','--work='+lib,'--workdir='+str(wd),*[str(vendor/f) for f in files]]);flags+=['-P'+str(wd)]
 original=(R/'tests/decoder_waits/tb_spc7110_mapper.vhd').read_text()
 old="procedure read_byte(a:natural;expected:std_logic_vector(7 downto 0);subowner:natural:=0) is\n  begin"
 new=old.replace('\n  begin','\n   variable staged_byte:std_logic_vector(7 downto 0);\n  begin')
 assert old in original;s=original.replace(old,new)
 old="ce_r<='1';rd<='0';tick;ce_r<='0';tick;"
 new="""ce_r<='1';rd<='0';tick;ce_r<='0';
   wait until falling_edge(clk);staged_byte:=q;wait for 1 ns;
   assert q=staged_byte and staged_byte=expected
    report "SPC negative-edge capture disagrees with settled real output" severity failure;
   report "SPC_HALF_CAPTURE "&to_hstring(ca)&" "&to_hstring(staged_byte);
   tick;"""
 assert old in s;s=s.replace(old,new);(w/'tb.vhd').write_text(s)
 sources=[D/'SPC7110_DEC_PKG.vhd',D/'SPC7110_DEC.vhd',R/'tests/decoder_waits/spc7110_dec_baseline.vhd',R/'rtl/upstream/chip/SA1/SA1RomBridge.vhd',R/'rtl/upstream/chip/RTC4513.vhd',D/'SPC7110_FIFO.vhd',D/'SPC7110_MULDIV.vhd',D/'SPC7110.vhd',D/'SPC7110Map.vhd']
 run('compile',['ghdl','-a',*flags,*map(str,sources),str(w/'tb.vhd')])
 for mode,offset in [(0,0),(1,0),(2,0),(2,9)]:
  name=f'mode{mode}-offset{offset}';log=run(name,['ghdl','-r',*flags,'tb_spc7110_mapper',f'-gMODE_ID={mode}',f'-gOFFSET_WORDS={offset}','--assert-level=error','--ieee-asserts=disable']);n=log.count('SPC_HALF_CAPTURE');assert n>70 and 'SPC mapper PASS' in log;checks.append({'mode':mode,'offset':offset,'captures':n});print(name,n,'PASS')
 (a.out/'summary.json').write_text(json.dumps({'checks':checks,'sources_sha256':{str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sources},'bench_sha256':hashlib.sha256(original.encode()).hexdigest(),'scope':'Actual SPC7110 mapper registered/ROM/DP output stable across negative-edge decoder work; not full console mixed-language execution'},indent=2)+'\n')
