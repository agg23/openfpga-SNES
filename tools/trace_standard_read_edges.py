#!/usr/bin/env python3
"""Trace real engine physical DQ sampling independently of read_data forwarding."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, default=ROOT)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--controls', action='store_true')
a = p.parse_args()
out, src = a.out.resolve(), a.source.resolve()
out.mkdir(parents=True, exist_ok=False)
files = [src / x for x in ['rtl/memory_ready/sdram_single_request.sv',
    'tests/memory_ready/as4c32m16msa_model.sv', 'tests/memory_ready/tb_sdram_single_request.sv']]
files.append(ROOT / 'tests/timing/tb_standard_read_edge_trace.sv')
before = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
results = []
for name, hz, delay, good in [('ntsc',107386350,3,True),('pal',106406850,3,True)] + (
        [('hold_negative',107386350,0,False),('setup_negative',107386350,10,False)] if a.controls else []):
    unit = out / name
    unit.mkdir()
    command = [shutil.which('verilator') or 'verilator','--binary','--timing','-Wno-fatal',
        '--top-module','tb_standard_read_edge_trace','-j','2','--Mdir',str(unit/'obj'),
        f'-GCLK_HZ={hz}',f'-GRETURN_DELAY_NS={delay}',*map(str,files)]
    c = subprocess.run(command, capture_output=True, text=True, timeout=240)
    (unit/'compile.log').write_text(c.stdout+c.stderr)
    if c.returncode: raise SystemExit('Compile failed: '+name)
    r = subprocess.run([str(unit/'obj/Vtb_standard_read_edge_trace')], capture_output=True, text=True, timeout=60)
    log = r.stdout+r.stderr
    (unit/'trace.log').write_text(log)
    ok = r.returncode == 0 and 'PASS EDGE TRACE' in log if good else r.returncode != 0 and 'EDGE_BAD_CAPTURE_WINDOW' in log
    print(name, 'PASS' if ok else 'FAIL', '\n'+log)
    results.append({'name':name,'hz':hz,'synthetic_return_ns':delay,'expected_valid_window':good,'passed':ok})
    if not ok: raise SystemExit('Trace expectation failed: '+name)
after = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
if before != after: raise SystemExit('Source changed during trace')
(out/'results.json').write_text(json.dumps({'scope':'Digital edge trace, synthetic R; not fitted/PCB timing',
    'source_sha256':before,'source_unchanged':True,'cases':results},indent=2)+'\n')
