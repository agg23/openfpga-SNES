#!/usr/bin/env python3
"""Create NEW local staging for an explicitly reviewed standard-refresh identity.

No install, SD merge, upload, publication or compiler invocation. Real build
reports are consistency evidence, not cryptographic compiler attestation.
"""
from __future__ import annotations

import argparse
import datetime
import importlib.util
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("legacy_msu_packaging", ROOT / "tools/package_msu1.py")
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
PackageError = legacy.PackageError
digest, json_bytes, parse_object = legacy.digest, legacy.json_bytes, legacy.parse_object
REVERSE_BYTE = legacy.REVERSE_BYTE
BASELINE = "982f103a0d7fa39294b760738ceaed5bb88eddad"  # Original template/homebrew anchor.
SOURCE_IDENTITIES = ROOT / "tools/standard_msu1_reviewed_sources.json"
DEFAULT_SOURCE_IDENTITY = "baseline-982f103"
AUTHOR, SHORTNAME = "agg23", "SNES-STD-EXPERIMENT"
CORE = Path("Cores") / f"{AUTHOR}.{SHORTNAME}"
BASENAME = "MSU1-STD-982f103-HOMEBREW"
PROFILES = {
    "msu_standard_ntsc": ("snes_msu_standard_ntsc.rev", "snes_main.rev", "main", 0),
    "msu_standard_pal": ("snes_msu_standard_pal.rev", "snes_pal.rev", "PAL", 2),
    "standard_ntsc_spc": ("snes_standard_spc.rev", "snes_spc.rev", "SPCSDD1", 1),
}
HARDWARE_PATHS = ("rtl", "platform", "target", "projects", "generate.tcl", "tools/build_msu1.sh")
REPORTS = ("quartus-version.log", "compile.log", "snes_pocket.map.rpt",
           "snes_pocket.fit.summary", "snes_pocket.asm.rpt", "snes_pocket.flow.rpt")
FIXTURE_MARKER = b"SYNTHETIC_FIXTURE_ONLY_NOT_FOR_HARDWARE/"
FITTER_REPORT = "snes_pocket.fit.rpt"
FITTER_SETTING_NAMES = ("Fitter Initial Placement Seed", "Fitter Effort",
                        "Optimize Hold Timing", "Optimize Multi-Corner Timing")
# These source commits require the new receipt, even when read_build is called
# directly. Removing the policy from the catalog cannot downgrade their schema.
FITTER_RECEIPT_SOURCE_IDENTITIES = {
    "e71101fd06a452da53cb0924e1d3701f53133435": "candidate-e71101f",
}
# Sanity envelope only, NOT FPGA format validation or compiler authentication.
# Actual historical standard images differ in length (NTSC 2139948, SPC 1919252).
MIN_REAL_RBF_BYTES, MAX_REAL_RBF_BYTES = 1_000_000, 8 * 1024 * 1024
WARNING = (
    "EXPERIMENTAL STANDARD-REFRESH STAGING ONLY. NOT A RELEASE. "
    "Timing, loadability and hardware operation are NOT certified by this tool. "
    "Use only a blank/spare SD and original homebrew. Core renaming does NOT "
    "isolate Saves/snes/common; back up all original saves and the entire SD."
)


def safe_path(path: Path) -> Path:
    """Reject symlinks in every existing path component, including parents."""
    path = Path(path).absolute()
    if ".." in path.parts:
        raise PackageError(f"parent traversal is not accepted: {path}")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise PackageError(f"symlink is not accepted: {part}")
    return path


def read_file(path: Path, *, allow_empty: bool = False) -> bytes:
    path = safe_path(path)
    try:
        mode = path.stat().st_mode
    except FileNotFoundError as error:
        raise PackageError(f"required regular file is missing: {path}") from error
    if not stat.S_ISREG(mode):
        raise PackageError(f"required regular file is missing: {path}")
    data = path.read_bytes()
    if not data and not allow_empty:
        raise PackageError(f"required file is empty: {path}")
    return data


