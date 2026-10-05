"""Real Git transport and immutable fixture integrity regression tests."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
from standard_package_fixtures import SourceFixtures

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('source_transport_package', ROOT / 'tools/package_standard_msu1.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class GitTransportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repository'
        self.repo.mkdir()
        self.run_git('init', '-q')
        (self.repo / 'rtl').mkdir()
        (self.repo / 'rtl/source.sv').write_bytes(b'module original; endmodule\n')
        self.run_git('add', '.')
        self.run_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        self.commit = self.run_git('rev-parse', 'HEAD').strip()

    def run_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True)

    def test_reads_committed_bytes_not_modified_worktree(self):
        (self.repo / 'rtl/source.sv').write_bytes(b'changed live bytes')
        self.assertEqual(pack.git_files(self.repo, self.commit, ('rtl',)),
                         {'rtl/source.sv': b'module original; endmodule\n'})

    def test_tree_and_blob_cannot_masquerade_as_commit(self):
        for ref in ('HEAD^{tree}', 'HEAD:rtl/source.sv'):
            with self.assertRaisesRegex(pack.PackageError, 'must identify a commit'):
                pack.git_files(self.repo, self.run_git('rev-parse', ref).strip(), ('rtl',))

    def test_missing_commit_and_empty_path_are_rejected(self):
        with self.assertRaisesRegex(pack.PackageError, 'source Git evidence unavailable'):
            pack.git_files(self.repo, 'a' * 40, ('rtl',))
        with self.assertRaisesRegex(pack.PackageError, 'no expected files'):
            pack.git_files(self.repo, self.commit, ('absent',))

    def test_symlink_blob_is_rejected(self):
        blob = self.run_git('rev-parse', 'HEAD:rtl/source.sv').strip()
        self.run_git('update-index', '--add', '--cacheinfo', '120000,' + blob + ',rtl/link')
        self.run_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'symlink fixture')
        with self.assertRaisesRegex(pack.PackageError, 'regular Git blobs'):
            pack.git_files(self.repo, self.run_git('rev-parse', 'HEAD').strip(), ('rtl',))


class FixtureIntegrityTests(unittest.TestCase):
    def test_all_recorded_hardware_fingerprints(self):
        fixtures = SourceFixtures(pack)
        for label in ('baseline-982f103', 'candidate-64b5b51', 'candidate-0da938e', 'candidate-e71101f'):
            identity, _ = pack.reviewed_source(label)
            for key in ('build_source_commit', 'hardware_commit'):
                files = fixtures.git_files(ROOT, identity[key], pack.HARDWARE_PATHS)
                self.assertEqual(pack.digest(pack.json_bytes(pack.inventory(files))), identity['hardware_inputs_sha256'])

    def test_corrupt_bytes_rejected_before_use(self):
        fixtures = SourceFixtures(pack)
        original = pack.read_file
        with mock.patch.object(pack, 'read_file', side_effect=lambda *a, **k: original(*a, **k) + b'corrupted'):
            with self.assertRaisesRegex(pack.PackageError, 'integrity mismatch'):
                fixtures.git_files(ROOT, pack.BASELINE, pack.HARDWARE_PATHS)

    def test_unknown_snapshot_and_unknown_query_rejected(self):
        fixtures = SourceFixtures(pack)
        with self.assertRaises(pack.PackageError):
            fixtures.git_files(ROOT, 'f' * 40, pack.HARDWARE_PATHS)
        with self.assertRaises(pack.PackageError):
            fixtures.git(ROOT, 'show', 'HEAD:rtl/source.sv')


if __name__ == '__main__':
    unittest.main()
