<p align="center">
  <img src="barracuda_status/assets/barracuda-connected.svg" width="128" alt="Barracuda Status">
</p>

# Barracuda Status

Linux support for the **Razer Barracuda X (2022)** wireless gaming headset and its
**Razer HyperSpeed Wireless 2.4 GHz USB-C dongle** (the "Razer Barracuda X 2.4"
USB audio device, `1532:0552`):

- **Tray app** that shows the wireless link status and switches desktop audio to
  the headset when it connects, restoring the previous output when it disconnects.
  English and Spanish interface.
- **Kernel driver** (`hid-razer-barracuda`, DKMS) for headset battery level,
  charging state and voltage in UPower and KDE, the USB `wireless_status`
  attribute, and jack switches, prepared for [kernel submission](docs/UPSTREAM.md).
- **Jack detection** for PipeWire through an `snd-usb-audio` quirk and an ALSA
  card profile set, so the headset's output and microphone become unavailable
  while it is off and WirePlumber switches devices itself.
- **`barracuda-pair`** to pair a headset with the dongle from Linux, the way
  Razer's Windows utility does.

Tested on Arch Linux and CachyOS with KDE Plasma and PipeWire. This is an
independent project, not an official Razer application.

## Install

On Arch Linux and CachyOS, download the two packages from the latest
[release](https://github.com/leag/razer-barracuda/releases) and install them:

```bash
sudo pacman -S --needed dkms linux-headers   # or the headers package for your kernel
sudo pacman -U barracuda-status-*.pkg.tar.zst hid-razer-barracuda-dkms-*.pkg.tar.zst
```

Reconnect the dongle once, add Barracuda Status to your session's autostart, and
select the Barracuda as output and input. For jack detection, also run
`sudo barracuda-snd-usb-audio-quirk` and reboot; see
[jack detection](docs/JACK_DETECTION.md).

Other distributions, building the packages yourself, and running from a checkout:
[docs/INSTALL.md](docs/INSTALL.md).

## Pairing

```bash
barracuda-pair --scan   # list nearby Bluetooth devices
barracuda-pair          # put the headset in pairing mode, then confirm
```

The tray menu offers the same as **Pair headset…**. Details, tray indicators,
audio routing rules and the play/pause button: [docs/USAGE.md](docs/USAGE.md).

## Documentation

- [Installation](docs/INSTALL.md), [usage](docs/USAGE.md) and
  [troubleshooting](docs/TROUBLESHOOTING.md)
- [DKMS driver](docs/DKMS.md) and [jack detection](docs/JACK_DETECTION.md)
- [Protocol observations](docs/PROTOCOL.md) and
  [firmware research](docs/FIRMWARE_ANALYSIS.md)
- [Architecture](docs/ARCHITECTURE.md), [kernel submission](docs/UPSTREAM.md),
  [releasing](docs/RELEASING.md) and [contributing](CONTRIBUTING.md)

## Development

```bash
uv sync --locked
uv run barracuda-status                 # English
uv run barracuda-status --language es   # Español
uv run python -m unittest discover -s tests -v
```

Tests use fake audio commands and Qt's offscreen platform; no hardware or real
audio changes are needed.

## License

Project code, documentation and original SVG icons are distributed under the
[MIT license](LICENSE). The kernel module is `Dual MIT/GPL`; the `snd-usb-audio`
patch and the sources it applies to are GPL-2.0.
