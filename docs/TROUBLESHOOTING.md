# Troubleshooting

## Unknown status after startup

The dongle does not necessarily emit its current state when the app starts.
Turn the headset off and on once. Do not treat a silent device or an available
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

## Analog versus digital profiles

These are audio-server profile names. The USB transport is digital even when the
selected profile is called analog stereo. The app leaves profiles and volumes
unchanged. The analog stereo profile was used during local validation.

## Duplicate instances or old versions

Use the tray's Quit action before launching another copy. If a local transient
service is active, stop it with `systemctl --user stop barracuda-status.service`.
An old `~/.local/bin/barracuda-status.py` copy is independent of this package.
The installer replaces the desktop entry with the new launcher but does not stop
that old process or remove old files.

## Uninstall

Remove the launcher `~/.local/bin/barracuda-status`, the `barracuda-status` package
directory under your XDG data directory, its desktop entry under `applications/`,
the matching entry under your XDG config `autostart/` directory, and
`icons/hicolor/scalable/apps/barracuda-status.svg` under your XDG data directory.
Optionally remove the saved state and the system udev rule if no longer needed.
Keep unrelated files and any local proprietary resources you wish to retain.
