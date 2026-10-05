#!/usr/bin/env python3
"""Prepare a new, local, explicitly unverified Pocket MSU experiment directory.

This does not compile, download, upload, publish, mount, install, or erase anything.
It never modifies a build, package template, asset source, or existing destination.
Hash integrity and completeness are not timing closure or hardware validation.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORE = Path("Cores/agg23.SNES")
PROFILES = {
    "msu_ntsc": ("snes_msu_ntsc.rev", "snes_main.rev", "main", 0),
    "msu_pal": ("snes_msu_pal.rev", "snes_pal.rev", "PAL", 2),
    "ntsc_spc": ("snes_spc.rev", "snes_spc.rev", "SPCSDD1", 1),
}
REVERSE_BYTE = bytes(int(f"{value:08b}"[::-1], 2) for value in range(256))
UNVERIFIED = (
    "EXPERIMENTAL, UNVERIFIED STAGING ONLY. Timing and hardware operation have "
    "NOT been verified by this tool. This is not a verified or safe release."
)


class PackageError(ValueError):
    """An input is incomplete, inconsistent, unsafe to copy, or unverified."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def read_file(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise PackageError(f"required regular file is missing or a symlink: {path}")
    data = path.read_bytes()
    if not data:
        raise PackageError(f"required file is empty: {path}")
    return data


def parse_object(data: bytes, description: str) -> dict:
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise PackageError(f"duplicate JSON key {key!r}: {description}")
            result[key] = value
        return result
    try:
        result = json.loads(data, object_pairs_hook=unique_pairs)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise PackageError(f"invalid JSON in {description}: {error}") from error
    if not isinstance(result, dict):
        raise PackageError(f"JSON root must be an object: {description}")
    return result


def verify_output(directory: Path, manifest: dict, filename: str) -> bytes:
    outputs = manifest.get("outputs")
    entry = outputs.get(filename) if isinstance(outputs, dict) else None
    if not isinstance(entry, dict):
        raise PackageError(f"build manifest lacks output {filename}: {directory}")
    data = read_file(directory / filename)
    if type(entry.get("bytes")) is not int or entry["bytes"] != len(data):
        raise PackageError(f"size mismatch for {directory / filename}")
    if entry.get("sha256") != digest(data):
        raise PackageError(f"SHA-256 mismatch for {directory / filename}")
    return data


def read_build(path: Path, profile: str, allow_test_fixtures: bool) -> dict:
    if path.name != "build.json":
        raise PackageError(f"pass the run's build.json, not a bitstream or directory: {path}")
    raw = read_file(path)
    manifest = parse_object(raw, str(path))
    if manifest.get("state") != "bitstream_generated_unverified":
        raise PackageError(f"{profile}: build is not bitstream_generated_unverified")
    if manifest.get("profile") != profile:
        raise PackageError(f"{profile}: wrong profile {manifest.get('profile')!r}")
    if type(manifest.get("compile_exit_code")) is not int or manifest["compile_exit_code"] != 0:
        raise PackageError(f"{profile}: compile_exit_code must be integer zero")
    if manifest.get("device") != "5CEBA4F23C8":
        raise PackageError(f"{profile}: wrong or missing target device")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", str(manifest.get("source_commit", ""))):
        raise PackageError(f"{profile}: missing full source commit hash")
    if not isinstance(manifest.get("source_status"), str):
        raise PackageError(f"{profile}: missing source_status provenance")
    for field in ("timing_verified", "hardware_verified"):
        if type(manifest.get(field)) is not bool:
            raise PackageError(f"{profile}: {field} must be an explicit boolean")
    if "test_fixture" in manifest and type(manifest["test_fixture"]) is not bool:
        raise PackageError(f"{profile}: test_fixture must be boolean")
    fixture = manifest.get("test_fixture", False)
    if fixture and not allow_test_fixtures:
        raise PackageError(f"{profile}: synthetic test fixture refused; not a real Quartus result")
    source_name, destination, _, _ = PROFILES[profile]
    rbf = verify_output(path.parent, manifest, "snes_pocket.rbf")
    rev = verify_output(path.parent, manifest, source_name)
    if rbf.translate(REVERSE_BYTE) != rev:
        raise PackageError(f"{profile}: REV is not the bytewise bit reversal of the recorded RBF")
    return {"manifest": manifest, "raw_manifest": raw, "bitstream": rev,
            "source_name": source_name, "destination": destination, "test_fixture": fixture}


