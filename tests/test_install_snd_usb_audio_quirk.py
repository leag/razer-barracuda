"""Offline checks for the snd-usb-audio jack quirk DKMS installer."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'install_snd_usb_audio_quirk', ROOT / 'scripts/install_snd_usb_audio_quirk.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class SndUsbAudioQuirkTests(unittest.TestCase):
    def test_upstream_version(self):
        self.assertEqual(installer.upstream_version('7.2.6-1-cachyos'), 'v7.2.6')
        self.assertEqual(installer.upstream_version('6.12.10'), 'v6.12.10')
        self.assertEqual(installer.upstream_version('7.3.0-1-cachyos'), 'v7.3')
        self.assertEqual(installer.upstream_version('7.3-arch1-1'), 'v7.3')
        for release in ('7.3.0-rc1-1-cachyos-rc', '7.3-rc2', 'custom'):
            with self.assertRaises(ValueError):
                installer.upstream_version(release)

    def test_dkms_conf_is_restricted_to_the_exact_kernel(self):
        conf = installer.dkms_conf('7.2.6-1-cachyos')
        self.assertIn('PACKAGE_VERSION="7.2.6-barracuda1"', conf)
        self.assertIn('BUILT_MODULE_NAME[0]="snd-usb-audio"', conf)
        pattern = re.search(r'BUILD_EXCLUSIVE_KERNEL="(.*)"', conf).group(1)
        self.assertTrue(re.match(pattern, '7.2.6-1-cachyos'))
        for other in ('7.2.7-1-cachyos', '7.2.6-2-cachyos', '7.2.6-1-cachyos-lts'):
            self.assertIsNone(re.match(pattern, other))

    def test_patch_applies_to_its_recorded_context(self):
        patch = installer.patches()[0]
        text = patch.read_text()
        self.assertTrue(text.startswith('SPDX-License-Identifier: GPL-2.0'))
        self.assertIn('USB_ID(0x1532, 0x0552)', text)
        hunk = text[text.index('\n@@'):]
        original = [line[1:] for line in hunk.splitlines()[1:] if line[:1] in (' ', '-')]
        with tempfile.TemporaryDirectory() as directory:
            tree = Path(directory)
            (tree / 'sound/usb').mkdir(parents=True)
            (tree / 'sound/usb/mixer_quirks.c').write_text('\n'.join(original) + '\n')
            subprocess.run(['git', 'apply', '--check', str(patch)], cwd=tree, check=True)
            subprocess.run(['git', 'apply', str(patch)], cwd=tree, check=True)
            patched = (tree / 'sound/usb/mixer_quirks.c').read_text()
            self.assertIn('case USB_ID(0x1532, 0x0552):', patched)
            # A changed upstream context must stop the build, not patch blindly.
            (tree / 'sound/usb/mixer_quirks.c').write_text('int unrelated;\n')
            with self.assertRaises(subprocess.CalledProcessError):
                installer.apply_patches(tree)

    def test_stage_refuses_existing_or_symlink_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tree = root / 'linux'
            (tree / 'sound/usb').mkdir(parents=True)
            (tree / 'sound/usb/card.c').write_text('/* stub */\n')
            target = root / 'target'
            installer.stage(tree, '7.2.6-1-cachyos', target)
            self.assertTrue((target / 'sound/usb/card.c').is_file())
            self.assertIn('7.2.6-barracuda1', (target / 'dkms.conf').read_text())
            with self.assertRaises(RuntimeError):
                installer.stage(tree, '7.2.6-1-cachyos', target)
            link = root / 'link'
            link.symlink_to(root / 'elsewhere')
            with self.assertRaises(RuntimeError):
                installer.stage(tree, '7.2.6-1-cachyos', link)

    def test_profile_set_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installer.install_profile_set(root)
            profile = root / 'usr/share/alsa-card-profile/mixer/profile-sets/razer-barracuda.conf'
            path = root / 'usr/share/alsa-card-profile/mixer/paths/analog-input-headset-mic-razer-barracuda.conf'
            rule = root / 'etc/udev/rules.d/89-razer-barracuda-acp.rules'
            self.assertIn('paths-input = analog-input-headset-mic-razer-barracuda', profile.read_text())
            self.assertNotIn('iec958', profile.read_text())
            self.assertIn('[Jack Headset Mic]', path.read_text())
            self.assertIn('[Element Mic]', path.read_text())
            self.assertIn('ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0552"', rule.read_text())
            self.assertIn('ENV{ACP_PROFILE_SET}="razer-barracuda.conf"', rule.read_text())
            installer.remove_profile_set(root)
            self.assertFalse(profile.exists() or path.exists() or rule.exists())
            link = root / 'etc/udev/rules.d/89-razer-barracuda-acp.rules'
            link.symlink_to(root / 'elsewhere')
            with self.assertRaises(RuntimeError):
                installer.install_profile_set(root)


if __name__ == '__main__':
    unittest.main()
