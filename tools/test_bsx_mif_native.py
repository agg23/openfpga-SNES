#!/usr/bin/env python3
"""Check real Quartus RAM initialization, including rejected missing-file designs.

Analysis/synthesis and functional netlist export only: no fitting, STA or device
programming. Reconstruct all 1024 bytes from the mapped Cyclone V RAM bit planes,
not merely a filename appearing in a log. Use an installed approved Quartus.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'rtl/upstream/chip/BSX/BSX_BS.vhd'
BINDING = 'rtl/upstream/chip/BSX/bsx_memory_init.qip'
MIF = 'rtl/upstream/chip/BSX/bsx121-124.mif'
FILES = [SOURCE, BINDING, MIF, 'rtl/upstream/chip/chip.qip', 'rtl/upstream/bram.vhd']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode_ram(netlist):
    fields = {}
    for name, key, value in re.findall(
        r'defparam\s+(\\[^\s]+)\s+\.(port_a_first_bit_number|mem_init0)\s*=\s*(.*?);',
        netlist,
    ):
        fields.setdefault(name, {})[key] = value.strip('"')
    planes = {
        int(v['port_a_first_bit_number']): int(v['mem_init0'], 16)
        for v in fields.values() if 'mem_init0' in v
    }
    # A missing-file design may optimize the ROM away entirely. Its absence is
    # evidence of failure, never a pass from an empty comparison.
    if set(planes) != set(range(8)):
        return None, len(planes)
    return bytes(sum(((value >> address) & 1) << bit for bit, value in planes.items())
                 for address in range(1024)), len(planes)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--quartus-sh', default=os.environ.get('QUARTUS_SH', 'quartus_sh'))
    ap.add_argument('--output', type=Path)
    args = ap.parse_args()
    qsh = shutil.which(args.quartus_sh)
    if not qsh:
        raise SystemExit('NOT RUN: installed approved Quartus required')
    bindir = Path(qsh).resolve().parent
    if args.output:
        out = args.output.resolve()
        out.mkdir(parents=True, exist_ok=True)
        if any(out.iterdir()):
            raise SystemExit('Use a new empty output directory')
    else:
        (ROOT / 'build').mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix='bsx-mif-native-', dir=ROOT / 'build'))
    before = {name: digest(ROOT / name) for name in FILES}
    text = (ROOT / SOURCE).read_text()
    assert 'generic map(10, 8, "bsx121-124.mif")' in text
    assert 'BSX/bsx_memory_init.qip' in (ROOT / FILES[3]).read_text()
    values = re.findall(r'^\s*([0-9A-F]+)\s*:\s*([0-9A-F]+);', (ROOT / MIF).read_text(), re.M)
    assert len(values) == 550 and len({a for a, _ in values}) == 550
    expected = bytearray(1024)
    for address, value in values:
        expected[int(address, 16)] = int(value, 16)
    assert any(expected) and not any(expected[550:])
    results = []
    cases = [('current', None, True), ('nested cwd with spaces/projects', None, True),
             ('historical-path', 'rtl/chip/BSX/bsx121-124.mif', False),
             ('wrong-basename', 'missing-bsx-channel-data.mif', True)]
    for name, replacement, include_binding in cases:
        work = out / name
        work.mkdir(parents=True)
        rtl = ROOT / SOURCE
        if replacement:
            rtl = work / 'BSX_BS.vhd'
            rtl.write_text(text.replace('"bsx121-124.mif"', '"' + replacement + '"'))
        (work / 'unit.qpf').write_text('QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n')
        qsf = f'''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY BS
set_global_assignment -name VHDL_FILE "{ROOT / 'rtl/upstream/bram.vhd'}"
set_global_assignment -name VHDL_FILE "{rtl}"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_instance_assignment -name VIRTUAL_PIN ON -to *
'''
        if include_binding:
            qsf += f'set_global_assignment -name QIP_FILE "{ROOT / BINDING}"\n'
        (work / 'unit.qsf').write_text(qsf)
        logs = {}
        commands = [[str(bindir / 'quartus_map'), 'unit'],
                    [str(bindir / 'quartus_eda'), 'unit', '--simulation', '--tool=modelsim',
                     '--format=verilog', '--functional=on', '--output_directory=netlist']]
        for label, command in zip(['map', 'eda'], commands):
            result = subprocess.run(command, cwd=work, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=180)
            logs[label] = result.stdout
            (work / (label + '.log')).write_text(result.stdout)
            if result.returncode:
                raise RuntimeError(f'{name} {label}: unrelated tool failure {result.returncode}')
        mapped, planes = decode_ram((work / 'netlist/unit.vo').read_text())
        equal = mapped == expected
        missing = 'Critical Warning (127003)' in logs['map']
        if replacement:
            assert missing and not equal, 'Missing-file negative control survived'
        else:
            assert not missing and equal, 'Initialization content mismatch'
            assert str(ROOT / MIF) in logs['map'], 'Resolved source filename not reported'
        results.append({'case': name, 'negative_control': bool(replacement),
                        'accepted_check': True, 'missing_file_warning': missing,
                        'mapped_bit_planes': planes, 'all_1024_bytes_match': equal,
                        'mapped_sha256': hashlib.sha256(mapped).hexdigest() if mapped else None,
                        'netlist_sha256': digest(work / 'netlist/unit.vo'),
                        'commands': commands})
        print('PASS', name, 'negative rejected' if replacement else '1024 bytes match')
    assert before == {name: digest(ROOT / name) for name in FILES}, 'Source changed during run'
    summary = {'status': 'PASS', 'stage': 'Native map + functional netlist export only',
               'source_sha256': before, 'source_stable': True, 'cases': results,
               'declared_mif_bytes': 550, 'mapped_memory_bytes': 1024,
               'nonzero_bytes': sum(x != 0 for x in expected),
               'expected_sha256': hashlib.sha256(expected).hexdigest(),
               'uninitialized_tail': '474 addresses explicitly checked as zero padding',
               'timing_verified': False, 'hardware_verified': False}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('PASS native BSX MIF content and path controls:', out)


if __name__ == '__main__':
    main()
