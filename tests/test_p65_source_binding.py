"""Historical P65 evidence must not silently follow later working-tree RTL."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = "84d8d5eb6f3e0de2d7f891581e1e922b109fb758"
SOURCES = ["rtl/upstream/CPU.vhd", "rtl/upstream/SNES.vhd", "rtl/upstream/SWRAM.vhd",
           "rtl/upstream/65C816/MCode.vhd", "rtl/upstream/65C816/P65C816.vhd"]


@unittest.skipUnless(shutil.which("git"), "git is required")
class SourceBindingTest(unittest.TestCase):
    def test_requested_snapshot_extracts_predecode_verbatim(self):
        reference = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        cpu = subprocess.check_output(['git', 'show', reference + ':rtl/upstream/CPU.vhd'], cwd=ROOT, text=True)
        swram = subprocess.check_output(['git', 'show', reference + ':rtl/upstream/SWRAM.vhd'], cwd=ROOT, text=True)
        if 'WMDATA_SEL <=' not in swram:
            self.skipTest('Requested revision predates the WRAM read predecode')
        with tempfile.TemporaryDirectory(prefix='p65-predecode-binding-') as temp:
            subprocess.run([sys.executable, str(ROOT / 'tools/extract_p65_wram_selectors.py'),
                            '--source-commit', reference, '--output', temp], cwd=ROOT,
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            model = (Path(temp) / 'selector_model.vhd').read_text()
            for source, anchor in [(cpu, 'PA_WMDATA <='), (swram, 'WMDATA_SEL <=')]:
                start = source.index(anchor)
                self.assertIn(source[start:source.index(';', start) + 1], model)
            self.assertIn('constant WMDATA_PREDECODE : boolean := true;', model)
            self.assertIn('signal PA_WMDATA, WMDATA_SEL : std_logic;', model)
            provenance = json.loads((Path(temp) / 'source_provenance.json').read_text())
            self.assertEqual(provenance['source_commit'], reference)

    def test_current_rtl_drift_cannot_change_pinned_model(self):
        with tempfile.TemporaryDirectory(prefix="p65-source-binding-") as temp:
            checkout = Path(temp) / "checkout"
            subprocess.run(["git", "clone", "--quiet", "--shared", "--no-checkout",
                            str(ROOT), str(checkout)], check=True)
            subprocess.run(["git", "checkout", REFERENCE, "--", *SOURCES],
                           cwd=checkout, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            script = checkout / "tools/extract_p65_wram_selectors.py"
            script.parent.mkdir()
            shutil.copyfile(ROOT / "tools/extract_p65_wram_selectors.py", script)
            before = Path(temp) / "before"
            after = Path(temp) / "after"
            def extract(out):
                subprocess.run([sys.executable, str(script), "--output", str(out)],
                               cwd=temp, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            extract(before)
            cpu = checkout / "rtl/upstream/CPU.vhd"
            source = cpu.read_text()
            old = "DMA_ACTIVE <= DMA_RUN or HDMA_RUN;"
            self.assertEqual(source.count(old), 1)
            # Mutate only the disposable test clone, never the real checkout.
            cpu.write_text(source.replace(old, "DMA_ACTIVE <= '0';"))
            extract(after)
            self.assertEqual((before / "selector_model.vhd").read_bytes(),
                             (after / "selector_model.vhd").read_bytes())
            self.assertEqual((before / "source_hashes.json").read_bytes(),
                             (after / "source_hashes.json").read_bytes())
            provenance = json.loads((after / "source_provenance.json").read_text())
            self.assertEqual(provenance["source_commit"], REFERENCE)
            self.assertEqual(provenance["working_tree_drift"], ["rtl/upstream/CPU.vhd"])
            self.assertEqual(provenance["input_origin"], "git objects, not working-tree RTL")


if __name__ == "__main__":
    unittest.main()
