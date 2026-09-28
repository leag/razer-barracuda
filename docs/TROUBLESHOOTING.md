# Troubleshooting

## Unknown status after startup

The app queries the current connection state when it opens the dongle. Allow
about six seconds for bounded attempts. If it stays unknown, check HID read/write
permissions. Turning the headset off and on can provide a passive notification. Do not treat a silent device or an available
USB audio sink as proof of a wireless link. Bluetooth-only use is not monitored.

## Permission errors

Install `packaging/99-razer-barracuda.rules`, reload udev rules and reconnect the
dongle. The app should run in the active desktop session, not as root.

## Audio does not switch

Inspect the disabled audio-status item in the tray menu, then check:

```bash
pactl info
pactl -f json list sinks
pactl get-default-sink
```

The card must expose an output with vendor `0x1532` and product `0x0552`.
The previous output must still exist to restore it. A manual default-output change
is respected. ALSA-direct applications are outside the scope of `pactl` routing.

## Playback pauses when the headset turns off

With jack detection enabled, the headset output becomes unavailable when the
wireless link drops. WirePlumber's `linking.pause-playback` setting is enabled by
default and pauses media players through MPRIS when their output sink is removed.
The tray app does not send playback commands; it leaves this routing to PipeWire
when jack detection is available.

Check the setting and disable the automatic pause for the current session:

```bash
wpctl settings linking.pause-playback
wpctl settings linking.pause-playback false
```

To keep the setting disabled across WirePlumber restarts, save it:

```bash
wpctl settings --save linking.pause-playback false
```

Reset the saved value to WirePlumber's default (`true`) with:

```bash
wpctl settings --reset linking.pause-playback
```

This setting applies to any removed output sink, not only the Barracuda. With
automatic pausing disabled, playback may continue through the fallback output.

## Analog versus digital profiles

These are audio-server profile names. The USB transport is digital even when the
selected profile is called analog stereo. The app leaves profiles and volumes
unchanged. The analog stereo profile was used during local validation.

The dongle declares one playback format and one capture format: 16-bit stereo
and 16-bit mono at 48 kHz, each in a single alternate setting, with a Speaker
and a Microphone terminal. It has no digital output terminal. Windows shows only
the stereo output. On Linux the extra "Digital Stereo (IEC958)" and "Digital
Surround 5.1 (IEC958/AC3)" profiles appear because:

1. PipeWire's ACP uses `profile-sets/default.conf` when no UCM profile exists.
   It opens each mapping's ALSA device on the card and offers every one that
   opens: `analog-stereo` (`front:`, priority 15), `iec958-stereo`
   (`iec958:`, priority 5) and `iec958-ac3-surround-51` (`a52:`, priority 3).
2. alsa-lib's `/usr/share/alsa/cards/USB-Audio.conf` defines `iec958` for every
   USB card as `hw:CARD,0` unless the card's name is listed in
   `USB-Audio.pcm.iec958_device`. That is the same PCM as analog; the file notes
   that it cannot set the AES parameters. Headsets without digital I/O are
   listed with `999` to prevent opening it, among them "SWTOR Gaming Headset by
   Razer", but "Razer Barracuda X 2.4" is not.
3. alsa-plugins' `a52` encodes AC3 in software on top of that `iec958` device.
   The headset does not decode AC3; this was not tested.

So the S/PDIF profile plays the same stereo stream, but it has no jack-aware
port. With jack detection it stays available while the headset is off, and
WirePlumber may pick its output. The quirk installer therefore installs the
`packaging/razer-barracuda.conf` profile set, selected by
`89-razer-barracuda-acp.rules`, which defines only the analog profiles. It also
gives the microphone a single port bound to the `Headset Mic Jack` through
`analog-input-headset-mic-razer-barracuda.conf`: the stock headset-mic path
expects a "Headset Mic" mixer element while this card's is "Mic", so the stock
set kept a jack-less "Microphone" port that never became unavailable. A
WirePlumber `device.profile-set` rule overrides the udev selection, so the
earlier `51-barracuda-analog-only.conf` must be removed. The equivalent upstream
fix for the profiles would be listing
"Razer Barracuda X 2.4" with `999` in alsa-lib's `USB-Audio.conf`; a local ALSA
override of that table has not been tested here.

## Duplicate instances or old versions

Use the tray's Quit action before launching another copy. If a local transient
service is active, stop it with `systemctl --user stop barracuda-status.service`.
An old `~/.local/bin/barracuda-status.py` copy is independent of this package.
The installer replaces the desktop entry with the new launcher but does not stop
that old process or remove old files. After switching to the Arch package,
remove the checkout installer's copies (`~/.local/bin/barracuda-status`,
`barracuda-pair`, the `barracuda-status` directory under your XDG data
directory and its desktop entry) and point the autostart entry's `Exec` at
`barracuda-status`, so only the packaged copy runs.

## Uninstall

With the Arch packages: `sudo pacman -R barracuda-status hid-razer-barracuda-dkms`,
then `sudo barracuda-snd-usb-audio-quirk --remove` first if the jack quirk was
installed, since that DKMS package is not owned by pacman. Saved routing state
under your XDG state directory and the autostart entry you added remain.

With the checkout installer: remove the launcher `~/.local/bin/barracuda-status`, the `barracuda-status` package
directory under your XDG data directory, its desktop entry under `applications/`,
the matching entry under your XDG config `autostart/` directory, and
`icons/hicolor/scalable/apps/barracuda-status.svg` under your XDG data directory.
Optionally remove the saved state and the system udev rule if no longer needed.
Keep unrelated files.
