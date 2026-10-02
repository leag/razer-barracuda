"""Native controls with fake driver replies; no HID or real audio changes."""
from contextlib import nullcontext
import errno
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

from barracuda_pair import headset


class HeadsetTests(unittest.TestCase):
    def test_bounded_payloads_and_forbidden_requests(self):
        self.assertEqual(headset.payload('preset', 7), bytes.fromhex('93000107'))
        self.assertEqual(headset.payload('gaming', True), bytes.fromhex('94000101'))
        self.assertEqual(headset.payload('bands', [0] * 10), bytes.fromhex('95000a') + b'\x05' * 10)
        for feature, value in [('preset', True), ('preset', 3), ('standby', 255),
                               ('bands', [6] * 10), ('bands', [False] * 10),
                               ('gaming', 1), ('firmware', 1), ('devices', '0011')]:
            with self.subTest(feature=feature, value=value), self.assertRaises(headset.HeadsetError):
                headset.payload(feature, value)

    def test_quick_connect_empty_and_malformed_lists(self):
        self.assertEqual(headset.quick_devices(b''), [])
        record = b'\x01' + bytes.fromhex('010203040506') + b'Phone\0'
        parsed = headset.quick_devices(bytes([len(record)]) + record)
        self.assertEqual(parsed, [{'address': '010203040506', 'active': True, 'name': 'Phone'}])
        for data in (b'\xff', b'\x00', b'\x08\x01', b'\x08' + b'\x02' * 8):
            with self.assertRaises(headset.HeadsetError):
                headset.quick_devices(data)

    def test_unknown_values_are_not_defaults(self):
        with patch.object(headset, 'exchange', return_value=b'\x03'):
            with self.assertRaisesRegex(headset.HeadsetError, 'unsupported-value'):
                headset.read(Mock(), 'preset')
        with patch.object(headset, 'exchange', return_value=b'\x05' * 10):
            self.assertEqual(headset.read(Mock(), 'bands'), [0] * 10)

    def test_snapshot_retains_partial_support(self):
        def read(path, feature):
            if feature == 'dnd':
                raise OSError(errno.ETIMEDOUT, 'No reply')
            return [] if feature == 'devices' else [0] * 10 if feature == 'bands' else 0
        with patch.object(headset, 'read', side_effect=read):
            result = headset.snapshot(Mock())
        self.assertIsNone(result['state']['dnd'])
        self.assertEqual(result['errors']['dnd'], 'timeout')
        self.assertEqual(result['state']['preset'], 0)

    def test_link_unknown_stops_without_claiming_disconnection(self):
        with patch.object(headset, 'read', side_effect=OSError(errno.ENOTCONN, 'Unknown')) as read:
            result = headset.snapshot(Mock())
        self.assertEqual(read.call_count, 1)
        self.assertTrue(all(value is None for value in result['state'].values()))
        self.assertEqual(set(result['errors'].values()), {'unknown-link'})

    def test_exchange_correlates_token_and_handles_empty_reply(self):
        path = MagicMock()
        path.open.return_value.__enter__.return_value.write.return_value = 16
        path.read_text.return_value = '12345678 \n'
        with patch.object(headset.secrets, 'token_hex', return_value='12345678'):
            self.assertEqual(headset.exchange(path, bytes.fromhex('2d0000')), b'')
            path.read_text.return_value = '87654321 00\n'
            with self.assertRaisesRegex(headset.HeadsetError, 'reply-conflict'):
                headset.exchange(path, bytes.fromhex('2d0000'))

    def test_set_checks_readback_and_never_retries(self):
        with patch.object(headset, 'control_lock', return_value=nullcontext()), \
                patch.object(headset, 'attribute', return_value=Mock()), \
                patch.object(headset, 'exchange', return_value=b'\0') as exchange, \
                patch.object(headset, 'read', return_value=0):
            with self.assertRaisesRegex(headset.HeadsetError, 'unconfirmed'):
                headset.dispatch({'op': 'set', 'feature': 'preset', 'value': 7})
            self.assertEqual(exchange.call_count, 1)

    def test_quick_connect_only_selects_known_devices_and_checks_gaming(self):
        with patch.object(headset, 'control_lock', return_value=nullcontext()), \
                patch.object(headset, 'attribute', return_value=Mock()), \
                patch.object(headset, 'exchange') as exchange, \
                patch.object(headset, 'read', return_value=[]):
            with self.assertRaisesRegex(headset.HeadsetError, 'unknown-device'):
                headset.dispatch({'op': 'set', 'feature': 'devices', 'value': '010203040506'})
            exchange.assert_not_called()

    def test_gaming_ack_without_state_change_is_not_success(self):
        with patch.object(headset, 'control_lock', return_value=nullcontext()), \
                patch.object(headset, 'attribute', return_value=Mock()), \
                patch.object(headset, 'exchange', return_value=b'\0') as exchange, \
                patch.object(headset, 'read', return_value=False):
            with self.assertRaisesRegex(headset.HeadsetError, 'gaming-not-applied'):
                headset.dispatch({'op': 'set', 'feature': 'gaming', 'value': True})
            exchange.assert_called_once()
            self.assertEqual(exchange.call_args.args[1], bytes.fromhex('94000101'))
        with patch.object(headset, 'control_lock', return_value=nullcontext()), \
                patch.object(headset, 'attribute', return_value=Mock()), \
                patch.object(headset, 'read', side_effect=[[{'address': '010203040506'}], True]), \
                patch.object(headset, 'exchange') as exchange:
            with self.assertRaisesRegex(headset.HeadsetError, 'gaming-active'):
                headset.dispatch({'op': 'set', 'feature': 'devices', 'value': '010203040506'})
            exchange.assert_not_called()

    def test_quick_connect_ack_then_disconnect_reports_requested_switch(self):
        with patch.object(headset, 'control_lock', return_value=nullcontext()), \
                patch.object(headset, 'attribute', return_value=Mock()), \
                patch.object(headset, 'exchange', return_value=b'\0') as exchange, \
                patch.object(headset, 'read', side_effect=[
                    [{'address': '010203040506'}], False,
                    OSError(errno.ENOTCONN, 'Switching hosts')]):
            result = headset.dispatch({'op': 'set', 'feature': 'devices', 'value': '010203040506'})
        self.assertTrue(result['ok'])
        self.assertEqual(result['sent'], 'devices')
        self.assertTrue(all(value is None for value in result['state'].values()))
        exchange.assert_called_once()

    def test_driver_upgrade_has_no_raw_hid_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            power = Path(directory) / 'headset_poweroff'
            power.touch()
            with patch.object(headset, 'power_attribute', return_value=power):
                with self.assertRaisesRegex(headset.HeadsetError, 'driver-required'):
                    headset.attribute()


    def adapter(self, root, link=None, driver='razer-barracuda', supply=None):
        interface = root / 'usb' / '1-1:1.3'
        interface.mkdir(parents=True)
        (interface / 'bInterfaceNumber').write_text('03\n')
        if link is not None:
            (interface / 'wireless_status').write_text(link + '\n')
        device = interface / '0003:1532:0552.0001'
        device.mkdir()
        (device / 'uevent').write_text('HID_ID=0003:00001532:00000552\n')
        (root / 'drivers' / driver).mkdir(parents=True)
        (device / 'driver').symlink_to(root / 'drivers' / driver)
        if supply is not None:
            battery = device / 'power_supply' / 'razer-barracuda-0003:1532:0552.0001-battery'
            battery.mkdir(parents=True)
            (battery / 'uevent').write_text(supply)
        (root / 'hid').mkdir()
        (root / 'hid' / device.name).symlink_to(device)
        return root / 'hid'

    def test_link_reads_published_state_and_keeps_unknown_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            hid = Path(directory) / 'hid'
            hid.mkdir()
            self.assertEqual(headset.usb_link(hid), {'adapter': 'missing'})
            self.assertEqual(headset.usb_link(Path(directory) / 'absent'), {'adapter': 'missing'})
        for link, expected in ((None, 'unknown'), ('connected', 'connected'),
                               ('disconnected', 'disconnected'), ('not supported', 'unknown')):
            with self.subTest(link=link), tempfile.TemporaryDirectory() as directory:
                result = headset.usb_link(self.adapter(Path(directory), link))
                self.assertEqual(result, {'adapter': 'present', 'driver': True,
                                          'link': expected, 'battery': None})
        with tempfile.TemporaryDirectory() as directory:
            # A stale attribute without the project driver is not link evidence.
            result = headset.usb_link(self.adapter(Path(directory), 'connected', driver='hid-generic'))
            self.assertEqual(result, {'adapter': 'present', 'driver': False,
                                      'link': 'unknown', 'battery': None})

    def test_link_battery_details_without_queries(self):
        supply = ('POWER_SUPPLY_NAME=razer-barracuda-battery\nPOWER_SUPPLY_STATUS=Charging\n'
                  'POWER_SUPPLY_CAPACITY=65\nPOWER_SUPPLY_VOLTAGE_NOW=4123456\n')
        with tempfile.TemporaryDirectory() as directory:
            result = headset.usb_link(self.adapter(Path(directory), 'connected', supply=supply))
            self.assertEqual(result['battery'], {'percent': 65, 'status': 'Charging',
                                                 'cable': True, 'voltage_mv': 4123})
        for text, expected in (('POWER_SUPPLY_STATUS=Discharging\n',
                                {'percent': None, 'status': 'Discharging', 'cable': False, 'voltage_mv': None}),
                               ('POWER_SUPPLY_STATUS=Full\nPOWER_SUPPLY_CAPACITY=100\n',
                                {'percent': 100, 'status': 'Full', 'cable': True, 'voltage_mv': None}),
                               ('POWER_SUPPLY_STATUS=Unknown\nPOWER_SUPPLY_CAPACITY=101\n'
                                'POWER_SUPPLY_VOLTAGE_NOW=-1\n',
                                {'percent': None, 'status': 'Unknown', 'cable': None, 'voltage_mv': None})):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as directory:
                result = headset.usb_link(self.adapter(Path(directory), 'connected', supply=text))
                self.assertEqual(result['battery'], expected)

    def test_link_request_is_read_only_and_unlocked(self):
        with patch.object(headset, 'control_lock', side_effect=AssertionError('locked')), \
                patch.object(headset, 'exchange', side_effect=AssertionError('query')), \
                patch.object(headset, 'usb_link', return_value={'adapter': 'missing'}), \
                patch.object(headset, 'headset_presence', return_value=None):
            self.assertEqual(headset.dispatch({'op': 'link'}),
                             {'ok': True, 'usb': {'adapter': 'missing'}, 'bluetooth': None})


if __name__ == '__main__':
    unittest.main()
