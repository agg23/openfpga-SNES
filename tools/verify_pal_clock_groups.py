#!/usr/bin/env python3
"""Run non-compiling Quartus clock-group checks on two completed post-fit DBs."""
import argparse
import fcntl
import hashlib
import json
import pathlib
import re
import subprocess
from contextlib import ExitStack
from datetime import datetime, timezone


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_files(project):
    root = project.parent
    files = [project / 'snes_pocket.qsf', *root.rglob('*.sdc')]
    files += [p for p in (project / 'output_files').rglob('snes_pocket.*')
              if p.suffix in {'.rpt', '.summary'}]
    return {str(p): digest(p) for p in sorted(set(files))}


def completed_build(project, region):
    qsf = (project / 'snes_pocket.qsf').read_text()
    match = re.search(r'^set_global_assignment -name PROJECT_OUTPUT_DIRECTORY (.+)$', qsf, re.M)
    require(match, f'No output directory in {project}')
    output = pathlib.Path(match.group(1).strip().strip('"'))
    if not output.is_absolute():
        output = project / output
    manifest = output / 'build.json'
    build = json.loads(manifest.read_text())
    require(build.get('profile') == f'msu_{region}', f'Unexpected region in {manifest}')
    require(build.get('compile_exit_code') == 0 and build.get('state') == 'bitstream_generated_unverified',
            f'Build is not completed in {manifest}')
    return {'manifest': str(manifest), 'manifest_sha256': digest(manifest), **build}


def transfers(path):
    table = {}
    for line in path.read_text().splitlines():
        if not line.startswith(';'):
            continue
        fields = [v.strip() for v in line.split(';')[1:-1]]
        if len(fields) != 6 or fields[0] == 'From Clock':
            continue
        def clock(name):
            match = re.fullmatch(r'ic\|mp1\|mf_pllbase(?:_pal)?_inst\|altera_pll_i\|general\[(\d)\]\.gpll~PLL_OUTPUT_COUNTER\|divclk', name)
            return f'counter{match.group(1)}' if match else name
        key = (clock(fields[0]), clock(fields[1]))
        require(key not in table, f'Duplicate transfer {key}')
        table[key] = fields[2:]
    require(len(table) > 0, f'No transfer rows in {path}')
    return table


def category(value):
    return 'cut' if value == 'false path' else 'absent' if value == '0' else 'analyzed'


def compare(output):
    results = {}
    for analysis in ('setup', 'hold'):
        tables = {f'{region}-{mode}': transfers(output / f'{region}-{mode}' / f'transfers-{analysis}.log')
                  for region in ('ntsc', 'pal') for mode in ('baseline', 'candidate')}
        nb, nc, pb, pc = (tables[k] for k in ('ntsc-baseline', 'ntsc-candidate', 'pal-baseline', 'pal-candidate'))
        require(nb == nc, f'NTSC {analysis} transfers changed')
        require(pb.keys() == pc.keys(), f'PAL {analysis} transfer topology changed')
        require(nc.keys() == pc.keys(), f'Regional {analysis} transfer topology differs; review required')
        for key in nc:
            require(list(map(category, nc[key])) == list(map(category, pc[key])),
                    f'PAL grouping differs from intended NTSC grouping for {analysis} {key}')
        for key in [('counter0', 'counter1'), ('counter1', 'counter0')]:
            require(pc[key] == pb[key], f'PAL system/memory transfer changed: {key}')
            require(category(pc[key][0]) == 'analyzed', f'System/memory is cut: {key}')
        groups = {'bridge_spiclk': 0, 'clk_74a': 1, 'clk_74b': 2,
                  'counter0': 3, 'counter1': 3, 'counter2': 4, 'counter3': 5}
        changes = []
        for key in pc:
            if pb[key] != pc[key]:
                require(all(c in groups for c in key) and groups[key[0]] != groups[key[1]],
                        f'Unexpected PAL transfer change: {key}')
                require(all(a == b or category(a) == 'analyzed' and category(b) == 'cut'
                            for a, b in zip(pb[key], pc[key])),
                        f'Unexpected PAL cut behavior: {key}')
                changes.append({'from': key[0], 'to': key[1], 'before': pb[key], 'after': pc[key]})
        results[analysis] = {'ntsc_identical': True, 'regional_cut_semantics_equal': True,
                             'pal_changes': changes, 'candidate_transfers': [
                                 {'from': key[0], 'to': key[1], 'ntsc': nc[key], 'pal': pc[key]}
                                 for key in nc]}
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quartus-sta', required=True, type=pathlib.Path)
    parser.add_argument('--ntsc-project', required=True, type=pathlib.Path)
    parser.add_argument('--pal-project', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path, help='A new directory')
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    core = root / 'target/pocket/core_constraints.sdc'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    projects = {r: getattr(args, f'{r}_project').resolve() for r in ('ntsc', 'pal')}
    summary = {'started_utc': datetime.now(timezone.utc).isoformat(), 'candidate_sha256': digest(core),
               'tool': str(args.quartus_sta.resolve()), 'builds': {}, 'protection': {}}
    with ExitStack() as stack:
        # Share the build wrapper's lock. Never query a compiling database.
        for region, project in projects.items():
            lock = stack.enter_context((project / 'output_files/.msu1-build.lock').open('r'))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            summary['builds'][region] = completed_build(project, region)
        for region, project in projects.items():
            original = project.parent / 'target/pocket/core_constraints.sdc'
            before_group, after_group = original.read_text().split('\nderive_clock_uncertainty', 1)
            require(before_group.count('mf_pllbase_inst') == 4, 'Expected four original PLL group filters')
            expected = before_group.replace('mf_pllbase_inst', 'mf_pllbase*_inst') + '\nderive_clock_uncertainty' + after_group
            require(core.read_text() == expected, 'Candidate must differ only in the four permitted filters')
            before = protected_files(project)
            for mode, sdc in [('baseline', original), ('candidate', core)]:
                label = f'{region}-{mode}'
                cmd = [str(args.quartus_sta.resolve()), '-t', str(root / 'tools/verify_pal_clock_groups.tcl'),
                       str(project), str(sdc), str(output / label), region, mode]
                with (output / f'{label}-console.log').open('w') as log:
                    subprocess.run(cmd, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
                require('result\tPASS\n' in (output / label / 'verification.tsv').read_text(),
                        f'Missing PASS result for {label}')
            after = protected_files(project)
            require(before == after, f'Protected QSF/SDC/reports changed for {region}')
            summary['protection'][region] = {'unchanged': True, 'files': before}
    summary['transfers'] = compare(output)
    summary['finished_utc'] = datetime.now(timezone.utc).isoformat()
    summary['result'] = 'PASS'
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
