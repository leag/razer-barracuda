# Change history

## Unreleased

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
