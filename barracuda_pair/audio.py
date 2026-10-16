"""Explicit Linux audio tuning for the Barracuda output and microphone."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


OWNER = '# Managed by barracuda-audio.\n'


class AudioError(Exception):
    def __init__(self, code, detail=''):
        self.code, self.detail = code, detail
        super().__init__(code + (': ' + detail if detail else ''))


def command(*args):
    try:
        return subprocess.run(args, check=True, capture_output=True, text=True, timeout=20).stdout
    except FileNotFoundError as exc:
        raise AudioError('missing-command', args[0]) from exc
    except subprocess.CalledProcessError as exc:
        raise AudioError('command-failed', (exc.stderr or str(exc)).strip()) from exc
    except subprocess.TimeoutExpired as exc:
        raise AudioError('command-timeout', args[0]) from exc


def config_home():
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))


def defaults():
    return {'version': 1,
            'tuning': {'quantum': 0, 'fixed_rate': False, 'never_suspend': False, 'headroom': 0},
            'pending_restart': False}


def normalize(value):
    """Validate tuning; keys written by older versions are ignored."""
    state = defaults()
    try:
        if value.get('version', 1) != 1:
            raise AudioError('invalid-settings')
        tuning = value['tuning']
        if (type(tuning['quantum']) is not int or tuning['quantum'] not in (0, 128, 256, 512, 1024)
                or type(tuning['headroom']) is not int or tuning['headroom'] not in (0, 128, 256, 512, 1024, 2048)
                or type(tuning['fixed_rate']) is not bool or type(tuning['never_suspend']) is not bool):
            raise AudioError('invalid-settings')
        state['tuning'] = {key: tuning[key] for key in state['tuning']}
        state['pending_restart'] = bool(value.get('pending_restart', False))
    except (KeyError, TypeError, AttributeError) as exc:
        raise AudioError('invalid-settings') from exc
    return state


def state_path():
    return config_home() / 'barracuda-audio/settings.json'


def load():
    try:
        return normalize(json.loads(state_path().read_text()))
    except FileNotFoundError:
        return defaults()
    except (ValueError, OSError) as exc:
        raise AudioError('invalid-settings', str(exc)) from exc


def nodes():
    try:
        objects = json.loads(command('pw-dump'))
        return [o for o in objects if o.get('type') == 'PipeWire:Interface:Node']
    except (ValueError, TypeError) as exc:
        raise AudioError('invalid-audio-response') from exc


def device(nodes_list, media_class):
    found = []
    for node in nodes_list:
        props = node.get('info', {}).get('props', {})
        if (props.get('media.class') == media_class
                and re.search(r'(^| )USB1532:0552( |$)', str(props.get('alsa.components', '')), re.I)):
            found.append(props)
    if len(found) > 1:
        raise AudioError('ambiguous-device')
    return found[0] if found else None


def documents(state):
    tune = state['tuning']
    clock = {}
    if tune['quantum']:
        clock['default.clock.quantum'] = tune['quantum']
    if tune['fixed_rate']:
        clock.update({'default.clock.rate': 48000, 'default.clock.allowed-rates': [48000]})
    rules = []
    for media_class in ('Audio/Sink', 'Audio/Source'):
        props = {}
        if tune['never_suspend']:
            props.update({'session.suspend-timeout-seconds': 0, 'node.pause-on-idle': False})
        if media_class == 'Audio/Sink' and tune['headroom']:
            props['api.alsa.headroom'] = tune['headroom']
        if props:
            rules.append({'matches': [{'alsa.components': 'USB1532:0552', 'media.class': media_class}],
                          'actions': {'update-props': props}})
    root = config_home()
    return {
        root / 'pipewire/pipewire.conf.d/91-barracuda-latency.conf': {'context.properties': clock},
        root / 'wireplumber/wireplumber.conf.d/90-barracuda-audio.conf': {'monitor.alsa.rules': rules}}


def spa_value(value, depth=0):
    """Encode native SPA configuration, quoting every string and property name."""
    indent = '    ' * depth
    if isinstance(value, dict):
        lines = [json.dumps(k) + ' = ' + spa_value(v, depth + 1) for k, v in value.items()]
        return '{\n' + ''.join(indent + '    ' + line + '\n' for line in lines) + indent + '}'
    if isinstance(value, list):
        return '[\n' + ''.join(indent + '    ' + spa_value(v, depth + 1) + '\n' for v in value) + indent + ']'
    return json.dumps(value, allow_nan=False)


def spa_config(document):
    return '\n'.join(json.dumps(k) + ' = ' + spa_value(v) for k, v in document.items()) + '\n'


def write_files(files):
    """Stage all files, refuse foreign fragments, and roll back failed replacements."""
    previous, staged, replaced = {}, {}, []
    try:
        for path, text in files.items():
            if path.is_symlink():
                raise AudioError('foreign-config', str(path))
            old = path.read_text() if path.exists() else None
            if path.suffix == '.conf' and old is not None and not old.startswith(OWNER):
                raise AudioError('foreign-config', str(path))
            previous[path] = old
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as temp:
                temp.write(text)
                staged[path] = Path(temp.name)
        for path, temp in staged.items():
            os.replace(temp, path)
            replaced.append(path)
    except Exception:
        for path in reversed(replaced):
            if previous[path] is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(previous[path])
        raise
    finally:
        for temp in staged.values():
            temp.unlink(missing_ok=True)


def snapshot(state, nodes_list):
    source, sink = device(nodes_list, 'Audio/Source'), device(nodes_list, 'Audio/Sink')
    return {'state': state, 'has_microphone': bool(source), 'has_output': bool(sink)}


def dispatch(request):
    op = request.get('op', 'status')
    if op == 'save_apply':
        result = dispatch({'op': 'save', 'state': request['state']})
        if result['state']['pending_restart'] and request.get('confirmed') is True:
            return dispatch({'op': 'apply', 'confirmed': True})
        return result
    old = load()
    if op not in ('status', 'save', 'apply', 'microphone'):
        raise AudioError('invalid-request')
    current_nodes = nodes()
    state = old
    if op == 'save':
        state = normalize(request['state'])
        generated = documents(state)
        # System policy changes require a confirmed audio restart.
        state['pending_restart'] = (old['pending_restart'] or state['pending_restart']
                                    or old['tuning'] != state['tuning'])
        files = {path: OWNER + spa_config(value) for path, value in generated.items()}
        files[state_path()] = json.dumps(state, indent=2) + '\n'
        write_files(files)
    elif op == 'apply':
        # Restarting the audio services requires an explicit confirmation.
        if request.get('confirmed') is not True:
            raise AudioError('confirmation-required')
        if not state_path().exists():
            raise AudioError('save-first')
        command('systemctl', '--user', 'restart', 'pipewire.service', 'pipewire-pulse.service', 'wireplumber.service')
        current_nodes = nodes()
        state['pending_restart'] = False
        write_files({state_path(): json.dumps(state, indent=2) + '\n'})
    elif op == 'microphone':
        source = device(current_nodes, 'Audio/Source')
        if not source:
            raise AudioError('missing-microphone')
        if 'muted' not in request and 'volume' not in request:
            raise AudioError('invalid-request')
        if 'muted' in request and type(request['muted']) is not bool:
            raise AudioError('invalid-request')
        if 'volume' in request and (type(request['volume']) is not int or not 0 <= request['volume'] <= 100):
            raise AudioError('invalid-request')
        if 'muted' in request:
            command('pactl', 'set-source-mute', source['node.name'], '1' if request['muted'] else '0')
        if 'volume' in request:
            command('pactl', 'set-source-volume', source['node.name'], str(request['volume']) + '%')
    return {'ok': True, **snapshot(state, current_nodes)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', default='{"op":"status"}',
                        help='JSON request: op status, save, apply, save_apply or microphone; '
                             'apply and save_apply restart audio only with "confirmed": true')
    args = parser.parse_args(argv)
    try:
        request = json.loads(args.request)
        if not isinstance(request, dict):
            raise AudioError('invalid-request')
        if request.get('op', 'status') == 'status':
            response = dispatch(request)
        else:
            state_path().parent.mkdir(parents=True, exist_ok=True)
            with (state_path().parent / '.lock').open('a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError as exc:
                    raise AudioError('busy') from exc
                response = dispatch(request)
    except AudioError as exc:
        response = {'ok': False, 'error': exc.code, 'detail': exc.detail}
    except (ValueError, KeyError, TypeError, OSError) as exc:
        response = {'ok': False, 'error': 'invalid-request', 'detail': str(exc)}
    print(json.dumps(response, ensure_ascii=True))
    return 0 if response['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
