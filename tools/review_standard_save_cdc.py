#!/usr/bin/env python3
"""Inspect new Save CDC only after a source-identified full flow has completed.

Extraction success is not CDC signoff. Review missing/merged chains, exceptions,
MTBF assumptions, recovery/removal, and normally timed mailbox payload paths.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def require_complete(project, fit):
    """Fail before reading any DB when routing/flow failed or source mismatches."""
    manifest = json.loads((fit.parent / 'build.json').read_text())
    revision = subprocess.check_output(['git', '-C', project.parent, 'rev-parse', 'HEAD'], text=True).strip()
    if manifest.get('compile_exit_code') != 0 or not manifest.get('finished_utc'):
        raise ValueError('Full compiler flow did not complete successfully')
    if manifest.get('source_commit') != revision:
        raise ValueError('Build manifest and source revision differ')
    for path, pattern in [(fit, r'Fitter Status\s*;\s*Successful'),
                          (fit.parent / 'snes_pocket.flow.rpt', r'Flow Status\s*;\s*Successful')]:
        if not re.search(pattern, path.read_text(errors='replace')):
            raise ValueError('Missing completed successful report: ' + str(path))
    if not (fit.parent / 'snes_pocket.sta.rpt').is_file():
        raise ValueError('Original full-flow STA report is absent')
    return revision


def main():
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
        revision = require_complete(project, fit)
        protected = list(fit.parent.glob('*.rpt')) + [fit.parent / 'build.json']
        protected += [project / 'snes_pocket.qsf', project / 'snes_pocket.sdc']
        protected += list((project.parent / 'target/pocket').glob('*.sdc'))
        protected += [project.parent / rel for rel in (
            'target/pocket/core_top.sv', 'target/pocket/host_reset_guard.sv',
            'target/pocket/data_unloader.sv', 'rtl/memory_ready/rom_download_queue.sv',
            'rtl/memory_ready/sdram_transaction_cdc.sv') if (project.parent / rel).exists()]

        def hashes():
            return {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in protected}

        before = hashes()
        command = [str(a.quartus_sta.resolve()), '-t', str(ROOT / 'tools/review_standard_save_cdc.tcl'), str(project), str(out)]
        result = subprocess.run(command, cwd=out, capture_output=True, text=True, timeout=900)
        log = result.stdout + result.stderr
        (out / 'query.log').write_text(log)
        unchanged = before == hashes()
        passed = result.returncode == 0 and 'SAVE_CDC_EXTRACTED_REQUIRES_REVIEW' in log and unchanged
        passed = passed and '332088' not in log and '332199' not in log
        passed = passed and not re.search(r'Warning[^\n]*(?:review_standard_save_cdc\.tcl|Command report_\w+ failed)', log)
        receipt = {
            'extraction_complete': passed, 'cdc_signoff': False,
            'protected_unchanged': unchanged, 'source_revision': revision,
            'command': command, 'protected_sha256': before,
            'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope': 'Original SDC, read-only Save/reset/FIFO/mailbox audit. No fit or assignment changes.',
        }
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if not passed:
            raise SystemExit('FAILED or rejected extraction; inspect ' + str(out / 'query.log'))
        print('Complete read-only extraction; original constraints/reports unchanged; CDC REVIEW REQUIRED')


if __name__ == '__main__':
    main()
