#!/usr/bin/env python3
"""Directed owner-progress tests; no fairness or whole-game proof is implied.

Real SCPU + shared bridge under bounded synthetic ROM timing and saturated second
client; real SA1 + P65C816 program under phase-constrained continuous SNES reads.
Never changes production RTL or arbitration policy and never runs fit/STA.
"""
import argparse,hashlib,json,os,pathlib,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=pathlib.Path,default=ROOT/'build/owner-liveness')
args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
if (out/'summary.json').exists():parser.error('output already has summary.json; use a fresh directory')
os.environ['OWNER_LIVENESS_OUTPUT']=str(out)
for tool in ('ghdl','iverilog','vvp'):
    if not shutil.which(tool):raise SystemExit('NOT RUN: missing '+tool)
parts=['P65816_pkg','AddrGen','BCDAdder','AddSubBCD','ALU','MCode','P65C816']
scpu=[ROOT/'rtl/upstream/65C816'/(p+'.vhd') for p in parts]+[ROOT/'rtl/upstream/CPU.vhd']
helper=ROOT/'rtl/upstream/chip/SA1/SA1RomBridge.vhd';bench=ROOT/'tests/owner_liveness/tb_scpu_owner_liveness.sv'
sources=[*scpu,helper,bench,ROOT/'tests/owner_liveness/run_sa1_liveness.py',
         ROOT/'rtl/upstream/chip/SA1/SA1.vhd',ROOT/'rtl/upstream/chip/SA1/SA1DIV.vhd',
         ROOT/'tests/sa1/tb_sa1_actual_wait.vhd',ROOT/'tests/sa1/sa1_test_program.vhd',
         ROOT/'tests/sa1/sa1_primitives.vhd',ROOT/'tests/test_sa1_memory_wait.py',pathlib.Path(__file__).resolve()]
before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
checks=[];scpu_results=[];finished=False
def run(name,cmd,expected=None,reject=False,save=None):
    r=subprocess.run(list(map(str,cmd)),cwd=ROOT,text=True,capture_output=True,timeout=180)
    text=r.stdout+r.stderr;(out/(name+'.log')).write_text(text)
    if save is not None:save.write_text(r.stdout)
    passed=(r.returncode!=0 if reject else r.returncode==0) and (expected is None or expected in text)
    checks.append({'name':name,'passed':passed,'command':list(map(str,cmd))})
    if not passed:raise RuntimeError(name+' failed: '+str(out/(name+'.log')))
    return r.stdout
try:
    run('synthesize-scpu',['ghdl','--synth','--std=08','-fsynopsys','--latches','--out=verilog',*scpu,'-e','SCPU'],save=out/'scpu.v')
    run('synthesize-bridge',['ghdl','--synth','--std=08','--out=verilog',helper,'-e','SA1RomBridge'],save=out/'bridge.v')
    for turbo in (0,1):
        for owner in (1,2,3):
            for delay in (0,1,7,31,127):
                name=f'scpu-{turbo}-{owner}-{delay}';exe=out/name
                run(name+'-compile',['iverilog','-g2012','-s','tb_scpu_owner_liveness',
                    f'-Ptb_scpu_owner_liveness.INTERNAL_OWNER={owner}',
                    f'-Ptb_scpu_owner_liveness.RESPONSE_DELAY={delay}',
                    f'-Ptb_scpu_owner_liveness.TURBO={turbo}','-o',exe,out/'scpu.v',out/'bridge.v',bench])
                text=run(name,['vvp',exe],expected='PASS SCPU_LIVENESS')
                line=next(l for l in text.splitlines() if l.startswith('PASS SCPU_LIVENESS'))
                row={k:int(v) for k,v in (field.split('=') for field in line.split()[2:])}
                scpu_results.append(row);print(line,flush=True)
    # Prove the bench detects starvation rather than merely observing some work.
    mutant=out/'starve-internal.vhd';text=helper.read_text()
    old="if not found and NEED(PRIORITY(p))='1' and"
    assert text.count(old)==1
    mutant.write_text(text.replace(old,"if not found and PRIORITY(p)=0 and NEED(PRIORITY(p))='1' and"))
    run('starvation-mutant-synth',['ghdl','--synth','--std=08','--out=verilog',mutant,'-e','SA1RomBridge'],save=out/'starve.v')
    run('starvation-mutant-compile',['iverilog','-g2012','-s','tb_scpu_owner_liveness','-o',out/'starve',out/'scpu.v',out/'starve.v',bench])
    run('starvation-mutant',['vvp',out/'starve'],expected='STARVATION',reject=True)
    print('PASS starvation negative control',flush=True)
    text=run('sa1-live-program',[sys.executable,ROOT/'tests/owner_liveness/run_sa1_liveness.py'],expected='PASS SA1 liveness response')
    print(text,flush=True);finished=True
finally:
    after={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    summary={'execution_finished':finished,'passed':finished and before==after and all(c['passed'] for c in checks),
             'source_stable':before==after,'source_sha256':before,'checks':checks,'scpu_results':scpu_results,
             'scope':'Bounded synthetic ROM timing; actual SCPU and helper, then actual SA1/P65 program. Not whole-core or unrestricted-software fairness proof.'}
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
