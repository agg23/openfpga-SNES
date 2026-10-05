#!/usr/bin/env python3
"""Exact-source DLH read-helper and guarded DMA-address equivalence checks.

Requires Python 3, GHDL with synthesis support, and Yosys. Default runs work
without Git using hash-checked frozen reference excerpts. --verify-reference-git
also re-extracts and verifies them against the pinned history. Writes generated
models/logs only below --output. No Quartus build or timing claim is made.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = "84d8d5eb6f3e0de2d7f891581e1e922b109fb758"
WRAM_EVIDENCE = "6cccdf26e7bd781364a9c4d3c435a513c3cd4ab2"
CPU_PATH = "rtl/upstream/CPU.vhd"
DLH_PATH = "rtl/upstream/chip/DSP/DSP_LHRomMap.vhd"
HELPER_PATH = "rtl/upstream/chip/DSP/DSP_LHReadSelect.vhd"
REFERENCE = ROOT / "tests/timing/dlh_dma_reference"
DLH_INPUTS = {
    "CA": 24, "MAP_CTRL": 8, "CC_DR": 8, "ROMSEL_N": 1,
    "RAMSEL_N": 1, "BSRAM_MASK": 24, "ROM_MASK": 24, "ROM_Q": 16,
    "DSP_DO": 8, "SRTC_DO": 8, "CC_SR": 8, "BSRAM_Q": 8, "OPENBUS": 8,
}
DLH_OUTPUTS = {
    "CART_ADDR": 24, "BRAM_ADDR": 20, "ROM_SEL": 1, "BSRAM_SEL": 1,
    "NO_BSRAM_SEL": 1, "DP_SEL": 1, "DSP_SEL": 1, "DSP_A0": 1,
    "OBC1_SEL": 1, "SRTC_SEL": 1, "CC_SEL": 1, "DO": 8,
}


def git_source(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT, text=True)


def snippet(source, path, start, end=None):
    """Fail closed on ambiguous anchors; preserve the selected source verbatim."""
    matches = list(re.finditer(r"(?<![A-Za-z_0-9])" + re.escape(start), source))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {start!r} in {path}; got {len(matches)}")
    a = matches[0].start()
    b = source.index(end, a) + len(end) if end else source.index(";", a) + 1
    return f"-- Source: {path}\n" + source[a:b] + "\n"


def vtype(width):
    return "std_logic" if width == 1 else f"std_logic_vector({width-1} downto 0)"


def ventity(name, inputs, outputs, body, declarations=""):
    ports = [f" {key} : {mode} {vtype(width)}" for mode, signals in
             (("in", inputs), ("out", outputs)) for key, width in signals.items()]
    return ("library IEEE;\nuse IEEE.std_logic_1164.all;\nuse IEEE.numeric_std.all;\n"
            "use IEEE.std_logic_unsigned.all;\n"
            f"entity {name} is port (\n" + ";\n".join(ports) +
            f"\n); end {name};\narchitecture exact of {name} is\n" + declarations +
            "\nbegin\n" + body + "\nend exact;\n")


def svport(mode, name, width):
    return f" {mode} " + (f"[{width-1}:0] " if width > 1 else "") + name


def dlh_miter():
    ports = [svport("input", k, w) for k, w in DLH_INPUTS.items()]
    ports += [" output equivalent"]
    lines = ["module dlh_miter (\n" + ",\n".join(ports) + "\n);"]
    for prefix, entity in (("ref", "DLHReference"), ("dut", "DSP_LHReadSelect")):
        lines += [svport("wire", prefix + "_" + k, w) + ";" for k, w in DLH_OUTPUTS.items()]
        bindings = [f".{k}({k})" for k in DLH_INPUTS]
        bindings += [f".{k if prefix == 'ref' or k == 'DO' else k + '_O'}({prefix}_{k})"
                     for k in DLH_OUTPUTS]
        lines.append(f"{entity} {prefix} (" + ", ".join(bindings) + ");")
    lines.append("assign equivalent = " + " && ".join(
        f"(ref_{k} == dut_{k})" for k in DLH_OUTPUTS) + ";")
    return "\n".join(lines) + "\nendmodule\n"


def address_model(source, path, name, candidate):
    body = snippet(source, path, "INT_A <=")
    body += snippet(source, path, "process(INT_A)", "end process;")
    body += snippet(source, path, "RAMSEL_N <= INT_RAMSEL_N;")
    body += snippet(source, path, "ROMSEL_N <= INT_ROMSEL_N;")
    outputs = {"CA": 24, "RAMSEL_N": 1, "ROMSEL_N": 1}
    if candidate:
        body += snippet(source, path, "DMA_ACTIVE <=")
        body += snippet(source, path, "DMA_OWNER <=")
        body += snippet(source, path, "process(DMA_A)", "end process;")
        outputs.update({"DMA_CA": 24, "DMA_RAMSEL_N": 1,
                        "DMA_ROMSEL_N": 1, "DMA_OWNER": 1})
    return ventity(name, {"P65_A": 24, "DMA_A": 24, "DMA_RUN": 1, "HDMA_RUN": 1}, outputs,
                   body, " signal INT_A : std_logic_vector(23 downto 0);\n"
                   " signal INT_RAMSEL_N, INT_ROMSEL_N, DMA_ACTIVE : std_logic;\n")


ADDRESS_MITER = """module address_miter (
 input [23:0] P65_A, DMA_A,
 input DMA_RUN, HDMA_RUN,
 output normal_equivalent, owner_equivalent, dma_equivalent,
 output unguarded_safe, corrupt_mirror_safe, owner,
 output [23:0] ref_ca, dut_ca, dma_ca,
 output ref_ram, ref_rom, dut_ram, dut_rom, dma_ram, dma_rom
);
AddressReference ref_model (.P65_A(P65_A), .DMA_A(DMA_A), .DMA_RUN(DMA_RUN),
 .HDMA_RUN(HDMA_RUN), .CA(ref_ca), .RAMSEL_N(ref_ram), .ROMSEL_N(ref_rom));
