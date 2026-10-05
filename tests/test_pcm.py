#!/usr/bin/env python3
"""Self-checking player/rate regressions; requires iverilog and vvp on PATH."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PCMTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for program in ("iverilog", "vvp"):
            if not shutil.which(program):
                raise unittest.SkipTest(f"{program} not installed")

    def run_testbench(self, name, *parameters):
        with tempfile.TemporaryDirectory(prefix="msu-pcm-") as work:
            binary = Path(work) / "test.vvp"
            subprocess.run(
                ["iverilog", "-g2012", "-s", name, *parameters, "-o", str(binary),
                 str(ROOT / "tests" / f"{name}.sv"),
                 str(ROOT / "rtl/msu1/msu_pcm_player.sv")], check=True)
            result = subprocess.run(["vvp", str(binary)], check=True,
                                    capture_output=True, text=True, timeout=90)
            self.assertIn("PASS", result.stdout)
            print(result.stdout.strip())

    def test_player_all_buffer_sizes(self):
        for size in (4096, 8192, 16384):
            with self.subTest(buffer_bytes=size):
                self.run_testbench("test_pcm_player", f"-Ptest_pcm_player.BUFFER_BYTES={size}")

    def test_phase_parameter_boundaries(self):
        self.run_testbench("test_pcm_phase")

    def test_ntsc_pal_fractional_rates(self):
        self.run_testbench("test_pcm_rate")


if __name__ == "__main__":
    unittest.main()