def reviewed_source(identity: str) -> tuple[dict, bytes]:
    """Only committed, named identities; there is no CLI baseline/hash override."""
    raw = read_file(SOURCE_IDENTITIES)
    configuration = parse_object(raw, str(SOURCE_IDENTITIES))
    if configuration.get("format") != "pocket-standard-reviewed-source-identities-v1":
        raise PackageError("unsupported reviewed-source identity configuration")
    identities = configuration.get("identities")
    if not isinstance(identities, dict) or identity not in identities:
        raise PackageError(f"unknown reviewed source identity: {identity}")
    record = identities[identity]
    required = {"build_source_commit", "hardware_commit", "hardware_inputs_sha256",
                "core_version", "homebrew_basename", "qualification_state"}
    if not isinstance(record, dict) or set(record) not in (required, required | {"expected_fitter_settings"}):
        raise PackageError("incomplete reviewed-source identity record")
    for key in ("build_source_commit", "hardware_commit"):
        if not re.fullmatch(r"[0-9a-f]{40}", str(record.get(key, ""))):
            raise PackageError(f"reviewed source identity requires full {key}")
    if not re.fullmatch(r"[0-9a-f]{64}", str(record.get("hardware_inputs_sha256", ""))):
        raise PackageError("reviewed source identity requires hardware SHA-256")
    if (not isinstance(record["core_version"], str) or not 1 <= len(record["core_version"]) <= 31
            or record["qualification_state"] != "unverified_candidate"
            or not isinstance(record["homebrew_basename"], str)):
        raise PackageError("invalid reviewed-source metadata or qualification state")
    needs_receipt = record["build_source_commit"] in FITTER_RECEIPT_SOURCE_IDENTITIES
    if ("expected_fitter_settings" in record) != needs_receipt:
        raise PackageError("reviewed source requires its source-specific fitter receipt policy")
    if needs_receipt:
        policy = record["expected_fitter_settings"]
        if not isinstance(policy, dict) or set(policy) != set(PROFILES):
            raise PackageError("fitter policy requires all three exact profiles")
        for profile, settings in policy.items():
            if (not isinstance(settings, dict) or set(settings) != set(FITTER_SETTING_NAMES)
                    or not all(isinstance(value, str) for value in settings.values())
                    or settings["Fitter Initial Placement Seed"] != ("2" if profile == "msu_standard_pal" else "1")
                    or settings["Fitter Effort"] != ("Standard Fit" if profile == "msu_standard_pal" else "Auto Fit")
                    or settings["Optimize Hold Timing"] != "All Paths"
                    or settings["Optimize Multi-Corner Timing"] != "On"):
                raise PackageError(f"invalid source/profile fitter policy or weakened hold/multicorner controls: {profile}")
    return record, raw


def git(repository: Path, *args: str) -> bytes:
    safe_path(repository)
    result = subprocess.run(["git", "-C", str(repository), *args], capture_output=True)
    if result.returncode:
        raise PackageError("source Git evidence unavailable: " + result.stderr.decode(errors="replace").strip())
    return result.stdout


def git_files(repository: Path, commit: str, paths: tuple[str, ...]) -> dict[str, bytes]:
    """Read immutable committed blobs, never a potentially generated live QSF."""
    if git(repository, "cat-file", "-t", commit).strip() != b"commit":
        raise PackageError("source Git evidence must identify a commit, not a tree/tag/blob")
    rows = git(repository, "ls-tree", "-rz", commit, "--", *paths).split(b"\0")
    records = []
    for row in rows:
        if not row:
            continue
        header, name = row.split(b"\t", 1)
        mode, kind, oid = header.split()
        if mode not in (b"100644", b"100755") or kind != b"blob":
            raise PackageError(f"source must contain regular Git blobs, not symlinks/submodules: {name!r}")
        records.append((name.decode(), oid))
    if not records:
        raise PackageError("source Git evidence contains no expected files")
    result = subprocess.run(["git", "-C", str(repository), "cat-file", "--batch"],
                            input=b"\n".join(oid for _, oid in records) + b"\n", capture_output=True)
    if result.returncode:
        raise PackageError("cannot read source Git blobs")
    output, offset, files = result.stdout, 0, {}
    for name, oid in records:
        end = output.index(b"\n", offset)
        actual, kind, count = output[offset:end].split()
        if actual != oid or kind != b"blob":
            raise PackageError("unexpected Git blob response")
        size = int(count)
        files[name] = output[end + 1:end + 1 + size]
        offset = end + size + 2
    return files


