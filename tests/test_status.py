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
                '01 80 0c 50 49 0e f5 00 00 00 00 02 00 e6 01 00 00'),
                bytes.fromhex('01 80 0e 50 49 08 f4 89 e6 5b 03 04 00 20 02 01 02')):
            self.assertEqual(status.parse_report(report), status.UNKNOWN)

    def test_e3_frames_and_invalid_variants(self):
        raw = bytes.fromhex('01 80 0c 50 49 0e e0 00 00 00 00 02 00 e3 00')
        for value in (0, 1):
            self.assertIs(status.parse_report(raw[:-1] + bytes([value])), bool(value))
        for index, value in ((0, 2), (2, 13), (5, 1), (11, 3),
                             (12, 1), (13, 0xe6), (14, 2)):
            changed = bytearray(raw)
            changed[index] = value
            self.assertEqual(status.parse_report(changed), status.UNKNOWN)
        for length in range(len(raw)):
            self.assertEqual(status.parse_report(raw[:length]), status.UNKNOWN)

    def test_query_timeout_is_bounded_and_never_emits_disconnected(self):
        reader = status.HidReader()
        with patch.object(reader, 'isInterruptionRequested',
                          side_effect=[False] * 5 + [True]), patch.object(
                status.time, 'monotonic', side_effect=range(0, 100, 3)), patch.object(
                status.select, 'select', return_value=([], [], [])), patch.object(
                status.os, 'write', return_value=64) as write, patch.object(
                reader, 'status_changed') as signal:
            reader.monitor(99, True)
            self.assertEqual(write.call_count, 3)
            for call in write.call_args_list:
                packet = call.args[1]
                self.assertEqual(len(packet), 64)
                self.assertEqual(packet[:6], bytes.fromhex('01 80 06 50 41 0e'))
                self.assertEqual(packet[7:9], bytes.fromhex('01 e3'))
            signal.emit.assert_not_called()

    def test_success_stops_queries_and_keeps_processing_transitions(self):
        reader = status.HidReader()
        reports = [bytes.fromhex('01 80 0c 50 49 0e e0 00 00 00 00 02 00 e3 01'),
                   bytes.fromhex('01 80 0e 50 49 08 f8 4c 70 69 00 04 00 20 02 01 00')]
        with patch.object(reader, 'isInterruptionRequested',
                          side_effect=[False, False, True]), patch.object(
                status.select, 'select', return_value=([99], [], [])), patch.object(
                status.os, 'read', side_effect=reports), patch.object(
                status.os, 'write', return_value=64) as write, patch.object(
                reader, 'status_changed') as signal:
            reader.monitor(99, True)
            write.assert_called_once()
            self.assertEqual([c.args[0] for c in signal.emit.call_args_list], [True, False])

    def test_read_only_permission_fallback(self):
        reader = status.HidReader()
        with patch.object(status.os, 'open', side_effect=[PermissionError(), 99]):
            self.assertEqual(reader.open_device('/fake'), (99, False))

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

    def tray(self):
        self.qt = status.QApplication.instance() or status.QApplication([])
        with patch.object(status.HidReader, 'start'), patch.object(status.AudioWorker, 'start'):
            return status.Tray()

    def test_pair_action_requires_confirmation(self):
        tray = self.tray()
        with patch.object(status.QMessageBox, 'question',
                          return_value=status.QMessageBox.StandardButton.No), patch.object(
                status.PairWorker, 'start') as start:
            tray.start_pairing()
            start.assert_not_called()
        self.assertTrue(tray.pair_action.isEnabled())
        with patch.object(status.QMessageBox, 'question',
                          return_value=status.QMessageBox.StandardButton.Yes), patch.object(
                status.PairWorker, 'start') as start:
            tray.start_pairing()
            start.assert_called_once()
        self.assertFalse(tray.pair_action.isEnabled())
        with patch.object(tray, 'showMessage') as show:
            tray.pairing_finished(True, 'done')
            show.assert_called_once()
        self.assertTrue(tray.pair_action.isEnabled())
        self.assertEqual(tray.pair_action.text(), 'Pair headset…')
        with patch.object(status.PairWorker, 'wait'):
            tray.close()

    def test_pair_worker_reports_result_and_missing_adapter(self):
        worker = status.PairWorker()
        results = []
        worker.finished_with.connect(lambda ok, message: results.append((ok, message)))
        with patch.object(status, 'find_hidraw', return_value=None):
            worker.run()
        with patch.object(status, 'find_hidraw', return_value='/fake'), patch.object(
                status.pairing, 'HidrawTransport') as transport, patch.object(
                status.pairing, 'run', side_effect=lambda session, **_: (
                    session.log('Paired. Turn the headset off and on to start the link'), 0)[1]):
            worker.run()
            transport.return_value.close.assert_called_once()
        with patch.object(status, 'find_hidraw', return_value='/fake'), patch.object(
                status.pairing, 'HidrawTransport'), patch.object(
                status.pairing, 'run', side_effect=status.pairing.PairingError('boom')):
            worker.run()
        self.assertEqual(results, [
            (False, 'Adapter not detected'),
            (True, 'Paired. Turn the headset off and on to start the link'),
            (False, 'Pairing failed: boom')])

if __name__ == '__main__':
    unittest.main()
