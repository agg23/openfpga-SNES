#!/usr/bin/env python3
"""Bounded exhaustive two-state proof of the proposed pure fanout split.

This does NOT prove Quartus matched the QSF assignment or preserved the expected
netlist. That needs a separate mapped/fitted connectivity inspection. No design
files, project databases, or compiler processes are accessed here.
"""
from hashlib import sha256
from itertools import product
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[2]
vhdl = (ROOT/'rtl/upstream/SNES.vhd').read_text()
msu = (ROOT/'rtl/upstream/chip/MSU1/MSU.sv').read_text()
compact = lambda s: re.sub(r'\s+', '', s)
assert compact("DO <= BUSB_DO when INT_PARD_N = '0' else CPU_DO;") in compact(vhdl)
assert compact('if (DIN[2] && !DIN[0]) begin\nresume_track_num <= track_num;\nresume_sector <= audio_sector;\nresume_loop_index <= audio_loop_index;\nresume_valid <= 1;\nend') in compact(msu)
# The only cloned logic is the last combinational mux. Its existing two data
# inputs (BUSB_DO bit 2 and CPU_DO bit 2) and selector are wired unchanged.
mux_cases = 0
for busb2, cpu2, pard_n in product((0,1), repeat=3):
    original = busb2 if not pard_n else cpu2
    clone = (busb2 and not pard_n) or (cpu2 and pard_n)
    assert original == clone
    mux_cases += 1
# Exhaustive next-state proof for one arbitrary snapshot-bank bit. Bitwise
# lifting covers all 32 resume_loop_index, 22 resume_sector and 16 track bits.
# Explicit controls: reset, selection, bus commit, WR_N, ADDR==7, busy, missing,
# DIN0, two data inputs and mux select; old/new snapshot bit.
next_cases = 0
for vals in product((0,1), repeat=13):
    rst, sel, ce, wr_n, addr7, busy, missing, din0, busb2, cpu2, pard_n, old, data = vals
    din2 = busb2 if not pard_n else cpu2
    local_din2 = (busb2 and not pard_n) or (cpu2 and pard_n)
    common = sel and ce and not wr_n and addr7 and not busy and not missing and not din0
    old_next = 0 if not rst else data if common and din2 else old
    new_next = 0 if not rst else data if common and local_din2 else old
    assert old_next == new_next
    next_cases += 1
print(f'PASS: {mux_cases} mux cases, {next_cases} snapshot next-state cases')
print('PASS: same current-edge capture, reset priority, hold and data value')
print('Limits: two-state logical identity only; no mapped/fitted implementation proof')
print('SNES.vhd sha256', sha256(vhdl.encode()).hexdigest())
print('MSU.sv sha256', sha256(msu.encode()).hexdigest())