def inventory(files: dict[str, bytes]) -> dict:
    return {name: {"bytes": len(data), "sha256": digest(data)} for name, data in sorted(files.items())}


def parameter_section(report: str, entity: str) -> dict[str, str]:
    heading = f"; Parameter Settings for User Entity Instance: {entity} ;"
    matches = [index for index, line in enumerate(report.splitlines()) if line.strip() == heading]
    if len(matches) != 1:
        raise PackageError(f"map report missing or duplicate parameter section: {entity}")
    values = {}
    for line in report.splitlines()[matches[0] + 1:]:
        if line.startswith("Note:") or "Parameter Settings for User Entity Instance:" in line:
            break
        columns = [item.strip() for item in line.split(";")]
        if len(columns) >= 4 and columns[1] not in ("", "Parameter Name"):
            if columns[1] in values:
                raise PackageError("duplicate map parameter")
            values[columns[1]] = columns[2].lstrip("'")
    return values


def verify_reports(directory: Path, profile: str) -> dict[str, bytes]:
    files = {name: read_file(directory / name) for name in REPORTS}
    for name, data in files.items():
        if re.search(rb"SYNTHETIC|TEST DOUBLE|NO_COMPILER|FAKE_FLOW", data, re.I):
            raise PackageError(f"synthetic/forged compiler evidence refused: {name}")
    texts = {name: data.decode() for name, data in files.items()}
    verify_report_texts(texts, profile)
    return files


def verify_report_texts(texts: dict[str, str], profile: str) -> None:
    """Check report semantics; verify_reports also enforces real-input markers."""
    version = texts["quartus-version.log"]
    if not re.search(r"Version 21\.1(?:\.\d+)? Build \d+ .*Lite Edition", version):
        raise PackageError("a real supported Quartus 21.1 Lite version log is required")
    for name, stage in (("snes_pocket.asm.rpt", "Assembler"), ("snes_pocket.flow.rpt", "Flow")):
        if not re.search(rf"; {stage} Status\s*; Successful -", texts[name]):
            raise PackageError(f"{name}: successful {stage} status missing")
        if not re.search(r"; Device\s*; 5CEBA4F23C8\s*;", texts[name]):
            raise PackageError(f"{name}: target device mismatch")
    if not re.search(r"^Fitter Status : Successful -", texts["snes_pocket.fit.summary"], re.M):
        raise PackageError("fitter success missing")
    if not re.search(r"^Device : 5CEBA4F23C8$", texts["snes_pocket.fit.summary"], re.M):
        raise PackageError("fitter target device mismatch")
    if "Quartus Prime Assembler was successful. 0 errors" not in texts["compile.log"]:
        raise PackageError("compile log lacks successful assembler")
    top = parameter_section(texts["snes_pocket.map.rpt"], "core_top:ic")
    main = parameter_section(texts["snes_pocket.map.rpt"], "core_top:ic|MAIN_SNES:snes")
    msu, pal = int(profile != "standard_ntsc_spc"), int(profile == "msu_standard_pal")
    expected_top = {"USE_STANDARD_SDRAM": 1, "USE_MSU_POCKET": msu, "PAL_PLL": pal}
    expected_main = {"USE_STANDARD_SDRAM": 1, "USE_MSU": msu,
                     **{name: msu for name in ("USE_CX4", "USE_GSU", "USE_SA1", "USE_DSPn")},
                     **{name: 1 - msu for name in ("USE_SDD1", "USE_SPC7110", "USE_BSX")}}
    for actual, expected in ((top, expected_top), (main, expected_main)):
        for key, value in expected.items():
            if actual.get(key) != str(value):
                raise PackageError(f"{profile}: map profile parameter mismatch: {key}")


def fitter_report_section(report: str, title: str) -> str:
    report = report.replace("\r\n", "\n")
    headings = list(re.finditer(r"^;[ \t]*" + re.escape(title) + r"[ \t]*;[ \t]*$", report, re.M))
    if len(headings) != 1:
        raise PackageError(f"full fitter report requires one section: {title}")
    remaining = report[headings[0].end():]
    next_heading = re.search(r"^;[ \t]*[^;\r\n]+[ \t]*;[ \t]*$", remaining, re.M)
    return remaining[:next_heading.start()] if next_heading else remaining


