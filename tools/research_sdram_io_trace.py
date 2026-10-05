#!/usr/bin/env python3
"""Trace a SHA-pinned historical controller; never modify production sources.

The external memory is NOT electrically modeled. DQ is held constant; printed
valid-window boundaries are annotations derived from the cited datasheet.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import shutil
import subprocess
import sys

REVISION = 'a1e3059dc60ca487109ff2b2d99eb229a2e0a25a'
SOURCE_PATH = 'rtl/upstream/sdram.sv'
SOURCE_SHA256 = '179977463c5730ec496b5e489511e1e72e85397ee963e52e179f0ac4ce07accf'
ROOT = Path(__file__).resolve().parents[1]


def pinned_source(repo, source_copy=None):
    if source_copy:
        data = Path(source_copy).read_bytes()
        origin = 'explicit source copy'
    else:
        try:
            result = subprocess.run(['git', '-C', str(repo), 'show',
                                     f'{REVISION}:{SOURCE_PATH}'],
                                    capture_output=True, check=False)
        except FileNotFoundError:
            result = None
        if result is not None and result.returncode == 0:
            data, origin = result.stdout, f'git object {REVISION}:{SOURCE_PATH}'
        else:
            # A historical source archive without .git is still reproducible,
            # but only if the same exact original source is present.
            data = (repo / SOURCE_PATH).read_bytes()
            origin = 'working file fallback (hash verified)'
    actual = hashlib.sha256(data).hexdigest()
    if actual != SOURCE_SHA256:
        raise ValueError(f'Pinned controller SHA-256 mismatch: {actual}; '
                         f'expected {SOURCE_SHA256}. Use the stated historical '
                         'revision or --source-copy with its exact source.')
    return data.decode('utf-8'), origin


def normalize_dq(source):
    # Simulator-only lowering from the existing test_sdram_early_equivalence
    # normalization. State, command, read pipeline and capture logic stay intact.
    replacements = {
        'inout  reg [15:0] SDRAM_DQ': 'inout wire [15:0] SDRAM_DQ',
        '\tlocalparam RASCAS_DELAY':
            "\treg [15:0] test_dq_out;\n\treg test_dq_oe;\n"
            "\tassign SDRAM_DQ = test_dq_oe ? test_dq_out : 16'hzzzz;\n\n"
            '\tlocalparam RASCAS_DELAY',
        "SDRAM_DQ <= 'Z;": 'test_dq_oe <= 0;',
        'begin SDRAM_DQ <= d; end':
            'begin test_dq_out <= d; test_dq_oe <= 1; end',
        "\talways @(posedge clk) begin\n\t\treg [4:0] reset = 5'h1f;\n\t\treg init_old = 0;":
            "\treg [4:0] reset = 5'h1f;\n\treg init_old = 0;\n\talways @(posedge clk) begin",
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError(f'Normalization pattern must match exactly once: {old!r}')
        source = source.replace(old, new)
    return source


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, default=ROOT,
                   help='Git/source repository containing the pinned revision')
    p.add_argument('--source-copy', type=Path,
                   help='Exact pinned controller for a source archive without history')
    p.add_argument('--frequency-mhz', type=float, default=85.909080)
    p.add_argument('--case', choices=('read', 'init-refresh'), default='read')
    p.add_argument('--output', type=Path,
                   help='Artifact directory; default build/sdram-io-evidence/<case>')
    p.add_argument('--verilator', default='verilator')
    a = p.parse_args()
    if not math.isfinite(a.frequency_mhz) or a.frequency_mhz <= 0:
        p.error('frequency must be finite and positive')
    repo = a.repo.resolve()
    out = (a.output or ROOT / 'build/sdram-io-evidence' / a.case).resolve()
    # Fail before creating build outputs when the source is not exact.
    try:
        source, origin = pinned_source(repo, a.source_copy)
    except (OSError, ValueError) as e:
        p.error(str(e))
    tool = shutil.which(a.verilator)
    if not tool:
        p.error('verilator is required; place it on PATH or pass --verilator')
    out.mkdir(parents=True, exist_ok=True)
    (out / 'sdram_pinned_normalized.sv').write_text(normalize_dq(source))
    tb = (ROOT / 'tests/timing/tb_sdram_io_evidence.sv').read_text()
    tb = tb.replace('@PERIOD_NS@', f'{1000 / a.frequency_mhz:.12f}')
    tb = tb.replace('@REQUEST_COUNT@', '1024' if a.case == 'init-refresh' else '1')
    (out / 'tb.sv').write_text(tb)
    version = subprocess.check_output([tool, '--version'], text=True).strip()
    manifest = dict(source_revision=REVISION, source_path=SOURCE_PATH,
                    source_sha256=SOURCE_SHA256, source_origin=origin,
                    frequency_mhz=a.frequency_mhz, case=a.case,
                    verilator_version=version,
                    model='real controller; zero-delay DDIO; constant DQ; no SDRAM electrical model')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    cmd = [tool, '--binary', '--timing', '--assert', '-Wno-fatal', '-j', '1',
           '--top-module', 'tb', '--Mdir', str(out / 'obj'),
           str(out / 'tb.sv'), str(out / 'sdram_pinned_normalized.sv')]
    compiled = subprocess.run(cmd, cwd=out, text=True, capture_output=True)
    (out / 'compile.log').write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print((compiled.stdout + compiled.stderr)[-5000:], file=sys.stderr)
        return compiled.returncode
    run = subprocess.run([str(out / 'obj/Vtb')], cwd=out, text=True,
                         capture_output=True, timeout=30)
    raw = run.stdout + run.stderr
    (out / 'simulation.log').write_text(raw)
    # Keep stable, small evidence without build paths or runtime speed statistics.
    lines = [line for line in raw.splitlines() if line.startswith(
        ('INIT_CMD ', 'REQUEST ', 'EXTERNAL_RISE ', 'DQ_', 'CAPTURE ',
         'SUMMARY ', 'PASS ', 'LIMIT '))]
    evidence = '\n'.join(lines) + '\n'
    (out / 'evidence.log').write_text(evidence)
    print(evidence, end='')
    if run.returncode:
        print(raw, file=sys.stderr)
    return run.returncode


if __name__ == '__main__':
    raise SystemExit(main())
