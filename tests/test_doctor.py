"""Installation check against a simulated filesystem; no device, udev or audio access."""
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from barracuda_pair import doctor, headset
from barracuda_pair.control import IDENTITY


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / 'root'
        self.home = Path(self.temporary.name) / 'home'
        self.home.mkdir()
        (self.root / 'sys/bus/hid/devices').mkdir(parents=True)
        (self.root / 'proc').mkdir()
        self.release = '7.3.0-4-cachyos'

    def tearDown(self):
        self.temporary.cleanup()

    def system(self, path=''):
        return doctor.System(self.root, self.home, self.release,
                             {'PATH': path, 'XDG_DATA_HOME': str(self.home / 'data')})

    def write(self, absolute, text=''):
        path = self.root / absolute.lstrip('/')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def dongle(self, driver='razer-barracuda', attributes=('headset_settings', 'headset_poweroff')):
        usb = self.root / 'sys/devices/usb1/1-1/1-1:1.3'
        hid = usb / '0003:1532:0552.0001'
        hid.mkdir(parents=True)
        (usb / 'bInterfaceNumber').write_text('03\n')
        (usb / 'wireless_status').write_text('connected\n')
        (hid / 'uevent').write_text(IDENTITY + '\n')
        if driver:
            target = self.root / 'sys/bus/hid/drivers' / driver
            target.mkdir(parents=True)
            (hid / 'driver').symlink_to(target)
        for name in attributes:
            (hid / name).write_text('')
        (self.root / 'sys/bus/hid/devices' / hid.name).symlink_to(hid)
        node = self.root / 'sys/class/hidraw/hidraw3/device'
        node.mkdir(parents=True)
        (node / 'uevent').write_text(IDENTITY + '\n')
        self.write('/dev/hidraw3')
        return hid

    def complete(self):
        self.write('/sys/module/hid_razer_barracuda/refcnt', '0')
        self.dongle()
        for name in doctor.RULES:
            self.write(f'/usr/lib/udev/rules.d/{name}')
        self.write('/usr/src/hid-razer-barracuda-0.6.0/dkms.conf')
        self.write('/usr/src/snd-usb-audio-barracuda-7.3.0-barracuda1-x/dkms.conf',
                   'BUILD_EXCLUSIVE_KERNEL="^7\\.3\\.0\\-4\\-cachyos$"\n')
        self.write(f'/usr/share/plasma/plasmoids/{doctor.WIDGET}/metadata.json')
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        for name in doctor.HELPERS:
            helper = bin_dir / name
            helper.write_text('#!/bin/sh\n')
            helper.chmod(0o755)
        return str(bin_dir)

    def statuses(self, checks):
        return {check.message: check.status for check in checks}

    def test_complete_installation_passes(self):
        checks = doctor.run_checks(self.system(self.complete()))
        self.assertNotIn(doctor.FAIL, {check.status for check in checks})
        self.assertNotIn(doctor.WARN, {check.status for check in checks})
        self.assertIn('Headset link reported by the driver: connected.', self.statuses(checks))
        stream = io.StringIO()
        self.assertEqual(doctor.report(checks, stream), 0)
        self.assertIn('Nothing was changed.', stream.getvalue())

    def test_missing_dongle_is_a_warning_not_a_failure(self):
        checks = doctor.run_checks(self.system())
        statuses = self.statuses(checks)
        self.assertEqual(statuses['Dongle not detected; device checks were skipped.'], doctor.WARN)
        self.assertEqual(statuses['The hid-razer-barracuda driver is not loaded.'], doctor.WARN)

    def test_unknown_link_is_not_reported_as_disconnected(self):
        path = self.complete()
        (self.root / 'sys/devices/usb1/1-1/1-1:1.3/wireless_status').unlink()
        messages = [check.message for check in doctor.run_checks(self.system(path))]
        self.assertIn('Headset link not confirmed yet; turn the headset on.', messages)
        self.assertFalse(any('disconnected' in message for message in messages))

    def test_unbound_dongle_and_missing_module(self):
        self.dongle(driver='hid-generic')
        statuses = self.statuses(doctor.run_checks(self.system()))
        self.assertEqual(statuses['The hid-razer-barracuda driver is not loaded.'], doctor.FAIL)
        self.write('/sys/module/hid_razer_barracuda/refcnt', '0')
        statuses = self.statuses(doctor.run_checks(self.system()))
        self.assertEqual(statuses['The dongle is bound to hid-generic, not razer-barracuda.'],
                         doctor.WARN)

    def test_settings_access_points_at_the_audio_group(self):
        path = self.complete()
        writable = lambda target, mode: not Path(target).name.startswith('headset_')
        with patch.object(doctor.os, 'access', side_effect=writable), \
                patch.object(doctor, 'in_audio_group', return_value=False):
            checks = doctor.run_checks(self.system(path))
        failed = [check for check in checks if check.status == doctor.FAIL]
        self.assertEqual([check.message for check in failed],
                         ['Headset settings and power-off need the audio group.'])
        self.assertIn('usermod -aG audio', failed[0].fix)

    def test_failed_quirk_build_gives_the_retry_command(self):
        path = self.complete()
        for conf in (self.root / 'usr/src').glob('snd-usb-audio-barracuda-*/dkms.conf'):
            conf.unlink()
        self.write('/var/lib/hid-razer-barracuda/quirk-retry', self.release + '\n')
        failed = [check for check in doctor.run_checks(self.system(path))
                  if check.status == doctor.FAIL]
        self.assertEqual(len(failed), 1)
        self.assertIn('barracuda-snd-usb-audio-quirk --all-kernels', failed[0].fix)

    def test_native_pipewire_support_needs_no_quirk(self):
        path = self.complete()
        for conf in (self.root / 'usr/src').glob('snd-usb-audio-barracuda-*/dkms.conf'):
            conf.unlink()
        self.write(doctor.SPA_ALSA_PLUGINS[0], 'x wireless_status x')
        statuses = self.statuses(doctor.run_checks(self.system(path)))
        self.assertIn('PipeWire follows the headset link natively; no jack quirk is needed.', statuses)

    def test_user_helpers_off_path_suggest_adding_local_bin(self):
        self.complete()
        local = self.home / '.local/bin'
        local.mkdir(parents=True)
        for name in doctor.HELPERS:
            (local / name).write_text('')
        failed = [check for check in doctor.run_checks(self.system('/nonexistent'))
                  if check.status == doctor.FAIL]
        self.assertEqual(len(failed), 1)
        self.assertIn(str(local), failed[0].fix)
        self.assertIn('this shell', failed[0].message)

    def test_plasma_session_path_is_preferred(self):
        path = self.complete()
        proc = self.root / 'proc/1234'
        proc.mkdir()
        (proc / 'comm').write_text('plasmashell\n')
        (proc / 'environ').write_bytes(b'HOME=/x\0PATH=' + path.encode() + b'\0')
        checks = doctor.run_checks(self.system('/nonexistent'))
        self.assertIn('Helpers are on the PATH of the Plasma session.', self.statuses(checks))

    def test_duplicate_installations_are_warned(self):
        path = self.complete()
        (self.home / 'data/plasma/plasmoids' / doctor.WIDGET).mkdir(parents=True)
        (self.home / 'data/plasma/plasmoids' / doctor.WIDGET / 'metadata.json').write_text('{}')
        self.write('/usr/bin/barracuda-pair')
        (self.home / '.local/bin').mkdir(parents=True)
        (self.home / '.local/bin/barracuda-pair').write_text('')
        warned = [check.message for check in doctor.run_checks(self.system(path))
                  if check.status == doctor.WARN]
        self.assertEqual(warned, ['Both a user copy and the barracuda-pair package are installed.',
                                  'The widget is installed both for your user and by a package.'])

    def test_failures_set_the_exit_status(self):
        stream = io.StringIO()
        status = doctor.report([doctor.Check(doctor.FAIL, 'Broken.', 'Fix it.')], stream)
        self.assertEqual(status, 1)
        self.assertIn('✗ Broken.\n    Fix it.', stream.getvalue())

    def test_headset_cli_runs_the_check(self):
        with patch.object(doctor, 'run_checks', return_value=[]) as run, \
                patch('sys.stdout', new_callable=io.StringIO) as stdout:
            self.assertEqual(headset.main(['doctor']), 0)
        run.assert_called_once_with()
        self.assertIn('Everything is in place.', stdout.getvalue())


if __name__ == '__main__':
    unittest.main()