def snapshot_template(template: Path) -> dict[str, bytes]:
    if template.is_symlink() or not template.is_dir():
        raise PackageError(f"package template must be a real directory: {template}")
    files = {}
    for path in sorted(template.rglob("*")):
        if path.is_symlink():
            raise PackageError(f"symlink in package template: {path}")
        if path.is_file():
            relative = path.relative_to(template).as_posix()
            # .gitkeep is the only intentionally empty template file.
            files[relative] = path.read_bytes()
            if path.suffix.lower() == ".json":
                parse_object(files[relative], str(path))

    def required(relative: Path | str) -> bytes:
        key = str(relative)
        if not files.get(key):
            raise PackageError(f"missing or empty package file: {key}")
        return files[key]

    parsed = {}
    for name in ("core", "audio", "data", "input", "interact", "variants", "video"):
        obj = parse_object(required(CORE / f"{name}.json"), name)
        section = obj.get(name)
        if not isinstance(section, dict) or section.get("magic") != "APF_VER_1":
            raise PackageError(f"invalid {name}.json APF_VER_1 section")
        parsed[name] = section
    core = parsed["core"]
    expected_modes = {(name, mode_id, destination)
                      for _, destination, name, mode_id in PROFILES.values()}
    modes = core.get("cores")
    if not isinstance(modes, list) or not all(isinstance(mode, dict) for mode in modes):
        raise PackageError("core.json must retain main, SPCSDD1 and PAL modes")
    if any(not isinstance(mode.get("name"), str) or type(mode.get("id")) is not int
           or not isinstance(mode.get("filename"), str) for mode in modes):
        raise PackageError("core mode names/filenames must be strings and IDs must be integers")
    actual_modes = {(mode["name"], mode["id"], mode["filename"]) for mode in modes}
    if len(modes) != 3 or actual_modes != expected_modes:
        raise PackageError("core.json must retain exactly main/id0, SPCSDD1/id1 and PAL/id2 filenames")
    framework, metadata = core.get("framework"), core.get("metadata")
    if not isinstance(framework, dict) or framework.get("chip32_vm") != "loader.bin":
        raise PackageError("core.json must retain the existing loader.bin")
    if (not isinstance(metadata, dict) or not isinstance(metadata.get("platform_ids"), list)
            or "snes" not in metadata["platform_ids"]):
        raise PackageError("core.json must reference the snes platform")
    for relative in (CORE / "loader.bin", CORE / "icon.bin", CORE / "info.txt",
                     "Platforms/_images/snes.bin"):
        required(relative)
    platform = parse_object(required("Platforms/snes.json"), "Platforms/snes.json")
    if not isinstance(platform.get("platform"), dict):
        raise PackageError("invalid Platforms/snes.json platform object")
    slots = parsed["data"].get("data_slots")
    if not isinstance(slots, list) or not all(isinstance(slot, dict) for slot in slots):
        raise PackageError("data.json must contain data_slots")
    if any(type(slot.get("id")) is not int for slot in slots):
        raise PackageError("data slot IDs must be integers")
    if any(not isinstance(slot.get("extensions"), list) for slot in slots):
        raise PackageError("data slot extensions must be lists")
    by_id = {slot["id"]: slot for slot in slots}
    if len(by_id) != len(slots):
        raise PackageError("duplicate data slot IDs")
    if (by_id.get(0, {}).get("required") is not True
            or "sfc" not in by_id.get(0, {}).get("extensions", [])):
        raise PackageError("cartridge slot 0 must retain required SFC support")
    if by_id.get(10, {}).get("nonvolatile") is not True:
        raise PackageError("save slot 10 must retain nonvolatile support")
    for slot_id, extension in ((100, "msu"), (101, "pcm")):
        slot = by_id.get(slot_id, {})
        if (slot.get("required") is not False or slot.get("deferload") is not True
                or slot.get("parameters") != "0x8" or extension not in slot.get("extensions", [])):
            raise PackageError(f"MSU slot {slot_id} must remain optional, deferred, read-only {extension}")
    if not parsed["input"].get("controllers") or not parsed["video"].get("scaler_modes"):
        raise PackageError("input controllers and video scaler_modes must be preserved")
    if not isinstance(parsed["variants"].get("variant_list"), list):
        raise PackageError("variants.json must retain variant_list")
    # Never import a stale template bitstream, save file, or third-party ROM.
    for relative in files:
        suffix = Path(relative).suffix.lower()
        if suffix in (".rev", ".rbf", ".sav", ".srm", ".sfc", ".smc", ".pcm", ".msu"):
            raise PackageError(f"use the source-only pkg/pocket template, not an installed core: {relative}")
    return files


