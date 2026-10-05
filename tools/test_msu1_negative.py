#!/usr/bin/env python3
"""Reproduce four directed SCPU mutation controls using actual GHDL simulation.

All modified VHDL and GHDL work files live in a TemporaryDirectory. Working RTL
and testbench assertions are never modified. Every fixture must first pass with
the unmodified SCPU, then fail with its exact intended assertion after mutation.
This tool does not download software, require Git history, or perform a fit.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PARTS = ['P65816_pkg', 'AddrGen', 'BCDAdder', 'AddSubBCD', 'ALU', 'MCode', 'P65C816']


def replace_once(source, old, new):
    count = source.count(old)
    if count != 1:
        raise ValueError(f'Mutation anchor must occur once; found {count}: {old!r}')
    return source.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/msu1-negative-controls',
                        help='Directory for logs and machine-readable summary')
    args = parser.parse_args()
    ghdl = shutil.which('ghdl')
    if not ghdl:
        parser.error('GHDL unavailable: negative controls NOT RUN; put GHDL in PATH')
    output = (ROOT / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    original = (ROOT / 'rtl/upstream/CPU.vhd').read_text()
    sha256 = hashlib.sha256(original.encode()).hexdigest()
    read_wait = (
        "READ_WAIT <= BUS_WAIT and P65_R_WN and (P65_VPA or P65_VDA)\n"
        "\t             when DMA_ACTIVE = '0' else\n"
        "\t             BUS_WAIT and ((not DMA_DIR and (DMA_TRANSFER or HDMA_TRANSFER)) or\n"
        "\t                           FETCH_SCANLINE_COUNTER or FETCH_IND_ADDR);"
    )
    # The transaction branch exports the same raw read intent separately.
    # Mutate the actual readiness term, never a reimplemented test-only copy.
    retained_intent = "READ_WAIT <= BUS_WAIT and A_READ_INTENT;"
    if retained_intent in original:
        read_wait = retained_intent
    mutations = [
        dict(name='no_bus_wait', bench='tb_scpu_msu_wait', generics=[],
             old=read_wait, new="READ_WAIT <= '0';",
             expected='DMA destination write began before source ready'),
        dict(name='no_frame_context', bench='tb_scpu_hdma_init_fetch_wait', generics=[],
             old="HDMA_FRAME_INIT <= '1';", new="HDMA_FRAME_INIT <= '0';",
             expected='HDMA source incorrect at write edge'),
        dict(name='no_frame_deferral', bench='tb_scpu_hdma_wait', generics=[],
             old="if (HDMA_RUN = '1' and BUS_WAIT_SEEN = '1') or READ_WAIT = '1' or WAIT_CYCLE = '1' then",
             new='if false then', expected='HDMA stalled-frame deadlock'),
        dict(name='pinned_refresh', bench='tb_scpu_msu_wait',
             generics=['-gHB_OFFSET=144', '-gREQUIRE_REFRESH_ENTRY=true'],
             old="if ENABLE = '1' and INT_CLKF_CE = '1' and\n\t\t\t   (REFRESHED = '1' or (READ_WAIT = '0' and WAIT_CYCLE = '0')) then",
             new="if ENABLE = '1' and BUS_CLKF_CE = '1' then",
             expected='NMI edge during stalled read was lost or duplicated'),
    ]
    if retained_intent in original:
        # The same frame/refresh guards now also include the independently
        # exported write-credit wait. Keep each original failure oracle intact.
        for mutation in mutations:
            if mutation['name'] == 'no_frame_deferral':
                mutation['old'] = mutation['old'].replace("or WAIT_CYCLE", "or WRITE_WAIT = '1' or WAIT_CYCLE")
            if mutation['name'] == 'pinned_refresh':
                mutation['old'] = mutation['old'].replace("and WAIT_CYCLE", "and WRITE_WAIT = '0' and WAIT_CYCLE")
    records = []
    passed = True
    with tempfile.TemporaryDirectory(prefix='msu1-negative-') as temporary:
        work = pathlib.Path(temporary)
        flags = ['--std=08', '-fsynopsys', '--workdir=' + str(work)]

        def run(label, action, *arguments):
            command = [ghdl, action, *flags, *map(str, arguments)]
            try:
                result = subprocess.run(command, cwd=ROOT, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
                text, code = result.stdout, result.returncode
            except subprocess.TimeoutExpired as error:
                text, code = str(error), 124
            (output / (label + '.log')).write_text(text)
            return code, text

        def require_success(label, action, *arguments):
            code, text = run(label, action, *arguments)
            if code:
                raise RuntimeError(f'{label} failed ({code}); see {output / (label + ".log")}\n{text}')
            return text

        try:
            require_success('common-compile', '-a',
                            *[ROOT / 'rtl/upstream/65C816' / (part + '.vhd') for part in PARTS],
                            ROOT / 'rtl/upstream/CPU.vhd')
            for mutation in mutations:
                name, bench = mutation['name'], mutation['bench']
                fixture = ROOT / 'tests/msu1' / (bench + '.vhd')
                require_success(name + '-positive-compile', '-a', fixture)
                require_success(name + '-positive-elaborate', '-e', bench)
                positive = require_success(name + '-positive', '-r', bench, *mutation['generics'],
                                           '--assert-level=error', '--ieee-asserts=disable')
                if 'PASS' not in positive:
                    raise RuntimeError(f'{name}: positive fixture exited without its PASS marker')

                # Only rename the actual entity/instance; all fixture assertions
                # and original ROM bytes remain present and unchanged.
                cpu = replace_once(original, mutation['old'], mutation['new'])
                cpu = re.sub(r'\bSCPU\b', 'SCPU_MUT', cpu)
                cpu_path = work / 'CPU_mutation.vhd'
                cpu_path.write_text(cpu)
                test = fixture.read_text()
                test = replace_once(test, 'work.SCPU', 'work.SCPU_MUT')
                test = re.sub(r'\b' + re.escape(bench) + r'\b', 'tb_mutation', test)
                test_path = work / 'tb_mutation.vhd'
                test_path.write_text(test)
                require_success(name + '-mutation-compile', '-a', cpu_path, test_path)
                require_success(name + '-mutation-elaborate', '-e', 'tb_mutation')
                code, result = run(name + '-mutation', '-r', 'tb_mutation', *mutation['generics'],
                                   '--assert-level=error', '--ieee-asserts=disable')
                detected = (code not in (0, 124) and '(assertion failure)' in result
                            and mutation['expected'] in result)
                records.append({'name': name, 'positive_passed': True,
                                'mutation_exit_code': code, 'detected': detected,
                                'expected_assertion': mutation['expected'],
                                'mutation': {'old': mutation['old'], 'new': mutation['new']}})
                passed = passed and detected
                print(('PASS ' if detected else 'FAIL ') + name + ': ' + mutation['expected'], flush=True)
        except (ValueError, RuntimeError) as error:
            passed = False
            records.append({'error': str(error)})
            print('FAIL ' + str(error), flush=True)

    unchanged = hashlib.sha256((ROOT / 'rtl/upstream/CPU.vhd').read_bytes()).hexdigest() == sha256
    passed = passed and unchanged
    summary = {'timestamp_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'passed': passed, 'working_rtl_unchanged': unchanged, 'cpu_source_sha256': sha256,
               'checks': records,
               'scope': 'Actual SCPU GHDL simulations using temporary mutated copies; no working RTL or assertions modified.'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