def fitter_setting_rows(report: str) -> dict[str, str]:
    """Read actual Setting column, rejecting missing/duplicate rows, even equal."""
    report = fitter_report_section(report, "Fitter Settings")
    settings = {}
    for name in FITTER_SETTING_NAMES:
        matches = re.findall(r"^;[ \t]*" + re.escape(name) + r"[ \t]*;[ \t]*([^;\r\n]+);", report, re.M)
        if len(matches) != 1:
            raise PackageError(f"full fitter report requires one unambiguous setting row: {name}")
        settings[name] = matches[0].strip()
    return settings


def verify_fitter_receipt(directory: Path, manifest: dict, profile: str,
                          expected: dict[str, str], *, fixture: bool) -> tuple[bytes, dict]:
    """Bind the build wrapper receipt and declared settings to the full report."""
    receipt = manifest.get("fitter_settings_report")
    if (not isinstance(receipt, dict) or set(receipt) != {"file", "bytes", "sha256"}
            or receipt.get("file") != FITTER_REPORT):
        raise PackageError("required fitter_settings_report must name the adjacent snes_pocket.fit.rpt")
    data = read_file(directory / FITTER_REPORT)
    if type(receipt.get("bytes")) is not int or receipt["bytes"] != len(data):
        raise PackageError("full fitter report size mismatch")
    if receipt.get("sha256") != digest(data):
        raise PackageError("full fitter report SHA-256 mismatch")
    marker = FIXTURE_MARKER + b"fitter-settings/" + profile.encode() + b"/\n"
    if fixture:
        if not data.startswith(marker):
            raise PackageError("synthetic fitter report must retain its explicit profile marker")
    elif re.search(rb"SYNTHETIC|TEST DOUBLE|NO_COMPILER|FAKE_FLOW", data, re.I):
        raise PackageError("synthetic/forged full fitter report refused")
    # Quartus full reports contain legacy-encoded degree symbols. Hash/copy
    # exact bytes; replace only undecodable display characters for ASCII parsing.
    text = data.decode(errors="replace").replace("\r\n", "\n")
    if len(re.findall(r"^Fitter report for snes_pocket$", text, re.M)) != 1:
        raise PackageError("required full fitter report header missing or duplicated")
    summary = fitter_report_section(text, "Fitter Summary")
    statuses = re.findall(r"^;[ \t]*Fitter Status[ \t]*;[ \t]*([^;\r\n]+);", summary, re.M)
    if len(statuses) != 1 or not statuses[0].strip().startswith("Successful -"):
        raise PackageError("full fitter report must record one successful fitting status")
    for key, value in (("Device", "5CEBA4F23C8"), ("Revision Name", "snes_pocket"),
                       ("Top-level Entity Name", "apf_top")):
        values = re.findall(r"^;[ \t]*" + re.escape(key) + r"[ \t]*;[ \t]*([^;\r\n]+);", summary, re.M)
        if len(values) != 1 or values[0].strip() != value:
            raise PackageError(f"full fitter report identity mismatch: {key}")
    actual = fitter_setting_rows(text)
    declared = manifest.get("actual_fitter_settings")
    if (not isinstance(declared, dict) or set(declared) != set(FITTER_SETTING_NAMES)
            or not all(isinstance(value, str) for value in declared.values())):
        raise PackageError("actual_fitter_settings must record all four exact string settings")
    if declared != actual:
        raise PackageError("actual_fitter_settings disagrees with full fitter report")
    if actual != expected:
        differences = ", ".join(key for key in FITTER_SETTING_NAMES if actual.get(key) != expected.get(key))
        raise PackageError(f"{profile}: full fitter settings violate reviewed source policy: {differences}")
    return data, actual


