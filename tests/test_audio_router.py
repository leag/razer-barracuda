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
