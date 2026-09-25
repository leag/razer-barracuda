# Architecture

- `barracuda_status/app.py`: Qt tray, icon rendering, HID reader and audio worker.
- `barracuda_status/audio_router.py`: `pactl` operations and previous-output state.
- `barracuda_status/i18n.py`: English source strings and Spanish translations.
- `barracuda_status/assets/`: original SVG icons shipped in the Python package.
- `barracuda_status/pairing.py`: pairing sequence and the `barracuda-pair` CLI.
- `packaging/`: desktop template, udev rules, and the ALSA card profile set with
  its microphone path for the jack quirk.
- `scripts/install.py`: installation for the current user without root.
- `scripts/install_dkms.py`, `scripts/install_snd_usb_audio_quirk.py`: DKMS installers.
- `kernel/hid-razer-barracuda/`: the out-of-tree HID driver and its KUnit tests,
  identical to the series in `upstream/` ([docs/UPSTREAM.md](UPSTREAM.md)).
- `kernel/snd-usb-audio/`: the GPL-2.0 jack-detection patch and DKMS Makefile.
- `tests/`: hardware-independent unit tests, including the installers and the
  check that keeps `upstream/` in sync with the sources.

The HID worker opens the matching device read/write, falling back to read-only
on permission errors, and uses nonblocking reads with `select` timeouts. It sends
only the validated E3 query, at most three times per open, until a valid state is
received. It validates E3 and transition reports before emitting state; query
failure never emits disconnected. Reopening resets the query budget.
Qt updates the tray on its main thread and sends states to a separate audio worker.
The audio worker serializes routing commands and retries transient failures.
Subprocess calls have timeouts. Shutdown requests interruption and joins workers.

Routing state is persisted by atomic replacement. The saved previous output is not
a cache of physical headset connectivity. English is selected explicitly by default;
Spanish is enabled with `--language es`, independent of the desktop locale.

The development workstation previously used a transient user unit named
`barracuda-status.service`. That unit is not part of this distribution. Session
startup is provided by a desktop autostart entry; avoid running both mechanisms.

## Tray icon design

The four original 32×32 SVGs share the rounded, outlined headset silhouette of
the unknown-state icon. Connected uses a green check, disconnected an amber minus,
and missing-adapter a red cross. Unknown uses a gray question mark drawn as paths
and a circle, with no font dependency. Color and shape both distinguish states.

The check, cross and minus are scaled to 70% around `(16, 21)` to keep them clear
of the earcups. The question mark retains its original size. Packaged SVGs have
priority over local SVG files, ensuring
that installations use the same state designs. The SVGs were visually checked at
16, 32 and 64 pixels before the final symbol-size adjustment.
