#!/usr/bin/env python3
"""Read-only, locked review of a completed source-identified Quartus project.

--clock-edges is an in-memory clock-model experiment, never an SDC edit or
compiler invocation. It first checks actual fitted PLL counter/phase evidence.
"""
import argparse, csv, datetime, fcntl, hashlib, json, pathlib, re, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED = 'a1e3059dc60ca487109ff2b2d99eb229a2e0a25a'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fitted_counters(report):
    text = report.read_text(encoding='latin1')
    require('; PLL Usage Summary' in text, 'No fitted PLL usage table')
    counters = {}; index = None
    keys = ['Output Clock Frequency', 'Output Clock Location',
            'C Counter Odd Divider Even Duty Enable', 'Duty Cycle', 'Phase Shift',
            'C Counter', 'C Counter PH Mux PRST', 'C Counter PRST']
    for line in text[text.index('; PLL Usage Summary'):].splitlines():
        fields = [x.strip() for x in line.split(';')]
        if len(fields) != 4:
            continue
        label = fields[1].lstrip('-').strip(); value = fields[2]
        match = re.search(r'general\[(\d)\]\.gpll~PLL_OUTPUT_COUNTER', label)
        if match:
            index = int(match.group(1))
            require(index not in counters, 'Ambiguous fitted PLL counter table')
            counters[index] = {'name': label}
        elif index is not None and label in keys:
            counters[index][label] = value
    require(0 in counters and 1 in counters, 'Missing memory/system counters')
    for n in (0, 1):
        c = counters[n]
        require(float(c['Phase Shift'].split()[0]) == 0, 'Nonzero fitted phase')
        require(float(c['Duty Cycle']) == 50, 'Non-50% fitted duty')
        require(c['C Counter PH Mux PRST'] == '0' and c['C Counter PRST'] == '1',
                'Unexpected fitted counter phase reset')
    mem = int(counters[0]['C Counter']); sys = int(counters[1]['C Counter'])
    if mem % 2:
        require(counters[0]['C Counter Odd Divider Even Duty Enable'] == 'On',
                'Odd memory counter lacks fitted even-duty support')
    require(sys == 4*mem, 'Fitted counters are not strictly 4:1')
    stem = lambda s: re.sub(r'general\[\d\]\.gpll~PLL_OUTPUT_COUNTER', '', s)
    require(stem(counters[0]['name']) == stem(counters[1]['name']), 'Different fitted PLLs')
    return counters, mem, sys

def transfers(path):
    result = {}
    for line in path.read_text().splitlines():
        f = [x.strip() for x in line.split(';')[1:-1]]
        if len(f) == 6 and f[0] != 'From Clock':
            key = tuple(f[:2]); require(key not in result, 'Duplicate transfer row')
            result[key] = f[2:]
    require(result, 'Empty clock transfer table')
    return result

def first_path(path):
    text = path.read_text().split('Path #1:')[1].split('Path #2:')[0]
    result = {}
    for line in text.splitlines():
        f = [x.strip() for x in line.split(';')]
        if len(f) > 3 and f[1] in ('From Node', 'To Node', 'Clock Skew', 'Data Delay',
                                 'Setup Relationship', 'Hold Relationship', 'Slack'):
            result[f[1]] = f[2]
    return result

def physical_clock_routes(path):
    result = {}
    for text in re.split(r'\nPath #\d+:', path.read_text())[1:]:
        start = re.search(r'; From Node\s*; (.*?)\s*;', text).group(1)
        end = re.search(r'; To Node\s*; (.*?)\s*;', text).group(1)
        rows = []; active = False
        for line in text.splitlines():
            col = [x.strip() for x in line.split(';')[1:-1]]
            if len(col) != 7:
                continue
            element = col[-1]
            if element == 'clock path':
                active = True
            elif element in ('data path', 'clock uncertainty', 'clock pessimism'):
                active = False
            if active:
                # Exclude absolute arrival time, which contains the changed
                # launch/latch edge. Keep every clock arc increment/location.
                rows.append(tuple(col[1:]))
        rows.append(('DATA_DELAY', re.search(r'; Data Delay\s*; (.*?)\s*;',text).group(1)))
        rows.append(('CLOCK_SKEW', re.search(r'; Clock Skew\s*; (.*?)\s*;',text).group(1)))
        result[(start,end)] = rows
    return result

