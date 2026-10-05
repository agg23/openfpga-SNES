#!/usr/bin/env python3
"""Compile isolated broken RTL variants; each must fail the real mapper test."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
os.environ['PATH'] = '/tmp/msu1-tools/bin:'+os.environ['PATH']
BASE = ROOT/'rtl/upstream/chip/SDD1'
BRIDGE = ROOT/'rtl/upstream/chip/SA1/SA1RomBridge.vhd'
if not BRIDGE.exists(): BRIDGE = ROOT.parent/'standard-sa1-waits/rtl/upstream/chip/SA1/SA1RomBridge.vhd'
variants = [
    ('drop_run2_on_enable_pause','Decoder.vhd',
     "if not ROM_HANDSHAKE then RUN2 <= '0'; end if;", "RUN2 <= '0';", 'mismatch'),
    ('ignore_input_empty','Decoder.vhd',
     'ENABLE and (not INPUT_REQ or INPUT_READY) and', 'ENABLE and', 'input pop without'),
    ('wrong_odd_header_lane','InputMgr.vhd',
     'q(n) := ROM_DATA(15 downto 8); n := n+1;', 'q(n) := ROM_DATA(7 downto 0); n := n+1;', 'mismatch'),
    ('repeat_output_pair','Decoder.vhd',
     "if ROM_HANDSHAKE and ENABLE='1' and OUTPUT_READY='1' then", 'if false then', 'mismatch'),
    ('wrong_snes_lane','SDD1Map.vhd',
     "when MEM_LANE(0)='0' else", "when true else", 'contending SNES lane/data mismatch'),
    ('erase_token_on_soft_reset','SDD1Map.vhd',
     'HARD_RESET_N=>ROM_HARD_RESET_N, EPOCH', 'HARD_RESET_N=>CORE_RESET_N, EPOCH', 'mismatched token released decoder'),
]
results = []
for name, file, old, new, error in variants:
    d = Path(tempfile.mkdtemp(prefix='sdd1-mutant-'+name+'-'))
    baseline = subprocess.check_output(['git','show','b63f800:rtl/upstream/chip/SDD1/Decoder.vhd'],text=True)
    (d/'baseline.vhd').write_text(baseline.replace('SDD1_Decoder','SDD1_Decoder_Baseline'))
    files=[]
    for filename in ['InputMgr.vhd','Decoder.vhd','SDD1.vhd','SDD1Map.vhd']:
        text=(BASE/filename).read_text()
        if filename == file:
            assert text.count(old)==1, (name,text.count(old))
            text=text.replace(old,new)
        (d/filename).write_text(text)
        files.append(str(d/filename))
    flags=['--std=08','-fsynopsys','--workdir='+str(d)]
    subprocess.run(['ghdl','-a',*flags,str(BRIDGE),str(d/'baseline.vhd'),*files,
                    'tests/sdd1_waits/tb_sdd1_waits.vhd'],check=True,capture_output=True,text=True)
    run=subprocess.run(['ghdl','-r',*flags,'tb_sdd1_waits','-gCASES=17','-gOUTPUT_BYTES=32',
                        '--assert-level=error'],capture_output=True,text=True,timeout=90)
    log=run.stdout+run.stderr
    (d/'result.log').write_text(log)
    assert run.returncode != 0 and error in log, f'{name} unexpectedly survived or failed differently: {log[-2000:]}'
    failure=next(line for line in log.splitlines() if '(assertion failure)' in line)
    results.append({'mutation':name,'detected':True,'failure':failure})
print(json.dumps(results,indent=2))
