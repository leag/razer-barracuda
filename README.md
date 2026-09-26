# Barracuda Status

Linux support for the **Razer Barracuda X (2022)** wireless gaming headset and its
**Razer HyperSpeed Wireless 2.4 GHz USB-C dongle** (the "Razer Barracuda X 2.4"
USB audio device, `1532:0552`): a system tray app that shows the wireless link
status and switches desktop audio to the headset when it connects, restoring the
previous output when it disconnects, plus an optional kernel driver for headset
battery level, charging state and jack detection, and a pairing tool for the
dongle's SmartSwitch 2.4 GHz mode. Tested on Arch Linux and CachyOS with KDE
Plasma and PipeWire.

The interface supports **English (default)** and **Spanish**. Project documentation
is in English. This is an independent project, not an official Razer application.

## Features

- Connected, disconnected, missing-adapter and unknown-state indicators.
- Automatic output selection through PipeWire/PulseAudio, including playback
  streams on the previous default output.
- Remembers the previous output across app restarts and respects manual output
  changes made while the headset is connected.
- Connection query at startup, then HID notifications; the monitor sends no firmware
  or pairing commands.
- Separate `barracuda-pair` command to pair a headset with the dongle from Linux.
- Original SVG headset icons included.
- Optional [DKMS HID driver](docs/DKMS.md) (`hid-razer-barracuda`) for native battery
  reporting to UPower/KDE, prepared for [kernel submission](docs/UPSTREAM.md).

## Requirements

- Linux, Python 3.10+, uv and a system tray (tested on KDE Plasma).
- PyQt6 is installed into the project environment by uv.
- PipeWire with PulseAudio compatibility, or PulseAudio, and `pactl`.
- Read/write access to the dongle's HID device (read-only access supports passive monitoring).

On Arch/CachyOS, install the dependencies:

```bash
sudo pacman -S python uv libpulse
```

## Install

### Arch Linux and CachyOS

Build and install the packages from a checkout:

```bash
sudo pacman -S --needed dkms linux-headers python-build python-installer   # headers for your kernel
packaging/arch/build.sh
sudo pacman -U packaging/arch/barracuda-status-*.pkg.tar.zst packaging/arch/hid-razer-barracuda-dkms-*.pkg.tar.zst
```

