"""Offline checks for the snd-usb-audio jack quirk DKMS installer."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'install_snd_usb_audio_quirk', ROOT / 'scripts/install_snd_usb_audio_quirk.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class SndUsbAudioQuirkTests(unittest.TestCase):
    def setUp(self):
        support = mock.patch.object(installer, 'pipewire_wireless_support', return_value=False)
        self.support = support.start()
        self.addCleanup(support.stop)

    def test_native_pipewire_skips_downloads_and_dkms(self):
        self.support.return_value = True
        with mock.patch.object(installer, 'install_kernel') as install, \
                mock.patch.object(installer, 'dkms_status') as status, \
                tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            headers = root / '7.2.6-1-cachyos/build'
            headers.mkdir(parents=True)
            (headers / 'Makefile').touch()
            self.assertEqual(installer.all_kernels(root, root), 0)
            install.assert_not_called()
            status.assert_not_called()
            self.assertEqual(installer.all_kernels(root, root, force=True), 0)
            install.assert_called_once()

    def test_native_pipewire_does_not_block_explicit_removal(self):
        self.support.return_value = True
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(installer, 'dkms_status', return_value='added'), \
                mock.patch.object(installer, 'run') as run:
            root = Path(directory)
            target = root / f'{installer.NAME}-test'
            target.mkdir()
            (target / '.pacman-managed').touch()
            self.assertEqual(installer.all_kernels(root, root, remove=True), 0)
            run.assert_called_once_with('dkms', 'remove', '-m', installer.NAME,
                                        '-v', 'test', '--all')
            self.assertFalse(target.exists())

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
        self.assertIn(f'PACKAGE_VERSION="{installer.package_version("7.2.6-1-cachyos")}"', conf)
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

    def test_distribution_kernels_have_distinct_packages(self):
        self.assertNotEqual(installer.package_version('7.2.6-1-cachyos'),
                            installer.package_version('7.2.6-arch1-1'))

    def test_automatic_install_retry_and_removal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            modules, sources = root / 'modules', root / 'sources'
            sources.mkdir()
            release = '7.2.6-1-cachyos'
            headers = modules / release / 'build'
            headers.mkdir(parents=True)
            (headers / 'Makefile').touch()
            (modules / '7.2.5-no-headers').mkdir()

            def fetch(tag, tree):
                (tree / 'sound/usb').mkdir(parents=True)
                (tree / 'sound/usb/card.c').write_text('/* stub */\n')

            with mock.patch.object(installer, 'fetch_sound_usb', side_effect=fetch) as download, \
                    mock.patch.object(installer, 'apply_patches') as patch, \
                    mock.patch.object(installer, 'dkms_status', return_value='added') as status, \
                    mock.patch.object(installer, 'run') as run:
                run.side_effect = subprocess.CalledProcessError(1, 'dkms')
                self.assertEqual(installer.all_kernels(modules, sources), 1)
                run.side_effect = None
                self.assertEqual(installer.all_kernels(modules, sources), 0)
                download.assert_called_once()
                patch.assert_called_once()
                version = installer.package_version(release)
                run.assert_called_with('dkms', 'install', '-m', installer.NAME,
                                       '-v', version, '-k', release)
                status.return_value = f'{installer.NAME}/{version}, {release}, x86_64: installed'
                run.reset_mock()
                self.assertEqual(installer.all_kernels(modules, sources), 0)
                run.assert_not_called()
                unmanaged = sources / f'{installer.NAME}-unmanaged'
                unmanaged.mkdir()
                self.assertEqual(installer.all_kernels(modules, sources, remove=True), 0)
                run.assert_called_with('dkms', 'remove', '-m', installer.NAME,
                                       '-v', version, '--all')
                self.assertEqual(list(sources.iterdir()), [unmanaged])

    def test_patch_failure_never_stages_or_builds(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(installer, 'fetch_sound_usb'), \
                mock.patch.object(installer, 'apply_patches',
                                  side_effect=subprocess.CalledProcessError(1, 'git')), \
                mock.patch.object(installer, 'run') as run:
            with self.assertRaises(subprocess.CalledProcessError):
                installer.install_kernel('7.2.6-1-cachyos', Path(directory))
            run.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_automatic_install_continues_after_unsupported_kernel(self):
        with tempfile.TemporaryDirectory() as directory:
            modules = Path(directory)
            for release in ('7.3-rc1', '7.3.1-arch1-1'):
                headers = modules / release / 'build'
                headers.mkdir(parents=True)
                (headers / 'Makefile').touch()
            with mock.patch.object(installer, 'install_kernel',
                                   side_effect=[ValueError('unsupported'), None]) as install:
                self.assertEqual(installer.all_kernels(modules, modules), 1)
                self.assertEqual(install.call_count, 2)


class PipeWireSupportTests(unittest.TestCase):
    def test_probe_matches_tray_for_supported_missing_and_old_plugins(self):
        from barracuda_status.audio_router import pipewire_wireless_support, SPA_ALSA_PLUGINS
        self.assertEqual(installer.SPA_ALSA_PLUGINS, SPA_ALSA_PLUGINS)
        with tempfile.TemporaryDirectory() as directory:
            plugin = Path(directory) / 'libspa-alsa.so'
            paths = (plugin,)
            self.assertFalse(installer.pipewire_wireless_support(paths))
            for content, expected in ((b'old plugin', False),
                                      (b'ELF\x00%s/wireless_status\x00', True)):
                plugin.write_bytes(content)
                self.assertEqual(installer.pipewire_wireless_support(paths), expected)
                self.assertEqual(installer.pipewire_wireless_support(paths),
                                 pipewire_wireless_support(paths))
            with mock.patch.object(Path, 'read_bytes', side_effect=PermissionError):
                self.assertFalse(installer.pipewire_wireless_support(paths))


if __name__ == '__main__':
    unittest.main()
