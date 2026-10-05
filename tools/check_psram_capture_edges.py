#!/usr/bin/env python3
"""Read-only derived edge model; not an RTL simulation.
Run from any directory: python3 tools/check_psram_capture_edges.py
"""
from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / 'rtl/upstream/DSP_PKG.vhd').read_text()
source = source.split('constant RS_TBL')[1].split(');', 1)[0]
table = re.findall(r'\((RS_[A-Z0-9]+),\s*(RS_[A-Z0-9]+),\s*(RS_[A-Z0-9]+),\s*(RS_[A-Z0-9]+)\)', source)
assert len(table) == 32
for system_frequency in (21477270, 21281370):
    accumulator = step = substep = 0
    ce = False
    busy_end = -1
    delayed = []
    counterexamples = []
    for memory_edge in range(200000):
        # All consumers first sample pre-edge source values, including at
        # coincident system/memory edges (SystemVerilog NBA/VHDL delta model).
        rs = table[step][substep]
        slot = (step, substep)
        if memory_edge > busy_end and rs != 'RS_IDLE':
            if rs in ('RS_SMP', 'RS_ECHOWRL', 'RS_ECHOWRH'):
                delayed.append((memory_edge + 1, memory_edge, slot, rs))
            busy_end = memory_edge + 8
        for capture_edge, accept_edge, accepted_slot, accepted_rs in list(delayed):
            if capture_edge == memory_edge:
                if accepted_slot != slot:
                    counterexamples.append((accept_edge, capture_edge, accepted_slot, accepted_rs, slot, rs))
                delayed.remove((capture_edge, accept_edge, accepted_slot, accepted_rs))
        if memory_edge % 4 == 0 and ce:
            substep += 1
            if substep == 4:
                substep = 0
                step = (step + 1) % 32
        if memory_edge % 4 == 2:
            accumulator += 4096000
            ce = accumulator >= system_frequency
            if ce:
                accumulator -= system_frequency
    assert counterexamples
    print(system_frequency, 'Hz; first +1-cycle delayed-capture crossing:', counterexamples[0])
    print('Crossings over 200000 memory edges:', len(counterexamples))
