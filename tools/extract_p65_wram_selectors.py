#!/usr/bin/env python3
"""Read-only P65 write-source enumeration and exact-source selector extraction.

Run: python3 tools/extract_p65_wram_selectors.py [--output build/p65-wram-selectors]
Writes only to the selected output directory. selector_model.vhd contains verbatim combinational
assignments/processes extracted from the selected Git snapshot, with symbolic inputs.
Default source is historical84d8d5e, never silently the current working-tree RTL.
"""
import argparse
import collections
import hashlib
import itertools
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REFERENCE_COMMIT = "84d8d5eb6f3e0de2d7f891581e1e922b109fb758"
SOURCE_PATHS = ["rtl/upstream/CPU.vhd", "rtl/upstream/SNES.vhd",
                "rtl/upstream/SWRAM.vhd", "rtl/upstream/65C816/MCode.vhd",
                "rtl/upstream/65C816/P65C816.vhd"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", default="build/p65-wram-selectors")
parser.add_argument("--source-commit", default=REFERENCE_COMMIT,
                    help="Git source revision to extract; defaults to the historical 84d8d5e proof inputs")
args = parser.parse_args()
HERE = (ROOT / args.output).resolve()
HERE.mkdir(parents=True, exist_ok=True)
source_commit = subprocess.check_output(
    ["git", "rev-parse", "--verify", args.source_commit + "^{commit}"],
    cwd=ROOT, text=True).strip()
sources = {path: subprocess.check_output(["git", "show", f"{source_commit}:{path}"], cwd=ROOT)
           for path in SOURCE_PATHS}
drift = []
for path, payload in sources.items():
    target = HERE / "source-snapshot" / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    current = ROOT / path
    if not current.exists() or current.read_bytes() != payload:
        drift.append(path)
(HERE / "source_provenance.json").write_text(json.dumps({
    "requested_ref": args.source_commit, "source_commit": source_commit,
    "input_origin": "git objects, not working-tree RTL", "working_tree_drift": drift,
    "default_historical_reference": REFERENCE_COMMIT,
}, indent=2) + "\n")
print(f"Historical selector proof source: {source_commit} (Git objects)")
if drift:
    print("NOTE: working-tree RTL differs and is intentionally NOT proved: " + ", ".join(drift))
fields = "stateCtrl addrBus addrInc loadP loadT muxCtrl addrCtrl loadPC loadSP regAXY loadDKB busCtrl ALUCtrl byteSel outBus va".split()
text = sources["rtl/upstream/65C816/MCode.vhd"].decode()
rows = []
opnames = {}
for lineno, line in enumerate(text.splitlines(), 1):
    if line.strip().startswith("type ALUCtrl_t"):
        break
    m = re.match(r"\s*-- ([0-9A-F]{2}) (.*)", line)
    if m:
        opnames[int(m[1], 16)] = m[2]
    vals = re.findall(r'"([01X]+)"', line.split("--", 1)[0])
    if len(vals) == len(fields):
        rows.append(dict(zip(fields, vals), line=lineno,
                         comment=line.partition("--")[2].strip()))
assert len(rows) == 2048

def nextstates(op, state, row):
    """Exact NextState equation, existentially quantified legal status inputs.

    Fresh status/control inputs each state are an overapproximation, not a
    sequential reachability proof. All returned table slots have concrete bits.
    """
    results = set()
    for ef, mf, xf, carry, jno, jtaken, dlnz in itertools.product(range(2), repeat=7):
        if ef and not (mf and xf):
            continue
        ctrl = row["stateCtrl"]
        wide = (row["regAXY"][1] == "0" and not mf and not ef) or (row["regAXY"][1] == "1" and not xf and not ef)
        if ctrl == "000": ns = state + 1
        elif ctrl == "001": ns = state + (2 if not carry and (xf or ef) else 1)
        elif ctrl == "010": ns = 2 if op & 31 == 16 and state == 1 and jtaken else 0
        elif ctrl == "011": ns = 0 if jno or not ef else state + 1
        elif ctrl == "100": ns = state + 1 if wide else 0
        elif ctrl == "101": ns = state + (1 if dlnz else 2)
        elif ctrl == "110": ns = state + (1 if wide else 2)
        elif ctrl == "111": ns = state + 1 if not ef else (0 if op == 0x40 else state + 2)
        else: raise AssertionError((op, state, ctrl))
        results.add(ns & 15)
    return results

reachable = set()
for op in range(256):
    pending = [1]
    seen = set()
    while pending:
        st = pending.pop()
        if st == 0 or st in seen:
            continue
        assert 1 <= st <= 8, (op, st)
        seen.add(st)
        idx = op * 8 + st - 1
        row = rows[idx]
        assert not any("X" in row[f] for f in fields), (op, st, row)
        reachable.add(idx)
        pending += list(nextstates(op, st, row))

writes = []
for i in sorted(reachable):
    row = rows[i]
    if row["outBus"] != "000":
        writes.append(dict(opcode=f"{i//8:02X}", mnemonic=opnames[i//8], state=i%8+1, **row))
out_counts = collections.Counter(r["outBus"] for r in writes)
sb_counts = collections.Counter(r["busCtrl"][:3] for r in writes if r["outBus"] == "101")
summary = {
    "table_rows": len(rows), "reachable_overapproximation_rows": len(reachable),
    "defined_rows": sum("X" not in r["outBus"] for r in rows),
    "write_rows": len(writes), "outBus_counts": dict(sorted(out_counts.items())),
    "write_SB_source_counts": dict(sorted(sb_counts.items())),
    "defined_rows_addrInc_bit1": sum(r["addrInc"][0] == "1" for r in rows),
    "write_rows_addrInc_bit1": sum(r["addrInc"][0] == "1" for r in writes),
    "analysis_limit": "State walk existentially quantifies legal status/control inputs per state; this is conservative control-flow enumeration, not full CPU sequential formal proof.",
}
(HERE / "microcode_writes.json").write_text(json.dumps(writes, indent=2) + "\n")
(HERE / "microcode_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))

def snippet(path, start, end=None):
    src = sources[path].decode()
    assert src.count(start) == 1, (path, start, src.count(start))
    a = src.index(start)
    b = src.index(end, a) + len(end) if end else src.index(";", a) + 1
    return "-- Source: " + path + "\n" + src[a:b] + "\n"

body = []
cpup = "rtl/upstream/CPU.vhd"
body.append(snippet(cpup, "DMA_ACTIVE <="))
body.append(snippet(cpup, "EN <= ENABLE and"))
body.append(snippet(cpup, "P65_EN <="))
body.append(snippet(cpup, "INT_A <="))
body.append(snippet(cpup, "process(INT_A)", "end process;"))
body.append(snippet(cpup, "process(P65_A, EN, CPU_RD, CPU_WR, DMA_B,", "end process;"))
# The historical default must remain byte-identical. Newer snapshots carry a
# standard-only read sideband; extract its actual equation instead of silently
# substituting a handwritten PA comparator or leaving RAM_CE_N unbound.
predecode = "WMDATA_SEL <=" in sources["rtl/upstream/SWRAM.vhd"].decode()
if predecode:
    body.append(snippet(cpup, "PA_WMDATA <="))
    body.append(snippet("rtl/upstream/SWRAM.vhd", "WMDATA_SEL <="))

snesp = "rtl/upstream/SNES.vhd"
for start in ("BUSA_SEL <=", "BUSA_DO <=", "WRAM_DI <="):
    body.append(snippet(snesp, start))
swramp = "rtl/upstream/SWRAM.vhd"
body.append("swrampart: block is\n alias DI : std_logic_vector(7 downto 0) is WRAM_DI;\nbegin\n")
for start in ("RAM_D <=", "RAM_CE_N <=", "RAM_WE_N <="):
    body.append(snippet(swramp, start))
body.append("end block;\n")

header = '''library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
entity SelectorModel is port (
 P65_A, DMA_A : in std_logic_vector(23 downto 0);
 DMA_B : in std_logic_vector(7 downto 0);
 ENABLE, REFRESHED, DMA_RUN, HDMA_RUN, CPU_RD, CPU_WR : in std_logic;
 DMA_TRANSFER, HDMA_BUS_ACTIVE : in std_logic;
 DMA_B_RD, DMA_B_WR, DMA_A_RD, DMA_A_WR : in std_logic;
 HDMA_A_RD, HDMA_A_WR, HDMA_B_RD, HDMA_B_WR : in std_logic;
 DI, BUSB_DO, CPU_DO : in std_logic_vector(7 downto 0);
 CA : out std_logic_vector(23 downto 0);
 PA : out std_logic_vector(7 downto 0);
 PARD_N, PAWR_N : out std_logic;
 WRAM_DI, RAM_D : out std_logic_vector(7 downto 0);
 RAM_CE_N, RAM_WE_N, DMA_ACTIVE, BUSA_SEL : out std_logic
); end SelectorModel;
architecture exact of SelectorModel is
 signal INT_A : std_logic_vector(23 downto 0);
 signal INT_RAMSEL_N, INT_ROMSEL_N, INT_CPUWR_N, INT_CPURD_N : std_logic;
 signal EN, P65_EN : std_logic;
 signal BUSA_DO : std_logic_vector(7 downto 0);
 alias INT_CA : std_logic_vector(23 downto 0) is CA;
 alias INT_PARD_N : std_logic is PARD_N;
 alias CPUWR_N : std_logic is INT_CPUWR_N;
 alias RAMSEL_N : std_logic is INT_RAMSEL_N;
begin
'''
if predecode:
    header = header.replace("begin\n", " signal PA_WMDATA, WMDATA_SEL : std_logic;\n"
                            " constant WMDATA_PREDECODE : boolean := true;\nbegin\n", 1)
    print("Current-ref standard WRAM sideband is extracted verbatim; legacy default snapshot is unchanged")
(HERE / "selector_model.vhd").write_text(header + "\n".join(body) + "\nend exact;\n")
(HERE / "source_hashes.json").write_text(json.dumps({p: hashlib.sha256(payload).hexdigest() for p, payload in sources.items()}, indent=2)+"\n")
