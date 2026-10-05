#!/usr/bin/env python3
"""Run the authorized local build with process-tree and OS resource evidence.

Does not install software, change clocks/constraints, program hardware or erase
old builds. MSU1_BUILD_JOBS is an explicit generate.tcl processor-count override.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def kernel_memory():
    result = {}
    try:
        for line in Path('/proc/meminfo').read_text().splitlines():
            key, value = line.split(':', 1)
            if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree'):
                result[key + '_KiB'] = int(value.split()[0])
        for line in Path('/proc/vmstat').read_text().splitlines():
            if line.startswith('oom_kill '):
                result['global_oom_kill'] = int(line.split()[1])
    except (OSError, ValueError):
        pass
    return result


def descendants(pid):
    entries = {}
    for path in Path('/proc').glob('[0-9]*'):
        try:
            stat = (path / 'stat').read_text()
            end = stat.rfind(')')
            fields = stat[end+2:].split()
            entries[int(path.name)] = (int(fields[1]), stat[stat.find('(')+1:end])
        except (OSError, ValueError, IndexError):
            pass
    selected = {pid}
    for _ in range(32):
        new = {p for p, (parent, _) in entries.items() if parent in selected}
        if new <= selected:
            break
        selected |= new
    rows = []
    for process in sorted(selected):
        try:
            row = {'pid': process, 'name': entries[process][1]}
            for line in Path(f'/proc/{process}/status').read_text().splitlines():
                key, value = line.split(':', 1)
                if key in ('VmRSS', 'VmHWM', 'VmPeak'):
                    row[key + '_KiB'] = int(value.split()[0])
            rows.append(row)
        except (OSError, KeyError, ValueError):
            pass
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('profile', nargs='?', choices=['msu_standard_ntsc','msu_standard_pal','standard_ntsc_spc'])
    ap.add_argument('--output', type=Path, required=True, help='New empty resource-log directory')
    ap.add_argument('--interval', type=float, default=2.0)
    ap.add_argument('--self-test', action='store_true')
    args = ap.parse_args()
    if not args.self_test and not args.profile:
        ap.error('profile required unless --self-test')
    if args.interval <= 0:
        ap.error('positive sample interval required')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    command = [str(ROOT / 'tools/build_msu1.sh'), args.profile] if not args.self_test else [
        sys.executable, '-c', 'import time; x=bytearray(48*1024*1024); time.sleep(.3); raise SystemExit(17)']
    before = kernel_memory()
    record = {'started_utc': utc(), 'command': command, 'cwd': str(ROOT),
              'parallel_processors_override': os.environ.get('MSU1_BUILD_JOBS'),
              'source_commit': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
              'source_status_before': subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines(),
              'kernel_before': before, 'state': 'running',
              'limits': ['sampled tree RSS peak is a lower bound, not continuous accounting',
                         'summed process RSS may count shared pages more than once',
                         'ru_maxrss is the largest waited child process, not the sum of concurrent processes',
                         'global OOM counter cannot identify the victim without kernel/cgroup evidence']}
    receipt = out / 'resources.json'
    receipt.write_text(json.dumps(record, indent=2) + '\n')
    sampled_peak = 0
    highest_child_hwm = 0
    interrupted = False
    started = time.monotonic()
    with (out/'build.log').open('w') as log, (out/'memory-samples.jsonl').open('w') as samples:
        process = subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            while True:
                rows = descendants(process.pid)
                rss = sum(p.get('VmRSS_KiB', 0) for p in rows)
                sampled_peak = max(sampled_peak, rss)
                highest_child_hwm = max([highest_child_hwm] + [p.get('VmHWM_KiB', 0) for p in rows])
                sample = {'utc': utc(), 'elapsed_s': time.monotonic()-started,
                          'tree_rss_KiB': rss, 'processes': rows, 'kernel': kernel_memory()}
                samples.write(json.dumps(sample) + '\n'); samples.flush()
                if process.poll() is not None:
                    break
                time.sleep(args.interval)
        except KeyboardInterrupt:
            interrupted = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        code = process.wait()
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    after = kernel_memory()
    record.update(finished_utc=utc(), elapsed_s=time.monotonic()-started,
                  returncode=code, interrupted=interrupted,
                  state='completed' if code == 0 else 'failed_or_interrupted',
                  largest_waited_child_rss_KiB=usage.ru_maxrss,
                  sampled_tree_peak_rss_KiB=sampled_peak,
                  observed_process_peak_hwm_KiB=highest_child_hwm,
                  child_user_seconds=usage.ru_utime,child_system_seconds=usage.ru_stime,
                  kernel_after=after)
    if 'global_oom_kill' in before and 'global_oom_kill' in after:
        record['global_oom_kill_delta'] = after['global_oom_kill']-before['global_oom_kill']
    if args.self_test:
        record['self_test_passed'] = code == 17 and usage.ru_maxrss >= 48*1024 and sampled_peak >= 48*1024
    receipt.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'returncode':code,'resources':str(receipt),
                      'largest_waited_child_rss_KiB':usage.ru_maxrss,'sampled_tree_peak_rss_KiB':sampled_peak}))
    if args.self_test:
        return 0 if record['self_test_passed'] else 1
    return 130 if interrupted else (code if code >= 0 else 128-code)


if __name__ == '__main__':
    raise SystemExit(main())
