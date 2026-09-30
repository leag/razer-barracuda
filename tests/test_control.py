"""Power actions use simulated sysfs and never touch physical devices."""
from contextlib import nullcontext
import errno
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from barracuda_pair import control, i18n


class PowerControlTests(unittest.TestCase):
    def tearDown(self):
        i18n.set_language('en')

    def adapter(self, root, name='adapter', identity=control.IDENTITY, interface='03'):
        parent = root / (name + '-interface')
        parent.mkdir()
        (parent / 'bInterfaceNumber').write_text(interface)
        actual = parent / name
        actual.mkdir()
        (actual / 'uevent').write_text(identity + '\n')
        device = root / 'hid' / name
        device.parent.mkdir(exist_ok=True)
        device.symlink_to(actual)
        return actual

    def test_discovery_requires_identity_interface_and_updated_driver(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.adapter(root, 'other', 'HID_ID=0003:00001532:00000001')
            self.adapter(root, 'audio', interface='00')
            with self.assertRaises(OSError) as error:
                control.power_attribute(root / 'hid')
            self.assertEqual(error.exception.errno, errno.ENODEV)
            actual = self.adapter(root)
            with self.assertRaises(OSError) as error:
                control.power_attribute(root / 'hid')
            self.assertEqual(error.exception.errno, errno.ENOSYS)
            (actual / 'headset_poweroff').touch()
            self.assertEqual(control.power_attribute(root / 'hid').resolve(), actual / 'headset_poweroff')
            self.adapter(root, 'second')
            with self.assertRaises(OSError) as error:
                control.power_attribute(root / 'hid')
            self.assertEqual(error.exception.errno, errno.EINVAL)

    def test_single_write_and_no_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            attribute = Path(temporary) / 'headset_poweroff'
            attribute.touch()
            with patch.object(control, 'control_lock', return_value=nullcontext()), \
                    patch.object(control, 'power_attribute', return_value=attribute):
                control.request_poweroff()
                self.assertEqual(attribute.read_text(), '1\n')
            with patch.object(control, 'control_lock', return_value=nullcontext()), \
                    patch.object(control, 'power_attribute', side_effect=OSError(errno.EBUSY, 'busy')) as lookup:
                with self.assertRaises(OSError):
                    control.request_poweroff()
                lookup.assert_called_once()

    def test_xdg_lock_rejects_competing_operation(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {'XDG_STATE_HOME': temporary}):
            with control.control_lock():
                with self.assertRaises(BlockingIOError):
                    with control.control_lock():
                        self.fail('Concurrent operation acquired the lock')
            self.assertTrue((Path(temporary) / 'barracuda-pair/control.lock').exists())

    def test_explicit_confirmation_and_both_languages(self):
        for language, expected in [('en', 'Power-off request sent'), ('es', 'Solicitud de apagado enviada')]:
            with patch.object(control, 'request_poweroff') as request, \
                    patch('builtins.input', return_value='n'), patch('sys.stdout', new_callable=io.StringIO):
                self.assertEqual(control.main(['--off', '--language', language]), 1)
                request.assert_not_called()
            with patch.object(control, 'request_poweroff') as request, \
                    patch('sys.stdout', new_callable=io.StringIO) as output:
                self.assertEqual(control.main(['--off', '--yes', '--language', language]), 0)
                request.assert_called_once()
                self.assertIn(expected, output.getvalue())

    def test_errors_preserve_unknown_state_and_localize(self):
        for number in (errno.EACCES, errno.EBUSY, errno.ENOTCONN, errno.ETIMEDOUT, errno.EIO):
            messages = []
            for language in ('en', 'es'):
                i18n.set_language(language)
                messages.append(control.error_text(OSError(number, 'test')))
            self.assertNotEqual(*messages)
        with patch.object(control, 'request_poweroff', side_effect=OSError(errno.ETIMEDOUT, 'test')), \
                patch('sys.stderr', new_callable=io.StringIO) as output:
            self.assertEqual(control.main(['--off', '--yes']), 1)
            self.assertIn('unknown', output.getvalue())
