"""Aggregate-lock tests with mocked jobs; these are NOT RTL/fit evidence."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/run_standard_memory_regression.py'
spec = importlib.util.spec_from_file_location('qualification_lock_unit', SCRIPT)
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


class QualificationLockTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_separate_process_contends_then_succeeds_after_release(self):
        code = '''import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('qualification', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    with m.qualification_lock(pathlib.Path(sys.argv[2])):
        print('acquired')
except m.QualificationBusyError as error:
    print(error); sys.exit(7)
'''
        command = [sys.executable, '-c', code, str(SCRIPT), str(self.root)]
        with qualification.qualification_lock(self.root):
            blocked = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertEqual(blocked.returncode, 7, blocked.stderr)
            self.assertIn('already running in this checkout', blocked.stdout)
        released = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(released.returncode, 0, released.stderr)
        self.assertEqual(released.stdout.strip(), 'acquired')
        self.assertTrue((self.root / 'build/.standard-memory-regression.lock').is_file())

    def test_contention_stops_before_output_cache_scan_or_jobs(self):
        out = self.root / 'unused-output'
        with qualification.qualification_lock(self.root), \
             mock.patch.object(qualification, 'ROOT', self.root), \
             mock.patch.object(qualification, 'run_qualification') as jobs, \
             mock.patch.object(sys, 'argv', ['qualification', '--output', str(out)]), \
             contextlib.redirect_stderr(io.StringIO()) as stderr, \
             self.assertRaises(SystemExit) as error:
            qualification.main()
        self.assertEqual(error.exception.code, 2)
        self.assertIn('NOT RUN: another standard-memory qualification', stderr.getvalue())
        jobs.assert_not_called()
        self.assertFalse(out.exists())

    def test_lock_covers_entire_run_and_releases_after_success_or_error(self):
        for fail in (False, True):
            def jobs(*args):
                with self.assertRaises(qualification.QualificationBusyError):
                    with qualification.qualification_lock(self.root):
                        self.fail('Concurrent aggregate must not enter')
                if fail:
                    raise ValueError('mock job failure')
                return 0
            with self.subTest(fail=fail), \
                 mock.patch.object(qualification, 'ROOT', self.root), \
                 mock.patch.object(qualification, 'run_qualification', side_effect=jobs), \
                 mock.patch.object(sys, 'argv', ['qualification']):
                if fail:
                    with self.assertRaisesRegex(ValueError, 'mock job failure'):
                        qualification.main()
                else:
                    self.assertEqual(qualification.main(), 0)
            with qualification.qualification_lock(self.root):
                pass


if __name__ == '__main__':
    unittest.main()