def read_homebrew(directory: Path, basename: str) -> dict[str, bytes]:
    if (not basename or basename in (".", "..") or basename[-1:] in (".", " ")
            or re.search(r'[<>:"/\\|?*\x00-\x1f]', basename)):
        raise PackageError("homebrew basename must be a FAT-friendly single filename stem")
    source = Path(__file__).with_name("msu1_testrom.py")
    spec = importlib.util.spec_from_file_location("pocket_package_homebrew", source)
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    rom, symbols = generator.build_rom()
    reference = {f"{basename}.sfc": rom, f"{basename}.msu": generator.make_data(),
                 f"{basename}-1.pcm": generator.make_pcm(1),
                 f"{basename}-2.pcm": generator.make_pcm(2)}
    manifest_name = f"{basename}.manifest.json"
    manifest_raw = read_file(directory / manifest_name)
    manifest = parse_object(manifest_raw, manifest_name)
    if (manifest.get("format") != "pocket-msu1-self-test-v1"
            or manifest.get("basename") != basename
            or not isinstance(manifest.get("files"), dict)
            or set(manifest["files"]) != set(reference)):
        raise PackageError("homebrew manifest format, basename or expected files do not match")
    if manifest.get("hardware_tested") is not False:
        raise PackageError("homebrew manifest must retain hardware_tested=false; this tool cannot validate hardware claims")
    for field, expected in (("sample_rate", 44100), ("channels", 2), ("sample_bits", 16),
                            ("frames_per_track", 88200), ("loop_frame", 22050),
                            ("intentionally_missing_track", 3)):
        if type(manifest.get(field)) is not int or manifest[field] != expected:
            raise PackageError(f"incorrect homebrew {field}")
    if (directory / f"{basename}-3.pcm").exists():
        raise PackageError("homebrew track 3 must be missing for the missing-track diagnostic")
    result = {manifest_name: manifest_raw}
    for name, expected_bytes in reference.items():
        data = read_file(directory / name)
        entry = manifest["files"][name]
        if (not isinstance(entry, dict) or type(entry.get("size")) is not int
                or entry["size"] != len(data) or entry.get("sha256") != digest(data)):
            raise PackageError(f"homebrew size/SHA-256 mismatch: {name}")
        if data != expected_bytes:
            raise PackageError(f"homebrew differs from this checkout's original generator: {name}")
        result[name] = data
    symbols_name = f"{basename}.symbols.json"
    symbols_raw = read_file(directory / symbols_name)
    if parse_object(symbols_raw, symbols_name) != symbols:
        raise PackageError("homebrew symbols do not match the generated diagnostic")
    result[symbols_name] = symbols_raw
    return result


