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
