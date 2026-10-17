# Architecture

- `barracuda_pair/pairing.py`: validated pairing and `barracuda-pair` CLI.
  Both the Python module (`barracuda_pair`) and distribution (`barracuda-pair`)
  use the pairing name; there is no `barracuda-status` executable.
- `barracuda_pair/audio.py`: CLI-only JSON helper for explicit Linux audio
  tuning and microphone control; it never opens HID and the widget does not use it.
- `barracuda_pair/headset.py`: finite native settings requests through the
  driver's bounded, serialized sysfs mailbox, and the read-only `link` request
  (driver `wireless_status`, power-supply values and BlueZ connection). No raw
  HID fallback or monitor.
- `barracuda_pair/i18n.py`: English/Spanish CLI translations.
- `plasmoid/`: native Plasma 6 QML widget for the headset connection. It runs
  the read-only `barracuda-headset` link query through Plasma5Support's
  executable engine: on load, every 5 s while the popup is open, and when a
  Barracuda battery appears or disappears or the default output changes.
  Pure JavaScript turns the result into distinct connected, disconnected,
  unconfirmed, missing-dongle and unavailable states, and into detail rows.
  `Server.defaultSink` only chooses the native-control transport when the link
  reports do not. Each function has one place. The popup (`HeadsetPanel`,
  `ConnectionSummary`) holds the headset and its connections: state and battery,
  the always-visible **Pair USB Dongle…** and **Turn Off Headset…** buttons with
  their confirmations right below, Do Not Disturb and Bluetooth Gaming Mode
  switches (`SettingRow`) and Quick Connect, all fed by one `barracuda-headset`
  status read each time the full view is shown with a confirmed link. Explicit
  pairing and power-off run the existing CLIs with `--yes` only after that
  confirmation; the widget shows activity and the final result. The single
  contextual action, **Configure Audio Devices…**, opens KDE's audio settings.
  The system tray draws it in its More actions menu on Plasma 6.8 and later,
  where the action sets `alwaysShowAsMenu`, and as a single heading button on
  earlier versions. In a panel or on the desktop the widget's own heading, a
  `PlasmoidHeading`, always builds the menu from `Plasmoid.contextualActions`,
  next to a gear for the configuration window.
  The configuration window (`contents/config`) has two categories,
  **Equalizer** and **Power Saving**; their changes are sent on Apply or OK as
  one chain that finishes even when Plasma closes the page. Help is one
  `Kirigami.ContextualHelpButton` per view at most. The powermanagement data
  engine supplies the Barracuda battery published by the driver through
  UPower/Solid, without HID reads. The popup loads KDE's detailed headset SVG
  with Qt Quick `Image`; panel and system tray icons use the theme's symbolic
  glyph through Kirigami. The package depends on `breeze-icons` rather than
  bundling artwork. The widget declares itself a system tray entry (category
  Hardware, enabled by default) and sets its tray status from the link state
  and battery.
- `packaging/`: hidraw and battery udev rules, ALSA profile/path and
  WirePlumber device-icon rule.
- `scripts/install.py`: isolated user installation of the pairing CLI.
- `scripts/install_dkms.py`, `scripts/install_snd_usb_audio_quirk.py`: drivers.
- `packaging/arch/`: three split packages; see [releasing](RELEASING.md).
- `kernel/hid-razer-barracuda/`: driver and KUnit tests matching `upstream/`.
- `kernel/snd-usb-audio/`: jack-detection patch and DKMS Makefile.
- `tests/`: simulated pairing, installer, packaging and QML checks.

Only the kernel driver monitors wireless state. WirePlumber owns routing.
The CLI pairs only on explicit request. The summary reads published link state; the
headset settings page invokes finite helper commands only on user actions. There are no
background Python workers, saved previous outputs, or autostart entries.
See [audio effects](AUDIO_EFFECTS.md) for configuration ownership and activation.

Device identity and default-output selection are presentation, not link evidence.
A failed driver query leaves link state unknown. Native battery reporting and
routing depend on validated driver reports and the audio stack.

The widget depends on a private KDE API, tested with Plasma 6.7.4. Its source is
independent of the Python wheel. All package versions, including widget metadata,
are synchronized by `scripts/version.py`.

The published v0.4.0 Python wheel used the internal `barracuda_status` module;
the checkout now uses `barracuda_pair`. The command remains `barracuda-pair`.
There is no compatibility import alias. Installation and release artifacts are
separate from working-tree edits; see [change history](CHANGELOG.md).

## Explicit power control

`barracuda-power` requests a single power-off operation through the matching
HID driver's write-only sysfs attribute. The driver validates the link and
serializes route selection, the one-shot MMI command and restoration with its
battery worker. The CLI shares a per-user XDG lock with pairing and provides no
raw-HID fallback. The plasmoid launches it only after explicit confirmation and
continues to obtain battery/link evidence from the existing native interfaces.
