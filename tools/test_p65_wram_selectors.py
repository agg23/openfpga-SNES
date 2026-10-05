#!/usr/bin/env python3
"""Check an extracted P65/WRAM selector model and require two negative controls.

This is a guarded combinational observation proof, not a whole-core, sequential,
clock-phase, or hardware timing sign-off. See docs/p65-wram-selector-evidence.md.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REFERENCE_COMMIT = "84d8d5eb6f3e0de2d7f891581e1e922b109fb758"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="build/p65-wram-selectors")
    parser.add_argument("--source-commit", default=REFERENCE_COMMIT,
                        help="Git source revision; defaults to historical 84d8d5e, not current RTL")
    args = parser.parse_args()
    out = (ROOT / args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for tool in ("ghdl", "yosys", "git"):
        if not shutil.which(tool):
            parser.error(f"{tool} is required on PATH")

    def run(command, log):
        result = subprocess.run(command, cwd=out, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / log).write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}); see {out / log}")
        return result.stdout

    run([sys.executable, str(ROOT / "tools/extract_p65_wram_selectors.py"),
         "--output", str(out), "--source-commit", args.source_commit], "enumeration.log")
    provenance = json.loads((out / "source_provenance.json").read_text())
    print(f"Source revision: {provenance['source_commit']} (Git objects)")
    if provenance["working_tree_drift"]:
        print("NOTE: current working-tree RTL differs; these results do not prove it")
    synth = subprocess.run(["ghdl", "--synth", "--std=08", "--out=verilog",
                            "selector_model.vhd", "-e", "SelectorModel"],
                           cwd=out, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out / "ghdl.log").write_text(synth.stderr)
    if synth.returncode:
        raise RuntimeError(f"GHDL synthesis failed; see {out / 'ghdl.log'}")
    (out / "selector_model.v").write_text(synth.stdout)
    # Copy only the verification harness, so Yosys paths are all local to out.
    shutil.copyfile(ROOT / "tests/timing/p65_wram_selector_miter.sv", out / "selector_miter.sv")
    prelude = "read_verilog -sv selector_model.v selector_miter.sv\nprep -top miter -flatten\n"
    checks = [
        ("selector-proof", "sat -set assumptions 1 -prove equivalent 1 "
         "-prove cpu_payload_independent 1 -prove read_bus_write_needs_dma 1 -verify",
         "SAT proof finished - no model found: SUCCESS!"),
        ("dma-data-counterexample", "sat -set assumptions 1 -set enable 1 "
         "-set refreshed 0 -set dma_run 1 -set hdma_run 0 -set dma_transfer 1 "
         "-set hdma_bus_active 0 -set dma_a 32768 -set dma_b 128 "
         "-set dma_a_rd 1 -set dma_a_wr 0 -set dma_b_rd 0 -set dma_b_wr 1 "
         "-set di 165 -set cpu_do 90 -set observed_write 1 "
         "-prove always_cpu_safe 1 -falsify -show-inputs -show-outputs",
         "SAT proof finished - model found: FAIL!"),
        ("unguarded-counterexample", "sat -prove equivalent 1 -falsify "
         "-show-inputs -show-outputs", "SAT proof finished - model found: FAIL!"),
    ]
    outcomes = {}
    for name, command, expected in checks:
        script = out / (name + ".ys")
        script.write_text(prelude + command + "\n")
        log = run(["yosys", "-Q", "-s", script.name], name + ".log")
        if expected not in log:
            raise RuntimeError(f"Unexpected SAT outcome; see {out / (name + '.log')}")
        outcomes[name] = "pass" if name == "selector-proof" else "rejected as expected"
        print(f"PASS {name}: {outcomes[name]}")

    versions = {tool: subprocess.check_output([tool, flag], text=True).strip()
                for tool, flag in (("ghdl", "--version"), ("yosys", "-V"))}
    summary = {
        "scope": "guarded combinational observation equivalence only",
        "assumptions": ["not (CPU_RD and CPU_WR)", "DMA_TRANSFER implies DMA_RUN",
                        "HDMA_BUS_ACTIVE implies HDMA_RUN"],
        "not_proved": ["whole-core equivalence", "sequential lifecycle invariants",
                       "memory-clock capture/glitch safety", "timing closure"],
        "checks": outcomes, "tools": versions,
        "source": provenance,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Evidence: {out}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
