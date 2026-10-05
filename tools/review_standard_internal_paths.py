#!/usr/bin/env python3
"""Read-only clock/chip endpoint reports from a completed standard-profile fit."""
import argparse
import datetime
import fcntl
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--project', type=pathlib.Path, required=True)
p.add_argument('--quartus-sta', type=pathlib.Path, required=True)
p.add_argument('--out', type=pathlib.Path, required=True)
p.add_argument('--fit-report', type=pathlib.Path, required=True)
a = p.parse_args()
project, out, fit = a.project.resolve(), a.out.resolve(), a.fit_report.resolve()
if not (project / 'snes_pocket.qpf').is_file():
    p.error('Require directory containing snes_pocket.qpf')
out.mkdir(parents=True, exist_ok=False)
with (project / 'output_files/.msu1-build.lock').open('r') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if not fit.is_file() or not re.search(r'Fitter Status\s*;\s*Successful', fit.read_text(errors='replace')):
        p.error('Require completed successful fit; no map-only fallback')
    protected = list(fit.parent.glob('*.rpt'))
    protected += [project / 'snes_pocket.qsf', project / 'snes_pocket.sdc']
    protected += list((project.parent / 'target/pocket').glob('*.sdc'))

    def hashes():
        return {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in protected}

    before = hashes()
    command = [str(a.quartus_sta.resolve()), '-t', str(ROOT / 'tools/review_standard_internal_paths.tcl'), str(project), str(out)]
    result = subprocess.run(command, cwd=out, capture_output=True, text=True, timeout=900)
    log = result.stdout + result.stderr
    (out / 'query.log').write_text(log)
    unchanged = before == hashes()
    passed = result.returncode == 0 and 'ORIGINAL_INTERNAL_PATHS_COMPLETE' in log and unchanged
    passed = passed and '332088' not in log and '332199' not in log
    receipt = {
        'passed': passed, 'protected_unchanged': unchanged,
        'source_revision': subprocess.check_output(['git', '-C', project.parent, 'rev-parse', 'HEAD'], text=True).strip(),
        'command': command, 'protected_sha256': before,
        'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': 'Original SDC. Read-only fitted internal setup queries, no I/O assumptions, no fit, no assignment changes.',
    }
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not passed:
        raise SystemExit('FAILED or rejected query; inspect ' + str(out / 'query.log'))
    print('PASS original-SDC internal path query; protected compiled reports and constraints unchanged')
