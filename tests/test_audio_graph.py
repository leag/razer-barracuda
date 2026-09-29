"""Load effects in a private PipeWire server with no devices or session manager."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from barracuda_pair import audio


@unittest.skipUnless(all(shutil.which(tool) for tool in ('pipewire', 'pw-dump', 'pw-cli')),
                     'PipeWire tools required for the isolated graph test')
class PrivateGraphTests(unittest.TestCase):
    def test_filters_load_and_accept_live_controls(self):
        with tempfile.TemporaryDirectory(prefix='barracuda-pw-') as directory:
            base = Path(directory)
            state = audio.defaults()
            for item in state['equalizers'].values():
                item['enabled'] = True
                item['gains'][2] = 4
            modules = [{'name': 'libpipewire-module-' + name} for name in
                       ('protocol-native', 'client-node', 'adapter', 'metadata',
                        'link-factory', 'spa-node-factory', 'access')]
            modules.extend(audio.equalizer(target, item) for target, item in state['equalizers'].items())
            modules.append(audio.sidetone_module(15, {'node.name': 'fake-mic'}, {'node.name': 'fake-sink'}))
            config = {'context.properties': {'core.daemon': True, 'core.name': 'barracuda-test'},
                      'context.spa-libs': {'audio.convert.*': 'audioconvert/libspa-audioconvert',
                                           'support.*': 'support/libspa-support'},
                      'context.modules': modules}
            path = base / 'test.conf'
            path.write_text(audio.spa_config(config))
            env = {**os.environ, 'XDG_RUNTIME_DIR': directory, 'PIPEWIRE_RUNTIME_DIR': directory,
                   'XDG_CONFIG_HOME': str(base / 'config'), 'PIPEWIRE_REMOTE': 'barracuda-test',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/nonexistent/barracuda-test',
                   'PIPEWIRE_DEBUG': '0', 'PULSE_SERVER': 'unix:/nonexistent/barracuda-test'}
            for key in ('PIPEWIRE_CONFIG_DIR', 'PIPEWIRE_CONFIG_NAME', 'PIPEWIRE_CONFIG_PREFIX'):
                env.pop(key, None)
            with (base / 'log').open('w') as log:
                process = subprocess.Popen(['pipewire', '-c', str(path)], env=env, stdout=log, stderr=log)
                try:
                    deadline = time.monotonic() + 5
                    while not (base / 'barracuda-test').exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(.02)
                    self.assertIsNone(process.poll(), (base / 'log').read_text())
                    result = subprocess.run(['pw-dump'], env=env, check=True, capture_output=True, text=True, timeout=5)
                    all_nodes = [o for o in json.loads(result.stdout) if o['type'].endswith(':Node')]
                    names = {o['info']['props']['node.name']: o for o in all_nodes}
                    self.assertEqual(len(names), 6)
                    for item in state['equalizers'].values():
                        item['gains'][2] = -3
                    with patch.dict(os.environ, env, clear=True):
                        audio.live_gains(state, all_nodes)
                    for name in ('barracuda.effects.output', 'barracuda.effects.microphone.stream'):
                        params = subprocess.run(['pw-cli', 'enum-params', str(names[name]['id']), 'Props'],
                                                env=env, check=True, capture_output=True, text=True, timeout=5)
                        self.assertIn('eq2:Gain', params.stdout)
                        self.assertIn('Float -3.000000', params.stdout)
                    self.assertNotIn('error', (base / 'log').read_text().lower())
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
