"""Route desktop playback through pactl (PipeWire/PulseAudio)."""
import json
import subprocess
from pathlib import Path

from .i18n import tr


class AudioRouter:
    def __init__(self, state_file):
        self.state_file = Path(state_file)
        self.previous = None
        self.headset = None
        self.last = 'unknown'
        try:
            saved = json.loads(self.state_file.read_text())
            self.previous = saved.get('previous')
            self.headset = saved.get('headset')
        except (OSError, ValueError, AttributeError):
            pass

    def command(self, *args):
        return subprocess.run(['pactl', *args], check=True, capture_output=True,
                              text=True, timeout=3).stdout.strip()

    def save(self):
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.state_file.with_suffix('.tmp')
        temporary.write_text(json.dumps({'previous': self.previous, 'headset': self.headset}))
        temporary.replace(self.state_file)

    def update(self, linked):
        if linked == 'unknown':
            return
        connected = linked is True
        if connected == self.last:
            return
        sinks = json.loads(self.command('-f', 'json', 'list', 'sinks'))
        names = {sink['name'] for sink in sinks}
        current = self.command('get-default-sink')
        if connected:
            headset = next((sink['name'] for sink in sinks
                            if sink.get('properties', {}).get('device.vendor.id') == '0x1532'
                            and sink.get('properties', {}).get('device.product.id') == '0x0552'), None)
            if not headset:
                raise RuntimeError(tr("The Barracuda audio output is not available yet"))
            self.headset = headset
            if current != headset:
                self.previous = current
            self.save()
            target = headset
        else:
            # Respect a manual output change made while the headset was connected.
            if current != self.headset:
                self.last = connected
                return
            if self.previous not in names:
                raise RuntimeError(tr("The previous audio output is unavailable"))
            target = self.previous
        self.command('set-default-sink', target)
        # Move streams on the old default, leaving explicitly routed apps alone.
        old_index = next((sink['index'] for sink in sinks if sink['name'] == current), None)
        streams = json.loads(self.command('-f', 'json', 'list', 'sink-inputs'))
        for stream in streams:
            if str(stream['sink']) == str(old_index) and current != target:
                try:
                    self.command('move-sink-input', str(stream['index']), target)
                except subprocess.CalledProcessError:
                    # Applications may close their stream between listing and moving.
                    remaining = json.loads(self.command('-f', 'json', 'list', 'sink-inputs'))
                    if any(item['index'] == stream['index'] for item in remaining):
                        raise
        self.last = connected