`barracuda-status` installs the tray app, `barracuda-pair`, the desktop entry
and the hidraw udev rule. `hid-razer-barracuda-dkms` installs the driver for
every installed kernel through DKMS, the battery udev rule, the dongle's ALSA
card profile set, and `barracuda-snd-usb-audio-quirk`, the per-kernel installer
for the [jack detection](#jack-detection-experimental) module. Add
Barracuda Status to your session's autostart from the desktop settings.
Reconnect the dongle once after installing the udev rules.

### From a checkout without packages

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

## Jack detection (experimental)

The DKMS driver reports the wireless link as `SW_HEADPHONE_INSERT` and
`SW_MICROPHONE_INSERT`. The official `snd-usb-audio` does not yet turn these into
ALSA jack controls for `1532:0552`; this needs a two-line quirk like the Sony
DualSense's. With such a module loaded, PipeWire marks the headset output
unavailable when the headset is off and switches outputs itself. The tray
detects this through the card's port availability group and stops changing the
default output, which would otherwise overwrite the output you configured.

To load such a module, install it as a DKMS package for the running kernel. The
installer downloads `sound/usb` for the matching upstream stable version (GPL-2.0,
not stored here), applies `kernel/snd-usb-audio/*.patch` only if it applies
cleanly, and restricts the package to that exact kernel release:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py          # then reboot
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove
```

With the Arch package, run `sudo barracuda-snd-usb-audio-quirk` instead; the
package already provides the profile set described below.

After a kernel update the package does not build, the official module loads,
and the tray routes outputs itself again. Rerun the installer for the new kernel.
The upstream stable `sound/usb` is used, so distribution changes to it (for
example in CachyOS kernels) are not included.

The installer also installs an ALSA card profile set for the dongle
(`packaging/razer-barracuda.conf`, selected by a udev rule). PipeWire's default
set gives the card S/PDIF and AC3 profiles, which play the same stereo stream
but have no jack-aware port, and a microphone port bound to no jack because the
stock headset-mic path expects a differently named mixer element. The
Barracuda set offers only the analog profiles and one microphone port that
follows the `Headset Mic Jack`, so both the output and the microphone become
unavailable while the headset is off. It applies after the reboot.

Select the Barracuda once as your output and input. WirePlumber falls back to
other devices while the headset is off and returns to them when it reconnects.
Earlier versions used a WirePlumber rule (`51-barracuda-analog-only.conf`) for
the profiles; remove it from `~/.config/wireplumber/wireplumber.conf.d/`, since
it overrides the profile set.

### When PipeWire handles wireless_status

The DKMS driver sets the standard USB `wireless_status` attribute.
PipeWire's upstream commit `03f894b` ("alsa-udev: Add wireless device status
monitoring", March 2026, not in the 1.6 series) hides a USB card while its
dongle reports `disconnected`. With such a PipeWire, WirePlumber falls back
and returns without the snd-usb-audio quirk or the profile set. The tray
detects this, from `wireless_status` in PipeWire's ALSA plugin and on the
dongle, and leaves output switching to PipeWire.

Check whether the installed PipeWire supports it:

```bash
grep -c wireless_status /usr/lib/spa-0.2/alsa/libspa-alsa.so
```

Once it does and switching works with the headset off and on, the quirk and
the profile set can be removed:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove   # then reboot
```

## Pairing a headset

`barracuda-pair` replaces the dongle's current pairing, the same way Razer's Windows
pairing utility does. It replays the sequence captured from that utility (see
[the protocol notes](docs/PROTOCOL.md#pairing)) and aborts on any unexpected reply.

```bash
~/.local/bin/barracuda-pair --scan   # list nearby Bluetooth devices only
~/.local/bin/barracuda-pair          # put the headset in pairing mode, then confirm
~/.local/bin/barracuda-pair --address AA:BB:CC:DD:EE:FF --yes
```

The tray menu offers the same action as **Pair headset…**, after a confirmation.
It needs the same HID write access as the monitor. It pairs with the first
headset whose name contains "Barracuda" and whose Bluetooth device class matches
the vendor utility's list, unless `--address` is given. After pairing, turn the headset off
and on: it keeps blinking blue until then, also with Razer's Windows utility.

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

USB presence alone does not confirm a wireless connection. On startup and after
reopening the dongle, the app queries its connection state, with up to three
attempts two seconds apart. It then listens for notifications. If the query fails,
status remains unknown until a valid report arrives; unknown status never changes
the audio output. Read-only permissions retain passive monitoring.

On connection, the app remembers the current default output and selects the
Barracuda sink by USB vendor/product properties. On disconnection it restores the
saved output if available and if the headset is still the default. Playback on
other outputs is left alone. It does not change volume, microphone or card profile.
Applications that bypass PipeWire/PulseAudio and use ALSA directly cannot be moved.

The previous output is stored in `$XDG_STATE_HOME/barracuda-status/audio.json`
(default: `~/.local/state/barracuda-status/audio.json`). Audio errors appear in the
tray menu and are retried while the confirmed state remains pending.

## Headset play/pause button

With the headset connected through the USB dongle, briefly press its power/play
button once to toggle playback in the desktop's active media player. The same
button handles both play and pause; there are no separate buttons for these actions.

The dongle sends a standard HID media-control event, which Linux and the desktop
handle. Barracuda Status monitors the wireless link and routes audio; it does not
implement or intercept playback control. The selected player must support desktop
media controls.

Single-press play/pause was verified on the physical device. Other press patterns
were not tested as part of this validation. See the
[captured button reports](docs/PROTOCOL.md#playpause-button) for technical details.

## Development

```bash
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_status scripts
```

Tests use fake audio commands and Qt's offscreen platform; no connected hardware
or real audio changes are required. See [CONTRIBUTING.md](CONTRIBUTING.md),
[protocol observations](docs/PROTOCOL.md),
[firmware research](docs/FIRMWARE_ANALYSIS.md), [architecture](docs/ARCHITECTURE.md),
[troubleshooting](docs/TROUBLESHOOTING.md) and
[publishing instructions](docs/RELEASING.md).

## License

Project code, documentation and original SVG icons are distributed under the
[MIT license](LICENSE).
