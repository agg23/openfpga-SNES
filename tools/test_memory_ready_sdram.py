#!/usr/bin/env python3
"""Run the independent AS4C32M16MSA-6BIN pin/data model and checker controls.

Generated executables/logs stay in --output. No RTL rewrites or Quartus fit.
Verilator 5.x with --binary --timing and a C++ toolchain is required.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "tests/memory_ready/as4c32m16msa_model.sv"
TB = ROOT / "tests/memory_ready/tb_sdram_single_request.sv"
NEG_TB = ROOT / "tests/memory_ready/tb_sdram_model_negative.sv"
DUT = ROOT / "rtl/memory_ready/sdram_single_request.sv"
NEGATIVE_CASES = {
    "init_wait": "INIT_WAIT", "missing_mr": "MISSING_MR",
    "missing_emr": "MISSING_EMR", "missing_ar": "MISSING_AR",
    "init_ar_spacing": "INIT_AR_SPACING", "bad_mr": "BAD_MR",
    "t_mrd": "T_MRD", "t_rp_act": "T_RP", "t_rcd": "T_RCD",
    "t_ras": "T_RAS", "t_wr": "T_WR", "t_rp_ar": "T_RP",
    "t_rfc": "T_RFC", "t_rrd": "T_RRD",
    "banks_active": "BANKS_ACTIVE", "refresh_late": "REFRESH_LATE",
    "contention": "CONTENTION",
}


def run(cmd: list[str], log: Path, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    start = time.monotonic()
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("$ " + " ".join(cmd) + "\n" + result.stdout + result.stderr)
    if result.returncode != 0 and "SDRAM_MODEL[" not in result.stdout and "TB_DATA:" not in result.stdout:
        print((result.stdout + result.stderr)[-4000:], file=sys.stderr)
    result.elapsed = time.monotonic() - start
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/memory-ready-sdram")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--quick", action="store_true", help="omit full row/column sweeps and shorten held response; not full qualification")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    # Negative controls deliberately invoke $fatal; do not create core dumps.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    results: list[dict] = []

    def build(name: str, top: str, sources: list[Path], parameters: list[str] | None = None) -> Path:
        target = out / name
        target.mkdir(exist_ok=True)
        command = [args.verilator, "--binary", "--timing", "--assert", "-j", str(args.jobs),
                   "-Wno-fatal", "--top-module", top, "--Mdir", str(target / "obj")]
        command += parameters or []
        command += [str(p) for p in sources]
        result = run(command, target / "compile.log")
        if result.returncode:
            raise RuntimeError(f"build {name} failed; see {target / 'compile.log'}")
        return target / "obj" / f"V{top}"

    def simulate(name: str, executable: Path, plusargs: list[str], expected: str,
                 must_fail: bool = False) -> None:
        result = run([str(executable), *plusargs], out / f"{name}.log")
        passed = ((result.returncode != 0) if must_fail else (result.returncode == 0)) and expected in result.stdout
        results.append({"name": name, "passed": passed, "expected_failure": must_fail,
                        "expected_diagnostic": expected, "exit_code": result.returncode,
                        "elapsed_seconds": round(result.elapsed, 3), "log": f"{name}.log"})
        if not passed:
            print((result.stdout + result.stderr)[-4000:], file=sys.stderr)
            raise RuntimeError(f"{name} did not meet expected outcome: {expected}")
        summaries = [line for line in result.stdout.splitlines() if line.startswith(("SUMMARY ", "PASS held response:"))]
        print(f"PASS {name}" + (" (expected rejection)" if must_fail else ""), flush=True)
        for line in summaries:
            print("  " + line, flush=True)

    try:
        direct = build("direct-model", "tb_sdram_model_negative", [NEG_TB, MODEL])
        simulate("direct-positive", direct, ["+case=valid"], "PASS direct-pin positive control")
        for name, tag in NEGATIVE_CASES.items():
            simulate("negative-" + name, direct, ["+case=" + name], "SDRAM_MODEL[" + tag + "]", True)

        quick = ["+quick"] if args.quick else []
        # The same conservative default engine parameter must also work with
        # the statically selected PAL PLL profile. Test that pairing explicitly.
        profiles = [
            ("ntsc", 107386350, 107386350),
            ("pal", 106406850, 106406850),
            ("pal-default-parameter", 107386350, 106406850),
        ]
        for name, clock_parameter, physical_clock in profiles:
            binary = build(name, "tb_sdram_single_request", [TB, MODEL, DUT],
                           [f"-GCLK_HZ={clock_parameter}", f"-GPHYSICAL_CLK_HZ={physical_clock}"])
            simulate(name, binary, quick, "PASS tb_sdram_single_request")
            if name == "ntsc":
                simulate("negative-corrupt-read", binary, ["+quick", "+corrupt_read"], "TB_DATA:", True)
        zero_r = build("zero-return-delay", "tb_sdram_single_request", [TB, MODEL, DUT],
                       ["-GRETURN_DELAY_NS=0.0"])
        simulate("negative-zero-return-delay", zero_r, ["+quick"], "TB_DATA:", True)
        high_r = build("long-return-delay", "tb_sdram_single_request", [TB, MODEL, DUT],
                       ["-GRETURN_DELAY_NS=10.0"])
        simulate("negative-long-return-delay", high_r, ["+quick"], "TB_DATA:", True)
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        status = 1
    else:
        status = 0
    summary = {
        "passed": status == 0, "full_geometry_and_refresh_sweep": not args.quick,
        "sources": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in [DUT, MODEL, TB, NEG_TB, Path(__file__).resolve()]},
        "device": "AS4C32M16MSA-6BIN, Alliance Rev1.0 Dec2017",
        "source_pdf_sha256": "bb49458b366aecffa8f16156b1afe1f19899071cd11181972c9822fbcd146fa5",
        "return_delay_ns": 3.0,
        "limits": "Independent restricted digital protocol model; synthetic aggregate return delay; no vendor-model, PCB/PVT/fitted-I/O, power sequencing, or reset/PLL retention signoff",
        "tests": results,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{'PASS' if status == 0 else 'FAIL'} {len(results)} checks; summary: {out / 'summary.json'}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
