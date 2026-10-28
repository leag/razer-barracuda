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
- `plasmoid/`: native Plasma 6.7+ QML widget for the headset connection. It
  runs the read-only `barracuda-headset` link query through Plasma5Support's
  executable engine: on load, every 5 s while the popup is open, and when a
  Barracuda battery appears or disappears or the default output changes. Pure
  JavaScript (`contents/code/output.js`) turns the result into distinct
  connected, disconnected, unconfirmed, missing-dongle and unavailable states
  and holds the status strings; the QML views word their own controls and
  messages. Every string has an English default and a Spanish translation,
  chosen by `Output.text()`. `Server.defaultSink` only chooses the
  native-control transport when the link reports do not. Each function has one
  place and one visual form, taken from Plasma's system applets. The commands
  are `Plasmoid.contextualActions`: the high-priority **Pair Headset…**, which
  the tray draws as the heading's '+', and **Turn Off Headset…**, a separator
  and **Configure Audio Devices…**, which it draws in More actions; in a panel
  or on the desktop the widget's own heading (`HeadsetHeading`, a
  `PlasmoidHeading`) draws the same row with the same selection rules. There
  is no configuration window. **Pair Headset…** and **Turn Off Headset…** open
  a `Kirigami.PromptDialog` (`HeadsetPrompt`) in the popup and run the
  existing CLI with `--yes` only after that confirmation; **Configure Audio
  Devices…** opens KDE's audio settings directly. The popup (`HeadsetView`, a
  `PlasmaExtras.Representation`) has, with a confirmed link, three tabs in its
  heading's `TabBar`, which in the tray is all the view's own heading holds:
  **Headset**, one `ListView` with the headset card (`HeroCard`,
  `DetailsGrid`), the Modes switch rows (`ModeSwitch`) and the Bluetooth
  Devices as `ExpandableListItem` rows; **Sound** (`SoundPage`), the sound
  profile (`ChoiceRow`) and the custom bands; and **Power** (`PowerPage`), the
  battery readings (`ValueRow`) and idle shutdown. One `barracuda-headset`
  status read each time the full view is shown with a confirmed link feeds all
  three, and each change is one request sent at once; band edits wait for the
  pointer to let go and for any running request, latest levels only. Every
  other state, pairing and a power-off without a confirmed link show one
  `StatePlaceholder` and no tabs; its Disconnected state offers the pairing
  action. One `Kirigami.InlineMessage` holds outcomes and problems. Help is one
  contextual help button per tab at most. The powermanagement data engine supplies the
  Barracuda battery published by the driver through UPower/Solid, without HID
  reads. The popup loads KDE's detailed headset SVG through `Kirigami.Icon`;
  panel and system tray icons use the theme's symbolic glyph. The package
  depends on `breeze-icons` rather than bundling artwork. The widget declares
  itself a system tray entry (category Hardware, enabled by default) and sets
  its tray status from the link state and battery.
- `packaging/`: hidraw and battery udev rules, ALSA profile/path and
  WirePlumber device-icon rule.
- `scripts/install.py`: isolated user installation of the pairing CLI.
- `scripts/install_dkms.py`, `scripts/install_snd_usb_audio_quirk.py`: drivers.
- `packaging/arch/`: three split packages; see [releasing](RELEASING.md).
- `kernel/hid-razer-barracuda/`: driver and KUnit tests matching `upstream/`.
- `kernel/snd-usb-audio/`: jack-detection patch and DKMS Makefile.
- `tests/`: simulated pairing, installer, packaging and QML checks.

Only the kernel driver monitors wireless state. WirePlumber owns routing.
The CLI pairs only on explicit request. The popup reads published link state and,
with a confirmed link, the headset settings once per showing; settings changes,
pairing and power-off run finite helper commands only on user actions. There are no
background Python workers, saved previous outputs, or autostart entries.
See [audio effects](AUDIO_EFFECTS.md) for configuration ownership and activation.

Device identity and default-output selection are presentation, not link evidence.
A failed driver query leaves link state unknown. Native battery reporting and
routing depend on validated driver reports and the audio stack.

The widget requires Plasma 6.7 or later, for `PlasmaExtras.ContextualHelpButton`,
and depends on a private KDE API, tested with Plasma 6.7.4. Its source is
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
