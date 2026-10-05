#!/usr/bin/env python3
"""Tiny native unit compares synchronizer labels without changing core sources."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--quartus-bin', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--negative-extra-stage', action='store_true',
    help='Deliberately allow a functional consumer into each chain; require the boundary check to reject it')
a = p.parse_args()
out, q = a.out.resolve(), a.quartus_bin.resolve()
out.mkdir(parents=True, exist_ok=False)
pins = {}
for line in (ROOT/'platform/pocket/pocket.tcl').read_text().splitlines():
    m = re.match(r'set_location_assignment (\S+) -to (clk_74[ab])$', line)
    if m: pins[m[2]] = m[1]
qsf = f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY standard_sync_identification_unit
set_global_assignment -name SYSTEMVERILOG_FILE "{ROOT/'tests/timing/standard_sync_identification_unit.sv'}"
set_global_assignment -name SDC_FILE unit.sdc
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name FITTER_EFFORT "FAST FIT"
set_location_assignment {pins['clk_74a']} -to clk_src
set_location_assignment {pins['clk_74b']} -to clk_dst
set_instance_assignment -name IO_STANDARD "1.8 V" -to clk_src
set_instance_assignment -name IO_STANDARD "1.8 V" -to clk_dst
'''
for port in ['data_in','reset_n',*[f'consumer[{i}]' for i in range(5)]]:
    qsf += f'set_instance_assignment -name VIRTUAL_PIN ON -to {port}\n'
# Consumers are functional endpoints, not extra metastability settling stages.
if not a.negative_extra_stage:
    qsf += 'set_instance_assignment -name SYNCHRONIZER_IDENTIFICATION OFF -to consumer*\n'
for name, count, method in [('forced_vector',2,'FORCED'),('fia_vector',2,'FORCED IF ASYNCHRONOUS'),
        ('forced_head',2,'HEAD'),('reset_vector',3,'FORCED'),('reset_head',3,'HEAD')]:
    for i in range(count):
        node = f'{name}[{i}]'
        value = ('FORCED' if i == 0 else 'AUTO') if method == 'HEAD' else method
        qsf += f'set_instance_assignment -name SYNCHRONIZER_IDENTIFICATION "{value}" -to {node}\n'
        qsf += f'set_instance_assignment -name DONT_MERGE_REGISTER ON -to {node}\n'
        qsf += f'set_instance_assignment -name PRESERVE_REGISTER ON -to {node}\n'
(out/'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
(out/'unit.qsf').write_text(qsf)
(out/'unit.sdc').write_text('''create_clock -name src -period 13.468 [get_ports clk_src]
create_clock -name dst -period 46.560 [get_ports clk_dst]
set_clock_groups -asynchronous -group {src} -group {dst}
set_input_delay -clock src -max 0 [get_ports data_in]
set_input_delay -clock src -min 0 [get_ports data_in]
set_false_path -from [get_ports reset_n]
set_output_delay -clock dst -max 0 [get_ports consumer*]
set_output_delay -clock dst -min 0 [get_ports consumer*]
derive_clock_uncertainty
''')
(out/'fit.tcl').write_text('load_package flow\nproject_open unit\nexecute_module -tool map\nexecute_module -tool fit\nproject_close\n')
(out/'query.tcl').write_text('''package require ::quartus::project
package require ::quartus::sta
project_open unit
create_timing_netlist -model slow
read_sdc;update_timing_netlist
report_metastability -nchains 100 -file chains.rpt
report_timing -setup -npaths 50 -detail full_path -file setup.rpt
report_timing -hold -npaths 50 -detail full_path -file hold.rpt
set f [open registers.tsv w]
foreach_in_collection r [get_registers *] {puts $f "[get_node_info -name $r]\\t[get_node_info -location $r]"}
close $f
delete_timing_netlist
project_close -dont_export_assignments
''')
for tool, file in [('quartus_sh','fit.tcl'),('quartus_sta','query.tcl')]:
    r = subprocess.run([str(q/tool),'-t',file],cwd=out,capture_output=True,text=True,timeout=240)
    log = r.stdout+r.stderr
    (out/(file+'.log')).write_text(log)
    if r.returncode or 'invalid node name' in log or '332199' in log:
        raise SystemExit('Native synchronizer unit failed: '+file)
chains = []
for block in (out/'chains.rpt').read_text().split('Synchronizer Chain #')[1:]:
    row = {}
    for line in block.splitlines():
        fields = [x.strip() for x in line.split(';')]
        if len(fields)>3 and fields[1] in ['Synchronization Node','Number of Synchronization Registers in Chain','Available Settling Time (ns)','Worst-Case MTBF (years)']:
            row[fields[1]] = fields[2]
    if row: chains.append(row)
found = {row['Synchronization Node']: int(row['Number of Synchronization Registers in Chain']) for row in chains}
expected = {'forced_vector[0]':1,'forced_vector[1]':1,'fia_vector[0]':2,'forced_head[0]':2,'reset_head[0]':3}
violations = {name: {'intended_stages': size, 'reported_stages': found.get(name)} for name, size in expected.items() if found.get(name) != size}
if a.negative_extra_stage:
    if not violations or not all(found.get(name)==expected[name]+1 for name in ['fia_vector[0]','forced_head[0]','reset_head[0]']):
        raise SystemExit('Negative control failed to expose the extra functional-consumer stage')
    print('PASS NEGATIVE: intended synchronizer boundary rejects extra functional-consumer stage')
elif violations:
    raise SystemExit('Native chain boundary mismatch: '+str(violations))
(out/'results.json').write_text(json.dumps({'scope':'Tiny native unit only; does not modify or sign off production CDC',
    'negative_extra_stage':a.negative_extra_stage,'boundary_violations':violations,'chains':chains},indent=2)+'\n')
print(json.dumps(chains,indent=2))
