#!/usr/bin/env python3
"""Prove the four-way ROM-owner slice change and optionally measure native area.

Actual complete helper RTL, six priority permutations, and two rejected mutants.
The paired async2sync formal model is complemented by the existing actual-chip
GHDL lifecycle regressions; this is not a physical timing/CDC proof. Native mode
runs analysis/synthesis ONLY, never fitting or STA, and installs nothing.
"""
import argparse
import hashlib
import itertools
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
REL = 'rtl/upstream/chip/SA1/SA1RomBridge.vhd'
BASELINE = 'af743650efbef9f44a4e2cd5b4690ecdb708473d'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=pathlib.Path, default=ROOT/'build/rom-owner-mux')
p.add_argument('--quartus-sh', type=pathlib.Path, help='Installed official Quartus; enables unit maps, not fit')
a = p.parse_args()
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
for tool in ('git', 'ghdl', 'yosys'):
    if not shutil.which(tool): raise SystemExit('NOT RUN: missing '+tool)
rtl = ROOT/REL
before = subprocess.check_output(['git', 'show', BASELINE+':'+REL], cwd=ROOT, text=True)
after = rtl.read_text()
hashes = {'before': hashlib.sha256(before.encode()).hexdigest(),
          'after': hashlib.sha256(after.encode()).hexdigest()}
(out/'before.vhd').write_text(before)
(out/'after.vhd').write_text(after)
checks = []; maps = []
def run(name, cmd, expected=None, rejected=False):
    result = subprocess.run(list(map(str, cmd)), cwd=ROOT, text=True, capture_output=True, timeout=180)
    log = result.stdout+result.stderr
    (out/(name+'.log')).write_text(log)
    passed = (result.returncode != 0 if rejected else result.returncode == 0)
    passed = passed and (expected is None or expected in log)
    checks.append({'name': name, 'passed': passed, 'command': list(map(str, cmd))})
    if not passed: raise RuntimeError(name+' failed: '+str(out/(name+'.log')))
    return result.stdout

def prove(label, priority, new_source, rejected=False):
    generics = [f'-gP{i+1}={v}' for i,v in enumerate(priority)]
    for side,source in [('before',out/'before.vhd'), ('after',new_source)]:
        verilog = run(label+'-'+side+'-synth', ['ghdl','--synth','--std=08','--out=verilog',
                      *generics,source,'-e','SA1RomBridge'])
        (out/(label+'-'+side+'.v')).write_text(verilog)
    # Hide only GHDL-generated intermediate nets. Keep named architectural state
    # such as next_tag, so induction may establish its paired invariant.
    script = ''
    for side in ('before','after'):
        script += f'''read_verilog {out/(label+'-'+side+'.v')}
prep -top SA1RomBridge
async2sync
rename -hide w:n*_o w:n*_q
rename SA1RomBridge {side}_bridge
design -stash {side}
'''
    script += '''design -copy-from before -as before_bridge before_bridge
design -copy-from after -as after_bridge after_bridge
equiv_make before_bridge after_bridge equiv
hierarchy -top equiv
equiv_simple
equiv_induct -seq 4
equiv_status -assert
'''
    ys=out/(label+'.ys'); ys.write_text(script)
    run(label, ['yosys','-s',ys], expected='unproven $equiv cells' if rejected else 'Equivalence successfully proven!', rejected=rejected)
    print('PASS '+label, flush=True)

def native_map(side, priority):
    label='map-'+side+'-'+''.join(map(str,priority))
    work=out/label;work.mkdir(exist_ok=True)
    (work/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
    qsf=f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY SA1RomBridge
set_global_assignment -name VHDL_FILE "{out/(side+'.vhd')}"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
set_instance_assignment -name VIRTUAL_PIN ON -to *
'''
    qsf+=''.join(f'set_parameter -name P{i+1} -entity SA1RomBridge {v}\n' for i,v in enumerate(priority))
    (work/'unit.qsf').write_text(qsf)
    tcl=work/'map.tcl';tcl.write_text(f'load_package flow\ncd {{{work}}}\nproject_open unit\nexecute_module -tool map\nproject_close\n')
    run(label, [a.quartus_sh.resolve(),'-t',tcl], expected='was successful')
    report=(work/'output_files/unit.map.rpt').read_text(errors='replace')
    def value(name):
        found=re.search(r';\s*'+re.escape(name)+r'\s*;\s*([\d,]+)',report)
        if not found: raise RuntimeError('Missing native resource '+name)
        return int(found[1].replace(',',''))
    row={'variant':side,'priority':[0,*priority],
         'combinational_aluts':value('Combinational ALUT usage for logic'),
         'registers':value('Total registers'),'dsp_blocks':value('Total DSP Blocks'),
         'estimated_alms':value('Estimate of Logic utilization (ALMs needed)'),
         'report_sha256':hashlib.sha256((work/'output_files/unit.map.rpt').read_bytes()).hexdigest()}
    maps.append(row);print('PASS '+label+' '+json.dumps(row),flush=True)

finished=False
try:
    for priority in itertools.permutations([1,2,3]):
        prove('equivalence-'+''.join(map(str,priority)),priority,out/'after.vhd')
    for label,old,new in [
        ('wrong-owner-slice','when 2 => offer_addr <= ADDRS(68 downto 46);',
         'when 2 => offer_addr <= ADDRS(45 downto 23);'),
        ('lost-first-offer-bypass','when 3 => offer_addr <= ADDRS(91 downto 69);',
         'when 3 => offer_addr <= addresses(3);'),
    ]:
        if after.count(old)!=1: raise RuntimeError('Mutation anchor missing: '+label)
        mutant=out/(label+'.vhd');mutant.write_text(after.replace(old,new))
        prove(label,(3,2,1),mutant,rejected=True)
    if a.quartus_sh:
        for priority in [(3,2,1),(1,2,3)]:
            for side in ('before','after'): native_map(side,priority)
    finished=True
finally:
    stable=rtl.read_text()==after
    (out/'summary.json').write_text(json.dumps({'baseline_commit':BASELINE,'rtl':REL,
        'source_sha256':hashes,'source_stable':stable,'checks':checks,'native_maps':maps,
        'formal_boundary':'Same async2sync transformation of both helpers; asynchronous reset lifecycle covered by separate GHDL chip suite',
        'physical_boundary':'Native synthesis only; no full-core fit, STA, or hardware timing claim',
        'execution_finished':finished,'passed':finished and stable and bool(checks) and all(c['passed'] for c in checks)},indent=2)+'\n')
    if not stable: raise RuntimeError('RTL changed during proof; rerun required')