def compare_clock_experiment(out, *, ignore_sdc_source_lines=False):
    log = (out/'query.log').read_text()
    require('Warning (332088)' not in log, 'Rejected zero-source-clock-latency model')
    results = {'transfers_unchanged': {}, 'corners': {},
               'limits': 'Checks the same routed design; no new fit, I/O budget or hardware sign-off'}
    for analysis in ('setup', 'hold'):
        old = transfers(out/f'original-transfers-{analysis}.rpt')
        new = transfers(out/f'common_vco_edges-transfers-{analysis}.rpt')
        require(old == new, 'Clock transfer counts/cuts changed')
        results['transfers_unchanged'][analysis] = True
    for corner in ('slow85', 'slow0', 'fast85', 'fast0'):
        results['corners'][corner] = {}
        def nonclock_constraints(path):
            rows = []
            for line in path.read_text().splitlines():
                if not line.startswith('; set_'):
                    continue
                row = [x.strip() for x in line.split(';')[1:-1]]
                if ignore_sdc_source_lines:
                    # Only the report's penultimate Source column, never a
                    # selector, constraint value or uncertainty, may normalize.
                    row[-2] = re.sub(r'^(.*\.sdc):[0-9]+$', r'\1:<line>', row[-2])
                rows.append(tuple(row))
            return sorted(rows)
        original_sdc = nonclock_constraints(out/f'original-{corner}-sdc.rpt')
        candidate_sdc = nonclock_constraints(out/f'common_vco_edges-{corner}-sdc.rpt')
        require(original_sdc == candidate_sdc, 'Uncertainty or non-clock constraint rows changed')
        results['corners'][corner]['uncertainty_and_nonclock_constraints_unchanged'] = True
        for analysis in ('setup', 'hold'):
            old = first_path(out/f'original-{corner}-capture-{analysis}.rpt')
            new = first_path(out/f'common_vco_edges-{corner}-capture-{analysis}.rpt')
            old_routes=physical_clock_routes(out/f'original-{corner}-capture-{analysis}.rpt')
            new_routes=physical_clock_routes(out/f'common_vco_edges-{corner}-capture-{analysis}.rpt')
            require(old_routes == new_routes, 'Detailed physical clock arcs changed')
            require(all(old[k] == new[k] for k in ('From Node','To Node','Clock Skew','Data Delay')),
                    'Physical worst-path endpoints/delay/skew changed; review separately')
            results['corners'][corner][analysis] = {'original':old, 'explicit_edges':new,
                                                   'physical_fields_unchanged':True,
                                                   'detailed_clock_route_pairs_unchanged':len(old_routes)}
    (out/'clock-comparison.json').write_text(json.dumps(results,indent=2)+'\n')
    return results

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project',type=pathlib.Path,required=True)
    p.add_argument('--manifest',type=pathlib.Path,required=True)
    p.add_argument('--output',type=pathlib.Path,required=True)
    p.add_argument('--region',choices=['ntsc','pal'],required=True)
    p.add_argument('--quartus-sta',type=pathlib.Path,required=True)
    p.add_argument('--expected-commit',default=EXPECTED)
    p.add_argument('--clock-edges',action='store_true')
    a = p.parse_args(); project=a.project.resolve(); manifest=a.manifest.resolve();out=a.output.resolve()
    def protection():
        files=[project/'snes_pocket.qsf',project/'snes_pocket.qpf',*project.parent.rglob('*.sdc')]
        files += list(manifest.parent.glob('snes_pocket.*'))
        return {str(f):sha(f) for f in files if f.is_file() and not f.is_relative_to(out)}
    with (project/'output_files/.msu1-build.lock').open('r') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        build=json.loads(manifest.read_text())
        require(build['compile_exit_code']==0 and build['state']=='bitstream_generated_unverified',
                'Build is not successfully completed')
        require(build['source_commit']==a.expected_commit and not build['source_status'],
                'Expected clean source commit does not match build manifest')
        require(build['profile']=='msu_'+a.region, 'Unexpected regional profile')
        match=re.search(r'^set_global_assignment -name PROJECT_OUTPUT_DIRECTORY (.+)$',
                        (project/'snes_pocket.qsf').read_text(),re.M)
        require(match, 'No output-directory assignment')
        effective=pathlib.Path(match.group(1).strip().strip('"'))
        if not effective.is_absolute(): effective=project/effective
        require(effective.resolve()==manifest.parent,'Project output and manifest disagree')
        out.mkdir(parents=True,exist_ok=False)
        before=protection()
        record={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'build':build,'manifest':str(manifest),'manifest_sha256':sha(manifest),
                'protected_before':before,'clock_edge_experiment':a.clock_edges}
        script=ROOT/'tools'/('review_msu1_clock_edges.tcl' if a.clock_edges else 'review_msu1_postfit.tcl')
        record['query_script_sha256']=sha(script)
        (out/script.name).write_bytes(script.read_bytes())
        (out/pathlib.Path(__file__).name).write_bytes(pathlib.Path(__file__).read_bytes())
        extra=[]
        if a.clock_edges:
            counters,mem,sys=fitted_counters(manifest.parent/'snes_pocket.fit.rpt')
            record['fitted_counters']=counters;extra=[str(mem),str(sys)]
            record['candidate_sdc_sha256']=sha(ROOT/'target/pocket/experiments/exact_counter_edges.sdc')
        command=[str(a.quartus_sta.resolve()),'-t',str(script),str(project),str(out),a.region,*extra]
        record['command']=command
        (out/'review-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
        with (out/'query.log').open('w') as log:
            result=subprocess.run(command,cwd=project,stdout=log,stderr=subprocess.STDOUT)
        record['protected_unchanged']=before==protection();record['exit_code']=result.returncode
        record['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out/'review-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
        require(record['protected_unchanged'],'Protected project/report bytes changed')
        require(result.returncode==0,'STA query failed; see query.log')
        status=out/('clocks-raw.tsv' if a.clock_edges else 'review.tsv')
        require('result\tPASS\n' in status.read_text(),'Missing final query PASS')
        if a.clock_edges:compare_clock_experiment(out)
        print('PASS read-only completed-build review:',out)
if __name__=='__main__':main()