def read_build(path: Path, profile: str, *, synthetic_fixture_only: bool = False) -> dict:
    if path.name != "build.json":
        raise PackageError("pass the completed run's build.json")
    raw = read_file(path)
    manifest = parse_object(raw, str(path))
    fixture = manifest.get("test_fixture", False)
    if type(fixture) is not bool:
        raise PackageError("test_fixture must be boolean")
    if fixture and not synthetic_fixture_only:
        raise PackageError("synthetic fixture refused; CLI accepts real builds only")
    expected_state = "synthetic_fixture_only" if fixture else "bitstream_generated_unverified"
    if manifest.get("state") != expected_state:
        raise PackageError(f"{profile}: incorrect or incomplete build state")
    if manifest.get("profile") != profile or manifest.get("device") != "5CEBA4F23C8":
        raise PackageError(f"{profile}: profile/device mismatch")
    if type(manifest.get("compile_exit_code")) is not int or manifest["compile_exit_code"] != 0:
        raise PackageError("compile_exit_code must be integer zero")
    if not re.fullmatch(r"[0-9a-f]{40}", str(manifest.get("source_commit", ""))):
        raise PackageError("full lowercase source_commit is required")
    if manifest.get("source_status") != "":
        raise PackageError("source_status must record a clean source checkout")
    for name in ("timing_verified", "hardware_verified"):
        if type(manifest.get(name)) is not bool:
            raise PackageError(f"{name} must be an explicit boolean")
    source, destination, _, _ = PROFILES[profile]
    if not isinstance(manifest.get("outputs"), dict) or set(manifest["outputs"]) != {"snes_pocket.rbf", source}:
        raise PackageError(f"{profile}: exact RBF/REV output set required")
    outputs = {}
    for name in ("snes_pocket.rbf", source):
        data = read_file(path.parent / name)
        record = manifest["outputs"][name]
        if not isinstance(record, dict) or type(record.get("bytes")) is not int or record["bytes"] != len(data):
            raise PackageError(f"size mismatch: {name}")
        if record.get("sha256") != digest(data):
            raise PackageError(f"SHA-256 mismatch: {name}")
        outputs[name] = data
    rbf, rev = outputs["snes_pocket.rbf"], outputs[source]
    if rbf.translate(REVERSE_BYTE) != rev:
        raise PackageError(f"{profile}: REV is not bytewise bit reversal of RBF")
    if fixture:
        if manifest.get("quartus_sh") != "SYNTHETIC_FIXTURE_ONLY" or not rbf.startswith(FIXTURE_MARKER + profile.encode() + b"/"):
            raise PackageError("synthetic fixture must retain its explicit marker/profile")
        reports = {}
    else:
        try:
            started, finished = (datetime.datetime.fromisoformat(manifest[key])
                                 for key in ("started_utc", "finished_utc"))
            if started.utcoffset() != datetime.timedelta(0) or finished.utcoffset() != datetime.timedelta(0) or finished < started:
                raise ValueError("timestamps must be ordered UTC values")
        except (KeyError, TypeError, ValueError) as error:
            raise PackageError("real build requires ordered started_utc/finished_utc timestamps") from error
        if not MIN_REAL_RBF_BYTES <= len(rbf) <= MAX_REAL_RBF_BYTES:
            raise PackageError("unsupported RBF byte count; tiny/forged fixture refused")
        if FIXTURE_MARKER in rbf or re.search(rb"SYNTHETIC|TEST.DOUBLE|NO.COMPILER", raw, re.I):
            raise PackageError("synthetic/forged build evidence refused")
        if not isinstance(manifest.get("quartus_sh"), str) or not manifest["quartus_sh"].endswith("quartus_sh"):
            raise PackageError("Quartus executable provenance missing")
        reports = verify_reports(path.parent, profile)
    checked_settings = None
    policy_identity = FITTER_RECEIPT_SOURCE_IDENTITIES.get(manifest["source_commit"])
    if policy_identity is not None:
        identity, _ = reviewed_source(policy_identity)
        if identity["build_source_commit"] != manifest["source_commit"]:
            raise PackageError("fitter receipt policy/source identity disagreement")
        report, checked_settings = verify_fitter_receipt(
            path.parent, manifest, profile, identity["expected_fitter_settings"][profile], fixture=fixture)
        reports[FITTER_REPORT] = report
    return {"manifest": manifest, "raw": raw, "rev": rev, "rbf_sha256": digest(rbf),
            "fixture": fixture, "reports": reports, "source": source, "destination": destination,
            "checked_fitter_settings": checked_settings}


