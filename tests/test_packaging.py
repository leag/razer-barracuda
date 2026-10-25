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
            units = destination / 'usr/lib/systemd/system'
            unit = units / 'barracuda-quirk-retry.service'
            self.assertIn('ConditionPathExists=/var/lib/hid-razer-barracuda/quirk-retry',
                          unit.read_text())
            self.assertIn('ExecStart=/usr/bin/barracuda-snd-usb-audio-quirk --all-kernels',
                          unit.read_text())
            wants = units / 'multi-user.target.wants/barracuda-quirk-retry.service'
            self.assertEqual(wants.readlink(), Path('../barracuda-quirk-retry.service'))
            self.assertEqual(wants.resolve(), unit.resolve())
            launcher = destination / 'usr/bin/barracuda-snd-usb-audio-quirk'
            self.assertIn('--no-profile-set', launcher.read_text())
            self.assertTrue(launcher.stat().st_mode & 0o111)
            self.assertTrue((destination / 'usr/share/hid-razer-barracuda/scripts/'
                             'install_snd_usb_audio_quirk.py').is_file())
            for path in destination.rglob('*'):
                self.assertNotIn('.git', path.parts)
                self.assertNotIn('sound/usb', str(path.relative_to(destination)))

    def test_upgrade_unregisters_other_driver_versions(self):
        status = ('hid-razer-barracuda/0.5.1.local1, 7.3.0-4-cachyos, x86_64: built\n'
                  'hid-razer-barracuda/0.5.1.local1, 6.18.55-2-cachyos-lts, x86_64: installed\n'
                  'hid-razer-barracuda/0.4.0: added\n'
                  'hid-razer-barracuda/0.6.0, 7.3.0-4-cachyos, x86_64: installed\n')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'status').write_text(status)
            dkms = root / 'dkms'
            dkms.write_text('#!/bin/sh\n'
                            f'[ "$1" = status ] && exec cat "{root}/status"\n'
                            f'echo "$*" >> "{root}/calls"\n')
            dkms.chmod(0o755)
            for scriptlet in ('post_install', 'post_upgrade'):
                (root / 'calls').unlink(missing_ok=True)
                subprocess.run(['sh', '-c', f'. "$1"; {scriptlet} 0.6.0-2 0.5.1-1', 'sh',
                                str(ROOT / 'packaging/arch/hid-razer-barracuda-dkms.install')],
                               env={'PATH': f'{root}:/usr/bin:/bin'}, check=True)
                self.assertEqual((root / 'calls').read_text().splitlines(),
                                 ['remove -m hid-razer-barracuda -v 0.4.0 --all',
                                  'remove -m hid-razer-barracuda -v 0.5.1.local1 --all'])

    def test_versions_agree(self):
        pkgver = field(PKGBUILD, r'^pkgver=(\S+)')
        self.assertEqual(field(ROOT / 'pyproject.toml', r'^version = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'barracuda_pair/__init__.py', r'^__version__ = "(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'kernel/hid-razer-barracuda/dkms.conf',
                               r'^PACKAGE_VERSION="(.+)"'), pkgver)
        self.assertEqual(field(ROOT / 'scripts/install_dkms.py', r"^VERSION = '(.+)'"), pkgver)
        self.assertEqual(field(ROOT / 'packaging/arch/.SRCINFO', r'^\tpkgver = (\S+)'), pkgver)

    def test_packaged_files_exist(self):
        text = PKGBUILD.read_text()
        names = set(re.findall(r'(?:packaging|kernel|scripts|barracuda_pair)/[\w./{},-]*[\w}*]', text))
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
