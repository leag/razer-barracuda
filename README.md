# Barracuda Status

A Linux system tray app for **Razer Barracuda X (2022), USB dongle `1532:0552`**.
Shows the observed wireless link status and switches desktop audio to the headset
when it connects, restoring the previous output when it disconnects.

The interface supports **English (default)** and **Spanish**. Project documentation
is in English. This is an independent project, not an official Razer application.

## Features

- Connected, disconnected, missing-adapter and unknown-state indicators.
- Automatic output selection through PipeWire/PulseAudio, including playback
  streams on the previous default output.
- Remembers the previous output across app restarts and respects manual output
  changes made while the headset is connected.
- Read-only HID monitoring; no firmware or pairing commands.
- Original generic headset icons included. No proprietary Razer assets required.

## Requirements

- Linux, Python 3.10+, uv and a system tray (tested on KDE Plasma).
- PyQt6 is installed into the project environment by uv.
- PipeWire with PulseAudio compatibility, or PulseAudio, and `pactl`.
- Read access to the dongle's HID device.

On Arch/CachyOS, install the dependencies:

```bash
sudo pacman -S python uv libpulse
```

## Install

From a checkout:

```bash
uv sync --locked
uv run python scripts/install.py --autostart
sudo install -Dm644 packaging/99-razer-barracuda.rules /etc/udev/rules.d/99-razer-barracuda.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Reconnect the dongle if permission errors persist. Run as your desktop user,
not root. Launch from your application menu or:

```bash
~/.local/bin/barracuda-status
```

Keep the checkout and its `.venv` available: the installed launcher uses that
virtual environment. Reinstall after moving the checkout.

The installer copies the package to your user data directory and creates a launcher
in `~/.local/bin`. It uses the Python interpreter that ran the installer, so keep
that interpreter available. It does not restart an existing instance.
`--autostart` creates a KDE/session autostart entry, not a permanent systemd unit.
Run only one instance to avoid competing audio changes. Stop an older instance
before launching an updated copy.

To install with Spanish as the launch language:

```bash
uv run python scripts/install.py --autostart --language es
```

For development without installation:

```bash
uv run barracuda-status                 # English
uv run barracuda-status --language es   # Español
```

Build release archives with `uv build`. To install the built wheel in a separate,
persistent environment, use `uv tool install dist/barracuda_status-0.1.0-py3-none-any.whl`.
This creates the CLI only; HID permissions and desktop integration remain separate.
Do not mix install methods unless you manage their paths.

## How it behaves

| Indicator | Meaning |
| --- | --- |
| Green | Headset link confirmed |
| Amber | No wireless link |
| Red | Adapter missing or read error |
| Gray | Waiting for a valid link report |

USB presence alone does not confirm a wireless connection. The dongle can remain
silent at startup: turn the headset off and on once to obtain the initial state.
Unknown status never changes the audio output. Restarting the app loses its
observed HID status until another report arrives.

On connection, the app remembers the current default output and selects the
Barracuda sink by USB vendor/product properties. On disconnection it restores the
saved output if available and if the headset is still the default. Playback on
other outputs is left alone. It does not change volume, microphone or card profile.
Applications that bypass PipeWire/PulseAudio and use ALSA directly cannot be moved.

The previous output is stored in `$XDG_STATE_HOME/barracuda-status/audio.json`
(default: `~/.local/state/barracuda-status/audio.json`). Audio errors appear in the
tray menu and are retried while the confirmed state remains pending.

## Development

```bash
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_status scripts
```

Tests use fake audio commands and Qt's offscreen platform; no connected hardware
or real audio changes are required. See [CONTRIBUTING.md](CONTRIBUTING.md),
[protocol observations](docs/PROTOCOL.md), [architecture](docs/ARCHITECTURE.md)
[troubleshooting](docs/TROUBLESHOOTING.md) and
[publishing instructions](docs/RELEASING.md).

## License and assets

Project code, documentation and original SVG icons are distributed under the
[MIT license](LICENSE). Razer trademarks, extracted logos, executables, firmware
and VM images are not covered by that license and are not part of the public
package. See [third-party assets](docs/THIRD_PARTY_ASSETS.md).
