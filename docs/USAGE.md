# Using Barracuda Status

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
[captured button reports](PROTOCOL.md#playpause-button) for technical details.

## Pairing a headset

`barracuda-pair` replaces the dongle's current pairing, the same way Razer's Windows
pairing utility does. It replays the sequence captured from that utility (see
[the protocol notes](PROTOCOL.md#pairing)) and aborts on any unexpected reply.

```bash
barracuda-pair --scan   # list nearby Bluetooth devices only
barracuda-pair          # put the headset in pairing mode, then confirm
barracuda-pair --address AA:BB:CC:DD:EE:FF --yes
```

The tray menu offers the same action as **Pair headset…**, after a confirmation.
It needs the same HID write access as the monitor. It pairs with the first
headset whose name contains "Barracuda" and whose Bluetooth device class matches
the vendor utility's list, unless `--address` is given. After pairing, turn the headset off
and on: it keeps blinking blue until then, also with Razer's Windows utility.

