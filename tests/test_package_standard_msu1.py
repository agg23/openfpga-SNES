"""SYNTHETIC FIXTURE ONLY packaging regression; never a usable FPGA package.

The positive end-to-end path is explicitly synthetic and has no sd/ directory.
Real compiler acceptance is tested separately against actual retained archives.
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


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pack = load("standard_package_tests", "package_standard_msu1.py")
homebrew = load("standard_homebrew_tests", "msu1_testrom.py")


def snapshot(path):
    return {p.relative_to(path).as_posix(): p.read_bytes() for p in path.rglob("*") if p.is_file()}


class StandardPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory(prefix="STANDARD-SYNTHETIC-assets-")
        homebrew.write_assets(Path(cls.shared.name), basename=pack.BASENAME)

    @classmethod
    def tearDownClass(cls):
        cls.shared.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="STANDARD-SYNTHETIC-NOT-FOR-HARDWARE-")
        self.root = Path(self.temp.name)
        self.output = self.root / "experiment"
        self.assets = self.root / "homebrew"
        shutil.copytree(self.shared.name, self.assets)
        self.template = self.root / "template"
        shutil.copytree(ROOT / "pkg/pocket", self.template)
        self.builds = {}
        for profile, (source, _, _, _) in pack.PROFILES.items():
            directory = self.root / "SYNTHETIC-FIXTURES" / profile
            directory.mkdir(parents=True)
            rbf = pack.FIXTURE_MARKER + profile.encode() + b"/" + bytes(range(256))
            rev = rbf.translate(pack.REVERSE_BYTE)
            manifest = {
                "state": "synthetic_fixture_only", "test_fixture": True,
                "profile": profile, "device": "5CEBA4F23C8", "compile_exit_code": 0,
                "source_commit": pack.BASELINE, "source_status": "",
                "quartus_sh": "SYNTHETIC_FIXTURE_ONLY",
                "started_utc": "2026-10-04T00:00:00+00:00",
                "finished_utc": "2026-10-04T00:00:01+00:00",
                "timing_verified": False, "hardware_verified": False,
                "outputs": pack.inventory({"snes_pocket.rbf": rbf, source: rev}),
            }
            (directory / "snes_pocket.rbf").write_bytes(rbf)
            (directory / source).write_bytes(rev)
            self.builds[profile] = directory / "build.json"
            self.builds[profile].write_bytes(pack.json_bytes(manifest))

    def tearDown(self):
        self.temp.cleanup()

    def prepare(self, **changes):
        args = dict(builds=self.builds, assets=self.assets, output=self.output,
                    template=self.template, synthetic_fixture_only=True)
        args.update(changes)
        return pack.prepare_package(**args)

    def mutate(self, profile="msu_standard_ntsc", action=None, **changes):
        path = self.builds[profile]
        value = json.loads(path.read_text())
        value.update(changes)
        if action:
            action(value)
        path.write_bytes(pack.json_bytes(value))

    def refused(self, pattern, **changes):
        with self.assertRaisesRegex(pack.PackageError, pattern):
            self.prepare(**changes)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".experiment.staging-*")))

    def rehash(self, profile):
        self.mutate(profile, outputs=pack.inventory({
            name: (self.builds[profile].parent / name).read_bytes()
            for name in ("snes_pocket.rbf", pack.PROFILES[profile][0])}))

    def test_complete_synthetic_only_and_unchanged_inputs(self):
        inputs = [self.template, self.assets, self.root / "SYNTHETIC-FIXTURES"]
        before = {str(path): snapshot(path) for path in inputs}
        manifest = self.prepare()
        self.assertEqual(manifest["state"], "synthetic_fixture_only")
        self.assertFalse((self.output / "sd").exists())
        prefix = self.output / "synthetic-not-for-hardware"
        for profile, (source, dest, _, _) in pack.PROFILES.items():
            self.assertEqual((prefix / pack.CORE / dest).read_bytes(),
                             (self.builds[profile].parent / source).read_bytes())
        for key in ("compiler_run_authenticated", "loadability_verified", "timing_verified",
                    "hardware_verified", "ready_for_release", "common_saves_isolated"):
            self.assertIs(manifest[key], False)
        self.assertTrue(manifest["package_complete"])
        self.assertTrue(manifest["committed_hardware_inputs_match"])
        for path in inputs:
            self.assertEqual(snapshot(path), before[str(path)])
        self.assertIn("SYNTHETIC FIXTURE ONLY", (self.output / "README-FIRST.txt").read_text())
        self.assertIn("Saves/snes/common", (self.output / "README-FIRST.txt").read_text())
        self.assertIn("blank/spare SD", (self.output / "README-FIRST.txt").read_text())

    def test_identity_mapping_and_features_preserved(self):
        self.prepare()
        directory = self.output / "synthetic-not-for-hardware" / pack.CORE
        original = json.loads((self.template / pack.legacy.CORE / "core.json").read_text())
        rewritten = json.loads((directory / "core.json").read_text())
        old_meta = original["core"].pop("metadata")
        new_meta = rewritten["core"].pop("metadata")
        self.assertEqual(original, rewritten)
        self.assertEqual(new_meta["author"], old_meta["author"])
        self.assertEqual(new_meta["url"], old_meta["url"])
        self.assertEqual(pack.CORE.name, new_meta["author"] + "." + new_meta["shortname"])
        self.assertLessEqual(len(new_meta["shortname"]), 31)
        self.assertLessEqual(len(new_meta["description"]), 63)
        self.assertLessEqual(len(new_meta["version"]), 31)
        self.assertIn("EXPERIMENTAL", new_meta["description"])
        for path in (self.template / pack.legacy.CORE).iterdir():
            if path.name not in ("core.json", "info.txt"):
                self.assertEqual((directory / path.name).read_bytes(), path.read_bytes())
        self.assertFalse((directory.parent / "agg23.SNES").exists())
        self.assertIn("srg320", (directory / "info.txt").read_text())

    def test_inventory_reproducibility_and_provenance(self):
        manifest = self.prepare()
        for name, record in manifest["files"].items():
            self.assertEqual(record, pack.inventory({name: (self.output / name).read_bytes()})[name])
        other = self.root / "second-output"
        self.assertEqual(manifest, self.prepare(output=other))
        self.assertEqual(snapshot(self.output), snapshot(other))
        for profile in self.builds:
            self.assertEqual((self.output / "evidence" / profile / "build.json").read_bytes(), self.builds[profile].read_bytes())
        hardware = json.loads((self.output / "evidence/hardware-inputs.json").read_text())
        for name in ("generate.tcl", "tools/build_msu1.sh", "target/pocket/core_top.sv", "projects/snes_pocket.sdc"):
            self.assertIn(name, hardware)

    def test_missing_profile(self):
        self.refused("all three standard", builds={p: v for p, v in self.builds.items() if p != "standard_ntsc_spc"})

    def test_wrong_legacy_profile(self):
        self.mutate(profile="standard_ntsc_spc", action=lambda m: m.update(profile="ntsc_spc"))
        self.refused("profile/device mismatch")

    def test_bad_states(self):
        for state in ("running", "compile_failed", "compile_succeeded", "bitstream_generated_unverified", None):
            with self.subTest(state=state):
                self.mutate(state=state)
                self.refused("build state")

    def test_bad_compile_exit_device_and_flags(self):
        for code in (None, False, "0", 1):
            self.mutate(compile_exit_code=code)
            self.refused("compile_exit_code")
        self.mutate(compile_exit_code=0, device="5CEBA2F17A7")
        self.refused("profile/device")
        self.mutate(device="5CEBA4F23C8", hardware_verified="false")
        self.refused("hardware_verified")
        self.mutate(hardware_verified=False, timing_verified=0)
        self.refused("timing_verified")

    def test_dirty_source_rejected(self):
        self.mutate(source_status=" M target/pocket/core_top.sv")
        self.refused("clean source checkout")

    def test_mixed_source_rejected(self):
        self.mutate(source_commit="a" * 40)
        self.refused("mixed source commits")

    def test_missing_and_short_git_evidence_rejected(self):
        self.mutate(source_commit="982f103")
        self.refused("full lowercase")
        for p in self.builds:
            self.mutate(p, source_commit="a" * 40)
        self.refused("source Git evidence")

    def test_tree_object_cannot_masquerade_as_source_commit(self):
        tree = pack.git(ROOT, "rev-parse", pack.BASELINE + "^{tree}").decode().strip()
        for profile in self.builds:
            self.mutate(profile, source_commit=tree)
        self.refused("must identify a commit")

    def test_old_hardware_revision_rejected(self):
        old = pack.git(ROOT, "rev-parse", pack.BASELINE + "^").decode().strip()
        for p in self.builds:
            self.mutate(p, source_commit=old)
        self.refused("hardware inputs differ")

    def final_candidate_sources(self, label="candidate-64b5b51"):
        identity, _ = pack.reviewed_source(label)
        for profile in self.builds:
            self.mutate(profile, source_commit=identity["build_source_commit"])
        return identity

    def test_registered_source_identity_fingerprints_are_explicit(self):
        for label in ("baseline-982f103", "candidate-64b5b51", "candidate-0da938e", "candidate-e71101f"):
            identity, _ = pack.reviewed_source(label)
            hardware = pack.git_files(ROOT, identity["hardware_commit"], pack.HARDWARE_PATHS)
            source = pack.git_files(ROOT, identity["build_source_commit"], pack.HARDWARE_PATHS)
            self.assertEqual(hardware, source)
            self.assertEqual(pack.digest(pack.json_bytes(pack.inventory(hardware))), identity["hardware_inputs_sha256"])
        self.assertEqual(pack.reviewed_source("baseline-982f103")[0]["hardware_commit"], pack.BASELINE)
        self.assertEqual(pack.reviewed_source("candidate-64b5b51")[0]["build_source_commit"],
                         "aed6dd78f7852304d25c396763f47ae14d549b21")

    def test_new_candidate_synthetic_package_records_selected_identity(self):
        identity = self.final_candidate_sources()
        assets = self.root / "candidate-original-homebrew"
        homebrew.write_assets(assets, basename=identity["homebrew_basename"])
        result = self.prepare(source_identity="candidate-64b5b51", assets=assets)
        self.assertEqual(result["reviewed_source_identity"], "candidate-64b5b51")
        self.assertEqual(result["frozen_hardware_commit"], identity["hardware_commit"])
        self.assertEqual(result["hardware_inputs_sha256"], identity["hardware_inputs_sha256"])
        self.assertEqual(result["template_and_homebrew_commit"], pack.BASELINE)
        self.assertEqual(result["reviewed_source"], identity)
        self.assertEqual(result["state"], "synthetic_fixture_only")
        self.assertFalse(result["ready_for_release"])
        self.assertFalse((self.output / "sd").exists())
        directory = self.output / "synthetic-not-for-hardware"
        core = json.loads((directory / pack.CORE / "core.json").read_text())["core"]
        self.assertEqual(core["metadata"]["version"], "0.4.4-std-exp.64b5b51")
        self.assertTrue((directory / "Assets/snes/common" / identity["homebrew_basename"]).is_dir())
        self.assertEqual((self.output / "evidence/reviewed-source-identities.json").read_bytes(),
                         pack.SOURCE_IDENTITIES.read_bytes())
        self.assertFalse(list(self.output.rglob("*.sav")))

    def test_old_inputs_cannot_use_new_identity(self):
        self.refused("hardware inputs differ from reviewed source identity", source_identity="candidate-64b5b51")

    def test_new_inputs_cannot_use_old_identity(self):
        self.final_candidate_sources()
        self.refused("hardware inputs differ from reviewed source identity", source_identity="baseline-982f103")

    def test_mixed_original_and_final_sources_refused(self):
        identity, _ = pack.reviewed_source("candidate-64b5b51")
        self.mutate("standard_ntsc_spc", source_commit=identity["build_source_commit"])
        self.refused("mixed source commits", source_identity="candidate-64b5b51")

    def test_same_hardware_unreviewed_build_commit_refused(self):
        identity = self.final_candidate_sources()
        for profile in self.builds:
            self.mutate(profile, source_commit=identity["hardware_commit"])
        self.refused("build source commit is not the reviewed source identity", source_identity="candidate-64b5b51")

    def test_reviewed_fingerprint_disagreement_cannot_be_ignored(self):
        identity = self.final_candidate_sources()
        changed = dict(identity, hardware_inputs_sha256="0" * 64)
        with mock.patch.object(pack, "reviewed_source", return_value=(changed, b"SYNTHETIC IN-MEMORY GATE TEST")):
            self.refused("hardware inputs differ from reviewed source identity", source_identity="candidate-64b5b51")

    def test_unknown_source_identity_is_not_a_baseline_override(self):
        for label in ("arbitrary", pack.BASELINE, "64b5b51", "--skip-validation"):
            self.refused("unknown reviewed source identity", source_identity=label)

    def test_candidate_still_checks_bitstream_hash_and_profile(self):
        self.final_candidate_sources()
        path = self.builds["standard_ntsc_spc"].parent / "snes_standard_spc.rev"
        original = path.read_bytes()
        path.write_bytes(b"!" + original[1:])
        self.refused("SHA-256 mismatch", source_identity="candidate-64b5b51")
        path.write_bytes(original)
        self.mutate("standard_ntsc_spc", action=lambda m: m.update(profile="msu_standard_ntsc"))
        self.refused("profile/device mismatch", source_identity="candidate-64b5b51")

    def test_cli_requires_explicit_source_identity(self):
        args = [sys.executable, str(ROOT / "tools/package_standard_msu1.py")]
        for profile, path in self.builds.items():
            args += ["--" + profile.replace("_", "-"), str(path)]
        args += ["--assets", str(self.assets), "--output", str(self.output)]
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--source-identity", result.stderr)
        self.assertFalse(self.output.exists())

    def test_latest_candidate_includes_new_wram_helper_in_fingerprint(self):
        identity, _ = pack.reviewed_source("candidate-0da938e")
        self.assertEqual(identity["build_source_commit"], "0da938eb1eaaefc6ff23347568cd69a8240e4f37")
        hardware = pack.git_files(ROOT, identity["hardware_commit"], pack.HARDWARE_PATHS)
        self.assertEqual(len(hardware), 172)
        self.assertEqual(pack.inventory(hardware)["target/pocket/standard_wram_state.tcl"],
                         {"bytes": 1450, "sha256": "346a0df40700c1e5497f07f52bbd0abcfc4fd9177ad0c59a9a9f238e2d1f264a"})
        self.assertIn(b"configure_standard_wram_state $standard_sdram_profile", hardware["generate.tcl"])
        self.assertEqual(pack.digest(pack.json_bytes(pack.inventory(hardware))),
                         "e639440406e489e7ac46dce032baa1b13ef7878593a88f40860742255601a723")

    def test_latest_candidate_synthetic_output_records_exact_identity(self):
        identity = self.final_candidate_sources("candidate-0da938e")
        assets = self.root / "latest-candidate-homebrew"
        homebrew.write_assets(assets, basename=identity["homebrew_basename"])
        result = self.prepare(source_identity="candidate-0da938e", assets=assets)
        self.assertEqual(result["reviewed_source"], identity)
        self.assertEqual(result["hardware_inputs_sha256"], identity["hardware_inputs_sha256"])
        self.assertEqual(result["state"], "synthetic_fixture_only")
        self.assertFalse((self.output / "sd").exists())
        for key in ("ready_for_release", "timing_verified", "hardware_verified", "loadability_verified", "common_saves_isolated"):
            self.assertIs(result[key], False)
        core = json.loads((self.output / "synthetic-not-for-hardware" / pack.CORE / "core.json").read_text())["core"]
        self.assertEqual(core["metadata"]["version"], "0.4.4-std-exp.0da938e")
        for profile in pack.PROFILES:
            self.assertEqual(result["profiles"][profile]["source_commit"], identity["build_source_commit"])
        self.assertFalse(list(self.output.rglob("*.sav")))

    def test_latest_identity_refuses_previous_candidate_inputs(self):
        self.final_candidate_sources("candidate-64b5b51")
        self.refused("hardware inputs differ", source_identity="candidate-0da938e")

    def test_latest_inputs_cannot_fall_back_to_prior_identities(self):
        self.final_candidate_sources("candidate-0da938e")
        for label in ("baseline-982f103", "candidate-64b5b51"):
            self.refused("hardware inputs differ", source_identity=label)

    def test_latest_identity_refuses_mixed_candidate_commits(self):
        self.final_candidate_sources("candidate-0da938e")
        previous, _ = pack.reviewed_source("candidate-64b5b51")
        self.mutate("standard_ntsc_spc", source_commit=previous["build_source_commit"])
        self.refused("mixed source commits", source_identity="candidate-0da938e")

    def test_latest_identity_requires_exact_commit_even_with_matching_hardware(self):
        identity = self.final_candidate_sources("candidate-0da938e")
        for profile in self.builds:
            self.mutate(profile, source_commit=identity["hardware_commit"])
        self.refused("build source commit is not the reviewed source identity", source_identity="candidate-0da938e")

    def test_latest_identity_cannot_ignore_omitted_helper(self):
        self.final_candidate_sources("candidate-0da938e")
        original = pack.git_files
        def omitted_helper(repository, commit, paths):
            files = original(repository, commit, paths)
            files.pop("target/pocket/standard_wram_state.tcl", None)
            return files
        # Both compared inventories lose the same file. The pinned digest still
        # rejects the incomplete input set; this is an in-memory negative test.
        with mock.patch.object(pack, "git_files", side_effect=omitted_helper):
            self.refused("hardware inputs differ", source_identity="candidate-0da938e")

    def test_latest_candidate_retains_hash_and_profile_gates(self):
        self.final_candidate_sources("candidate-0da938e")
        path = self.builds["standard_ntsc_spc"].parent / "snes_standard_spc.rev"
        original = path.read_bytes()
        path.write_bytes(b"!" + original[1:])
        self.refused("SHA-256 mismatch", source_identity="candidate-0da938e")
        path.write_bytes(original)
        self.mutate("standard_ntsc_spc", action=lambda m: m.update(profile="msu_standard_ntsc"))
        self.refused("profile/device mismatch", source_identity="candidate-0da938e")

    def write_controlled_report(self, profile, settings=None):
        identity, _ = pack.reviewed_source("candidate-e71101f")
        settings = dict(identity["expected_fitter_settings"][profile] if settings is None else settings)
        data = (pack.FIXTURE_MARKER + b"fitter-settings/" + profile.encode() + b"/\n" +
                b"Fitter report for snes_pocket\n; Fitter Summary ;\n"
                b"; Fitter Status ; Successful - SYNTHETIC PARSER FIXTURE ;\n"
                b"; Device ; 5CEBA4F23C8 ;\n; Revision Name ; snes_pocket ;\n"
                b"; Top-level Entity Name ; apf_top ;\n; Fitter Settings ;\n"
                b"; Device ; 5CEBA4F23C8 ; default ;\n" +
                "".join(f"; {key} ; {value} ; Default Value ;\n" for key, value in settings.items()).encode() +
                b"; Other Report Section ;\nSynthetic fixture only, not a real fit.\n")
        path = self.builds[profile].parent / pack.FITTER_REPORT
        path.write_bytes(data)
        self.mutate(profile, actual_fitter_settings=settings,
                    fitter_settings_report={"file": pack.FITTER_REPORT, "bytes": len(data), "sha256": pack.digest(data)})
        return path

    def controlled_sources(self):
        identity = self.final_candidate_sources("candidate-e71101f")
        for profile in self.builds:
            self.write_controlled_report(profile)
        return identity

    def rehash_fitter(self, profile):
        path = self.builds[profile].parent / pack.FITTER_REPORT
        data = path.read_bytes()
        self.mutate(profile, fitter_settings_report={"file": path.name, "bytes": len(data), "sha256": pack.digest(data)})

    def test_controlled_identity_pins_wrapper_helper_and_exact_source(self):
        identity, _ = pack.reviewed_source("candidate-e71101f")
        self.assertEqual(identity["build_source_commit"], "e71101fd06a452da53cb0924e1d3701f53133435")
        files = pack.git_files(ROOT, identity["build_source_commit"], pack.HARDWARE_PATHS)
        self.assertEqual(len(files), 173)
        self.assertIn("target/pocket/standard_pal_fit.tcl", files)
        self.assertIn("tools/build_msu1.sh", files)
        self.assertEqual(pack.digest(pack.json_bytes(pack.inventory(files))), identity["hardware_inputs_sha256"])
        self.assertEqual(identity["expected_fitter_settings"]["msu_standard_pal"]["Fitter Initial Placement Seed"], "2")
        for profile in ("msu_standard_ntsc", "standard_ntsc_spc"):
            self.assertEqual(identity["expected_fitter_settings"][profile]["Fitter Initial Placement Seed"], "1")

    def test_controlled_synthetic_package_copies_bound_full_reports(self):
        identity = self.controlled_sources()
        assets = self.root / "controlled-original-homebrew"
        homebrew.write_assets(assets, basename=identity["homebrew_basename"])
        result = self.prepare(source_identity="candidate-e71101f", assets=assets)
        self.assertEqual(result["state"], "synthetic_fixture_only")
        self.assertFalse((self.output / "sd").exists())
        for key in ("ready_for_release", "timing_verified", "hardware_verified", "loadability_verified"):
            self.assertIs(result[key], False)
        for profile in pack.PROFILES:
            original = (self.builds[profile].parent / pack.FITTER_REPORT).read_bytes()
            self.assertEqual((self.output / "evidence" / profile / pack.FITTER_REPORT).read_bytes(), original)
            self.assertEqual(result["profiles"][profile]["checked_fitter_settings"], identity["expected_fitter_settings"][profile])
            self.assertEqual(result["profiles"][profile]["fitter_settings_report"]["sha256"], pack.digest(original))

    def test_controlled_missing_receipt_and_missing_full_report(self):
        self.controlled_sources()
        self.mutate("msu_standard_pal", action=lambda m: m.pop("fitter_settings_report"))
        self.refused("required fitter_settings_report", source_identity="candidate-e71101f")
        path = self.write_controlled_report("msu_standard_pal")
        path.unlink()
        self.refused("regular file is missing", source_identity="candidate-e71101f")

    def test_controlled_receipt_filename_cannot_escape_archive(self):
        self.controlled_sources()
        for name in ("../other.fit.rpt", "/tmp/report", "snes_pocket.fit.summary", "other.fit.rpt"):
            self.mutate("msu_standard_pal", action=lambda m: m["fitter_settings_report"].update(file=name))
            self.refused("adjacent snes_pocket.fit.rpt", source_identity="candidate-e71101f")

    def test_controlled_receipt_size_hash_and_type(self):
        self.controlled_sources()
        for change, message in (({"bytes": False}, "size mismatch"), ({"bytes": 1}, "size mismatch"),
                                ({"sha256": "0" * 64}, "SHA-256 mismatch")):
            self.write_controlled_report("msu_standard_pal")
            self.mutate("msu_standard_pal", action=lambda m: m["fitter_settings_report"].update(change))
            self.refused(message, source_identity="candidate-e71101f")

    def test_controlled_changed_actual_report_cannot_keep_old_receipt(self):
        self.controlled_sources()
        path = self.builds["msu_standard_pal"].parent / pack.FITTER_REPORT
        data = path.read_bytes()
        path.write_bytes(data.replace(b"Standard Fit", b"STANDARD FIT"))  # same size, different bytes
        self.refused("SHA-256 mismatch", source_identity="candidate-e71101f")

    def test_controlled_declared_settings_must_match_actual_report(self):
        self.controlled_sources()
        self.mutate("msu_standard_pal", action=lambda m: m["actual_fitter_settings"].update({"Fitter Initial Placement Seed": "1"}))
        self.refused("disagrees with full fitter report", source_identity="candidate-e71101f")

    def test_controlled_declared_settings_exact_shape_and_types(self):
        self.controlled_sources()
        for change in (None, {}, {"Fitter Initial Placement Seed": 2}):
            self.mutate("msu_standard_pal", actual_fitter_settings=change)
            self.refused("all four exact string", source_identity="candidate-e71101f")
        self.write_controlled_report("msu_standard_pal")
        self.mutate("msu_standard_pal", action=lambda m: m["actual_fitter_settings"].update(extra="value"))
        self.refused("all four exact string", source_identity="candidate-e71101f")

    def test_controlled_wrong_seed_effort_hold_or_multicorner_rejected_per_profile(self):
        identity = self.controlled_sources()
        for profile in pack.PROFILES:
            for key in pack.FITTER_SETTING_NAMES:
                with self.subTest(profile=profile, key=key):
                    wrong = dict(identity["expected_fitter_settings"][profile])
                    wrong[key] = {"Fitter Initial Placement Seed": "9", "Fitter Effort": "Fast Fit",
                                  "Optimize Hold Timing": "Off", "Optimize Multi-Corner Timing": "Off"}[key]
                    # Receipt, declared settings and actual report agree; only source policy catches it.
                    self.write_controlled_report(profile, wrong)
                    self.refused("violate reviewed source policy", source_identity="candidate-e71101f")
                    self.write_controlled_report(profile)

    def test_controlled_pal_settings_cannot_be_used_for_other_profiles(self):
        identity = self.controlled_sources()
        for profile in ("msu_standard_ntsc", "standard_ntsc_spc"):
            self.write_controlled_report(profile, identity["expected_fitter_settings"]["msu_standard_pal"])
            self.refused("violate reviewed source policy", source_identity="candidate-e71101f")
            self.write_controlled_report(profile)
        self.write_controlled_report("msu_standard_pal", identity["expected_fitter_settings"]["msu_standard_ntsc"])
        self.refused("violate reviewed source policy", source_identity="candidate-e71101f")

    def test_controlled_missing_or_duplicate_setting_rows(self):
        self.controlled_sources()
        for extra in (False, True):
            path = self.write_controlled_report("msu_standard_pal")
            text = path.read_text()
            row = "; Fitter Initial Placement Seed ; 2 ; Default Value ;\n"
            path.write_text(text.replace(row, row + row if extra else ""))
            self.rehash_fitter("msu_standard_pal")
            self.refused("one unambiguous setting row", source_identity="candidate-e71101f")

    def test_controlled_full_report_identity_and_status_required(self):
        self.controlled_sources()
        for before, after, message in (("5CEBA4F23C8", "WRONGDEVICE", "identity mismatch"),
                                       ("; snes_pocket ;", "; other ;", "identity mismatch"),
                                       ("; apf_top ;", "; wrong_top ;", "identity mismatch"),
                                       ("Successful -", "Failed -", "one successful fitting"),
                                       ("Fitter report for snes_pocket", "Summary report", "header"),
                                       ("; Fitter Settings ;", "; Absent Settings ;", "one section")):
            path = self.write_controlled_report("msu_standard_pal")
            path.write_text(path.read_text().replace(before, after))
            self.rehash_fitter("msu_standard_pal")
            self.refused(message, source_identity="candidate-e71101f")

    def test_controlled_duplicate_status_and_sections_fail_closed(self):
        self.controlled_sources()
        for token, message in (("; Fitter Status ; Successful - SYNTHETIC PARSER FIXTURE ;\n", "one successful fitting"),
                               ("; Fitter Settings ;\n", "one section")):
            path = self.write_controlled_report("msu_standard_pal")
            path.write_text(path.read_text().replace(token, token + token))
            self.rehash_fitter("msu_standard_pal")
            self.refused(message, source_identity="candidate-e71101f")

    def test_controlled_report_symlink_and_marker_stripping_refused(self):
        self.controlled_sources()
        path = self.builds["msu_standard_pal"].parent / pack.FITTER_REPORT
        path.unlink()
        path.symlink_to(self.builds["msu_standard_ntsc"].parent / pack.FITTER_REPORT)
        self.refused("symlink", source_identity="candidate-e71101f")
        path.unlink(); self.write_controlled_report("msu_standard_pal")
        path.write_bytes(path.read_bytes().split(b"\n", 1)[1])
        self.rehash_fitter("msu_standard_pal")
        self.refused("explicit profile marker", source_identity="candidate-e71101f")

    def test_controlled_report_legacy_display_encoding_preserved(self):
        identity = self.controlled_sources()
        path = self.builds["msu_standard_pal"].parent / pack.FITTER_REPORT
        path.write_bytes(path.read_bytes() + b"Temperature unit: \xb0C\n")
        self.rehash_fitter("msu_standard_pal")
        checked = pack.read_build(self.builds["msu_standard_pal"], "msu_standard_pal", synthetic_fixture_only=True)
        self.assertEqual(checked["reports"][pack.FITTER_REPORT], path.read_bytes())
        self.assertEqual(checked["checked_fitter_settings"], identity["expected_fitter_settings"]["msu_standard_pal"])
        marker, body = path.read_bytes().split(b"\n", 1)
        path.write_bytes(marker + b"\n" + body.replace(b"\n", b"\r\n"))
        self.rehash_fitter("msu_standard_pal")
        checked = pack.read_build(self.builds["msu_standard_pal"], "msu_standard_pal", synthetic_fixture_only=True)
        self.assertEqual(checked["reports"][pack.FITTER_REPORT], path.read_bytes())

    def test_controlled_direct_read_cannot_skip_receipt(self):
        self.final_candidate_sources("candidate-e71101f")
        with self.assertRaisesRegex(pack.PackageError, "required fitter_settings_report"):
            pack.read_build(self.builds["msu_standard_ntsc"], "msu_standard_ntsc", synthetic_fixture_only=True)

    def test_controlled_catalog_policy_cannot_be_removed(self):
        self.controlled_sources()
        config = json.loads(pack.SOURCE_IDENTITIES.read_text())
        config["identities"]["candidate-e71101f"].pop("expected_fitter_settings")
        path = self.root / "SYNTHETIC-catalog-policy-negative.json"
        path.write_bytes(pack.json_bytes(config))
        with mock.patch.object(pack, "SOURCE_IDENTITIES", path):
            self.refused("source-specific fitter receipt policy", source_identity="candidate-e71101f")

    def test_controlled_catalog_requires_every_profile_and_safe_hold_flags(self):
        for profile, key in (("msu_standard_pal", None), ("msu_standard_ntsc", "Optimize Hold Timing"),
                             ("standard_ntsc_spc", "Optimize Multi-Corner Timing")):
            config = json.loads(pack.SOURCE_IDENTITIES.read_text())
            policy = config["identities"]["candidate-e71101f"]["expected_fitter_settings"]
            if key is None:
                del policy[profile]
                message = "all three exact profiles"
            else:
                policy[profile][key] = "Off"
                message = "weakened hold/multicorner"
            path = self.root / "SYNTHETIC-catalog-policy-negative.json"
            path.write_bytes(pack.json_bytes(config))
            with mock.patch.object(pack, "SOURCE_IDENTITIES", path):
                self.refused(message, source_identity="candidate-e71101f")

    def test_controlled_catalog_cannot_swap_seed_or_effort_between_profiles(self):
        for profile in pack.PROFILES:
            for key in ("Fitter Initial Placement Seed", "Fitter Effort"):
                with self.subTest(profile=profile, key=key):
                    config = json.loads(pack.SOURCE_IDENTITIES.read_text())
                    policy = config["identities"]["candidate-e71101f"]["expected_fitter_settings"]
                    donor = "msu_standard_ntsc" if profile == "msu_standard_pal" else "msu_standard_pal"
                    policy[profile][key] = policy[donor][key]
                    path = self.root / "SYNTHETIC-catalog-profile-negative.json"
                    path.write_bytes(pack.json_bytes(config))
                    with mock.patch.object(pack, "SOURCE_IDENTITIES", path):
                        self.refused("source/profile fitter policy", source_identity="candidate-e71101f")

    def test_controlled_identity_rejects_mixed_sources_and_old_identity_fallback(self):
        self.controlled_sources()
        self.refused("hardware inputs differ", source_identity="candidate-0da938e")
        old, _ = pack.reviewed_source("candidate-0da938e")
        self.mutate("standard_ntsc_spc", source_commit=old["build_source_commit"])
        self.refused("mixed source commits", source_identity="candidate-e71101f")

    def test_controlled_other_profile_parameters_remain_checked(self):
        self.controlled_sources()
        self.mutate("standard_ntsc_spc", action=lambda m: m.update(profile="msu_standard_ntsc"))
        self.refused("profile/device mismatch", source_identity="candidate-e71101f")

    def test_controlled_synthetic_report_cannot_be_real_evidence(self):
        identity = self.controlled_sources()
        manifest = json.loads(self.builds["msu_standard_pal"].read_text())
        with self.assertRaisesRegex(pack.PackageError, "synthetic/forged full fitter"):
            pack.verify_fitter_receipt(self.builds["msu_standard_pal"].parent, manifest, "msu_standard_pal",
                                       identity["expected_fitter_settings"]["msu_standard_pal"], fixture=False)

    def test_old_identities_keep_old_schema_and_do_not_require_new_receipt(self):
        old_raw = pack.git(ROOT, "show", "e71101fd06a452da53cb0924e1d3701f53133435:tools/standard_msu1_reviewed_sources.json")
        previous = json.loads(old_raw)["identities"]
        for label, old in previous.items():
            identity, _ = pack.reviewed_source(label)
            self.assertEqual(identity, old)
            self.assertNotIn("expected_fitter_settings", identity)
        checked = pack.read_build(self.builds["msu_standard_ntsc"], "msu_standard_ntsc", synthetic_fixture_only=True)
        self.assertIsNone(checked["checked_fitter_settings"])
        self.assertNotIn(pack.FITTER_REPORT, checked["reports"])

    def test_fixture_no_cli_escape_hatch(self):
        self.refused("synthetic fixture refused", synthetic_fixture_only=False)
        args = [sys.executable, str(ROOT / "tools/package_standard_msu1.py")]
        for p, path in self.builds.items():
            args += ["--" + p.replace("_", "-"), str(path)]
        args += ["--source-identity", pack.DEFAULT_SOURCE_IDENTITY, "--assets", str(self.assets), "--output", str(self.output)]
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("No complete or loadable package is claimed", result.stderr)
        self.assertFalse(self.output.exists())
        result = subprocess.run(args + ["--allow-test-fixtures"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_real_incomplete_or_reversed_timestamps_refused(self):
        self.mutate(test_fixture=False, state="bitstream_generated_unverified", quartus_sh="/real-looking/quartus_sh")
        for finish in (None, "2026-10-03T00:00:00+00:00", "2026-10-04T00:00:01"):
            self.mutate(finished_utc=finish)
            self.refused("ordered started_utc/finished_utc")

    def test_forged_fixture_flag_stripping_rejected(self):
        self.mutate(test_fixture=False, state="bitstream_generated_unverified", quartus_sh="/real-looking/quartus_sh")
        self.refused("tiny/forged fixture")

    def test_relabelled_fixture_requires_marker_and_correct_profile(self):
        self.mutate(quartus_sh="quartus_sh")
        self.refused("explicit marker/profile")

    def test_forged_full_size_fixture_marker_rejected(self):
        profile = "msu_standard_ntsc"
        directory = self.builds[profile].parent
        data = (pack.FIXTURE_MARKER + bytes(pack.MIN_REAL_RBF_BYTES))[:pack.MIN_REAL_RBF_BYTES]
        (directory / "snes_pocket.rbf").write_bytes(data)
        (directory / pack.PROFILES[profile][0]).write_bytes(data.translate(pack.REVERSE_BYTE))
        self.rehash(profile)
        self.mutate(test_fixture=False, state="bitstream_generated_unverified", quartus_sh="/real-looking/quartus_sh")
        self.refused("synthetic/forged build")

    def test_duplicate_or_relabelled_spc_main_image_rejected(self):
        main = self.builds["msu_standard_ntsc"].parent
        spc = self.builds["standard_ntsc_spc"].parent
        (spc / "snes_pocket.rbf").write_bytes((main / "snes_pocket.rbf").read_bytes())
        (spc / "snes_standard_spc.rev").write_bytes((main / "snes_msu_standard_ntsc.rev").read_bytes())
        self.rehash("standard_ntsc_spc")
        self.refused("explicit marker/profile")

    def test_hash_and_size_and_conversion_checked(self):
        profile = "msu_standard_ntsc"
        path = self.builds[profile].parent / pack.PROFILES[profile][0]
        data = path.read_bytes()
        path.write_bytes(b"!" + data[1:])
        self.refused("SHA-256 mismatch")
        path.write_bytes(data + b"!")
        self.refused("size mismatch")
        self.rehash(profile)
        self.refused("bytewise bit reversal")

    def test_rbf_hash_checked(self):
        path = self.builds["msu_standard_ntsc"].parent / "snes_pocket.rbf"
        data = path.read_bytes()
        path.write_bytes(b"!" + data[1:])
        self.refused("SHA-256 mismatch")

    def test_empty_missing_and_unexpected_outputs(self):
        self.mutate(action=lambda m: m["outputs"].update({"unexpected.rev": {}}))
        self.refused("exact RBF/REV")
        self.mutate(action=lambda m: m["outputs"].pop("unexpected.rev"))
        path = self.builds["standard_ntsc_spc"].parent / "snes_standard_spc.rev"
        path.write_bytes(b"")
        self.refused("file is empty")
        path.unlink()
        self.refused("regular file is missing")

    def test_existing_output_untouched(self):
        self.output.mkdir()
        (self.output / "saves").write_bytes(b"PRECIOUS")
        with self.assertRaisesRegex(pack.PackageError, "overwrite"):
            self.prepare()
        self.assertEqual((self.output / "saves").read_bytes(), b"PRECIOUS")

    def test_nested_missing_parent_outputs(self):
        for source in (self.template, self.assets, self.builds["standard_ntsc_spc"].parent):
            with self.assertRaisesRegex(pack.PackageError, "outside input"):
                self.prepare(output=source / "nested")
            self.assertFalse((source / "nested").exists())
        with self.assertRaisesRegex(pack.PackageError, "parent must already exist"):
            self.prepare(output=self.root / "missing" / "out")

    def test_output_symlink_and_parent_symlink(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        for target in (alias / "out", alias):
            with self.assertRaisesRegex(pack.PackageError, "symlink"):
                self.prepare(output=target)
        self.assertFalse((self.root / "out").exists())

    def test_build_ancestor_symlink(self):
        alias = self.root / "alias"
        alias.symlink_to(self.builds["msu_standard_ntsc"].parent, target_is_directory=True)
        builds = dict(self.builds, msu_standard_ntsc=alias / "build.json")
        self.refused("symlink", builds=builds)

    def test_template_asset_and_bitstream_symlinks(self):
        for path in (self.template / pack.legacy.CORE / "loader.bin",
                     self.assets / (pack.BASENAME + ".msu"),
                     self.builds["standard_ntsc_spc"].parent / "snes_standard_spc.rev"):
            original = path.read_bytes()
            path.unlink()
            path.symlink_to(self.builds["msu_standard_ntsc"])
            self.refused("symlink")
            path.unlink()
            path.write_bytes(original)

    def test_all_configuration_features_pinned(self):
        for name in ("interact.json", "input.json", "video.json", "loader.bin", "info.txt"):
            path = self.template / pack.legacy.CORE / name
            original = path.read_bytes()
            path.write_bytes(original + b" ")
            self.refused("exactly match frozen source")
            path.write_bytes(original)

    def test_spc_mode_cannot_be_removed_or_swapped(self):
        path = self.template / pack.legacy.CORE / "core.json"
        obj = json.loads(path.read_text())
        obj["core"]["cores"][1]["filename"] = "snes_main.rev"
        path.write_bytes(pack.json_bytes(obj))
        self.refused("retain exactly")

    def test_third_party_assets_and_bad_basename_refused(self):
        (self.assets / "commercial.sfc").write_bytes(b"DO NOT COPY")
        self.refused("only the original generated asset set")
        for basename in ("MSU Test", "../MSU1-STD-x", "MSU1-STD-evil/name"):
            self.refused("distinctive MSU1-STD-", basename=basename)

    def test_rehashed_audio_cannot_replace_original_homebrew(self):
        path = self.assets / (pack.BASENAME + "-1.pcm")
        data = path.read_bytes()
        changed = data[:-1] + bytes([data[-1] ^ 1])
        path.write_bytes(changed)
        manifest_path = self.assets / (pack.BASENAME + ".manifest.json")
        manifest = json.loads(manifest_path.read_text())
        manifest["files"][path.name]["sha256"] = pack.digest(changed)
        manifest_path.write_bytes(pack.json_bytes(manifest))
        self.refused("differs from this checkout")

    def test_complete_homebrew_manifest_and_symbols_bytes_pinned(self):
        path = self.assets / (pack.BASENAME + ".manifest.json")
        original = path.read_bytes()
        for change in ({"data_formula": "INCORRECT"}, {"extra_review_probe": True}):
            value = json.loads(original)
            value.update(change)
            path.write_bytes(pack.json_bytes(value))
            self.refused("exactly match regenerated original")
        path.write_bytes(original)
        symbols = self.assets / (pack.BASENAME + ".symbols.json")
        symbols.write_text(json.dumps(json.loads(symbols.read_text())))
        self.refused("exactly match regenerated original")

    def test_actual_duplicate_bitstream_gate(self):
        original = pack.read_build
        def modified_record(path, profile, **kwargs):
            record = original(path, profile, **kwargs)
            record["rbf_sha256"] = "a" * 64  # In-memory gate test only, no forged evidence file.
            return record
        with mock.patch.object(pack, "read_build", side_effect=modified_record):
            self.refused("duplicate profile bitstreams")

    def test_mixed_fixture_gate(self):
        original = pack.read_build
        def modified_record(path, profile, **kwargs):
            record = original(path, profile, **kwargs)
            record["fixture"] = profile != "standard_ntsc_spc"
            return record
        with mock.patch.object(pack, "read_build", side_effect=modified_record):
            self.refused("mixed real/synthetic")

    def test_duplicate_json_key(self):
        self.builds["msu_standard_ntsc"].write_text('{"state":"a", "state":"b"}')
        self.refused("duplicate JSON key")

    def test_rollback_removes_only_new_staging(self):
        before = snapshot(self.template)
        with mock.patch.object(Path, "rename", side_effect=OSError("injected move failure")):
            with self.assertRaisesRegex(OSError, "injected move"):
                self.prepare()
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".experiment.staging-*")))
        self.assertEqual(snapshot(self.template), before)

    def test_source_claims_cannot_promote_package(self):
        for p in self.builds:
            self.mutate(p, timing_verified=True, hardware_verified=True)
        result = self.prepare()
        self.assertFalse(result["ready_for_release"])
        self.assertFalse(result["hardware_verified"])
        self.assertTrue(result["profiles"]["msu_standard_ntsc"]["declared_hardware_verified"])


class ReportParserTests(unittest.TestCase):
    def parser_fixture(self, profile):
        # String-only SYNTHETIC parser cases, never on-disk compiler evidence.
        notice = "SYNTHETIC PARSER FIXTURE ONLY - NOT COMPILER EVIDENCE\n"
        msu, pal = int(profile != "standard_ntsc_spc"), int(profile == "msu_standard_pal")
        top = {"USE_STANDARD_SDRAM": 1, "USE_MSU_POCKET": msu, "PAL_PLL": pal}
        main = {"USE_STANDARD_SDRAM": 1, "USE_MSU": msu,
                **{key: msu for key in ("USE_CX4", "USE_GSU", "USE_SA1", "USE_DSPn")},
                **{key: 1-msu for key in ("USE_SDD1", "USE_SPC7110", "USE_BSX")}}
        def section(entity, values):
            return f"; Parameter Settings for User Entity Instance: {entity} ;\n" + "".join(
                f"; {key} ; '{value} ; Untyped ;\n" for key, value in values.items()) + "Note: end\n"
        return {
            "quartus-version.log": notice + "Version 21.1.1 Build 850 Example Lite Edition\n",
            "compile.log": notice + "Quartus Prime Assembler was successful. 0 errors\n",
            "snes_pocket.fit.summary": notice + "Fitter Status : Successful - example\nDevice : 5CEBA4F23C8\n",
            "snes_pocket.asm.rpt": notice + "; Assembler Status ; Successful - example ;\n; Device ; 5CEBA4F23C8 ;\n",
            "snes_pocket.flow.rpt": notice + "; Flow Status ; Successful - example ;\n; Device ; 5CEBA4F23C8 ;\n",
            "snes_pocket.map.rpt": notice + section("core_top:ic", top) + section("core_top:ic|MAIN_SNES:snes", main),
        }

    def test_each_standard_profile_parser_and_parameter_mismatch(self):
        for profile in pack.PROFILES:
            files = self.parser_fixture(profile)
            pack.verify_report_texts(files, profile)
            for key in ("USE_STANDARD_SDRAM", "USE_MSU_POCKET", "PAL_PLL", "USE_MSU",
                        "USE_CX4", "USE_GSU", "USE_SA1", "USE_DSPn", "USE_SDD1", "USE_SPC7110", "USE_BSX"):
                with self.subTest(profile=profile, key=key):
                    changed = dict(files)
                    changed["snes_pocket.map.rpt"] = changed["snes_pocket.map.rpt"].replace(f"; {key} ;", "; WRONG_NAME ;")
                    with self.assertRaisesRegex(pack.PackageError, "profile parameter mismatch|duplicate map parameter"):
                        pack.verify_report_texts(changed, profile)

    def test_report_version_status_device_and_compile_failures(self):
        files = self.parser_fixture("msu_standard_ntsc")
        mutations = [("quartus-version.log", "21.1.1", "22.1", "Quartus 21.1"),
                     ("compile.log", "was successful", "failed", "compile log"),
                     ("snes_pocket.fit.summary", "Successful", "Failed", "fitter success"),
                     ("snes_pocket.fit.summary", "5CEBA4F23C8", "OTHER", "fitter target"),
                     ("snes_pocket.asm.rpt", "Successful", "Failed", "successful Assembler"),
                     ("snes_pocket.asm.rpt", "5CEBA4F23C8", "OTHER", "target device"),
                     ("snes_pocket.flow.rpt", "Successful", "Failed", "successful Flow"),
                     ("snes_pocket.flow.rpt", "5CEBA4F23C8", "OTHER", "target device")]
        for name, before, after, message in mutations:
            with self.subTest(name=name, before=before):
                changed = dict(files)
                changed[name] = changed[name].replace(before, after)
                with self.assertRaisesRegex(pack.PackageError, message):
                    pack.verify_report_texts(changed, "msu_standard_ntsc")

    def test_exact_parameter_section_not_child_or_table_of_contents(self):
        text = """SYNTHETIC PARSER FIXTURE ONLY - NOT COMPILER EVIDENCE
