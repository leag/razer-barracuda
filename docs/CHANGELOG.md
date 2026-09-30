# Change history

## v0.5.0

- Add native headset EQ, Gaming, Do Not Disturb, idle shutdown and Bluetooth
  Quick Connect through explicit USB and Bluetooth helpers. Keep unknown settings
  distinct from confirmed values and restore the USB diagnostic route after use.
- Add confirmed pairing and explicit headset power-off actions to the Plasma widget.
- Replace EQ preset buttons with a readback-confirmed Profile selector. Show custom
  bands under Custom, with explicit Apply changes.
- Rename Audio effects to Headset settings and add formatted English/Spanish Help
  with control explanations and step-by-step instructions.
- Fit overview and headset settings heights to visible content, consolidate repeated
  errors, and adapt footer actions to narrow layouts. Hide the battery section when
  neither a Barracuda reading nor an identified Barracuda output is available.
- Remove software EQ and sidetone from the widget; retain explicit legacy-filter
  cleanup. Session tuning is not exposed in the widget.
- Rename the internal Python package from `barracuda_status` to `barracuda_pair`;
  the public pairing command remains `barracuda-pair`.
- Use KDE Breeze's detailed headset artwork, including its microphone. Icons remain
  an external dependency and are not bundled.

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
