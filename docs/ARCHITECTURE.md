# Architecture

- `barracuda_status/app.py`: Qt tray, icon rendering, HID reader and audio worker.
- `barracuda_status/audio_router.py`: `pactl` operations and previous-output state.
- `barracuda_status/i18n.py`: English source strings and Spanish translations.
- `barracuda_status/assets/`: original SVG icons shipped in the Python package.
- `packaging/`: desktop template and udev rule.
- `scripts/install.py`: installation for the current user without root.
- `tests/`: hardware-independent unit tests.

The HID worker opens the matching device read-only and uses nonblocking reads with
`select` timeouts. It validates the observed report format before emitting state.
Qt updates the tray on its main thread and sends states to a separate audio worker.
The audio worker serializes routing commands and retries transient failures.
Subprocess calls have timeouts. Shutdown requests interruption and joins workers.

Routing state is persisted by atomic replacement. The saved previous output is not
a cache of physical headset connectivity. English is selected explicitly by default;
Spanish is enabled with `--language es`, independent of the desktop locale.

The development workstation previously used a transient user unit named
`barracuda-status.service`. That unit is not part of this distribution. Session
startup is provided by a desktop autostart entry; avoid running both mechanisms.
