# Barracuda Linux

Linux support for the Razer Barracuda X (2022), USB `1532:0552`.

- `barracuda-pair`: command-line pairing, in English or Spanish. No tray process.
- `hid-razer-barracuda-dkms`: native battery reporting, wireless link and jack
  detection, including the automatic snd-usb-audio quirk when needed.
- `plasma6-applets-barracuda`: **Current Audio Output**, a Plasma 6 widget showing
  the default output's device icon. Barracuda uses KDE Breeze's detailed headset
  icon, including the microphone.

WirePlumber manages audio switching. Optional [audio effects](docs/AUDIO_EFFECTS.md)
use its smart-filter policy; effects and system tuning require explicit activation. This is an independent project, not an official Razer application.

## Install

See [installation](docs/INSTALL.md) for package builds and checkout installation.
The new package layout starts with v0.4.0; older releases contain the former
tray application.
The documentation describes this checkout. The Python module rename and headset
icon change are newer than the v0.4.0 tag; see [change history](docs/CHANGELOG.md).

## Pairing

```bash
barracuda-pair --scan
barracuda-pair
barracuda-pair --language es
```

Pairing requires explicit confirmation. After pairing, power-cycle the headset.
The widget offers native pairing confirmation and displays the result. There is no autostart service.

## Plasma widget

Add **Current Audio Output** (**Salida de audio actual**) from Plasma's widget
picker. The panel icon follows the default audio device; hover shows its name
and volume/mute state. Click opens a summary for any default output, with secondary
actions for KDE Sound settings and native Barracuda pairing. It also shows the
Barracuda battery reported by KDE. The **Equalizer**, **Microphone** and **System** tabs offer optional output
and microphone EQ, profiles, sidetone and persistent PipeWire/WirePlumber tuning.
Pairing requires `barracuda-pair` on `PATH`. This is a separate widget, not
a modification of KDE's stock volume applet. See [usage](docs/USAGE.md).
The detailed artwork comes from the installed `breeze-icons` package, not from
bundled project icons. After a widget update, Plasma may need to be
[reloaded](docs/TROUBLESHOOTING.md#widget-update-not-visible).

## Documentation

- [Installation](docs/INSTALL.md), [usage](docs/USAGE.md),
  [troubleshooting](docs/TROUBLESHOOTING.md)
- [Driver](docs/DKMS.md), [jack detection](docs/JACK_DETECTION.md)
- [Protocol](docs/PROTOCOL.md), [firmware research](docs/FIRMWARE_ANALYSIS.md)
- [Architecture](docs/ARCHITECTURE.md), [kernel submission](docs/UPSTREAM.md)
- [Change history](docs/CHANGELOG.md), [releasing](docs/RELEASING.md),
  [contributing](CONTRIBUTING.md)

## Development

```bash
uv sync --locked
uv run barracuda-pair --help
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_pair scripts
```

Tests use temporary directories and simulated devices; no real audio changes.
QML logic tests run when the Qt 6 test runner is installed. Rendering tests also
require Plasma components and Breeze icons; missing dependencies cause a skip.

## License

Project code and documentation: [MIT](LICENSE).
HID driver: Dual MIT/GPL. The snd-usb-audio patch and kernel sources: GPL-2.0.
