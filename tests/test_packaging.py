"""Keep the Arch PKGBUILD in step with the versions and files in the tree."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / 'packaging/arch/PKGBUILD'


def field(path, pattern):
    return re.search(pattern, path.read_text(), re.M).group(1)


class PackagingTests(unittest.TestCase):
    def test_driver_package_stages_automatic_quirk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = field(PKGBUILD, r'^pkgver=(\S+)')
            (root / f'razer-barracuda-{version}').symlink_to(ROOT, target_is_directory=True)
            destination = root / 'package'
            subprocess.run(['bash', '-c',
                            'source "$1"; pkgdir="$2"; pkgname=hid-razer-barracuda-dkms; '
                            'package_hid-razer-barracuda-dkms',
                            'bash', str(PKGBUILD), str(destination)], cwd=root, check=True)
            hook = destination / 'usr/share/libalpm/hooks/71-barracuda-quirk.hook'
            self.assertIn('Target = usr/lib/modules/*/build/Makefile', hook.read_text())
            self.assertIn('When = PostTransaction', hook.read_text())
            self.assertIn('--all-kernels', hook.read_text())
            launcher = destination / 'usr/bin/barracuda-snd-usb-audio-quirk'
            self.assertIn('--no-profile-set', launcher.read_text())
            self.assertTrue(launcher.stat().st_mode & 0o111)
            self.assertTrue((destination / 'usr/share/hid-razer-barracuda/scripts/'
                             'install_snd_usb_audio_quirk.py').is_file())
            for path in destination.rglob('*'):
                self.assertNotIn('.git', path.parts)
                self.assertNotIn('sound/usb', str(path.relative_to(destination)))

    def test_versions_agree(self):
        pkgver = field(PKGBUILD, r'^pkgver=(\S+)')
        self.assertEqual(field(ROOT / 'pyproject.toml', r'^version = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'barracuda_status/__init__.py', r'^__version__ = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'kernel/hid-razer-barracuda/dkms.conf',
                               r'^PACKAGE_VERSION="(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'scripts/install_dkms.py', r"^VERSION = '(.+)'"), pkgver)
        self.assertEqual(field(ROOT / 'packaging/arch/.SRCINFO', r'^\tpkgver = (\S+)'), pkgver)

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
