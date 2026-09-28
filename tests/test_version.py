"""Exercise release version updates in disposable projects, without publishing."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('release_version', ROOT / 'scripts/version.py')
version = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(version)


@unittest.skipUnless(shutil.which('uv'), 'uv is required for version integration tests')
class VersionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in version.FIELDS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, path)
        for path, content in version.planned_updates(self.root, '1.2.3').items():
            path.write_text(content)
        (self.root / 'pyproject.toml').write_text(
            '[project]\nname = "version-test"\nversion = "1.2.3"\n'
            'requires-python = ">=3.10"\n')
        environment = mock.patch.dict(os.environ, {'UV_OFFLINE': '1'})
        environment.start()
        self.addCleanup(environment.stop)

    def contents(self):
        return {str(path.relative_to(self.root)): path.read_bytes()
                for path in self.root.rglob('*') if path.is_file()}

    def test_bump_updates_all_versions_and_lockfile(self):
        for name, pattern, replacement in (
                ('packaging/arch/PKGBUILD', 'pkgrel=1', 'pkgrel=4'),
                ('packaging/arch/.SRCINFO', 'pkgrel = 1', 'pkgrel = 4')):
            path = self.root / name
            path.write_text(path.read_text().replace(pattern, replacement))
        self.assertEqual(version.main(['--bump', 'patch'], self.root), 0)
        self.assertIn('version = "1.2.4"', (self.root / 'pyproject.toml').read_text())
        self.assertIn('version = "1.2.4"', (self.root / 'uv.lock').read_text())
        self.assertEqual(version.planned_updates(self.root, '1.2.4'), {})
        self.assertIn('pkgrel=1', (self.root / 'packaging/arch/PKGBUILD').read_text())
        self.assertEqual(version.main(['--check'], self.root), 0)
        self.assertFalse((self.root / '.venv').exists())

    def test_dry_run_preserves_every_file(self):
        before = self.contents()
        self.assertEqual(version.main(['--bump', 'minor', '--dry-run'], self.root), 0)
        self.assertEqual(self.contents(), before)

    def test_set_sync_and_check(self):
        self.assertEqual(version.main(['--set', '2.0.0'], self.root), 0)
        path = self.root / 'pyproject.toml'
        path.write_text(path.read_text().replace('2.0.0', '2.0.1'))
        self.assertEqual(version.main(['--check'], self.root), 1)
        self.assertEqual(version.main(['--sync'], self.root), 0)
        self.assertEqual(version.main(['--check'], self.root), 0)
        self.assertIn('version = "2.0.1"', (self.root / 'uv.lock').read_text())

    def test_malformed_metadata_fails_before_any_write(self):
        (self.root / 'scripts/install_dkms.py').write_text('missing version field\n')
        before = self.contents()
        with self.assertRaises(ValueError):
            version.main(['--bump', 'major'], self.root)
        self.assertEqual(self.contents(), before)

    def test_prereleases_are_rejected_before_writing(self):
        before = self.contents()
        with self.assertRaises(ValueError):
            version.main(['--set', '2.0.0rc1'], self.root)
        self.assertEqual(self.contents(), before)

    def test_uv_failure_restores_project_and_metadata(self):
        before = self.contents()

        def fail(*args, **kwargs):
            (self.root / 'pyproject.toml').write_text('partially updated\n')
            (self.root / 'uv.lock').touch()
            raise subprocess.CalledProcessError(1, 'uv')

        preview = subprocess.CompletedProcess([], 0, stdout='{"version": "1.2.4"}')
        with mock.patch.object(version.subprocess, 'run', side_effect=
                               lambda *a, **kw: preview if '--dry-run' in a[0] else fail()):
            with self.assertRaises(subprocess.CalledProcessError):
                version.main(['--bump', 'patch'], self.root)
        self.assertEqual(self.contents(), before)


if __name__ == '__main__':
    unittest.main()
