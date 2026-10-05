"""Prevent a failed/unfinished full flow from being mistaken for fitted evidence."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('save_cdc', Path(__file__).parents[1] / 'tools/review_standard_save_cdc.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompleteFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'projects'
        self.project.mkdir()
        self.fit = self.root / 'snes_pocket.fit.rpt'
        self.fit.write_text('; Fitter Status ; Successful ;')
        (self.root / 'snes_pocket.flow.rpt').write_text('; Flow Status ; Successful ;')
        (self.root / 'snes_pocket.sta.rpt').write_text('Timing Analyzer report')
        self.manifest = {'compile_exit_code': 0, 'source_commit': 'abc', 'finished_utc': '2026-10-04T00:00:00Z'}
        self.write_manifest()
        patch = mock.patch.object(module.subprocess, 'check_output', return_value='abc\n')
        patch.start()
        self.addCleanup(patch.stop)

    def write_manifest(self):
        (self.root / 'build.json').write_text(json.dumps(self.manifest))

    def check(self):
        return module.require_complete(self.project, self.fit)

    def test_complete_flow(self):
        self.assertEqual(self.check(), 'abc')

    def test_failed_routing(self):
        self.manifest['compile_exit_code'] = 3
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'did not complete'):
            self.check()

    def test_still_running(self):
        del self.manifest['finished_utc']
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'did not complete'):
            self.check()

    def test_source_mismatch(self):
        self.manifest['source_commit'] = 'def'
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'revision differ'):
            self.check()

    def test_failed_fitter_report(self):
        self.fit.write_text('; Fitter Status ; Failed ;')
        with self.assertRaisesRegex(ValueError, 'successful report'):
            self.check()

    def test_failed_flow_report(self):
        (self.root / 'snes_pocket.flow.rpt').write_text('; Flow Status ; Failed ;')
        with self.assertRaisesRegex(ValueError, 'successful report'):
            self.check()

    def test_missing_sta(self):
        (self.root / 'snes_pocket.sta.rpt').unlink()
        with self.assertRaisesRegex(ValueError, 'STA report is absent'):
            self.check()


if __name__ == '__main__':
    unittest.main()
