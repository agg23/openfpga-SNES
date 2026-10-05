"""Packaging tests use SYNTHETIC fixtures, never real Quartus/build evidence.

The tiny fake RBF/REV payloads are unusable on hardware. The opt-in fixture
switch and resulting package marker prevent them masquerading as built cores.
"""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pack = load_module("test_package_module", ROOT / "tools/package_msu1.py")
homebrew = load_module("test_package_assets", ROOT / "tools/msu1_testrom.py")


def snapshot(directory):
    return {p.relative_to(directory).as_posix(): p.read_bytes()
            for p in directory.rglob("*") if p.is_file()}


class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory(prefix="msu1-original-homebrew-fixture-")
        cls.shared_assets = Path(cls.shared.name)
        homebrew.write_assets(cls.shared_assets)

    @classmethod
    def tearDownClass(cls):
        cls.shared.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="msu1-SYNTHETIC-package-test-")
        self.root = Path(self.temp.name)
        self.template = self.root / "source-package"
        shutil.copytree(ROOT / "pkg/pocket", self.template)
        self.assets = self.root / "original-homebrew"
        shutil.copytree(self.shared_assets, self.assets)
        self.output = self.root / "experiment"
        self.builds = {}
        for profile, (source, _, _, _) in pack.PROFILES.items():
            directory = self.root / "SYNTHETIC-BUILDS-NOT-FOR-HARDWARE" / profile
            directory.mkdir(parents=True)
            # NOT a bitstream. Distinct payloads catch swapped profile mappings.
            rbf = b"SYNTHETIC FIXTURE ONLY / NO QUARTUS / " + profile.encode() + bytes(range(256))
            rev = rbf.translate(pack.REVERSE_BYTE)
            (directory / "snes_pocket.rbf").write_bytes(rbf)
            (directory / source).write_bytes(rev)
            path = directory / "build.json"
            manifest = {
                "state": "bitstream_generated_unverified", "profile": profile,
                "device": "5CEBA4F23C8", "compile_exit_code": 0,
                "source_commit": "a" * 40, "source_status": "",
                "quartus_sh": "SYNTHETIC_TEST_FIXTURE_NO_COMPILER_WAS_RUN",
                "timing_verified": False, "hardware_verified": False,
                "test_fixture": True,
                "fixture_notice": "SYNTHETIC TEST FIXTURE. NOT A QUARTUS RESULT. NOT FOR HARDWARE.",
                "outputs": {
                    name: {"bytes": len(data), "sha256": pack.digest(data)}
                    for name, data in (("snes_pocket.rbf", rbf), (source, rev))
                },
            }
            path.write_bytes(pack.json_bytes(manifest))
            self.builds[profile] = path

    def tearDown(self):
        self.temp.cleanup()

    def prepare(self, **changes):
        arguments = dict(builds=self.builds, assets=self.assets, output=self.output,
                         template=self.template, allow_test_fixtures=True)
        arguments.update(changes)
        return pack.prepare_package(**arguments)

    def change_manifest(self, selected_profile, **changes):
        path = self.builds[selected_profile]
        data = json.loads(path.read_text())
        data.update(changes)
        path.write_bytes(pack.json_bytes(data))

    def mutate_json(self, path, action):
        data = json.loads(path.read_text())
        action(data)
        path.write_bytes(pack.json_bytes(data))

    def refused(self, message, **changes):
        with self.assertRaisesRegex(pack.PackageError, message):
            self.prepare(**changes)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".experiment.staging-*")))

    def test_complete_fixture_maps_three_profiles_without_modifying_inputs(self):
        source_before = {str(path): snapshot(path) for path in
                         (self.template, self.assets, self.builds["msu_ntsc"].parent.parent)}
        manifest = self.prepare()
        self.assertEqual(manifest["state"], "synthetic_fixture_only")
        self.assertTrue(manifest["test_fixture"])
        self.assertTrue(manifest["package_complete"])
        self.assertTrue(manifest["bitstream_integrity_verified"])
        for flag in ("loadability_verified", "timing_verified", "hardware_verified", "ready_for_release"):
            self.assertIs(manifest[flag], False)
        for profile, (source, destination, _, _) in pack.PROFILES.items():
            self.assertEqual((self.output / "sd" / pack.CORE / destination).read_bytes(),
                             (self.builds[profile].parent / source).read_bytes())
            self.assertEqual((self.output / "evidence" / profile / "build.json").read_bytes(),
                             self.builds[profile].read_bytes())
        for name, data in snapshot(self.template).items():
            self.assertEqual((self.output / "sd" / name).read_bytes(), data)
        for name, data in snapshot(self.assets).items():
            self.assertEqual((self.output / "sd/Assets/snes/common/MSU Test" / name).read_bytes(), data)
        self.assertFalse((self.output / "sd/Assets/snes/common/MSU Test/MSU Test-3.pcm").exists())
        self.assertIn("SYNTHETIC TEST FIXTURE ONLY", (self.output / "README-FIRST.txt").read_text())
        self.assertIn("Back up the entire original core and all saves", (self.output / "README-FIRST.txt").read_text())
        for path in (self.template, self.assets, self.builds["msu_ntsc"].parent.parent):
            self.assertEqual(snapshot(path), source_before[str(path)])

    def test_inventory_and_reproducibility(self):
        manifest = self.prepare()
        for name, record in manifest["files"].items():
            data = (self.output / name).read_bytes()
            self.assertEqual(record, {"bytes": len(data), "sha256": pack.digest(data)})
        second = self.root / "another-name"
        self.assertEqual(manifest, self.prepare(output=second))
        self.assertEqual(snapshot(self.output), snapshot(second))
        self.assertEqual(json.loads((self.output / "package.json").read_text()), manifest)

    def test_fixture_default_refusal(self):
        self.refused("synthetic test fixture refused", allow_test_fixtures=False)

    def test_missing_profile_is_not_optional_even_for_spc(self):
        builds = dict(self.builds)
        del builds["ntsc_spc"]
        self.refused("all three builds", builds=builds)

    def test_wrong_profile_rejected(self):
        self.change_manifest("ntsc_spc", profile="ntsc")
        self.refused("wrong profile")

    def test_failed_running_and_partial_build_states_rejected(self):
        for state in ("running", "compile_failed", "compile_succeeded", "verified", None):
            with self.subTest(state=state):
                self.change_manifest("msu_ntsc", state=state)
                self.refused("not bitstream_generated_unverified")

    def test_bad_exit_status_and_device_rejected(self):
        for code in (1, "0", False, None):
            with self.subTest(code=code):
                self.change_manifest("msu_ntsc", compile_exit_code=code)
                self.refused("compile_exit_code")
        self.change_manifest("msu_ntsc", compile_exit_code=0, device="5CEBA2F17A7")
        self.refused("wrong or missing target")

    def test_provenance_and_verification_booleans_required(self):
        self.change_manifest("msu_ntsc", source_commit="short")
        self.refused("source commit")
        self.change_manifest("msu_ntsc", source_commit="a" * 40, source_status=None)
        self.refused("source_status")
        self.change_manifest("msu_ntsc", source_status="", timing_verified="false")
        self.refused("timing_verified")
        self.change_manifest("msu_ntsc", timing_verified=False, hardware_verified=0)
        self.refused("hardware_verified")

    def test_source_verification_claims_never_promote_package(self):
        for profile in self.builds:
            self.change_manifest(profile, timing_verified=True, hardware_verified=True)
        manifest = self.prepare()
        self.assertFalse(manifest["timing_verified"])
        self.assertFalse(manifest["hardware_verified"])
        self.assertFalse(manifest["ready_for_release"])
        for profile in self.builds:
            self.assertTrue(manifest["profiles"][profile]["declared_timing_verified"])
            self.assertTrue(manifest["profiles"][profile]["declared_hardware_verified"])

    def test_mixed_source_revisions_and_dirty_status_remain_visible(self):
        self.change_manifest("msu_pal", source_commit="b" * 40, source_status=" M projects/snes_pocket.qsf")
        manifest = self.prepare()
        self.assertFalse(manifest["source_revisions_match"])
        self.assertEqual(manifest["profiles"]["msu_pal"]["source_status"], " M projects/snes_pocket.qsf")
        self.assertFalse(manifest["ready_for_release"])

    def test_missing_spc_bitstream_and_rbf_rejected(self):
        path = self.builds["ntsc_spc"].parent / "snes_spc.rev"
        original = path.read_bytes()
        path.unlink()
        self.refused("required regular file")
        path.write_bytes(original)
        (self.builds["msu_pal"].parent / "snes_pocket.rbf").unlink()
        self.refused("required regular file")

    def test_empty_bitstream_rejected(self):
        (self.builds["msu_ntsc"].parent / "snes_msu_ntsc.rev").write_bytes(b"")
        self.refused("required file is empty")

    def test_actual_hash_and_size_are_both_checked(self):
        path = self.builds["msu_ntsc"].parent / "snes_msu_ntsc.rev"
        original = path.read_bytes()
        path.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        self.refused("SHA-256 mismatch")
        path.write_bytes(original + b"extra")
        self.refused("size mismatch")

    def test_rbf_hash_checked_not_only_rev(self):
        path = self.builds["msu_ntsc"].parent / "snes_pocket.rbf"
        original = path.read_bytes()
        path.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        self.refused("SHA-256 mismatch")

    def test_rehashed_wrong_rev_conversion_rejected(self):
        path = self.builds["msu_ntsc"].parent / "snes_msu_ntsc.rev"
        wrong = bytes([0x55]) * path.stat().st_size
        path.write_bytes(wrong)
        self.mutate_json(self.builds["msu_ntsc"],
                         lambda m: m["outputs"][path.name].update(sha256=pack.digest(wrong)))
        self.refused("not the bytewise bit reversal")

    def test_existing_output_directory_file_or_symlink_never_overwritten(self):
        self.output.mkdir()
        keep = self.output / "ORIGINAL-CORE-AND-SAVES"
        keep.write_bytes(b"DO NOT TOUCH")
        with self.assertRaisesRegex(pack.PackageError, "refusing to overwrite"):
            self.prepare()
        self.assertEqual(keep.read_bytes(), b"DO NOT TOUCH")
        keep.unlink(); self.output.rmdir()
        self.output.write_bytes(b"ORIGINAL")
        with self.assertRaises(pack.PackageError): self.prepare()
        self.assertEqual(self.output.read_bytes(), b"ORIGINAL")
        self.output.unlink()
        self.output.symlink_to(self.template, target_is_directory=True)
        with self.assertRaises(pack.PackageError): self.prepare()
        self.assertTrue(self.output.is_symlink())

    def test_nested_output_and_missing_parent_rejected(self):
        for source in (self.template, self.assets, self.builds["msu_ntsc"].parent):
            with self.subTest(source=source):
                with self.assertRaisesRegex(pack.PackageError, "outside input"):
                    self.prepare(output=source / "nested")
                self.assertFalse((source / "nested").exists())
        with self.assertRaisesRegex(pack.PackageError, "parent must already exist"):
            self.prepare(output=self.root / "absent-parent" / "package")

    def test_missing_loader_and_invalid_required_json_rejected(self):
        loader = self.template / pack.CORE / "loader.bin"
        original = loader.read_bytes()
        loader.unlink()
        self.refused("missing or empty package file")
        loader.write_bytes(original)
        (self.template / pack.CORE / "input.json").write_text("{bad")
        self.refused("invalid JSON")

    def test_spc_configuration_cannot_be_silently_dropped(self):
        self.mutate_json(self.template / pack.CORE / "core.json",
                         lambda m: m["core"]["cores"].pop(1))
        self.refused("retain exactly")

    def test_spc_filename_cannot_be_replaced_with_main_image(self):
        self.mutate_json(self.template / pack.CORE / "core.json",
                         lambda m: m["core"]["cores"][1].update(filename="snes_main.rev"))
        self.refused("retain exactly")

    def test_optional_readonly_msu_data_slots_required(self):
        path = self.template / pack.CORE / "data.json"
        original = path.read_bytes()
        for change in ({"required": True}, {"deferload": False}, {"parameters": "0x84"}):
            path.write_bytes(original)
            self.mutate_json(path, lambda m: m["data"]["data_slots"][2].update(change))
            self.refused("MSU slot 100")

    def test_source_template_cannot_contain_stale_bitstreams_or_saves(self):
        for filename in ("snes_main.rev", "precious.sav", "commercial.sfc"):
            path = self.template / pack.CORE / filename
            path.write_bytes(b"DO NOT PACKAGE")
            self.refused("source-only pkg/pocket")
            path.unlink()

    def test_source_symlinks_rejected(self):
        path = self.template / pack.CORE / "loader.bin"
        path.unlink()
        path.symlink_to(self.builds["msu_ntsc"])
        self.refused("symlink in package template")

    def test_missing_homebrew_pcm_rejected(self):
        (self.assets / "MSU Test-2.pcm").unlink()
        self.refused("required regular file")

    def test_homebrew_manifest_hash_cannot_hide_modified_audio(self):
        path = self.assets / "MSU Test-1.pcm"
        data = bytearray(path.read_bytes())
        data[4:8] = bytes(4)  # Wrong loop index, then update the self-reported hash.
        path.write_bytes(data)
        self.mutate_json(self.assets / "MSU Test.manifest.json",
                         lambda m: m["files"][path.name].update(sha256=pack.digest(data)))
        self.refused("differs from this checkout")

    def test_homebrew_corrupted_hash_or_missing_track_case_rejected(self):
        self.mutate_json(self.assets / "MSU Test.manifest.json",
                         lambda m: m["files"]["MSU Test.msu"].update(sha256="0" * 64))
        self.refused("homebrew size/SHA-256 mismatch")
        shutil.copy2(self.shared_assets / "MSU Test.manifest.json", self.assets)
        (self.assets / "MSU Test-3.pcm").write_bytes(b"unexpected")
        self.refused("track 3 must be missing")

    def test_symbols_and_basename_checked(self):
        (self.assets / "MSU Test.symbols.json").write_text("{}")
        self.refused("symbols do not match")
        for stem in ("../escape", "bad/name", "bad\\name", "bad:fat", "tail."):
            self.refused("FAT-friendly", basename=stem)

    def test_duplicate_json_keys_rejected(self):
        path = self.builds["msu_ntsc"]
        path.write_text('{"state":"running", "state":"bitstream_generated_unverified"}')
        self.refused("duplicate JSON key")

    def test_malformed_core_mode_types_fail_cleanly(self):
        self.mutate_json(self.template / pack.CORE / "core.json",
                         lambda m: m["core"]["cores"][1].update(id=False))
        self.refused("IDs must be integers")

    def test_homebrew_cannot_claim_hardware_verification(self):
        self.mutate_json(self.assets / "MSU Test.manifest.json",
                         lambda m: m.update(hardware_tested=True))
        self.refused("hardware_tested=false")

    def test_output_io_failure_removes_only_new_partial_staging(self):
        source_before = snapshot(self.template)
        with mock.patch.object(Path, "rename", side_effect=OSError("injected staging move failure")):
            with self.assertRaisesRegex(OSError, "injected"):
                self.prepare()
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".experiment.staging-*")))
        self.assertEqual(snapshot(self.template), source_before)

    def test_cli_fixture_is_explicit_and_failure_does_not_claim_loadability(self):
        args = [sys.executable, str(ROOT / "tools/package_msu1.py"),
                "--msu-ntsc", str(self.builds["msu_ntsc"]),
                "--msu-pal", str(self.builds["msu_pal"]),
                "--ntsc-spc", str(self.builds["ntsc_spc"]),
                "--assets", str(self.assets), "--output", str(self.output),
                "--template", str(self.template)]
        failed = subprocess.run(args, text=True, capture_output=True)
        self.assertEqual(failed.returncode, 1)
        self.assertIn("No complete or loadable package is claimed", failed.stderr)
        self.assertFalse(self.output.exists())
        result = subprocess.run(args + ["--allow-test-fixtures"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SYNTHETIC TEST FIXTURE ONLY", result.stdout)
        self.assertIn("not a verified or safe release", result.stdout)
        self.assertTrue((self.output / "package.json").exists())


if __name__ == "__main__":
    unittest.main()
