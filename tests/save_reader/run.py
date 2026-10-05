#!/usr/bin/env python3
"""Actual Intel FIFO/RAM Save reader qualification; no firmware pacing claim."""
import argparse,hashlib,json,pathlib,re,subprocess,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=pathlib.Path,default=ROOT/'build/save-reader')
p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=ROOT.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
if (out/'summary.json').exists():p.error('Use a fresh output directory')
files=[ROOT/'target/pocket/data_unloader.sv',ROOT/'rtl/upstream/bram.vhd',ROOT/'tests/save_reader/tb_save_reader.sv',pathlib.Path(__file__).resolve()]
def hashes():return {str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest()for x in files}
before=hashes();checks=[];rows=[];complete=False
# Preserve exact generic/port mappings of the production Intel primitive.
bram=files[1].read_text();body=bram[bram.index('entity dpram_dif is'):bram.index('entity dpram_difclk is')]
gm=re.search(r'GENERIC MAP \((.*?)\n\s*\)\s*PORT MAP',body,re.S)[1]
pm=re.search(r'PORT MAP \((.*?)\n\s*\);',body,re.S)[1]
def mapping(m):return ',\n'.join('.'+k.strip()+'('+v.strip().replace(' and ',' && ')+')'for k,v in(item.split('=>')for item in m.split(',')))
wrapper=out/'ram.sv';wrapper.write_text('''module dpram_dif #(parameter addr_width_a=8,data_width_a=8,addr_width_b=8,data_width_b=8,parameter mem_init_file="")(
input wire clock,input wire[addr_width_a-1:0]address_a,input wire[data_width_a-1:0]data_a,input wire wren_a,output wire[data_width_a-1:0]q_a,
input wire[addr_width_b-1:0]address_b,input wire[data_width_b-1:0]data_b,input wire wren_b,output wire[data_width_b-1:0]q_b);
wire enable_a=1,enable_b=1,cs_a=1,cs_b=1;wire[data_width_a-1:0]q0;wire[data_width_b-1:0]q1;assign q_a=q0;assign q_b=q1;
altsyncram #(\n'''+mapping(gm)+') altsyncram_component (\n'+mapping(pm)+');\nendmodule\n')
def run(name,cmd,expected='PASS SAVE_READER',reject=False):
 t=time.monotonic();r=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,timeout=120);txt=r.stdout+r.stderr
 (out/(name+'.log')).write_text(txt)
 ok=(r.returncode!=0 if reject else r.returncode==0)and(expected is None or expected in txt)
 checks.append(dict(name=name,passed=ok,command=list(map(str,cmd)),returncode=r.returncode,seconds=round(time.monotonic()-t,3)))
 if not ok:raise RuntimeError(name+' failed: '+txt[-1800:])
 for line in txt.splitlines():
  if line.startswith('PASS SAVE_READER'):rows.append(dict(field.split('=')for field in line.split()[2:]))
 return txt
def compile_case(name,safe=1,delay=2,word=2,source=None):
 exe=out/(name+'.vvp')
 run(name+'-compile',['iverilog','-g2012','-s','tb_save_reader',f'-Ptb_save_reader.SAFE={safe}',f'-Ptb_save_reader.DELAY={delay}',f'-Ptb_save_reader.WORD={word}','-o',exe,source or files[0],files[2],wrapper,a.vendor_sim_dir/'altera_mf.v'],None)
 return exe
try:
 exe=compile_case('safe')
 for pal in (0,1):
  for phase in range(16):
   for little in (0,1):
    name=f'pal{pal}-phase{phase}-endian{little}'
    run(name,['vvp',exe,f'+pal={pal}',f'+phase={phase}',f'+little={little}','+interval=75',f'+reset_case={int(phase in (0,7,15))}'])
 old=compile_case('old-unguarded',safe=0)
 run('old-unguarded-rejected',['vvp',old,'+interval=150'],expected='READ_DATA_OR_DEADLINE',reject=True)
 bad=compile_case('too-early-memory',delay=1)
 run('too-early-memory-rejected',['vvp',bad],expected='READ_DATA_OR_DEADLINE',reject=True)
 # The deadline oracle must reject an intentionally excessive read rate.
 run('next-strobe-too-early',['vvp',exe,'+interval=40'],expected='READ_DATA_OR_DEADLINE',reject=True)
 # Retain generic seven-cycle and byte-wide functional behavior at explicit,
 # slower host read pacing; neither is production's measured 75-cycle profile.
 slow=compile_case('safe-delay7',delay=7)
 byte=compile_case('safe-byte',word=1)
 for pal in (0,1):
  for little in (0,1):
   run(f'slow-{pal}-{little}',['vvp',slow,f'+pal={pal}',f'+little={little}','+interval=200','+reset_case=1'])
   run(f'byte-{pal}-{little}',['vvp',byte,f'+pal={pal}',f'+little={little}','+interval=200','+reset_case=1'])
 # Reset and rearm negatives must fail their semantic oracles, not compilation.
 mutant=out/'no-fifo-reset.sv';mutant.write_text(files[0].read_text().replace('SAFE_RESPONSE_HANDSHAKE ? !reset_n : 1\'b0',"1'b0"))
 ex=compile_case('no-fifo-reset',source=mutant)
 run('fifo-reset-negative',['vvp',ex,'+reset_case=1'],expected='POST_RESET_READ_DATA',reject=True)
 mutant=out/'no-source-rearm.sv';mutant.write_text(files[0].read_text().replace('(!SAFE_RESPONSE_HANDSHAKE || source_armed) && ',''))
 ex=compile_case('no-source-rearm',source=mutant)
 run('source-rearm-negative',['vvp',ex,'+reset_case=1'],expected='HELD_READ_REPLAYED_AFTER_RESET',reject=True)
 complete=True
finally:
 after=hashes();summary=dict(completed=complete,source_stable=before==after,passed=complete and before==after and all(c['passed']for c in checks),source_sha256=before,checks=checks,measurements=rows,
 limits=['Real Intel FIFO/BRAM models and source-derived primitive configuration; not a complete console simulation','75 clk74 is a tested read pacing, not a documented minimum firmware interval','Official bridge deadline is before the next read strobe; no wait-state extension is introduced','Unmodeled board/metastability behavior and real firmware pacing require hardware confirmation'])
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
if not summary['passed']:raise SystemExit('FAIL incomplete or source-changing Save reader qualification')
print('PASS SAVE reader qualification',len(checks),'checks')
