#!/usr/bin/env python3
import argparse,pathlib,subprocess,hashlib,json
R=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,default=R/'build/save-reader-legacy');p.add_argument('--vendor-sim-dir',type=pathlib.Path,default=R.parent/'toolchain/intelFPGA_lite/21.1/quartus/eda/sim_lib');a=p.parse_args();o=a.output.resolve();o.mkdir(parents=True,exist_ok=True)
if(o/'summary.json').exists():p.error('Use fresh output')
src=[R/'target/pocket/data_unloader.sv',R/'tests/save_reader/reference_data_unloader.sv',R/'tests/save_reader/tb_legacy_cycle.sv',pathlib.Path(__file__).resolve()]
def hashes():return{str(x.relative_to(R)):hashlib.sha256(x.read_bytes()).hexdigest()for x in src}
before=hashes();checks=[];complete=False
try:
 for early in (0,1):
  for w in (1,2):
   for d in (1,2,7):
    name=f'w{w}-d{d}-early{early}';exe=o/name
    c=['iverilog','-g2012','-s','tb_legacy_cycle',f'-Ptb_legacy_cycle.WORD={w}',f'-Ptb_legacy_cycle.DELAY={d}',f'-Ptb_legacy_cycle.EARLY_READ={early}','-o',str(exe),*map(str,src[:-1]),str(a.vendor_sim_dir/'altera_mf.v')]
    r=subprocess.run(c,capture_output=True,text=True,timeout=120);(o/(name+'-compile.log')).write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
    r=subprocess.run(['vvp',str(exe)],capture_output=True,text=True,timeout=120);txt=r.stdout+r.stderr;(o/(name+'.log')).write_text(txt)
    ok=r.returncode==0 and 'PASS LEGACY_CYCLE' in txt;checks.append(dict(name=name,passed=ok));assert ok,txt[-1000:]
 # Independent review found that unconditional reset synchronization changes
 # the very first legacy read. Preserve an executable negative control.
 mutant=o/'unconditional-aclr-sync.sv';text=src[0].read_text();assert text.count('SAFE_RESPONSE_HANDSHAKE ? "ON" : "OFF"')==4
 mutant.write_text(text.replace('SAFE_RESPONSE_HANDSHAKE ? "ON" : "OFF"','"ON"'))
 exe=o/'early-read-negative'
 c=['iverilog','-g2012','-s','tb_legacy_cycle','-Ptb_legacy_cycle.EARLY_READ=1','-o',str(exe),str(mutant),*map(str,src[1:-1]),str(a.vendor_sim_dir/'altera_mf.v')]
 r=subprocess.run(c,capture_output=True,text=True,timeout=120);(o/'early-read-negative-compile.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
 r=subprocess.run(['vvp',str(exe)],capture_output=True,text=True,timeout=120);txt=r.stdout+r.stderr;(o/'early-read-negative.log').write_text(txt)
 ok=r.returncode!=0 and 'LEGACY_CYCLE_MISMATCH'in txt;checks.append(dict(name='unconditional-aclr-sync-early-read',passed=ok,negative=True));assert ok,txt
 complete=True
finally:
 stable=before==hashes();s=dict(completed=complete,source_stable=stable,passed=complete and stable and all(x['passed']for x in checks),source_sha256=before,checks=checks,scope='12 parameter/startup combinations, 30000 clk74 edges each; actual Intel FIFOs; synthetic common memory input. Default parameter preserves original cycle trace including its known underflow; not a proof of functional backup safety.')
 (o/'summary.json').write_text(json.dumps(s,indent=2)+'\n')
if not s['passed']:raise SystemExit(1)
print('PASS legacy default cycle equivalence',len(checks),'checks including early-read negative')
