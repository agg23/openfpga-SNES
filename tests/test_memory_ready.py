"""Experimental standard-refresh transaction tests; not hardware readiness."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class MemoryReadyTests(unittest.TestCase):
    def run_sv(self, name, rtl):
        if not shutil.which('iverilog') or not shutil.which('vvp'):
            self.skipTest('Icarus unavailable: memory-ready transaction simulation NOT RUN')
        with tempfile.TemporaryDirectory(prefix='memory-ready-') as d:
            out = str(pathlib.Path(d) / name)
            subprocess.run(['iverilog', '-g2012', '-s', name, '-o', out,
                            str(ROOT / rtl), str(ROOT / 'tests/memory_ready' / (name + '.sv'))],
                           check=True, capture_output=True, text=True, timeout=60)
            r = subprocess.run(['vvp', out], check=True, capture_output=True, text=True, timeout=60)
            self.assertIn('PASS', r.stdout)
            print(r.stdout.strip())

    def test_cdc_transaction_lifecycle(self):
        self.run_sv('tb_sdram_transaction_cdc', 'rtl/memory_ready/sdram_transaction_cdc.sv')

    def test_scpu_rom_client(self):
        self.run_sv('tb_snes_rom_client', 'rtl/memory_ready/snes_rom_client.sv')

    def test_legacy_address_geometry(self):
        # The old controller used row[13:1], col[22:14], bank={channel,addr23}.
        # Verify an injective translation at all bit boundaries and random samples.
        import random
        addresses = [0,1,0xffffff] + [((1 << b) + delta) & 0xffffff
                    for b in range(24) for delta in [-1,0,1]]
        rng = random.Random(6301)
        addresses += [rng.randrange(1 << 24) for _ in range(10000)]
        seen = {}
        for channel in [0,1]:
            for a in addresses:
                bank = (channel << 1) | ((a >> 23) & 1)
                row = (a >> 1) & 0x1fff
                col = (a >> 14) & 0x1ff
                p = (bank << 24) | (row << 11) | (col << 1) | (a & 1)
                self.assertLess(p, 0x4000000)
                self.assertEqual((p >> 24) & 3, bank)
                self.assertEqual((p >> 11) & 0x1fff, row)
                self.assertEqual((p >> 1) & 0x3ff, col)
                self.assertEqual(p & 1, a & 1)
                self.assertEqual(seen.setdefault(p, (channel,a)), (channel,a))
