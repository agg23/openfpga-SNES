"""Test wrapper control flow with a fake tool, never FPGA synthesis results."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "build_msu1.sh"


class BuildWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="msu1-build-wrapper-")
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        self.script = self.root / "tools" / "build_msu1.sh"
        shutil.copy2(SCRIPT, self.script)
        self.fake = self.root / "quartus_sh"
        self.fake.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "if sys.argv[1:] == ['--version']:\n"
            "    print('Version 21.1.1 Build 850 TEST DOUBLE ONLY')\n"
            "    sys.exit(0)\n"
            "assert sys.argv[1:3] == ['-t', 'generate.tcl']\n"
            "out = pathlib.Path(os.environ['MSU1_OUTPUT_DIR'])\n"
            "(out / 'invocation.json').write_text(__import__('json').dumps(sys.argv[1:]))\n"
            "if not os.environ.get('MOCK_NO_RBF'):\n"
            "    (out / 'snes_pocket.rbf').write_bytes(bytes(range(256)))\n"
            "print('Synthetic wrapper test, not a Quartus result')\n"
            "sys.exit(int(os.environ.get('MOCK_EXIT', '0')))\n"
        )
        self.fake.chmod(0o755)
        self.env = dict(os.environ)
        self.env.pop("MSU1_BUILD_ROOT", None)
        self.env.update(QUARTUS_SH=str(self.fake))

    def tearDown(self):
        self.temp.cleanup()

    def run_wrapper(self, arg):
        return subprocess.run(
            ["bash", str(self.script), arg],
            env=self.env, cwd=self.root, text=True, capture_output=True,
        )

    def manifests(self):
        return list(self.root.glob("projects/output_files/msu1-builds/*/build.json"))

    def test_invalid_profile(self):
        result = self.run_wrapper("typo")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.manifests(), [])

    def test_missing_tool(self):
        self.env["QUARTUS_SH"] = str(self.root / "absent")
        result = self.run_wrapper("msu_ntsc")
        self.assertEqual(result.returncode, 127)
        self.assertIn("No fitter", result.stderr)
        self.assertEqual(self.manifests(), [])

    def test_check_does_not_build(self):
        result = self.run_wrapper("--check-tools")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.manifests(), [])

    def test_profiles_and_bit_reversal(self):
        names = {
            "msu_ntsc": "snes_msu_ntsc.rev", "msu_pal": "snes_msu_pal.rev",
            "ntsc": "snes_main.rev", "none": "snes_main.rev",
            "pal": "snes_pal.rev", "none_pal": "snes_pal.rev",
            "ntsc_spc": "snes_spc.rev",
            "msu_standard_ntsc": "snes_msu_standard_ntsc.rev",
            "msu_standard_pal": "snes_msu_standard_pal.rev",
            "standard_ntsc_spc": "snes_standard_spc.rev",
        }
        for profile, output in names.items():
            with self.subTest(profile=profile):
                result = self.run_wrapper(profile)
                self.assertEqual(result.returncode, 0, result.stderr)
                paths = list(self.root.glob(f"projects/output_files/msu1-builds/{profile}-*/build.json"))
                self.assertEqual(len(paths), 1)
                path = paths[0]
                metadata = json.loads(path.read_text())
                self.assertEqual(metadata["state"], "bitstream_generated_unverified")
                self.assertFalse(metadata["timing_verified"])
                self.assertFalse(metadata["hardware_verified"])
                data = (path.parent / output).read_bytes()
                self.assertEqual(len(data), 256)
                for value in range(256):
                    expected = sum(((value >> bit) & 1) << (7-bit) for bit in range(8))
                    self.assertEqual(data[value], expected)

    def test_compile_failure_is_preserved(self):
        self.env["MOCK_EXIT"] = "23"
        result = self.run_wrapper("msu_ntsc")
        self.assertEqual(result.returncode, 23)
        path, = self.manifests()
        data = json.loads(path.read_text())
        self.assertEqual(data["state"], "compile_failed")
        self.assertEqual(data["compile_exit_code"], 23)
        self.assertFalse(list(path.parent.glob("*.rev")))

    def test_missing_bitstream_is_not_success(self):
        self.env["MOCK_NO_RBF"] = "1"
        result = self.run_wrapper("msu_pal")
        self.assertEqual(result.returncode, 1)
        self.assertIn("without a new RBF", result.stderr)
        path, = self.manifests()
        self.assertFalse(list(path.parent.glob("*.rev")))


if __name__ == "__main__":
    unittest.main()