def snapshot_template(template: Path, expected: dict[str, bytes], *, core_version: str) -> dict[str, bytes]:
    safe_path(template)
    if not template.is_dir():
        raise PackageError("source package template missing")
    for path in template.rglob("*"):
        safe_path(path)
        if not path.is_dir() and not stat.S_ISREG(path.stat().st_mode):
            raise PackageError(f"template special file refused: {path}")
    files = legacy.snapshot_template(template)
    reference = {name.removeprefix("pkg/pocket/"): data for name, data in expected.items()}
    if files != reference:
        raise PackageError("template must exactly match frozen source: loader, slots, features and assets cannot be changed")
    transformed = {}
    for name, data in files.items():
        path = Path(name)
        if path.is_relative_to(legacy.CORE):
            path = CORE / path.relative_to(legacy.CORE)
        transformed[path.as_posix()] = data
    core_path = (CORE / "core.json").as_posix()
    core = parse_object(transformed[core_path], core_path)
    core["core"]["metadata"].update(shortname=SHORTNAME,
        description="EXPERIMENTAL standard-refresh SNES/MSU; unverified",
        version=core_version, date_release="2026-10-04")
    transformed[core_path] = json_bytes(core)
    # Keep upstream attribution, but avoid displaying upstream's support request
    # or compatibility assertions as promises for this unpublished experiment.
    info_path = (CORE / "info.txt").as_posix()
    transformed[info_path] = (
        "EXPERIMENTAL - NOT AN OFFICIAL RELEASE\n"
        "Local standard-refresh / MSU experiment.\n"
        "Upstream Pocket port by agg23. SNES core by srg320.\n"
        "https://github.com/agg23/openfpga-snes\n"
        "Not endorsed or released by upstream.\n"
        "Timing and hardware behavior remain unverified.\n"
        "Use blank/spare SD and original homebrew only.\n"
        "Renaming this core does not isolate common saves.\n"
        "See README-FIRST.txt and package.json in staging root.\n"
    ).encode()
    return transformed


