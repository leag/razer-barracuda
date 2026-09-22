# Agent guide

## Scope and language

This is a Linux tray monitor for Barracuda X (2022), USB `1532:0552`, with automatic
PipeWire/PulseAudio output routing. Documentation and code comments are English.
The UI supports English (default) and Spanish via `--language es`. Respond to the
user in their conversation language. Read README.md and docs/PROTOCOL.md first.

## Layout

- barracuda_status/app.py: Qt tray, icons, HID and audio workers.
- barracuda_status/audio_router.py: pactl routing and saved previous output.
- barracuda_status/i18n.py: explicit UI translations.
- barracuda_status/assets/: original, distributable SVGs.
- tests/: hardware-independent unittest suite.
- scripts/install.py and packaging/: user installation, desktop entry, udev rule.
- private/: ignored proprietary resources and local research tools/notes.
- .vm/: ignored VM storage; preserve disks during cleanup.

## Protocol invariants

The monitor opens HID read-only. Never introduce firmware, pairing or unverified
output commands. USB presence does not confirm headset connectivity.
Validate bytes 0..4 (`01 80 0E 50 49`) and 11..15 (`04 00 20 02 01`) before
interpreting byte 16 as 00/01. Byte 10 varies. Ignore other report formats,
especially `01 80 0C 50 49`; these previously caused false disconnects.
Keep unknown, disconnected and missing-adapter states distinct. A silent dongle
is not a disconnected headset. Reads must be interruptible and workers joined.

## Audio invariants

Use pactl, not global ALSA configuration. Match device VID/PID properties, not
fixed sink indices. Save the previous output, move streams from the previous
default on connection, and restore it on disconnection if it still exists.
Respect manual output changes. Unknown state must never trigger routing.
Do not change microphone, volume or card profile unless explicitly in scope.
Preserve XDG directory support and atomic state replacement. Saved routing state
is not physical link evidence. Keep commands off the GUI thread, with timeouts.

## Validation

Run `uv run python -m unittest discover -s tests -v` for functional changes.
Run `uv run python -m compileall -q barracuda_status scripts` for syntax validation.
Use fake audio commands and offscreen Qt; tests must not mutate real audio.
Cover link frames, unknown states, restoration, missing outputs and manual choice
when affected. Documentation-only edits do not need audio tests.
Test installation in temporary HOME/XDG directories. Inspect built archives for
private files. Distinguish unit tests, live routing and physical-device checks.

## Distribution and local deployment

Never force-add private files. Public icons are original SVGs; Razer resources,
Windows binaries and VM images are outside the MIT-licensed distribution.
Keep all public docs in English, and ensure default English and Spanish strings
are tested. Do not introduce personal absolute paths into tracked files.

Repository edits do not update an installed copy automatically. The user installer
copies the package, creates a launcher and optionally a desktop autostart entry.
A legacy local barracuda-status.service may exist as a transient user service;
it is not a permanent unit supplied by this project. Avoid duplicate instances.
Do not turn session autostart into a permanent service as a side effect.
Group authorized runtime updates into one restart: restarting loses observed HID
state until the next headset transition. Explain that limitation rather than
reporting initial unknown state as a disconnection. Publication preparation alone
does not require restarting the user's working audio monitor.
