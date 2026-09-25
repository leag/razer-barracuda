"""Isolated checks for native driver installation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'install_dkms', Path(__file__).resolve().parents[1] / 'scripts/install_dkms.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class DkmsInstallerTests(unittest.TestCase):
    def test_package_matches_sources(self):
        kernel = Path(__file__).resolve().parents[1] / 'kernel' / installer.NAME
        conf = (kernel / 'dkms.conf').read_text()
        self.assertIn(f'PACKAGE_NAME="{installer.NAME}"', conf)
        self.assertIn(f'PACKAGE_VERSION="{installer.VERSION}"', conf)
        self.assertIn(f'BUILT_MODULE_NAME[0]="{installer.NAME}"', conf)
        for name in installer.FILES:
            self.assertTrue((kernel / name).is_file(), name)
        source = (kernel / f'{installer.NAME}.c').read_text()
        self.assertIn(f'.name = "{installer.DRIVER}"', source)
        # Version strings are not used in-tree; dkms.conf carries the version.
        self.assertNotIn('MODULE_VERSION', source)

    def test_legacy_package_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            src = Path(directory)
            self.assertEqual(installer.legacy_sources(src), [])
            (src / f'{installer.NAME}-{installer.VERSION}').mkdir()
            self.assertEqual(installer.legacy_sources(src), [])
            (src / 'hid-barracuda-0.2.1').mkdir()
            self.assertEqual(installer.legacy_sources(src), [src / 'hid-barracuda-0.2.1'])

    def test_copy_whitelist_and_refuse_changed_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            for name in installer.FILES:
                (source / name).write_text(name)
            (source / 'private.key').write_text('excluded')
            target = root / 'target'
            installer.install(source, target)
            self.assertEqual(set(p.name for p in target.iterdir()), set(installer.FILES))
            installer.install(source, target)
            (source / installer.FILES[0]).write_text('changed')
            with self.assertRaises(RuntimeError):
                installer.install(source, target)

    def test_only_exact_usb_identity_and_interface(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bus = root / 'devices'
            bus.mkdir()
            for number, identity in [('03', installer.IDENTITY), ('02', installer.IDENTITY),
                                     ('04', 'HID_ID=0003:00001532:00009999')]:
                interface = root / number
                interface.mkdir()
                (interface / 'bInterfaceNumber').write_text(number)
                device = interface / 'hid'
                device.mkdir()
                (device / 'uevent').write_text(identity + '\n')
                (bus / number).symlink_to(device)
            self.assertEqual(installer.matching_devices(bus), [bus / '03'])

    def test_specialized_driver_is_not_rebound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root / 'device'
            device.mkdir()
            specialized = root / 'specialized'
            specialized.mkdir()
            (device / 'driver').symlink_to(specialized)
            with patch.object(installer, 'run') as run:
                with self.assertRaises(RuntimeError):
                    installer.activate([device], root)
                run.assert_not_called()

    def test_refuse_symlink_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'target'
            target.symlink_to(root / 'elsewhere')
            with self.assertRaises(RuntimeError):
                installer.install(root, target)
