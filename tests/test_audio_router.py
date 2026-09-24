import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
from barracuda_status.audio_router import AudioRouter


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.router = AudioRouter(Path(self.tmp.name) / 'audio.json')
        self.current = 'speakers'
        self.sinks = [{'name': 'speakers', 'index': 1}, {'name': 'headset', 'index': 2,
                      'properties': {'device.vendor.id': '0x1532', 'device.product.id': '0x0552'}}]
        self.moves = []
        self.cards = []
        self.router.command = Mock(side_effect=self.command)
        # Never probe the real system's PipeWire plugin or USB devices.
        self.router.spa_plugins = ()
        self.router.usb_devices = Path(self.tmp.name) / 'usb'

    def command(self, *args):
        if args == ('get-default-sink',):
            return self.current
        if args == ('-f', 'json', 'list', 'sinks'):
            return json.dumps(self.sinks)
        if args == ('-f', 'json', 'list', 'cards'):
            return json.dumps(self.cards)
        if args == ('-f', 'json', 'list', 'sink-inputs'):
            return json.dumps([{'index': 10, 'sink': 1}, {'index': 20, 'sink': 2}])
        if args[0] == 'set-default-sink':
            self.current = args[1]
        if args[0] == 'move-sink-input':
            self.moves.append(args[1:])
        return ''

    def test_connect_and_restore_with_playing_streams(self):
        self.router.update(True)
        self.assertEqual(self.current, 'headset')
        self.assertEqual(self.moves, [('10', 'headset')])
        count = self.router.command.call_count
        self.router.update(True)
        self.router.update('unknown')
        self.assertEqual(self.router.command.call_count, count)
        self.router.update(False)
        self.assertEqual(self.current, 'speakers')
        self.assertEqual(self.moves[-1], ('20', 'speakers'))

    def test_restore_after_restart_and_usb_removal(self):
        self.router.update(True)
        restored = AudioRouter(self.router.state_file)
        restored.command = self.router.command
        self.sinks.pop()
        restored.update(None)
        self.assertEqual(self.current, 'speakers')

    def test_respect_manual_selection(self):
        self.router.update(True)
        self.current = 'hdmi'
        self.router.update(False)
        self.assertEqual(self.current, 'hdmi')

    def test_missing_headset_retries(self):
        headset = self.sinks.pop()
        with self.assertRaises(RuntimeError):
            self.router.update(True)
        self.assertEqual(self.current, 'speakers')
        self.sinks.append(headset)
        self.router.update(True)
        self.assertEqual(self.current, 'headset')

    def test_missing_previous_does_not_choose_arbitrary_output(self):
        self.router.update(True)
        self.sinks.pop(0)
        with self.assertRaises(RuntimeError):
            self.router.update(False)
        self.assertEqual(self.current, 'headset')

    def barracuda_card(self, group):
        return {'name': 'alsa_card.usb-barracuda',
                'properties': {'device.vendor.id': '0x1532', 'device.product.id': '0x0552'},
                'ports': {'analog-output-headphones': {'availability_group': group},
                          'analog-input-mic': {'availability_group': ''}}}

    def test_jack_detection_leaves_switching_to_pipewire(self):
        self.cards = [{'name': 'other', 'properties': {}, 'ports': {
            'x': {'availability_group': 'Legacy 1'}}}, self.barracuda_card('Legacy 1')]
        self.router.update(True)
        self.router.update(False)
        self.assertEqual(self.current, 'speakers')
        self.assertEqual(self.moves, [])
        self.assertEqual(self.router.mode, 'pipewire')
        self.assertFalse(any(call.args and call.args[0] == 'set-default-sink'
                             for call in self.router.command.call_args_list))

    def test_without_jack_detection_routes_as_before(self):
        for cards in ([], [self.barracuda_card('')]):
            self.cards = cards
            self.router.last = 'unknown'
            self.current = 'speakers'
            self.router.update(True)
            self.assertEqual(self.current, 'headset')
            self.assertEqual(self.router.mode, 'pactl')

    def test_unreadable_cards_fall_back_to_routing(self):
        original = self.command

        def broken(*args):
            if args == ('-f', 'json', 'list', 'cards'):
                return 'not json'
            return original(*args)
        self.router.command = Mock(side_effect=broken)
        self.router.update(True)
        self.assertEqual(self.current, 'headset')

    def make_usb(self, vendor='1532', product='0552'):
        root = Path(self.tmp.name) / 'usb'
        device = Path(self.tmp.name) / 'devices' / '1-1'
        interface = device / '1-1:1.3'
        interface.mkdir(parents=True)
        (device / 'idVendor').write_text(vendor + '\n')
        (device / 'idProduct').write_text(product + '\n')
        (interface / 'wireless_status').write_text('disconnected\n')
        root.mkdir()
        (root / '1-1:1.3').symlink_to(interface)
        return root

    def test_wireless_status_with_supporting_pipewire_delegates(self):
        plugin = Path(self.tmp.name) / 'libspa-alsa.so'
        plugin.write_bytes(b'\0...%s/wireless_status\0...')
        self.router.spa_plugins = (str(plugin),)
        self.router.usb_devices = self.make_usb()
        self.router.update(True)
        self.assertEqual(self.router.mode, 'pipewire')
        self.assertEqual(self.current, 'speakers')

    def test_wireless_status_needs_both_pipewire_and_dongle_support(self):
        old_plugin = Path(self.tmp.name) / 'old-libspa-alsa.so'
        old_plugin.write_bytes(b'\0no such feature\0')
        self.router.spa_plugins = (str(old_plugin),)
        self.router.usb_devices = self.make_usb()
        self.router.update(True)
        self.assertEqual(self.router.mode, 'pactl')
        self.assertEqual(self.current, 'headset')

    def test_wireless_status_of_other_devices_is_ignored(self):
        from barracuda_status import audio_router
        self.assertFalse(audio_router.dongle_wireless_status(self.make_usb('046d', 'c52b')))
        self.assertFalse(audio_router.dongle_wireless_status(Path(self.tmp.name) / 'missing'))
        self.assertFalse(audio_router.pipewire_wireless_support(('/nonexistent',)))