def prepare_package(*, builds: dict[str, Path], assets: Path, output: Path,
                    template: Path = ROOT / "pkg/pocket", source_repository: Path = ROOT,
                    basename: str | None = None, synthetic_fixture_only: bool = False,
                    source_identity: str = DEFAULT_SOURCE_IDENTITY) -> dict:
    identity, identity_raw = reviewed_source(source_identity)
    basename = identity["homebrew_basename"] if basename is None else basename
    if set(builds) != set(PROFILES):
        raise PackageError("all three standard profiles are mandatory")
    output = safe_path(output)
    if output.exists():
        raise PackageError("refusing to overwrite any existing output or SD directory")
    if not output.parent.is_dir():
        raise PackageError("output parent must already exist")
    inputs = [safe_path(template), safe_path(assets), *(safe_path(Path(p).parent) for p in builds.values())]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in inputs):
        raise PackageError("output must be outside input directories")
    checked = {p: read_build(Path(builds[p]), p, synthetic_fixture_only=synthetic_fixture_only) for p in PROFILES}
    if len({b["fixture"] for b in checked.values()}) != 1:
        raise PackageError("mixed real/synthetic builds refused")
    if len({b["manifest"]["source_commit"] for b in checked.values()}) != 1:
        raise PackageError("mixed source commits refused")
    if len({b["rbf_sha256"] for b in checked.values()}) != 3:
        raise PackageError("duplicate profile bitstreams refused; SPC cannot use main image")
    commit = next(iter(checked.values()))["manifest"]["source_commit"]
    hardware = git_files(source_repository, commit, HARDWARE_PATHS)
    expected_hardware = git_files(source_repository, identity["hardware_commit"], HARDWARE_PATHS)
    actual_fingerprint = digest(json_bytes(inventory(hardware)))
    expected_fingerprint = digest(json_bytes(inventory(expected_hardware)))
    if (hardware != expected_hardware or actual_fingerprint != identity["hardware_inputs_sha256"]
            or expected_fingerprint != identity["hardware_inputs_sha256"]):
        raise PackageError(f"hardware inputs differ from reviewed source identity {source_identity}")
    if commit != identity["build_source_commit"]:
        raise PackageError(f"build source commit is not the reviewed source identity {source_identity}")
    template_source = git_files(source_repository, BASELINE, ("pkg/pocket",))
    template_files = snapshot_template(template, template_source, core_version=identity["core_version"])
    if not re.fullmatch(r"MSU1-STD-[A-Za-z0-9_-]{1,50}", basename):
        raise PackageError("basename must be a distinctive MSU1-STD- prefix plus letters/digits/hyphen/underscore")
    # The original generator is pinned too: cannot rehash arbitrary third-party assets.
    generator = read_file(ROOT / "tools/msu1_testrom.py")
    if {"tools/msu1_testrom.py": generator} != git_files(source_repository, BASELINE, ("tools/msu1_testrom.py",)):
        raise PackageError("homebrew generator differs from frozen original source")
    for path in assets.rglob("*"):
        safe_path(path)
        if not path.is_dir() and not stat.S_ISREG(path.stat().st_mode):
            raise PackageError("homebrew special file refused")
    homebrew = legacy.read_homebrew(assets, basename)
    generator_spec = importlib.util.spec_from_file_location("standard_original_homebrew", ROOT / "tools/msu1_testrom.py")
    generator_module = importlib.util.module_from_spec(generator_spec)
    generator_spec.loader.exec_module(generator_module)
    with tempfile.TemporaryDirectory(prefix="standard-original-homebrew-reference-") as temporary:
        reference_dir = Path(temporary)
        generator_module.write_assets(reference_dir, basename=basename)
        reference = {p.name: p.read_bytes() for p in reference_dir.iterdir()}
        if homebrew != reference:
            raise PackageError("homebrew must exactly match regenerated original files, manifest and symbols bytes")
    if {p.relative_to(assets).as_posix() for p in assets.rglob("*") if p.is_file()} != set(homebrew):
        raise PackageError("homebrew directory must contain only the original generated asset set")
    synthetic = next(iter(checked.values()))["fixture"]
    prefix = "synthetic-not-for-hardware" if synthetic else "sd"
    files = {f"{prefix}/{name}": data for name, data in template_files.items()}
    provenance = {}
    for profile, build in checked.items():
        destination = f"{prefix}/{CORE}/{build['destination']}"
        files[destination] = build["rev"]
        files[f"evidence/{profile}/build.json"] = build["raw"]
        for name, data in build["reports"].items():
            files[f"evidence/{profile}/{name}"] = data
        provenance[profile] = {
            "source_commit": commit, "source_status": "", "source_file": build["source"],
            "destination": destination, "rbf_sha256": build["rbf_sha256"],
            "rev_sha256": digest(build["rev"]), "build_manifest_sha256": digest(build["raw"]),
            "declared_timing_verified": build["manifest"]["timing_verified"],
            "declared_hardware_verified": build["manifest"]["hardware_verified"],
            "test_fixture": synthetic,
        }
        if build["checked_fitter_settings"] is not None:
            provenance[profile]["checked_fitter_settings"] = build["checked_fitter_settings"]
            provenance[profile]["fitter_settings_report"] = build["manifest"]["fitter_settings_report"]
    for name, data in homebrew.items():
        files[f"{prefix}/Assets/snes/common/{basename}/{name}"] = data
    files["evidence/hardware-inputs.json"] = json_bytes(inventory(hardware))
    files["evidence/reviewed-source-identities.json"] = identity_raw
    # Preserve exact upstream core metadata/info separately for auditability.
    for name in ("core.json", "info.txt"):
        files[f"evidence/upstream/{name}"] = template_source[f"pkg/pocket/{legacy.CORE}/{name}"]
    notice = (
        "POCKET STANDARD-REFRESH LOCAL EXPERIMENT\n\n" + WARNING + "\n\n"
        f"Identity: {CORE}. Distinct from agg23.SNES and previous b63 packages.\n"
        f"Reviewed source identity: {source_identity} (unverified candidate).\n"
        f"Build source: {identity['build_source_commit']}\n"
        f"Hardware anchor: {identity['hardware_commit']}\n"
        "This is a fresh staging tree, never an installation or a verified release.\n"
        "Do not merge it into your working SD or overwrite Cores/Assets/Platforms.\n"
        "First testing requires a blank/spare SD with only these homebrew assets.\n"
        "Save slot 10 retains nonvolatile common-platform behavior. Selecting any\n"
        "existing game can reuse its Saves/snes/common data despite the new core ID.\n"
        "Back up the entire original SD and all saves to a separate readable copy.\n"
        "The loader.bin and main/id0, SPCSDD1/id1, PAL/id2 mappings are preserved.\n"
        "SPCSDD1 uses standard_ntsc_spc, never an MSU main image.\n"
        "All original data slots, expansion-chip settings and JSON features remain.\n"
        "Only core metadata and displayed info are relabeled as a local experiment.\n"
        "Upstream port: agg23; SNES core: srg320. Not an upstream release.\n"
        "No commercial ROM or soundtrack is included.\n"
        "Review exact fitter/timing/CDC/I/O evidence before any hardware decision.\n"
        "Negative slack and package completeness do not establish safe operation.\n"
        "Hashes/reports cannot authenticate a maliciously fabricated compiler run.\n"
        "Nothing was installed, uploaded, published or copied to a real SD.\n"
    )
    if synthetic:
        notice = "SYNTHETIC FIXTURE ONLY - NOT FOR HARDWARE; NO QUARTUS RUN\n\n" + notice
    files["README-FIRST.txt"] = notice.encode()
    manifest = {
        "format": "pocket-standard-msu1-local-package-v1",
        "state": "synthetic_fixture_only" if synthetic else "experimental_staging_unverified",
        "test_fixture": synthetic, "package_complete": True, "core_id": CORE.name,
        "bitstream_integrity_verified": True, "source_revisions_match": True,
        "committed_hardware_inputs_match": True,
        "reviewed_source_identity": source_identity, "reviewed_source": identity,
        "source_identity_configuration_sha256": digest(identity_raw),
        "frozen_hardware_commit": identity["hardware_commit"],
        "template_and_homebrew_commit": BASELINE,
        "hardware_inputs_sha256": digest(files["evidence/hardware-inputs.json"]),
        "compiler_run_authenticated": False, "loadability_verified": False,
        "timing_verified": False, "hardware_verified": False, "ready_for_release": False,
        "common_saves_isolated": False, "warning": WARNING, "profiles": provenance,
        "verification_scope": "File integrity, committed hardware inputs, report/profile consistency and original homebrew only",
        "packager_sha256": digest(read_file(Path(__file__))),
        "legacy_helper_sha256": digest(read_file(ROOT / "tools/package_msu1.py")),
        "homebrew_generator_sha256": digest(generator), "files": inventory(files),
    }
    files["package.json"] = json_bytes(manifest)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent))
    created_output = False
    try:
        for name, data in files.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        output.mkdir()  # Exclusive reservation. Never reuse a directory, even empty.
        created_output = True
        for child in stage.iterdir():
            child.rename(output / child.name)
    except BaseException:
        if created_output:
            shutil.rmtree(output)
        raise
    finally:
        shutil.rmtree(stage)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in PROFILES:
        parser.add_argument("--" + name.replace("_", "-"), type=Path, required=True, metavar="BUILD_JSON")
    parser.add_argument("--source-identity", required=True,
                        help="explicit reviewed identity: baseline-982f103, candidate-64b5b51, candidate-0da938e or candidate-e71101f")
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--template", type=Path, default=ROOT / "pkg/pocket")
    parser.add_argument("--source-repository", type=Path, default=ROOT)
    parser.add_argument("--basename", default=None, help="defaults to the selected identity's unique homebrew stem")
    args = parser.parse_args()
    try:
        prepare_package(builds={p: getattr(args, p) for p in PROFILES}, assets=args.assets,
                        output=args.output, template=args.template, source_repository=args.source_repository,
                        basename=args.basename, source_identity=args.source_identity)
    except (PackageError, OSError, UnicodeError) as error:
        parser.exit(1, f"Package refused: {error}\nNo complete or loadable package is claimed.\n")
    print(f"Prepared NEW local standard experiment: {args.output}")
    print(WARNING)
    print("Nothing installed, uploaded or published.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