def prepare_package(*, builds: dict[str, Path], assets: Path, output: Path,
                    template: Path = ROOT / "pkg/pocket", basename: str = "MSU Test",
                    allow_test_fixtures: bool = False) -> dict:
    """Validate all input snapshots, then create one entirely new staging directory."""
    if set(builds) != set(PROFILES):
        raise PackageError("all three builds are mandatory: msu_ntsc, msu_pal, ntsc_spc")
    output = output.absolute()
    if output.exists() or output.is_symlink():
        raise PackageError(f"refusing to overwrite an existing output or SD directory: {output}")
    if not output.parent.is_dir():
        raise PackageError(f"output parent must already exist: {output.parent}")
    output = output.parent.resolve() / output.name
    # Also protect inputs from an accidentally nested destination.
    for source in [template, assets, *(path.parent for path in builds.values())]:
        if output.is_relative_to(source.resolve()):
            raise PackageError(f"output must be outside input directories: {source}")
    checked = {profile: read_build(Path(builds[profile]), profile, allow_test_fixtures)
               for profile in PROFILES}
    template_files = snapshot_template(template)
    homebrew = read_homebrew(assets, basename)
    synthetic = any(build["test_fixture"] for build in checked.values())
    package_files = {"sd/" + relative: data for relative, data in template_files.items()}
    provenance = {}
    for profile, build in checked.items():
        destination = f"sd/{CORE}/{build['destination']}"
        package_files[destination] = build["bitstream"]
        evidence = f"evidence/{profile}/build.json"
        package_files[evidence] = build["raw_manifest"]
        original = build["manifest"]
        provenance[profile] = {
            "build_manifest": evidence, "build_manifest_sha256": digest(build["raw_manifest"]),
            "source_file": build["source_name"], "destination": destination,
            "sha256": digest(build["bitstream"]), "bytes": len(build["bitstream"]),
            "source_commit": original["source_commit"], "source_status": original["source_status"],
            "declared_timing_verified": original["timing_verified"],
            "declared_hardware_verified": original["hardware_verified"],
            "test_fixture": build["test_fixture"],
        }
    for name, data in homebrew.items():
        destination = f"sd/Assets/snes/common/{basename}/{name}"
        if destination in package_files:
            raise PackageError(f"homebrew collides with package template: {destination}")
        package_files[destination] = data
    notice = (
        "POCKET MSU-1 LOCAL EXPERIMENT\n\n" + UNVERIFIED + "\n\n"
        "The sd/ directory is a fresh staging tree, not an installation.\n"
        "Back up the entire original core and all saves before any manual SD merge.\n"
        "Review each build's fitter, all timing corners, unconstrained paths, ignored\n"
        "exceptions and warnings first. Negative timing slack is not a safe release.\n"
        "Keep a known-good rollback copy. Hardware operation remains untested.\n"
        "Do not automatically overwrite or replace existing Assets/Cores/Platforms.\n"
        "The loader and all JSON files are preserved byte-for-byte, including SPCSDD1.\n"
        "The SPC-specific image comes from ntsc_spc, never from an MSU main image.\n"
        "Read package.json and evidence/*/build.json for provenance and source status.\n"
        "No commercial ROM or soundtrack is included. Only original homebrew assets.\n"
    )
    if synthetic:
        notice = "SYNTHETIC TEST FIXTURE ONLY — NOT FOR HARDWARE\n\n" + notice
    package_files["README-FIRST.txt"] = notice.encode("utf-8")
    inventory = {name: {"bytes": len(data), "sha256": digest(data)}
                 for name, data in sorted(package_files.items())}
    manifest = {
        "format": "pocket-msu1-local-package-v1",
        "state": "synthetic_fixture_only" if synthetic else "experimental_staging_unverified",
        "test_fixture": synthetic, "package_complete": True,
        "bitstream_integrity_verified": True, "loadability_verified": False,
        "timing_verified": False, "hardware_verified": False, "ready_for_release": False,
        "warning": UNVERIFIED,
        "verification_scope": "Completeness, hashes, source homebrew, JSON invariants and RBF-to-REV conversion only",
        "source_revisions_match": len({b["manifest"]["source_commit"] for b in checked.values()}) == 1,
        "profiles": provenance,
        "packager_sha256": digest(Path(__file__).read_bytes()),
        "homebrew_generator_sha256": digest(Path(__file__).with_name("msu1_testrom.py").read_bytes()),
        "files": inventory,
    }
    package_files["package.json"] = json_bytes(manifest)
    # Validate before any output creation. A hidden sibling is private scratch;
    # reserve the final name with mkdir(exist_ok=False), never replacing a path.
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent))
    created_output = False
    try:
        for name, data in package_files.items():
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        output.mkdir()  # Exclusive destination reservation: an existing path is an error.
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
    parser.add_argument("--msu-ntsc", required=True, type=Path, metavar="BUILD_JSON")
    parser.add_argument("--msu-pal", required=True, type=Path, metavar="BUILD_JSON")
    parser.add_argument("--ntsc-spc", required=True, type=Path, metavar="BUILD_JSON")
    parser.add_argument("--assets", required=True, type=Path, help="generated original homebrew directory")
    parser.add_argument("--output", required=True, type=Path, help="entirely NEW local staging directory")
    parser.add_argument("--template", type=Path, default=ROOT / "pkg/pocket")
    parser.add_argument("--basename", default="MSU Test")
    parser.add_argument("--allow-test-fixtures", action="store_true",
                        help="TESTING ONLY: explicitly label synthetic output NOT FOR HARDWARE")
    args = parser.parse_args()
    try:
        result = prepare_package(
            builds={"msu_ntsc": args.msu_ntsc, "msu_pal": args.msu_pal, "ntsc_spc": args.ntsc_spc},
            assets=args.assets, output=args.output, template=args.template, basename=args.basename,
            allow_test_fixtures=args.allow_test_fixtures)
    except (PackageError, OSError) as error:
        parser.exit(1, f"Package refused: {error}\nNo complete or loadable package is claimed.\n")
    if result["test_fixture"]:
        print("SYNTHETIC TEST FIXTURE ONLY — NOT FOR HARDWARE")
    print(f"Prepared a new local staging directory: {args.output}")
    print(UNVERIFIED)
    print("Nothing was installed, uploaded or published. Back up the original core and saves before manual testing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
