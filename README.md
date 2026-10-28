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
- **English and Spanish widget:** the widget follows the desktop locale with
  English fallback; the command-line tools are English only.

Pairing, settings changes and power-off run only on user request. The widget is
a native Plasma applet that can live in the system tray; there is no separate
tray application or background Python monitor. A missing USB dongle, an unknown
link and a confirmed disconnection are reported as distinct states; USB presence
alone does not establish a headset connection.

## Components and requirements

| Component | Purpose | Requirements |
| --- | --- | --- |
| `barracuda-pair` | Pairing CLI and headset helpers | Linux, Python 3.10+, device permissions; no third-party Python runtime dependencies |
| `hid-razer-barracuda-dkms` | Native battery, link and jack reporting | DKMS and headers matching the installed kernel; includes the automatic `snd-usb-audio` quirk when needed |
| `plasma6-applets-barracuda` | Barracuda Headset widget | Plasma 6.7 or later, `plasma-pa` and `breeze-icons`; headset status requires the helpers and HID driver |

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
pairing from the widget. This installer copies the Python helper modules and creates the
`barracuda-pair`, `barracuda-power` and `barracuda-headset` launchers. It does
not install the driver or Plasma widget.

To install the Plasma widget with its dependencies already available:

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

The system tray is the main place for the widget: it enables **Barracuda
Headset** (**Auricular Barracuda**) by itself the first time it finds it, at the
next Plasma start. You can also add it to a panel from Plasma's widget picker.
Use `--upgrade plasmoid` for an existing user installation. Installing the widget
does not change panel layouts.

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
```

Pairing replaces the dongle's existing headset pairing and asks for confirmation.
After success, **power the headset off and on**. You can also pair from the
widget: **Pair Headset…** is the **+** in its popup heading.

### Use the Plasma widget

The widget lives in the system tray (or a panel, if you add it there). Its icon
stays visible in every state, so pairing is always one click away when the
headset is not connected. Hover over the icon for a one-line summary of the
connection and battery. Click it to open the popup:

- The heading holds the commands, as in KDE's Bluetooth applet: **+**
  (**Pair Headset…**) and **More actions** (☰) with **Turn Off Headset…** and
  **Configure Audio Devices…** (KDE's audio settings). Pairing and turning off
  ask first in a dialog whose safe default is **Cancel**.
- With a confirmed link, the popup has three tabs, as KDE's volume applet has
  **Devices** and **Applications**. It always opens on the first:
  - **Headset**: a card with the state, the battery percentage with a bar and
    the transport (USB dongle, Bluetooth or both), which you can click for
    connection details; **Modes**, with **Do not disturb** and **Bluetooth
    gaming mode** (low-latency Bluetooth audio) switches, where gaming mode is
    shown only over Bluetooth, the one place it can be changed, and turns off
    with the headset; and **Bluetooth Devices**, the sources the
    headset knows (Razer Quick Connect), with **Connect** for each inactive
    one.
  - **Sound**: the sound profile and, with **Custom**, its ten bands.
  - **Power**: the battery charge, charging cable and voltage, and when the
    headset turns itself off.
- Settings are read from the headset each time the popup opens with a
  confirmed link. Every change is sent at once: a profile or idle shutdown
  when you choose it, the bands when you let go of a slider.
- Without a confirmed link, one message replaces all of this: Disconnected
  (with a **Pair Headset…** button), Link not confirmed, USB dongle not
  detected, Status unavailable or Checking.

The right-click menu holds the same commands as the heading.

Status reads do not send commands to the headset. Native controls require the
appropriate helpers, permissions and supported transport. Software EQ and
sidetone are no longer provided.
See [usage](docs/USAGE.md) and [headset controls and audio tuning](docs/AUDIO_EFFECTS.md)
for dependencies, behavior and validation limits.

### Turn off the headset

Choose **Turn Off Headset…** in the widget's **More actions** menu (☰) or its
right-click menu and confirm, or run:

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
| Protocol and research | [Protocol observations](docs/PROTOCOL.md), [firmware research index](docs/FIRMWARE_ANALYSIS.md#research-index-and-completed-static-analysis-scope), [installed dongle flash](docs/LIVE_DONGLE_FLASH.md), [dongle-to-headset commands](docs/DONGLE_HEADSET_COMMANDS.md), [voice prompts](docs/VOICE_PROMPT_ANALYSIS.md) |
| Design proposals | [Separating controls into userspace](docs/CONTROL_SEPARATION_SPEC.md), [implementation plan](docs/CONTROL_SEPARATION_PLAN.md) |
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
