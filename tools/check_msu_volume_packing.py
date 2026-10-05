#!/usr/bin/env python3
"""Reproduce targeted MSU.volume register packing, never a whole-core build.

Default: source-bound unit analysis/synthesis only. --fit additionally fits the
small baseline/candidate units with one worker and verifies physical FF packing.
Quartus 21.1-compatible binaries must already be installed/on PATH.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ATTR = '(* altera_attribute = "-name QII_AUTO_PACKED_REGISTERS OFF" *)'


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def normalized(text):
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'\s+', '', text)


def function(text, name):
    pattern = r'function automatic signed \[15:0\] ' + name + r';.*?endfunction'
    matches = re.findall(pattern, text, flags=re.S)
    if len(matches) != 1:
        raise RuntimeError(f'Expected one actual {name} function, got {len(matches)}')
    return normalized(matches[0])


def run(command, work, logfile):
    result = subprocess.run(command, cwd=work, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    (work / logfile).write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{command[0]} failed; see {work / logfile}')
    return result.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--fit', action='store_true')
    ap.add_argument('--output', type=Path, default=ROOT / 'build/msu-volume-packing-check')
    args = ap.parse_args()
    required = ['quartus_map'] + (['quartus_fit', 'quartus_cdb', 'quartus_sta'] if args.fit else [])
    bins = {tool: shutil.which(tool) for tool in required}
    if not all(bins.values()):
        raise RuntimeError('Installed Quartus tools required: ' + ', '.join(required))
    args.output.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='unit-', dir=args.output.resolve()))
    print(out, flush=True)
    msu = (ROOT / 'rtl/upstream/chip/MSU1/MSU.sv').read_text()
    unit = (ROOT / 'tests/timing/msu_volume_unit.sv').read_text()
    player = (ROOT / 'rtl/msu1/msu_pcm_player.sv').read_text()
    if msu.count(ATTR) != 1 or not re.search(re.escape(ATTR) + r'\s*output reg\s+\[7:0\] volume', msu):
        raise RuntimeError('Expected exactly one packing attribute on MSU.volume')
    for name in ['scale_sample', 'saturated_add']:
        if function(unit, name) != function(player, name):
            raise RuntimeError(f'Unit {name} differs from actual player source')
    baseline = msu.replace(ATTR, '')
    manifest = {'scope': 'small unit only; no whole-core closure claim',
                'source_sha256': {'MSU': sha(msu), 'player': sha(player), 'unit': sha(unit)},
                'variants': {}, 'fit': args.fit}
    atoms = '''package require ::quartus::project
package require ::quartus::atoms
project_open unit
read_atom_netlist -type cmp
foreach_in_collection n [get_atom_nodes] {
 set name [get_atom_node_info -node $n -key name]
 if {[string match *volume* $name] || [string match *Mult* $name]} {
 puts "ATOM $name [get_atom_node_info -node $n -key type] [get_atom_node_info -node $n -key location]"
 }
}
project_close
'''
    sta = '''project_open unit
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -from [get_registers {*msu*volume*}] -npaths 4 -detail full_path -file volume-out.rpt
report_timing -hold -from [get_registers {*msu*volume*}] -npaths 4 -detail full_path -file volume-hold.rpt
report_timing -to [get_registers {*msu*volume*}] -npaths 4 -detail full_path -file volume-in.rpt
report_clock_fmax_summary -file fmax.rpt
project_close
'''
    for name, source in [('original', baseline), ('rtl_off', msu)]:
        d = out / name
        d.mkdir()
        (d / 'unit.sv').write_text(unit)
        (d / 'MSU.sv').write_text(source)
        (d / 'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
        (d / 'unit.qsf').write_text('''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY unit
set_global_assignment -name SYSTEMVERILOG_FILE unit.sv
set_global_assignment -name SYSTEMVERILOG_FILE MSU.sv
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
set_global_assignment -name MUX_RESTRUCTURE ON
set_global_assignment -name AUTO_RESOURCE_SHARING ON
set_global_assignment -name SDC_FILE unit.sdc
set_instance_assignment -name VIRTUAL_PIN ON -to *
''')
        (d / 'unit.sdc').write_text('create_clock -name sys -period 46.978 [get_ports clk]\nderive_clock_uncertainty\n')
        manifest['variants'][name] = {p.name: sha(p.read_text()) for p in d.iterdir()}
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        run([bins['quartus_map'], 'unit'], d, 'map.log')
        if args.fit:
            run([bins['quartus_fit'], 'unit'], d, 'fit.log')
            (d / 'atoms.tcl').write_text(atoms)
            (d / 'sta.tcl').write_text(sta)
            dump = run([bins['quartus_cdb'], '-t', 'atoms.tcl'], d, 'atoms.log')
            run([bins['quartus_sta'], '-t', 'sta.tcl'], d, 'sta.log')
            ff = re.findall(r'ATOM MSU:msu\|volume\[(\d)\] FF (FF_\S+)', dump)
            report = (d / 'volume-out.rpt').read_text()
            if name == 'original':
                if ff or not re.search(r'DSP_X[^\n]*MSU:msu\|volume', report):
                    raise RuntimeError('Baseline did not reproduce DSP input packing')
            else:
                if {int(bit) for bit, _ in ff} != set(range(8)):
                    raise RuntimeError('Candidate volume bits are not all standalone logic FFs')
                if re.search(r'DSP_X[^\n]*MSU:msu\|volume', report):
                    raise RuntimeError('Candidate volume is still DSP-packed')
            print(f'{name}: physical packing check PASS', flush=True)
        else:
            print(f'{name}: map PASS; physical packing NOT VERIFIED without --fit', flush=True)
    print('PASS source-bound unit comparison; inspect preserved reports for timing/resource results')


if __name__ == '__main__':
    main()