144. Parameter Settings for User Entity Instance: core_top:ic
; Parameter Settings for User Entity Instance: core_top:ic ;
+---+
; Parameter Name ; Value ; Type ;
; USE_STANDARD_SDRAM ; 1 ; Untyped ;
; PAL_PLL ; '0 ; Untyped ;
Note: end
; Parameter Settings for User Entity Instance: core_top:ic|child ;
; PAL_PLL ; '1 ; Untyped ;
"""
        self.assertEqual(pack.parameter_section(text, "core_top:ic"), {"USE_STANDARD_SDRAM": "1", "PAL_PLL": "0"})
        with self.assertRaisesRegex(pack.PackageError, "missing or duplicate"):
            pack.parameter_section(text + text, "core_top:ic")
        with self.assertRaisesRegex(pack.PackageError, "missing or duplicate"):
            pack.parameter_section(text, "core_top:wrong")

    def test_fabricated_report_marker_refused(self):
        with tempfile.TemporaryDirectory(prefix="SYNTHETIC-REPORTS-") as temp:
            path = Path(temp)
            for name in pack.REPORTS:
                (path / name).write_bytes(b"SYNTHETIC FIXTURE ONLY; NOT A QUARTUS RESULT")
            with self.assertRaisesRegex(pack.PackageError, "synthetic/forged compiler"):
                pack.verify_reports(path, "msu_standard_ntsc")


if __name__ == "__main__":
    unittest.main()
