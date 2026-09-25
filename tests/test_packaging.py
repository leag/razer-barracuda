"""Keep the Arch PKGBUILD in step with the versions and files in the tree."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / 'packaging/arch/PKGBUILD'


def field(path, pattern):
    return re.search(pattern, path.read_text(), re.M).group(1)


class PackagingTests(unittest.TestCase):
    def test_versions_agree(self):
        pkgver = field(PKGBUILD, r'^pkgver=(\S+)')
        self.assertEqual(field(ROOT / 'pyproject.toml', r'^version = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'barracuda_status/__init__.py', r'^__version__ = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'kernel/hid-razer-barracuda/dkms.conf',
                               r'^PACKAGE_VERSION="(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'scripts/install_dkms.py', r"^VERSION = '(.+)'"), pkgver)

    def test_packaged_files_exist(self):
        text = PKGBUILD.read_text()
        names = set(re.findall(r'(?:packaging|kernel|scripts|barracuda_status)/[\w./{},-]*[\w}*]', text))
        for name in names:
            match = re.match(r'(.*)\{(.*)\}(.*)', name)
            parts = [match.group(1) + p + match.group(3) for p in match.group(2).split(',')] \
                if match else [name]
            for part in parts:
                if '*' in part:
                    self.assertTrue(list(ROOT.glob(part)), part)
                else:
                    self.assertTrue((ROOT / part).exists(), part)
        self.assertIn('--no-profile-set', text)


if __name__ == '__main__':
    unittest.main()
