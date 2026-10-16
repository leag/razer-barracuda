# Native headset controls and Linux audio tuning

The widget's configuration window has an **Equalizer** page for the native EQ
and a **Power Saving** page for idle shutdown, whose changes are sent with the
window's Apply or OK; there is no System tab. Do Not Disturb, Bluetooth gaming
mode and Quick Connect Bluetooth source switching are in the popup. Software output EQ,
microphone EQ and sidetone are removed. Native sidetone is not exposed because
its audible effect and gain semantics remain unresolved.

## Headset controls

`barracuda-headset` performs finite JSON requests through the driver's
`headset_settings` sysfs mailbox. A settings read requires an explicit mailbox
write; reading the attribute returns its last response and never queries hardware.
The driver allowlists payloads, serializes them with battery queries, checks
E3 and the existing headset transport, and always restores the local route.
There is no raw HID fallback, periodic settings polling or background service.

| Control | Native implementation |
| --- | --- |
| EQ presets | Default, Game, Music, Movie and Custom; applied preset shown in bold |
| Custom EQ | Ten bands from 31 Hz to 16 kHz; relative levels -5 to +5, encoded as 0–10 |
| Bluetooth gaming mode | Low-latency Bluetooth audio; readable through USB and Bluetooth; settable only over Bluetooth (USB SET was accepted without changing GET state); the widget's switch is disabled through the dongle; separate from Game EQ |
| Do Not Disturb | Native Boolean setting, stored through USB or Bluetooth; firmware applies it to the connected Bluetooth link, or when that link connects |
| Idle shutdown | Never, 5, 15, 30, 45 or 60 minutes |
| Quick Connect | Switch only to a Bluetooth address returned by the headset |

Each ordinary SET is followed by GET to confirm the value. An unconfirmed change
clears the UI state and is never retried automatically. Quick Connect reports
only that a switch was requested; Refresh checks the active device afterwards.
It is disabled while Gaming is on. Unknown states do not become defaults or
link-loss evidence. Partially supported firmware exposes only successful reads.

Default/Game EQ has physical USB validation. The other controls have Android
and firmware evidence but have not all been physically exercised on this device.
Native state setters are explicitly authorized additions for this local build;
they are not an assertion that every function has been validated on hardware.
Read [firmware analysis](HEADSET_FIRMWARE_ANALYSIS.md) for exact evidence and limits.
No firmware, storage, reboot, reset, language-installation or sidetone commands
are accepted by the mailbox. Native settings can be persistent; do not assume
that closing the widget resets them. Band levels are relative units, not a
measured dB scale.

## Installation

Install the updated HID driver, its headset-control permissions rule and
`barracuda-headset`. For the userspace helpers:

```sh
python scripts/install.py
```

Installation does not change audio settings or restart audio. The mailbox requires
the new driver to be loaded; old drivers show an upgrade message instead of
falling back to unsynchronized device writes. The installed plasmoid must also
be updated independently. Packaging includes all helpers and QML components.

## Transports

Native controls use the USB driver when the dongle is selected, and Bluetooth
SPP when the headset is the Bluetooth output. Bluetooth Gaming, presets, custom
bands, DND and standby have physical setter/readback validation. See
[Bluetooth controls](BLUETOOTH_CONTROLS.md).

## Linux system settings

`barracuda-audio` (installed with `--audio-controls`) retains explicit session
buffer, optional 48 kHz sample rate, Barracuda keep-awake policy and output
headroom. These are Linux audio settings, not firmware features. Smaller buffers
may crackle. Use system defaults first. These controls are available through the
CLI only. Changes require explicit restart confirmation. Keys written by older
versions for software EQ and sidetone are ignored and dropped on the next save;
a fragment those versions left at
`~/.config/pipewire/pipewire.conf.d/90-barracuda-effects.conf` is no longer
managed and can be deleted. WirePlumber
continues to own routing; native controls do not select outputs, change volume,
change card profiles or modify microphone state.

## Validation

Python tests use fake mailbox replies and isolated configuration directories.
QML tests use fake controllers and offscreen Qt. KUnit checks bounded commands,
malformed/stale responses and the existing link/route behavior. Compiled builds
and these tests do not replace physical validation of every new setting.
