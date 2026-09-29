# Change history

## Unreleased

- Add native output summaries, Barracuda battery updates and confirmed pairing
  to the Plasma widget, with compact artwork and explicit volume/battery labels.
- Add an optional native audio-effects page: output/mic EQ, saved profiles and
  favorites, software sidetone, opt-in microphone controls, and persistent
  PipeWire/WirePlumber tuning through the finite `barracuda-audio` helper.
  Preserve the MIT attribution for the reference project's preset curves.
  Hardware controls from USB 1532:053c are not sent to USB 1532:0552.
- Separate audio controls into tabs with collapsible frequency bands and profile
  management; scrolling over sliders leaves their values unchanged.
- Request 128-frame processing at 48 kHz for software sidetone to reduce its
  processing delay without forcing the session quantum.

- Rename the internal Python package from `barracuda_status` to `barracuda_pair`;
  update imports, entry point, installers, tests, CI and version synchronization.
  The public command remains `barracuda-pair`.
- Use KDE Breeze's detailed `audio-headset.svg` (with microphone) instead of
  `audio-headphones.svg` for the widget's headset presentation and picker icon.
  Artwork remains owned by `breeze-icons`, not bundled in this repository.
- Update installation, Plasma reload, troubleshooting and release instructions.

The headset change has been built locally as `0.4.0-6`. It is not part of the
published v0.4.0 tag; a new source release is required to distribute these changes.

## v0.4.0

- Replace the Python tray monitor with the standalone `barracuda-pair` CLI.
  Remove Qt dependencies, desktop/autostart integration and Python audio routing.
- Add `plasma6-applets-barracuda`, a read-only Plasma 6 default-output widget
  with KDE sound-settings access, English/Spanish text and detailed Breeze icons.
- Ship three independent Arch packages: pairing CLI, DKMS driver and plasmoid.
  Keep availability-driven audio routing in the driver/PipeWire/WirePlumber stack.
- Move the WirePlumber device-icon rule to the driver package.
- Synchronize plasmoid metadata through the centralized version command.
- Add QML icon-selection and rendering tests, including panel sizing regressions.

Published Arch package revision: `0.4.0-5`. The Python wheel in this tag still
uses the internal `barracuda_status` name. Older driver validation history remains
in [DKMS notes](DKMS.md#validation); protocol observations are in [PROTOCOL.md](PROTOCOL.md).