AddressCandidate dut_model (.P65_A(P65_A), .DMA_A(DMA_A), .DMA_RUN(DMA_RUN),
 .HDMA_RUN(HDMA_RUN), .CA(dut_ca), .RAMSEL_N(dut_ram), .ROMSEL_N(dut_rom),
 .DMA_CA(dma_ca), .DMA_RAMSEL_N(dma_ram), .DMA_ROMSEL_N(dma_rom), .DMA_OWNER(owner));
assign normal_equivalent = {ref_ca, ref_ram, ref_rom} == {dut_ca, dut_ram, dut_rom};
assign owner_equivalent = owner == (DMA_RUN || HDMA_RUN);
assign unguarded_safe = {ref_ca, ref_ram, ref_rom} == {dma_ca, dma_ram, dma_rom};
assign dma_equivalent = !owner || unguarded_safe;
// Test-only lower-bank corruption makes a mirrored DMA address observably wrong.
assign corrupt_mirror_safe = !owner || ref_ca == (dma_ca ^ 24'h010000);
endmodule
"""


def wram_model(sources, candidate=False):
    """Reuse the original extracted selector claim without rerunning M_TAB analysis."""
    body = []
    cpu = sources[CPU_PATH]
    for start, end in (("DMA_ACTIVE <=", None), ("EN <= ENABLE and", None),
                       ("P65_EN <=", None), ("INT_A <=", None),
                       ("process(INT_A)", "end process;"),
                       ("process(P65_A, EN, CPU_RD, CPU_WR, DMA_B,", "end process;")):
        body.append(snippet(cpu, CPU_PATH, start, end))
    snespath = "rtl/upstream/SNES.vhd"
    if candidate:
        body.append(snippet(cpu, CPU_PATH, "DMA_OWNER <="))
        body.append(snippet(cpu, CPU_PATH, "process(DMA_A)", "end process;"))
        for start in ("DMA_BUSA_SEL <=", "DMA_BUSA_DO <="):
            body.append(snippet(sources[snespath], snespath, start))
        # Fail closed if the real instance no longer matches these aliases.
        cpu_map = snippet(sources[snespath], snespath, "CPU : entity work.SCPU", ");")
        for formal, actual in (("CA", "INT_CA"), ("DMA_CA", "INT_DMA_CA"),
                               ("DMA_OWNER", "DMA_OWNER"), ("PARD_N", "INT_PARD_N"),
                               ("CPUWR_N", "INT_CPUWR_N"), ("RAMSEL_N", "INT_RAMSEL_N")):
            if not re.search(r"\b" + formal + r"\s*=>\s*" + actual + r"\s*,", cpu_map):
                raise RuntimeError(f"SCPU binding changed: {formal} => {actual}")
    for start in ("BUSA_SEL <=", "BUSA_DO <=", "WRAM_DI <="):
        body.append(snippet(sources[snespath], snespath, start))
    body.append("swrampart: block is\n alias DI : std_logic_vector(7 downto 0) is WRAM_DI;\nbegin\n")
    swram = "rtl/upstream/SWRAM.vhd"
    for start in ("RAM_D <=", "RAM_CE_N <=", "RAM_WE_N <="):
        body.append(snippet(sources[swram], swram, start))
    body.append("end block;")
    inputs = {"P65_A": 24, "DMA_A": 24, "DMA_B": 8,
              **{k: 1 for k in ("ENABLE REFRESHED DMA_RUN HDMA_RUN CPU_RD CPU_WR "
                               "DMA_TRANSFER HDMA_BUS_ACTIVE DMA_B_RD DMA_B_WR DMA_A_RD DMA_A_WR "
                               "HDMA_A_RD HDMA_A_WR HDMA_B_RD HDMA_B_WR").split()},
              "DI": 8, "BUSB_DO": 8, "CPU_DO": 8}
    outputs = {"CA": 24, "PA": 8, "PARD_N": 1, "PAWR_N": 1, "WRAM_DI": 8, "RAM_D": 8,
               "RAM_CE_N": 1, "RAM_WE_N": 1, "DMA_ACTIVE": 1, "BUSA_SEL": 1}
    declarations = """ signal INT_A : std_logic_vector(23 downto 0);
 signal INT_RAMSEL_N, INT_ROMSEL_N, INT_CPUWR_N, INT_CPURD_N : std_logic;
 signal EN, P65_EN : std_logic;
 signal BUSA_DO : std_logic_vector(7 downto 0);
 alias INT_CA : std_logic_vector(23 downto 0) is CA;
 alias INT_PARD_N : std_logic is PARD_N;
 alias CPUWR_N : std_logic is INT_CPUWR_N;
 alias RAMSEL_N : std_logic is INT_RAMSEL_N;
"""
    if candidate:
        inputs["DMA_DI"] = 8
        declarations += """ signal DMA_CA : std_logic_vector(23 downto 0);
 alias INT_DMA_CA : std_logic_vector(23 downto 0) is DMA_CA;
 signal DMA_OWNER, DMA_RAMSEL_N, DMA_ROMSEL_N, DMA_BUSA_SEL : std_logic;
 signal DMA_BUSA_DO : std_logic_vector(7 downto 0);
"""
    return ventity("SelectorCandidate" if candidate else "SelectorModel", inputs, outputs,
                   "\n".join(body), declarations)


def main_mux_model(source, name):
    """Wrap the full real combinational output mux, including non-read outputs.

    Only declarations are synthesized here: statements and ordering are verbatim.
    Reject unknown tokens/declarations rather than silently omitting dependencies.
    """
    anchor = "always @(*) begin\n\tcase (MAP_ACTIVE)"
    if source.count(anchor) != 1:
        raise RuntimeError("main.v MAP_ACTIVE block anchor changed")
    body = source[source.index(anchor):source.rindex("endmodule")].strip()
    clean = re.sub(r"//[^\n]*|/\*.*?\*/", "", body, flags=re.S)
    if len(re.findall(r"\balways\b", clean)) != 1:
        raise RuntimeError("main.v extraction includes unexpected additional always block")
    without_literals = re.sub(r"(?:\d+)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+", "", clean)
    tokens = set(re.findall(r"\b[A-Za-z_]\w*\b", without_literals))
    tokens -= set("always begin end case endcase default if else".split())
    outputs = set(re.findall(r"\b(\w+)\s*=(?!=)", clean))
    inputs = tokens - outputs
    widths = {}
    declarations = re.sub(r"//[^\n]*|/\*.*?\*/", "", source, flags=re.S)
    for match in re.finditer(r"\b(?:input|output|inout|wire|reg)\s+(?:(?:reg|wire)\s+)?"
                             r"(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*)?(\w+)", declarations):
        hi, lo, key = match.groups()
        width = int(hi) - int(lo) + 1 if hi is not None else 1
        if key in widths and widths[key] != width:
            raise RuntimeError(f"Ambiguous width in main.v: {key}")
        widths[key] = width
    missing = tokens - set(widths)
    if missing:
        raise RuntimeError(f"Undeclared main.v extraction signals: {sorted(missing)}")
    inports = {key: widths[key] for key in sorted(inputs)}
    outports = {key: widths[key] for key in sorted(outputs)}
    header = ",\n".join([svport("input", k, w) for k, w in inports.items()] +
                         [svport("output reg", k, w) for k, w in outports.items()])
    return f"module {name} (\n{header}\n);\n{body}\nendmodule\n", inports, outports


def main_mux_miter(inputs, outputs):
    ports = [svport("input", k, w) for k, w in inputs.items()]
    ports += [" output payload_equal, normal_equivalent, dma_equivalent, ss_priority, msu_priority"]
    lines = ["module main_mux_miter (\n" + ",\n".join(ports) + "\n);"]
    for prefix, entity in (("ref", "MainMuxReference"), ("dut", "MainMuxCandidate")):
        ins = [k for k in inputs if prefix == "dut" or k != "DLH_DMA_DO"]
        outs = [k for k in outputs if prefix == "dut" or k != "DMA_DI"]
        lines += [svport("wire", prefix + "_" + k, outputs[k]) + ";" for k in outs]
        bindings = [f".{k}({k})" for k in ins] + [f".{k}({prefix}_{k})" for k in outs]
        lines.append(f"{entity} {prefix} (" + ", ".join(bindings) + ");")
    lines.append("assign payload_equal = DLH_DMA_DO == DLH_DO;")
    lines.append("assign normal_equivalent = " + " && ".join(
        f"ref_{k} == dut_{k}" for k in outputs if k != "DMA_DI") + ";")
    lines.append("assign dma_equivalent = dut_DMA_DI == dut_DI;")
    lines.append("assign ss_priority = !SS_DO_OVR || (dut_DI == SS_DO && dut_DMA_DI == SS_DO);")
    lines.append("assign msu_priority = SS_DO_OVR || !MSU_SEL || (dut_DI == MSU_DO && dut_DMA_DI == MSU_DO);")
    return "\n".join(lines) + "\nendmodule\n"


def wram_composition_miter():
    inputs = {"P65_A": 24, "DMA_A": 24, "DMA_B": 8,
              **{k: 1 for k in ("ENABLE REFRESHED DMA_RUN HDMA_RUN CPU_RD CPU_WR "
                               "DMA_TRANSFER HDMA_BUS_ACTIVE DMA_B_RD DMA_B_WR DMA_A_RD DMA_A_WR "
                               "HDMA_A_RD HDMA_A_WR HDMA_B_RD HDMA_B_WR").split()},
              "DI": 8, "DMA_DI": 8, "BUSB_DO": 8, "CPU_DO": 8}
    outputs = {"CA": 24, "PA": 8, "PARD_N": 1, "PAWR_N": 1, "WRAM_DI": 8, "RAM_D": 8,
               "RAM_CE_N": 1, "RAM_WE_N": 1, "DMA_ACTIVE": 1, "BUSA_SEL": 1}
    ports = [svport("input", k, w) for k, w in inputs.items()]
    ports += ["output guards, payload_equal, controls_equal, observed_write, wram_equal, ram_equal"]
    lines = ["module wram_composition_miter (\n" + ",\n".join(ports) + "\n);"]
    for prefix, entity in (("ref", "SelectorModel"), ("dut", "SelectorCandidate")):
        lines += [svport("wire", prefix + "_" + k, w) + ";" for k, w in outputs.items()]
        bindings = [f".{k}({k})" for k in inputs if prefix == "dut" or k != "DMA_DI"]
        bindings += [f".{k}({prefix}_{k})" for k in outputs]
        lines.append(f"{entity} {prefix} (" + ", ".join(bindings) + ");")
    lines += [
        "assign guards = !(CPU_RD && CPU_WR) && (!DMA_TRANSFER || DMA_RUN) && (!HDMA_BUS_ACTIVE || HDMA_RUN);",
        "assign payload_equal = !dut_DMA_ACTIVE || DMA_DI == DI;",
        "assign controls_equal = " + " && ".join(f"ref_{k} == dut_{k}" for k in outputs
                                                 if k not in ("RAM_D", "WRAM_DI")) + ";",
        "wire ram_write = !ref_RAM_CE_N && !ref_RAM_WE_N;",
        "wire wmadd_write = ENABLE && !ref_PAWR_N && (ref_PA == 8'h81 || ref_PA == 8'h82 || ref_PA == 8'h83);",
        "assign observed_write = ram_write || wmadd_write;",
        "assign wram_equal = !observed_write || ref_WRAM_DI == dut_WRAM_DI;",
        "assign ram_equal = !ram_write || ref_RAM_D == dut_RAM_D;",
    ]
    return "\n".join(lines) + "\nendmodule\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="build/dlh-dma-equivalence")
    parser.add_argument("--verify-reference-git", action="store_true",
                        help="re-extract frozen models from pinned Git history and require byte equality")
    args = parser.parse_args()
    for tool in (("git", "ghdl", "yosys") if args.verify_reference_git else ("ghdl", "yosys")):
        if not shutil.which(tool):
            parser.error(f"{tool} is required on PATH")
    out = (ROOT / args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((REFERENCE / "provenance.json").read_text())
    if provenance["baseline"] != BASE or provenance["wram_evidence"] != WRAM_EVIDENCE:
        raise RuntimeError("Frozen-reference revision mismatch")
    frozen = {}
    for name, expected in provenance["snapshot_sha256"].items():
        data = (REFERENCE / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Frozen-reference hash mismatch: {name}")
        frozen[name] = data.decode()
    hashes = dict(provenance["source_sha256"])
    if args.verify_reference_git:
        refs = {path: git_source(BASE, path) for path in
                (DLH_PATH, CPU_PATH, "rtl/upstream/SNES.vhd", "rtl/upstream/SWRAM.vhd", "rtl/upstream/main.v")}
        for path, src in refs.items():
            if hashlib.sha256(src.encode()).hexdigest() != hashes[f"{BASE}:{path}"]:
                raise RuntimeError(f"Original-source hash mismatch: {path}")
        body = snippet(refs[DLH_PATH], DLH_PATH,
                       "process( CA, MAP_CTRL, CC_DR, ROMSEL_N, RAMSEL_N, BSRAM_MASK, ROM_MASK )",
                       "end process;")
        body += snippet(refs[DLH_PATH], DLH_PATH, "ROM_SEL <=")
        body += snippet(refs[DLH_PATH], DLH_PATH, "DO <= ROM_Q")
        originals = {
            "dlh_reference.vhd": ventity("DLHReference", DLH_INPUTS, DLH_OUTPUTS, body),
            "address_reference.vhd": address_model(refs[CPU_PATH], CPU_PATH, "AddressReference", False),
            "selector_model.vhd": wram_model(refs),
            "selector_miter.sv": git_source(WRAM_EVIDENCE, "tests/timing/p65_wram_selector_miter.sv"),
            "main_mux_reference.sv": main_mux_model(refs["rtl/upstream/main.v"], "MainMuxReference")[0],
        }
        for name, src in originals.items():
            if src != frozen[name]:
                raise RuntimeError(f"Frozen source differs from original Git extraction: {name}")
        print("PASS frozen references match pinned Git extraction", flush=True)
    candidate_cpu = (ROOT / CPU_PATH).read_text()
    candidate_helper = (ROOT / HELPER_PATH).read_text()
    for path, src in ((CPU_PATH, candidate_cpu), (HELPER_PATH, candidate_helper)):
        hashes[f"working-tree:{path}"] = hashlib.sha256(src.encode()).hexdigest()
    current = {path: (ROOT / path).read_text() for path in
               (CPU_PATH, "rtl/upstream/SNES.vhd", "rtl/upstream/SWRAM.vhd", "rtl/upstream/main.v")}
    for path, src in current.items():
        hashes[f"working-tree:{path}"] = hashlib.sha256(src.encode()).hexdigest()
    main_candidate, main_inputs, main_outputs = main_mux_model(current["rtl/upstream/main.v"], "MainMuxCandidate")
    _, reference_inputs, reference_outputs = main_mux_model(frozen["main_mux_reference.sv"], "MainMuxReference")
    if {k: w for k, w in main_inputs.items() if k != "DLH_DMA_DO"} != reference_inputs:
        raise RuntimeError("main.v extracted input interface changed beyond DLH_DMA_DO")
    if {k: w for k, w in main_outputs.items() if k != "DMA_DI"} != reference_outputs:
        raise RuntimeError("main.v extracted output interface changed beyond DMA_DI")
    models = dict(frozen)
    models.update({
        "DSP_LHReadSelect.vhd": candidate_helper,
        "address_candidate.vhd": address_model(candidate_cpu, CPU_PATH, "AddressCandidate", True),
        "selector_candidate.vhd": wram_model(current, True),
        "main_mux_candidate.sv": main_candidate,
    })
    # Mutate test copies of actual source, never repository RTL. Both variants
    # retain every unchanged decoder branch and are checked by the same miter.
    mutations = {
        "dlh_bad_data.vhd": ("DO <= ROM_Q(7 downto 0)", "DO <= ROM_Q(15 downto 8)"),
        "dlh_bad_address.vhd": ("'0' & not CA(23) & CA(22 downto 16)",
                                "'0' & CA(23) & CA(22 downto 16)"),
    }
    for filename, (old, new) in mutations.items():
        if candidate_helper.count(old) != 1:
            raise RuntimeError(f"Negative-control source anchor changed: {old}")
        models[filename] = candidate_helper.replace(old, new)
    for filename, src in models.items():
        (out / filename).write_text(src)
    (out / "dlh_miter.sv").write_text(dlh_miter())
    (out / "address_miter.sv").write_text(ADDRESS_MITER)
    (out / "main_mux_miter.sv").write_text(main_mux_miter(main_inputs, main_outputs))
    (out / "wram_composition_miter.sv").write_text(wram_composition_miter())
    (out / "source_hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")

    def synth(filename, entity, output_name=None):
        output_name = output_name or entity
        result = subprocess.run(["ghdl", "--synth", "--std=08", "-fsynopsys", "--out=verilog",
                                 filename, "-e", entity], cwd=out, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (out / (output_name + "-ghdl.log")).write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f"GHDL failed; see {out / (output_name + '-ghdl.log')}")
        (out / (output_name + ".v")).write_text(result.stdout)
        return output_name + ".v"

    dlh_files = [synth("dlh_reference.vhd", "DLHReference"),
                 synth("DSP_LHReadSelect.vhd", "DSP_LHReadSelect"), "dlh_miter.sv"]
    address_files = [synth("address_reference.vhd", "AddressReference"),
                     synth("address_candidate.vhd", "AddressCandidate"), "address_miter.sv"]
    wram_files = [synth("selector_model.vhd", "SelectorModel"), "selector_miter.sv"]
    composition_files = [wram_files[0], synth("selector_candidate.vhd", "SelectorCandidate"),
                         "wram_composition_miter.sv"]
    main_files = ["main_mux_reference.sv", "main_mux_candidate.sv", "main_mux_miter.sv"]
    outcomes = {}

    def check(name, files, top, command, positive=True):
        script = ("read_verilog -sv " + " ".join(files) + "\n" +
                  f"prep -top {top} -flatten\n" + command + "\n")
        (out / (name + ".ys")).write_text(script)
        result = subprocess.run(["yosys", "-Q", "-s", name + ".ys"], cwd=out, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / (name + ".log")).write_text(result.stdout)
        expected = ("SAT proof finished - no model found: SUCCESS!" if positive else
                    "SAT proof finished - model found: FAIL!")
        if result.returncode or expected not in result.stdout:
            raise RuntimeError(f"Unexpected SAT result; see {out / (name + '.log')}")
        outcomes[name] = "proved" if positive else "counterexample found as required"
        print(f"PASS {name}: {outcomes[name]}", flush=True)

    check("dlh-all-outputs", dlh_files, "dlh_miter", "sat -prove equivalent 1 -verify")
    for name, filename in (("dlh-data-corruption", "dlh_bad_data.vhd"),
                           ("dlh-address-corruption", "dlh_bad_address.vhd")):
        corrupted = synth(filename, "DSP_LHReadSelect", name)
        check(name, [dlh_files[0], corrupted, "dlh_miter.sv"], "dlh_miter",
              "sat -prove equivalent 1 -falsify -show-inputs -show-outputs", False)
    check("dma-guarded-address", address_files, "address_miter",
          "sat -prove normal_equivalent 1 -prove owner_equivalent 1 -prove dma_equivalent 1 -verify")
    check("dma-unguarded-counterexample", address_files, "address_miter",
          "sat -set DMA_RUN 0 -set HDMA_RUN 0 -prove unguarded_safe 1 -falsify -show-inputs -show-outputs", False)
    check("dma-mirror-corruption", address_files, "address_miter",
          "sat -set DMA_RUN 1 -set HDMA_RUN 0 -set DMA_A 0 "
          "-prove corrupt_mirror_safe 1 -falsify -show-inputs -show-outputs", False)
    check("wram-reused-guarded-selector", wram_files, "miter",
          "sat -set assumptions 1 -prove equivalent 1 -prove cpu_payload_independent 1 "
          "-prove read_bus_write_needs_dma 1 -verify")
    check("wram-reused-dma-counterexample", wram_files, "miter",
          "sat -set assumptions 1 -set enable 1 -set refreshed 0 -set dma_run 1 "
          "-set hdma_run 0 -set dma_transfer 1 -set hdma_bus_active 0 "
          "-set dma_a 32768 -set dma_b 128 -set dma_a_rd 1 -set dma_a_wr 0 "
          "-set dma_b_rd 0 -set dma_b_wr 1 -set di 165 -set cpu_do 90 -set observed_write 1 "
          "-prove always_cpu_safe 1 -falsify -show-inputs -show-outputs", False)
    check("wram-reused-unguarded-counterexample", wram_files, "miter",
          "sat -prove equivalent 1 -falsify -show-inputs -show-outputs", False)
    check("main-normal-mux", main_files, "main_mux_miter",
          "sat -prove normal_equivalent 1 -prove ss_priority 1 -prove msu_priority 1 -verify")
    check("main-dma-mux", main_files, "main_mux_miter",
          "sat -set payload_equal 1 -prove dma_equivalent 1 -verify")
    check("main-unguarded-counterexample", main_files, "main_mux_miter",
          "sat -prove dma_equivalent 1 -falsify -show-inputs -show-outputs", False)
    check("wram-current-controls", composition_files, "wram_composition_miter",
          "sat -prove controls_equal 1 -verify")
    check("wram-current-guarded-composition", composition_files, "wram_composition_miter",
          "sat -set guards 1 -set payload_equal 1 -prove wram_equal 1 -prove ram_equal 1 -verify")
    check("wram-current-unguarded-counterexample", composition_files, "wram_composition_miter",
          "sat -set payload_equal 1 -prove wram_equal 1 -falsify -show-inputs -show-outputs", False)
    check("wram-current-payload-counterexample", composition_files, "wram_composition_miter",
          "sat -set guards 1 -prove wram_equal 1 -falsify -show-inputs -show-outputs", False)
    summary = {
        "scope": "two-state settled combinational equivalence/observational claims only",
        "baseline": BASE, "reused_wram_evidence": WRAM_EVIDENCE,
        "frozen_references_verified_against_git": args.verify_reference_git,
        "dlh_unconstrained_input_bits": sum(DLH_INPUTS.values()),
        "dlh_compared_output_bits": sum(DLH_OUTPUTS.values()),
        "dlh_outputs": list(DLH_OUTPUTS),
        "dma_guard": "DMA_OWNER = DMA_RUN or HDMA_RUN",
        "main_normal_outputs": reference_outputs,
        "main_map_active_patterns": 128,
        "composition_payload_guards": ["DLH_DMA_DO = DLH_DO for main mux equality",
                                       "DMA_DI = DI when DMA_OWNER for WRAM write equivalence"],
        "wram_assumptions": ["not (CPU_RD and CPU_WR)", "DMA_TRANSFER implies DMA_RUN",
                             "HDMA_BUS_ACTIVE implies HDMA_RUN"],
        "not_proved": ["sequential reachability or lifecycle invariants", "subcycle/glitch/capture safety",
                       "whole-core integration equivalence", "hardware behavior or timing closure"],
        "checks": outcomes,
        "tools": {tool: subprocess.check_output([tool, flag], text=True).strip()
                  for tool, flag in (("ghdl", "--version"), ("yosys", "-V"))},
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
