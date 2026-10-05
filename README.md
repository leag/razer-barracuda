# Barracuda Linux

Linux support for the **Razer Barracuda X (2022)** and its USB dongle
(`1532:0552`): pairing, native battery and wireless-link reporting, headset
settings, and a Plasma 6 widget.

This is an independent project, not an official Razer application.
**WirePlumber manages audio routing**; the project's tools and widget do not
select outputs, change volume, or control the microphone.

## Features

- **Pairing:** pair the headset with its USB dongle using `barracuda-pair`.
- **Native status:** the HID driver reports the wireless link, battery,
  charging cable and voltage, with jack detection for audio availability.
- **Plasma integration:** the **Barracuda Headset** widget displays connection
  details and battery status, and provides access to headset controls.
- **Headset settings:** native EQ, gaming mode, Do Not Disturb, idle shutdown
  and Bluetooth Quick Connect, through USB or the paired Bluetooth headset.
- **Power-off:** explicitly turn off the headset from the CLI or widget.
- **English and Spanish:** CLIs default to English and support `--language es`;
  the widget follows the desktop locale with English fallback.

Pairing, settings changes and power-off run only on user request. There is no
tray application or background Python monitor. A missing adapter, an unknown
link and a confirmed disconnection are reported as distinct states; USB presence
alone does not establish a headset connection.

## Components and requirements

| Component | Purpose | Requirements |
| --- | --- | --- |
| `barracuda-pair` | Pairing CLI and headset helpers | Linux, Python 3.10+, device permissions; no third-party Python runtime dependencies |
| `hid-razer-barracuda-dkms` | Native battery, link and jack reporting | DKMS and headers matching the installed kernel; includes the automatic `snd-usb-audio` quirk when needed |
| `plasma6-applets-barracuda` | Barracuda Headset widget | Plasma 6, `plasma-pa` and `breeze-icons`; headset status requires the helpers and HID driver |

The supported USB device is `1532:0552`. Support for other Barracuda models or
USB IDs is not established. Bluetooth headset controls are documented
[separately](docs/BLUETOOTH_CONTROLS.md).

The widget uses artwork from the installed KDE Breeze theme. It is a separate
widget; keep KDE's volume applet for volume and output selection.

## Installation

### Arch Linux and CachyOS

Download the three matching packages from
[GitHub releases](https://github.com/leag/razer-barracuda/releases).
Install DKMS and the header package for your kernel, then install the packages:

```bash
# linux-headers is for Arch's standard linux kernel; use your kernel's headers.
sudo pacman -S --needed dkms linux-headers

# Run in a directory containing only the three selected package archives.
sudo pacman -U barracuda-pair-*.pkg.tar.zst hid-razer-barracuda-dkms-*.pkg.tar.zst plasma6-applets-barracuda-*.pkg.tar.zst
```

Reboot to load the driver, reconnect the dongle to apply device permissions,
and select the Barracuda output once. WirePlumber handles subsequent
availability changes. The automatic jack-quirk build may need internet access.

See the [installation guide](docs/INSTALL.md) for kernel-specific requirements,
local package builds and migration from the former `barracuda-status` package.

### From a checkout

Install the pairing CLI and its device-access rule:

```bash
python3 scripts/install.py
sudo install -Dm644 packaging/99-razer-barracuda.rules /etc/udev/rules.d/99-razer-barracuda.rules
sudo udevadm control --reload-rules
~/.local/bin/barracuda-pair --help
```

Reconnect the dongle. Add `~/.local/bin` to your desktop session's `PATH` to use
pairing from the widget. This installer copies only the pairing modules and CLI
launcher; it does not install the driver or the other headset helpers.

To install the Plasma widget with its dependencies already available:

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

Then add **Barracuda Headset** (**Auricular Barracuda**) from Plasma's widget
picker. Use `--upgrade plasmoid` for an existing user installation. Installing
the widget does not change panel layouts.

Follow the [installation guide](docs/INSTALL.md) for other checkout options and
the [driver guide](docs/DKMS.md) for DKMS setup. Checkout edits do not update
installed copies automatically; Plasma may also need a
[reload after widget updates](docs/TROUBLESHOOTING.md#widget-update-not-visible).

## Usage

### Pair the headset

Put the headset in pairing mode, then run:

```bash
barracuda-pair --scan          # List nearby devices without replacing pairing.
barracuda-pair                 # Confirm and pair with a Barracuda headset.
barracuda-pair --language es   # Use Spanish prompts.
```

Pairing replaces the dongle's existing headset pairing and asks for confirmation.
After success, **power the headset off and on**. You can also pair through
**More actions → Pair Barracuda…** in the widget.

### Use the Plasma widget

Hover over the panel icon for connection and battery status. Click to view the
USB dongle, wireless link, Bluetooth connection and available battery telemetry.

- **Sound settings…** opens KDE's audio controls.
- **Headset settings…** opens native EQ; **More settings** contains gaming mode,
  Do Not Disturb, idle shutdown and Bluetooth Quick Connect.
- **More actions** provides pairing, headset power-off and help.

Status reads do not send commands to the headset. Native controls require the
appropriate helpers, permissions and supported transport. Software EQ and
sidetone are no longer provided; legacy filters have an explicit cleanup action.
See [usage](docs/USAGE.md) and [headset controls and audio tuning](docs/AUDIO_EFFECTS.md)
for dependencies, behavior and validation limits.

### Turn off the headset

Use **More actions → Turn off headset…**, or run:

```bash
barracuda-power --off
```

USB power-off requires the updated HID driver and its power-control udev rule.
Turn the headset back on with its physical button.

## Documentation

| Topic | Guides |
| --- | --- |
| Getting started | [Installation](docs/INSTALL.md), [usage](docs/USAGE.md), [troubleshooting](docs/TROUBLESHOOTING.md) |
| Headset controls | [Native settings and audio tuning](docs/AUDIO_EFFECTS.md), [Bluetooth controls](docs/BLUETOOTH_CONTROLS.md) |
| Linux integration | [HID driver and DKMS](docs/DKMS.md), [jack detection](docs/JACK_DETECTION.md), [architecture](docs/ARCHITECTURE.md) |
| Protocol and research | [Protocol observations](docs/PROTOCOL.md), [firmware research index](docs/FIRMWARE_ANALYSIS.md#research-index-and-completed-static-analysis-scope), [dongle-to-headset commands](docs/DONGLE_HEADSET_COMMANDS.md), [voice prompts](docs/VOICE_PROMPT_ANALYSIS.md) |
| Design proposals | [Separating controls into userspace](docs/CONTROL_SEPARATION_SPEC.md) |
| Project development | [Contributing](CONTRIBUTING.md), [kernel submission](docs/UPSTREAM.md), [releasing](docs/RELEASING.md), [change history](docs/CHANGELOG.md) |

## Development

```bash
uv sync --locked
uv run barracuda-pair --help
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_pair scripts
```

Tests use temporary directories and simulated devices without changing real
audio. QML logic tests require the Qt 6 test runner; rendering tests additionally
require Plasma components and Breeze icons. Missing dependencies cause those
tests to be skipped. Simulated tests do not establish physical-device support.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before making changes and
[docs/PROTOCOL.md](docs/PROTOCOL.md) before changing HID behavior. Driver changes
must also follow the build, KUnit and patch-series checks in the
[kernel submission guide](docs/UPSTREAM.md).

## License

Project code and documentation are licensed under [MIT](LICENSE).
The HID driver is dual-licensed under GPL-2.0-only or MIT. The `snd-usb-audio`
patch and kernel sources are GPL-2.0.
