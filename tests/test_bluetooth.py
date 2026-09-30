"""Bluetooth transport tests use synthetic SDP/PI streams, never real devices."""
from contextlib import nullcontext
import errno
import struct
import unittest
from unittest.mock import MagicMock, Mock, patch

from barracuda_pair import bluetooth, headset


def pi(command, value, operation=1):
    data = bytes([command, operation, len(value)]) + value
    return b'PI\x08\xc5\0\0\0\0' + len(data).to_bytes(2, 'little') + data


class BluetoothTests(unittest.TestCase):
    def setUp(self):
        # Some managed Python builds omit Bluetooth constants; sockets stay mocked.
        for name, value in [('AF_BLUETOOTH', 31), ('BTPROTO_L2CAP', 0), ('BTPROTO_RFCOMM', 3)]:
            setting = patch.object(bluetooth.socket, name, value, create=True)
            setting.start()
            self.addCleanup(setting.stop)

    def test_sdp_discovers_channel_without_assuming_six(self):
        # One service record with a ProtocolDescriptorList and RFCOMM channel 9.
        # Build an exact minimal record instead of relying on lengths by inspection.
        rfcomm = b'\x35\x05\x19\x00\x03\x08\x09'
        protocols = b'\x35' + bytes([len(rfcomm)]) + rfcomm
        record = b'\x09\x00\x04' + protocols
        record = b'\x35' + bytes([len(record)]) + record
        attrs = b'\x35' + bytes([len(record)]) + record
        response = len(attrs).to_bytes(2, 'big') + attrs + b'\0'
        conn = MagicMock(); conn.__enter__.return_value = conn
        conn.recv.return_value = struct.pack('>BHH', 7, 1, len(response)) + response
        with patch.object(bluetooth.socket, 'socket', return_value=conn):
            self.assertEqual(bluetooth.spp_channel('01:02:03:04:05:06'), 9)
        conn.connect.assert_called_once_with(('01:02:03:04:05:06', 1))
        conn.recv.return_value = b'\x07\0'
        with patch.object(bluetooth.socket, 'socket', return_value=conn), self.assertRaises(OSError):
            bluetooth.spp_channel('01:02:03:04:05:06')

    def test_sdp_bounds_and_truncation(self):
        for raw in (b'', b'\x35\xff', b'\x36\0', b'\x09\0'):
            with self.subTest(raw=raw), self.assertRaises(OSError):
                bluetooth.sdp_element(raw)

    def test_fragmented_replies_skip_unsolicited_data(self):
        session = bluetooth.BluetoothSession('01:02:03:04:05:06')
        session.conn = Mock()
        raw = pi(0x13, b'\x09', 2) + pi(0x14, b'\0') + pi(0x13, b'\x07')
        session.conn.recv.side_effect = [raw[:5], raw[5:12], raw[12:]]
        self.assertEqual(session.exchange(bytes.fromhex('130000')), b'\x07')
        session.conn.sendall.assert_called_once_with(bytes.fromhex('5041084103130000'))

    def test_rejected_set_and_disconnect_are_not_retried(self):
        session = bluetooth.BluetoothSession('01:02:03:04:05:06'); session.conn = Mock()
        session.conn.recv.return_value = pi(0x93, b'\x01')
        self.assertEqual(session.exchange(bytes.fromhex('93000107')), b'\x01')
        session.conn.recv.return_value = b''
        with self.assertRaises(OSError) as caught:
            session.exchange(bytes.fromhex('130000'))
        self.assertEqual(caught.exception.errno, errno.ENOTCONN)
        self.assertEqual(session.conn.sendall.call_count, 2)

    def test_invalid_and_oversized_frames(self):
        for raw in (b'bad framing', b'PI\x08\0\0\0\0\0\xff\xff', pi(0x13,b'\0')[:-1]+b'\0\0'):
            session = bluetooth.BluetoothSession('01:02:03:04:05:06'); session.conn = Mock()
            if raw.startswith(b'PI') and len(raw)>12 and raw[8]==4:
                raw=raw[:12]+b'\x02'+raw[13:]  # Declared customer length disagrees.
            session.conn.recv.side_effect = [raw, b'']
            with self.assertRaises(OSError):
                session.exchange(bytes.fromhex('130000'))

    def test_identity_and_connection_are_required(self):
        adapter = Mock(name='adapter'); adapter.name = 'hci7'
        with patch.object(bluetooth.Path, 'glob', return_value=[adapter]), \
                patch.object(bluetooth.subprocess, 'run', return_value=Mock(stdout='{"data":"Other headset"}')):
            with self.assertRaises(OSError):
                bluetooth.paired_headset('01:02:03:04:05:06')
        with self.assertRaises(ValueError):
            bluetooth.paired_headset('$(touch nope)')

    def test_session_closes_on_connect_failure_and_interrupt(self):
        conn=Mock(); conn.connect.side_effect=OSError(errno.ECONNREFUSED,'Refused')
        with patch.object(bluetooth,'paired_headset',return_value='01:02:03:04:05:06'), \
                patch.object(bluetooth,'spp_channel',return_value=9), \
                patch.object(bluetooth.socket,'socket',return_value=conn):
            with self.assertRaises(OSError):
                with bluetooth.BluetoothSession('01:02:03:04:05:06'):
                    pass
        conn.close.assert_called_once()

    def test_bluetooth_dispatch_never_uses_usb_driver(self):
        session=bluetooth.BluetoothSession('01:02:03:04:05:06')
        session.exchange=Mock(return_value=b'\0')
        with patch.object(headset,'control_lock',return_value=nullcontext()), \
                patch.object(bluetooth.BluetoothSession,'__enter__',return_value=session), \
                patch.object(bluetooth.BluetoothSession,'__exit__',return_value=None), \
                patch.object(headset,'attribute') as usb, \
                patch.object(headset,'snapshot',return_value={'ok':True,'state':{}}):
            self.assertTrue(headset.dispatch({'op':'status','transport':'bluetooth','address':session.address})['ok'])
            usb.assert_not_called()
