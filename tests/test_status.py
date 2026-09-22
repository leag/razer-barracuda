import os
import unittest
from unittest.mock import patch

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from barracuda_status import app as status

class StatusTests(unittest.TestCase):
    def setUp(self):
        status.set_language("en")

    def test_observed_reports(self):
        for prefix in ('01 80 0e 50 49 08 f8 4c 70 69 00',
                       '01 80 0e 50 49 08 f4 89 e6 5b 03'):
            for value in (0, 1):
                report = bytes.fromhex(prefix + ' 04 00 20 02 01') + bytes([value])
                self.assertIs(status.parse_report(report), bool(value))
        for report in (b'', b'\x02\x00', bytes.fromhex(
                '01 80 0c 50 49 0e f5 00 00 00 00 02 00 e3 01 00 00'),
                bytes.fromhex('01 80 0e 50 49 08 f4 89 e6 5b 03 04 00 20 02 01 02')):
            self.assertEqual(status.parse_report(report), status.UNKNOWN)

    def test_icons_and_states(self):
        app = status.QApplication.instance() or status.QApplication([])
        with patch.object(status.HidReader, 'start'), patch.object(status.AudioWorker, 'start'):
            tray = status.Tray()
            for value, label in ((True, 'Connected'), (False, 'Disconnected'),
                                 (None, 'Adapter not detected'),
                                 (status.UNKNOWN, 'Adapter connected; link unconfirmed')):
                tray.update_status(value)
                self.assertEqual(tray.status_action.text(), label)
                self.assertFalse(tray.icon().pixmap(32, 32).isNull())
            tray.show_error('I/O error')
            self.assertIn('I/O error', tray.toolTip())
            tray.close()

    def test_idle_reader_stops(self):
        read_fd, write_fd = os.pipe()
        try:
            with patch.object(status, 'find_hidraw', return_value='/fake'), patch.object(
                    status.os, 'open', return_value=os.dup(read_fd)):
                reader = status.HidReader()
                reader.start()
                status.QThread.msleep(100)
                reader.requestInterruption()
                self.assertTrue(reader.wait(1000))
        finally:
            os.close(read_fd)
            os.close(write_fd)

if __name__ == '__main__':
    unittest.main()
