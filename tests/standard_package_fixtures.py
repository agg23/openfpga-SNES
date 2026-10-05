"""Test-only source provider; never used by production package generation.

Snapshots are authenticated against byte sizes, SHA-256 and Git blob IDs.
One unavailable commit has an explicit hardware-equivalence provenance record;
the provider does not recreate a commit object or claim its complete tree.
"""
import hashlib
import json
from pathlib import Path


class SourceFixtures:
    def __init__(self, package):
        self.package = package
        self.root = Path(__file__).resolve().parents[1]
        self.directory = self.root / 'tests/fixtures/standard_package'
        self.manifest = json.loads((self.directory / 'manifest.json').read_text())

    def git(self, repository, *args):
        self.package.safe_path(repository)
        base = self.package.BASELINE
        if args == ('rev-parse', base + '^{tree}'):
            return (self.manifest['baseline_tree'] + '\n').encode()
        if args == ('rev-parse', base + '^'):
            return (self.manifest['baseline_parent'] + '\n').encode()
        if args == ('show', 'e71101fd06a452da53cb0924e1d3701f53133435:tools/standard_msu1_reviewed_sources.json'):
            return self.package.json_bytes(self.manifest['old_catalog'])
        raise self.package.PackageError('source Git evidence unavailable in test snapshot: ' + repr(args))

    def git_files(self, repository, commit, paths):
        self.package.safe_path(repository)
        if commit == self.manifest['baseline_tree']:
            raise self.package.PackageError('source Git evidence must identify a commit, not a tree/tag/blob')
        record = self.manifest['commits'].get(commit)
        if record is None:
            raise self.package.PackageError('source Git evidence unavailable in test snapshot: ' + commit)
        result = {}
        for name, item in record['files'].items():
            if not any(name == prefix or name.startswith(prefix.rstrip('/') + '/') for prefix in paths):
                continue
            path = (self.root / name if item['location'] == 'checkout'
                    else self.directory / 'blobs' / item['sha256'])
            data = self.package.read_file(path, allow_empty=True)
            blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            if (len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']
                    or blob != item['git_blob']):
                raise self.package.PackageError('source fixture integrity mismatch: ' + name)
            result[name] = data
        if not result:
            raise self.package.PackageError('source Git evidence contains no expected files')
        return result
