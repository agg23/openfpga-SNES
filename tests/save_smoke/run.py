#!/usr/bin/env python3
"""Execute original save ROM on exact production SCPU/P65 using serial GHDL.
No Quartus, Verilator, C++ build, external install or production source edits.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("standard_save_testrom", ROOT / "tools/standard_save_testrom.py")
ROM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROM)
CPU_PARTS = ["P65816_pkg", "AddrGen", "BCDAdder", "AddSubBCD", "ALU", "MCode", "P65C816"]


def expected_save(counter):
    # Independent test oracle; do not call the generator's save_image helper.
    data = bytearray(2048)
    for page in range(8):
        for low in range(256):
            data[page*256+low] = ((low*73) & 255) ^ page ^ 167
    data[:16] = b"POCKET-SRAM-v1!!"
    data[16:18] = bytes((counter, 255-counter))
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/save-smoke-cpu")
    parser.add_argument("--ghdl", help="GHDL executable or existing project wrapper")
    args = parser.parse_args()
    ghdl = args.ghdl or shutil.which("ghdl")
    if not ghdl and Path("/tmp/msu1-tools/bin/ghdl").is_file():
        ghdl = "/tmp/msu1-tools/bin/ghdl"
    if not ghdl:
        raise SystemExit("GHDL unavailable; actual SCPU/P65 ROM tests NOT RUN")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    work = out / "ghdl-work"; work.mkdir()
    flags = ["--std=08", "-fsynopsys", f"--workdir={work}"]
    sources = [ROOT / "rtl/upstream/65C816" / (name+".vhd") for name in CPU_PARTS]
    sources += [ROOT / "rtl/upstream/CPU.vhd", ROOT / "tests/save_smoke/tb_standard_save_rom.vhd"]
    checks = []
    summary = {"scope": "actual unchanged SCPU/P65 executing generated original ROM; simple RAM/PPU fixture",
               "hardware_verified": False, "full_console_verified": False,
               "save_transport_verified": False, "checks": checks,
               "sources_sha256": {str(p.relative_to(ROOT)): ROM.sha256(p.read_bytes()) for p in sources + [Path(__file__), ROOT / "tools/standard_save_testrom.py"]}}
    def run(name, command, negative=False, marker=None):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
        log = result.stdout+result.stderr
        (out/(name+".log")).write_text(log)
        passed = result.returncode != 0 if negative else result.returncode == 0
        if marker: passed = passed and marker in log
        checks.append({"name": name, "passed": passed, "negative_control": negative,
                       "returncode": result.returncode, "command": list(map(str, command)),
                       "metrics": re.findall(r"PASS actual SCPU/P65[^\n]*", log)})
        if not passed: raise AssertionError(name+"\n"+log[-6000:])
        print("PASS "+name, flush=True)
        return log
    def hex_file(path, data):
        path.write_text("".join(f"{value:02X}\n" for value in data))
    rom, symbols = ROM.build_rom()
    summary["rom"] = ROM.validate_rom(rom)
    hex_file(out/"rom.hex", rom)
    def simulate(name, initial, expected, color, writes, read_all=False, write_all=False,
                 required_read=-1, turbo=False, rom_name="rom.hex", negative=False, marker="PASS actual SCPU/P65"):
        input_file, output_file = out/(name+"-input.hex"), out/(name+"-output.hex")
        hex_file(input_file, initial)
        command = [ghdl, "-r", *flags, "tb_standard_save_rom", f"-gROM_FILE={out/rom_name}",
                   f"-gSAVE_FILE={input_file}", f"-gOUTPUT_FILE={output_file}",
                   f"-gEXPECT_COLOR={color}", f"-gEXPECT_WRITES={writes}",
                   f"-gEXPECT_READ_ALL={str(read_all).lower()}", f"-gEXPECT_WRITE_ALL={str(write_all).lower()}",
                   f"-gREQUIRED_READ={required_read}", f"-gTURBO_MODE={str(turbo).lower()}",
                   "--assert-level=error", "--ieee-asserts=disable"]
        run(name, command, negative, marker)
        if negative: return
        data = bytes.fromhex(output_file.read_text())
        assert data == expected, f"{name}: all-2048-byte independent SRAM comparison failed"
        checks[-1].update({"output_bytes": len(data), "output_sha256": ROM.sha256(data),
                           "expected_sha256": ROM.sha256(expected), "all_2048_bytes_match": True})
        (out/(name+".sav")).write_bytes(data)
        return data
    try:
        run("analyze-exact-production-vhdl", [ghdl, "-a", *flags, *map(str,sources)])
        cold = simulate("cold-ff-blue", bytes([255])*2048, expected_save(1), 0x7C00, 2048, True, True)
        restored = simulate("restore-from-actual-cold-green", cold, expected_save(2), 0x03E0, 2, True)
        simulate("restore-from-actual-second-green", restored, expected_save(3), 0x03E0, 2, True)
        simulate("turbo-cold-blue", bytes([255])*2048, expected_save(1), 0x7C00, 2048, True, True, turbo=True)
        simulate("turbo-restore-green", cold, expected_save(2), 0x03E0, 2, True, turbo=True)
        for counter in (0, 127, 254, 255):
            simulate(f"counter-{counter}-green", expected_save(counter), expected_save((counter+1)&255), 0x03E0, 2, True)
        for offset in (0, 15, 16, 17, 18, 255, 256, 511, 512, 1023, 1024, 2046, 2047):
            damaged = bytearray(cold); damaged[offset] ^= 0x80
            simulate(f"corrupt-{offset:04x}-red-no-write", damaged, damaged, 0x001F, 0, required_read=offset)
        for name, initial in (("zero-filled", bytes(2048)),
                              ("only-last-non-ff", bytes([255])*2047+b"\xFE"),
                              ("torn-first-256", cold[:256]+bytes([255])*1792)):
            simulate(name+"-red-no-write", initial, initial, 0x001F, 0)
        # Negative control: mutate cold-loop CPX #$0800 to #$07FF. The actual CPU
        # now omits $70:07FF; the independent write-count/coverage guard must fail.
        broken = bytearray(rom)
        end = symbols["validate"]-0x8000
        start = symbols["initialize"]-0x8000
        index = broken.index(bytes((0xE0, 0x00, 0x08)), start, end)
        broken[index+1:index+3] = bytes((0xFF, 0x07))
        hex_file(out/"negative-short-copy.hex", broken)
        simulate("negative-short-copy", bytes([255])*2048, None, 0x7C00, 2048,
                 True, True, rom_name="negative-short-copy.hex", negative=True,
                 marker="unexpected SRAM write count")
        # Independent checker verifies bytes exported by actual CPU execution,
        # including the exact count-two SHA, and never modifies the input.
        for name, counter in (("cold-ff-blue",1), ("restore-from-actual-cold-green",2)):
            path = out/(name+".sav"); before = path.read_bytes()
            run(name+"-read-only-checker", ["python3", str(ROOT/"tools/standard_save_testrom.py"),
                 "check-save", str(path), "--expect-counter", str(counter),
                 "--expect-sha256", ROM.sha256(expected_save(counter))], marker='"pattern_verified": true')
            assert path.read_bytes()==before
        summary["passed"] = True
    finally:
        summary.setdefault("passed", False)
        (out/"summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(f"PASS {len(checks)} checks; {out/'summary.json'}")

if __name__ == "__main__":
    main()
