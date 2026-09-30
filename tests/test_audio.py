"""Software-effects tests; all audio commands are mocked and files isolated."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from barracuda_pair import audio

ROOT = Path(__file__).resolve().parents[1]


def node(index, name, media_class, identity='USB1532:0552', **extra):
    return {'id': index, 'type': 'PipeWire:Interface:Node', 'info': {'props': {
        'node.name': name, 'media.class': media_class, 'alsa.components': identity, **extra}}}


DEVICES = [node(12, 'headset-output', 'Audio/Sink'), node(83, 'headset-input', 'Audio/Source'),
           node(7, 'speakers', 'Audio/Sink', 'OTHER'), node(15, 'webcam', 'Audio/Source', 'OTHER')]


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='barracuda audio ')
        self.addCleanup(self.directory.cleanup)
        self.env = patch.dict(os.environ, {'XDG_CONFIG_HOME': self.directory.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.commands = patch.object(audio, 'command', return_value=json.dumps(DEVICES)).start()
        self.addCleanup(patch.stopall)

    def test_status_is_read_only(self):
        result = audio.dispatch({'op': 'status'})
        self.assertTrue(result['has_microphone'])
        self.assertTrue(result['has_output'])
        self.assertEqual(list(Path(self.directory.name).iterdir()), [])
        self.commands.assert_called_once_with('pw-dump')

    def test_identity_not_fixed_index_or_default(self):
        self.assertEqual(audio.device(DEVICES, 'Audio/Source')['node.name'], 'headset-input')
        self.assertIsNone(audio.device([node(12, 'Barracuda', 'Audio/Sink', 'USB1532:05520')], 'Audio/Sink'))
        with self.assertRaisesRegex(audio.AudioError, 'ambiguous-device'):
            audio.device(DEVICES + [node(99, 'second-headset', 'Audio/Sink')], 'Audio/Sink')

    def test_invalid_gains_and_profiles(self):
        for values in ([0] * 9, [13] * 10, [float('nan')] * 10, [True] * 10, ['1'] * 10):
            with self.assertRaises(audio.AudioError):
                audio.gains(values)
        state = audio.defaults()
        state['equalizers']['output']['custom']['__proto__'] = [0] * 10
        with self.assertRaisesRegex(audio.AudioError, 'invalid-profile'):
            audio.normalize(state)

    def test_filter_graphs_and_scoped_policy(self):
        state = audio.defaults()
        for eq in state['equalizers'].values():
            eq['enabled'] = True
            eq['gains'][2] = 6
        state['tuning'].update(never_suspend=True, quantum=512, fixed_rate=True, headroom=1024)
        documents = {p.name: doc for p, doc in audio.documents(state, DEVICES).items()}
        self.assertEqual(documents['90-barracuda-effects.conf']['context.modules'], [])
        rules = documents['90-barracuda-audio.conf']['monitor.alsa.rules']
        self.assertTrue(all(rule['matches'][0]['alsa.components'] == 'USB1532:0552' for rule in rules))
        self.assertNotIn('api.alsa.headroom', rules[1]['actions']['update-props'])
        self.assertNotIn('api.alsa.period-size', json.dumps(documents))

    def test_small_buffer_options(self):
        for frames in (128, 256):
            state = audio.defaults()
            state['tuning'].update(quantum=frames, headroom=frames)
            state = audio.normalize(state)
            documents = {p.name: doc for p, doc in audio.documents(state, DEVICES).items()}
            self.assertEqual(documents['91-barracuda-latency.conf']['context.properties']['default.clock.quantum'], frames)
            rules = documents['90-barracuda-audio.conf']['monitor.alsa.rules']
            self.assertEqual(rules[0]['actions']['update-props']['api.alsa.headroom'], frames)

    def test_save_does_not_restart_or_change_defaults(self):
        state = audio.defaults()
        state['tuning']['quantum'] = 128
        result = audio.dispatch({'op': 'save', 'state': state})
        self.assertTrue(result['state']['pending_restart'])
        self.commands.assert_called_once_with('pw-dump')
        self.assertTrue(audio.state_path().exists())
        self.assertEqual(audio.load(), result['state'])
        self.assertEqual(len(list(Path(self.directory.name).rglob('*.conf'))), 3)
        self.assertNotIn('set-default', str(self.commands.call_args_list))

    def test_legacy_eq_is_detected_and_removed_only_on_explicit_request(self):
        state = audio.defaults()
        state['equalizers']['output']['enabled'] = True
        audio.state_path().parent.mkdir(parents=True)
        audio.state_path().write_text(json.dumps(state))
        legacy = DEVICES + [node(500, 'barracuda.effects.output', 'Audio/Sink', '')]
        self.assertTrue(audio.snapshot(state, legacy)['legacy_eq_loaded'])
        with self.assertRaisesRegex(audio.AudioError, 'confirmation-required'):
            audio.dispatch({'op': 'remove_eq'})
        self.assertNotIn('systemctl', str(self.commands.call_args_list))
        result = audio.dispatch({'op': 'remove_eq', 'confirmed': True})
        self.assertFalse(result['state']['equalizers']['output']['enabled'])
        self.assertNotIn('filter-chain', (Path(self.directory.name) / 'pipewire/pipewire.conf.d/90-barracuda-effects.conf').read_text())
        self.commands.assert_any_call('systemctl', '--user', 'restart', 'pipewire.service',
                                     'pipewire-pulse.service', 'wireplumber.service')

    def test_removed_sidetone_does_not_generate_a_filter(self):
        state = audio.defaults()
        state['sidetone'].update(enabled=True, level=17)
        document = next(iter(audio.documents(state, DEVICES).values()))
        self.assertEqual(document['context.modules'], [])
        result = audio.dispatch({'op': 'save', 'state': state})
        self.assertFalse(result['state']['sidetone']['enabled'])

    def test_sidetone_status_distinguishes_loaded_and_running(self):
        state = audio.defaults()
        self.assertFalse(audio.snapshot(state, DEVICES)['sidetone_loaded'])
        capture = node(201, audio.effect_name('sidetone'), 'Stream/Input/Audio', '')
        playback = node(202, audio.effect_name('sidetone') + '.stream', 'Stream/Output/Audio', '')
        current = DEVICES + [capture, playback]
        self.assertTrue(audio.snapshot(state, current)['sidetone_loaded'])
        self.assertFalse(audio.snapshot(state, current)['sidetone_running'])
        capture['info']['state'] = playback['info']['state'] = 'running'
        self.assertTrue(audio.snapshot(state, current)['sidetone_running'])
        self.assertFalse(audio.snapshot(state, current[:-1])['sidetone_running'])

    def test_profiles_and_favorites_persist(self):
        state = audio.defaults()
        state['equalizers']['output']['custom']["Música '$(touch nope)'"] = [1] * 10
        state['equalizers']['output']['favorites'] = ["Música '$(touch nope)'", 'Flat', 'missing']
        audio.dispatch({'op': 'save', 'state': state})
        saved = audio.load()
        self.assertEqual(saved['equalizers']['output']['favorites'], ["Música '$(touch nope)'"])
        self.assertFalse(saved['pending_restart'])
        self.commands.assert_called_once_with('pw-dump')

    def test_foreign_config_and_symlinks_are_not_overwritten(self):
        target = next(iter(audio.documents(audio.defaults(), DEVICES)))
        target.parent.mkdir(parents=True)
        target.write_text('existing user configuration')
        with self.assertRaisesRegex(audio.AudioError, 'foreign-config'):
            audio.dispatch({'op': 'save', 'state': audio.defaults()})
        self.assertEqual(target.read_text(), 'existing user configuration')
        self.assertFalse(audio.state_path().exists())
        target.unlink()
        foreign = Path(self.directory.name) / 'foreign'
        foreign.write_text('untouched')
        target.symlink_to(foreign)
        with self.assertRaisesRegex(audio.AudioError, 'foreign-config'):
            audio.dispatch({'op': 'save', 'state': audio.defaults()})
        self.assertEqual(foreign.read_text(), 'untouched')

    def test_restart_requires_explicit_confirmation(self):
        audio.dispatch({'op': 'save', 'state': audio.defaults()})
        self.commands.reset_mock()
        with self.assertRaisesRegex(audio.AudioError, 'confirmation-required'):
            audio.dispatch({'op': 'apply'})
        self.assertNotIn('systemctl', str(self.commands.call_args_list))
        audio.dispatch({'op': 'apply', 'confirmed': True})
        self.commands.assert_any_call('systemctl', '--user', 'restart', 'pipewire.service',
                                      'pipewire-pulse.service', 'wireplumber.service')

    def test_single_apply_only_restarts_when_needed_and_authorized(self):
        state = audio.defaults()
        result = audio.dispatch({'op': 'save_apply', 'state': state, 'confirmed': True})
        self.assertFalse(result['state']['pending_restart'])
        self.assertNotIn('systemctl', str(self.commands.call_args_list))
        state['tuning']['quantum'] = 128
        result = audio.dispatch({'op': 'save_apply', 'state': state, 'confirmed': False})
        self.assertTrue(result['state']['pending_restart'])
        self.assertNotIn('systemctl', str(self.commands.call_args_list))
        self.commands.reset_mock()
        result = audio.dispatch({'op': 'save_apply', 'state': state, 'confirmed': True})
        self.assertFalse(result['state']['pending_restart'])
        restarts = [call for call in self.commands.call_args_list if call.args[0] == 'systemctl']
        self.assertEqual(len(restarts), 1)

    def test_disable_restores_empty_owned_fragments(self):
        state = audio.defaults()
        state['equalizers']['output']['enabled'] = True
        state['tuning']['never_suspend'] = True
        audio.dispatch({'op': 'save', 'state': state})
        audio.dispatch({'op': 'save', 'state': audio.defaults()})
        for path, value in audio.documents(audio.defaults(), DEVICES).items():
            self.assertEqual(path.read_text(), audio.OWNER + audio.spa_config(value))
            self.assertTrue(all(not item for item in value.values()))

    def test_microphone_muting_targets_physical_device(self):
        audio.dispatch({'op': 'microphone', 'muted': True})
        self.commands.assert_any_call('pactl', 'set-source-mute', 'headset-input', '1')
        self.commands.return_value = json.dumps(DEVICES[:1])
        with self.assertRaisesRegex(audio.AudioError, 'missing-microphone'):
            audio.dispatch({'op': 'microphone', 'muted': False})

    def test_microphone_volume_is_explicit_and_bounded(self):
        audio.dispatch({'op': 'microphone', 'volume': 57})
        self.commands.assert_any_call('pactl', 'set-source-volume', 'headset-input', '57%')
        self.commands.reset_mock()
        with self.assertRaises(audio.AudioError):
            audio.dispatch({'op': 'microphone', 'volume': 101})
        self.commands.assert_called_once_with('pw-dump')

    def test_failed_file_replacement_rolls_back(self):
        first = Path(self.directory.name) / 'first.conf'
        second = Path(self.directory.name) / 'second.conf'
        first.write_text(audio.OWNER + 'original')
        replace = os.replace
        def fail_second(source, destination):
            if destination == second:
                raise OSError('simulated disk failure')
            return replace(source, destination)
        with patch.object(audio.os, 'replace', side_effect=fail_second):
            with self.assertRaises(OSError):
                audio.write_files({first: audio.OWNER + 'new', second: audio.OWNER + 'other'})
        self.assertEqual(first.read_text(), audio.OWNER + 'original')
        self.assertFalse(second.exists())
        self.assertEqual(list(Path(self.directory.name).iterdir()), [first])

    def test_optional_install_uses_xdg_without_enabling_audio(self):
        home = Path(self.directory.name) / 'home'
        home.mkdir()
        env = {**os.environ, 'HOME': str(home), 'XDG_DATA_HOME': str(home / 'data')}
        subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'), '--audio-controls'],
                       env=env, check=True, capture_output=True)
        launcher = home / '.local/bin/barracuda-audio'
        result = subprocess.run([str(launcher), '--help'], cwd=home, env=env,
                                check=True, capture_output=True, text=True)
        self.assertIn('--request', result.stdout)
        self.assertFalse((Path(self.directory.name) / 'pipewire').exists())
        self.assertTrue((home / 'data/barracuda-pair/LICENSES/TarikTopalovic-MIT.txt').exists())
