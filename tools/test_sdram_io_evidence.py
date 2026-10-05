#!/usr/bin/env python3
"""Check symbolic arithmetic, no-false-signoff status, and historical hash guard."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
from research_sdram_io_trace import ROOT, SOURCE_SHA256, normalize_dq, pinned_source

BUDGET = Path(__file__).with_name('research_sdram_io_budget.py')

def budget(*args, ok=True):
    r = subprocess.run([sys.executable, str(BUDGET), *map(str, args)],
                       capture_output=True, text=True)
    assert (r.returncode == 0) == ok, (args, r.stdout, r.stderr)
    return json.loads(r.stdout) if ok else r.stderr

for f, legal in [(85.909080, False), (85.125480, False), (80.0, True)]:
    j = budget('--frequency-mhz', f)
    assert j['cl2_frequency_in_published_range'] == legal
    assert j['status'] == 'NOT_BOARD_SIGNOFF'
    assert abs(j['read_lower_R_before_FF_hold_and_uncertainty_ns'] - (500/f-2.5)) < 1e-12
    assert abs(j['read_upper_R_before_FF_setup_and_uncertainty_ns'] - (1500/f-6)) < 1e-12
args = ['--read-r-min-ns', '4', '--read-r-max-ns', '5', '--ff-setup-ns', '1',
        '--ff-hold-ns', '0.1', '--setup-uncertainty-ns', '0.1', '--hold-uncertainty-ns', '0.1']
j = budget(*args)
assert j['conditional_setup_slack_ns'] > 0 and j['conditional_hold_slack_ns'] > 0
assert j['status'] == 'NOT_BOARD_SIGNOFF' and not j['cl2_frequency_in_published_range']
args[1] = '1'
assert budget(*args)['conditional_hold_slack_ns'] < 0
args[3] = '20'
assert budget(*args)['conditional_setup_slack_ns'] < 0
budget('--read-r-min-ns', 0, ok=False)
for invalid in ('0', '-1', 'nan', 'inf'):
    budget('--frequency-mhz', invalid, ok=False)
source, _ = pinned_source(ROOT)
normalized = normalize_dq(source)
assert 'if (early_bank0) sys_dq0 <= SDRAM_DQ;' in normalized
assert 'if (data_read) rbuf <= SDRAM_DQ;' in normalized
with tempfile.TemporaryDirectory() as d:
    bad = Path(d)/'bad.sv'
    bad.write_text(source+'\n// hash mismatch negative control\n')
    try:
        pinned_source(ROOT, bad)
    except ValueError as e:
        assert 'SHA-256 mismatch' in str(e)
    else:
        raise AssertionError('modified controller accepted')
print('PASS exact pinned controller SHA-256 '+SOURCE_SHA256)
print('PASS normalization preserves controller read and capture logic')
print('PASS NTSC/PAL/80MHz symbolic budgets and CL2 frequency guard')
print('PASS synthetic setup/hold negative controls; positive margins never imply signoff')
print('PASS incomplete/nonfinite inputs and modified-source negative controls rejected')
