#!/usr/bin/env python3
"""Native Analysis & Synthesis only, for the standalone SDRAM engine.

No fitter, core project, PLL or user deliverable is changed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--quartus-bin', type=Path, required=True)
parser.add_argument('--output', type=Path, default=Path('build/memory-ready-sdram-unit'))
args = parser.parse_args()
source = ROOT / 'rtl/memory_ready/sdram_single_request.sv'
output = (ROOT / args.output).resolve()
records = []
for region, hz in [('ntsc', 107386350), ('pal', 106406850)]:
    directory = output / region
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'sdram_single_request.sv').write_bytes(source.read_bytes())
    (directory / 'sdram_single_request.qpf').write_text(
        'QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "sdram_single_request"\n')
    (directory / 'sdram_single_request.qsf').write_text(f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY sdram_single_request
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name SYSTEMVERILOG_FILE sdram_single_request.sv
set_parameter -name CLK_HZ {hz}
''')
    command = [str(args.quartus_bin.resolve() / 'quartus_map'), 'sdram_single_request',
               '--read_settings_files=on', '--write_settings_files=off']
    process = subprocess.run(command, cwd=directory, capture_output=True, text=True)
    (directory / 'map.log').write_text(process.stdout + process.stderr)
    if process.returncode:
        raise SystemExit(f'Native map failed: {directory / "map.log"}')
    report = (directory / 'output_files/sdram_single_request.map.rpt').read_text()
    if 'Analysis & Synthesis was successful' not in report:
        raise SystemExit(f'Missing success evidence: {directory}')
    # Include the report's native resource names instead of relabeling generic
    # Yosys cells as fitted ALMs. A map estimate is not a whole-core fit.
    resources = [line.strip() for line in report.splitlines()
                 if re.search(r'; (?:Total registers|Total block memory bits|Total PLLs|Total logic elements|Combinational ALUTs|Dedicated logic registers|Total combinational functions|Logic utilization)', line)]
    resources += [line.strip() for line in report.splitlines()
                  if re.match(r'; \|sdram_single_request\s+;', line)]
    record = {'region': region, 'clock_hz': hz, 'passed': True,
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'command': command, 'resources': resources,
              'limits': 'Standalone map only; no fitter, board I/O or whole-core timing signoff'}
    records.append(record)
    print(json.dumps(record, indent=2))
(output / 'summary.json').write_text(json.dumps(records, indent=2) + '\n')
