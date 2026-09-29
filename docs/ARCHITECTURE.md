# Architecture

- `barracuda_pair/pairing.py`: validated pairing and `barracuda-pair` CLI.
  Both the Python module (`barracuda_pair`) and distribution (`barracuda-pair`)
  use the pairing name; there is no `barracuda-status` executable.
- `barracuda_pair/audio.py`: optional JSON helper for explicit software-effect
  configuration and live EQ controls; it never opens HID. The presets are in
  `audio_presets.py`, with their MIT attribution preserved.
- `barracuda_pair/i18n.py`: English/Spanish CLI translations.
- `plasmoid/`: native Plasma 6 QML widget. `Server.defaultSink` from
  `org.kde.plasma.private.volume` provides the default output and notifications.
  Pure JavaScript selects the device icon and formats volume/mute information.
  The expanded view summarizes any default output using native Plasma controls.
  KDE opens its own Sound settings as a secondary action. Explicit pairing uses
  Plasma5Support's executable engine to run the existing CLI with `--yes` only
  after native UI confirmation. The widget shows activity and the final result;
  no command runs when it loads. The powermanagement data engine supplies the
  Barracuda battery published by the driver through UPower/Solid, without HID reads.
  The compact view loads KDE's detailed headset/speaker SVGs with Qt Quick
  `Image`, avoiding theme recoloring and small symbolic variants. Other device
  icons use Kirigami's theme lookup. The package depends on `breeze-icons`
  rather than bundling artwork.
- `packaging/`: hidraw and battery udev rules, ALSA profile/path and
  WirePlumber device-icon rule.
- `scripts/install.py`: isolated user installation of the pairing CLI.
- `scripts/install_dkms.py`, `scripts/install_snd_usb_audio_quirk.py`: drivers.
- `packaging/arch/`: three split packages; see [releasing](RELEASING.md).
- `kernel/hid-razer-barracuda/`: driver and KUnit tests matching `upstream/`.
- `kernel/snd-usb-audio/`: jack-detection patch and DKMS Makefile.
- `tests/`: simulated pairing, installer, packaging and QML checks.

Only the kernel driver monitors wireless state. WirePlumber owns routing.
The CLI pairs only on explicit request. The summary reads audio state; the optional
effects tab invokes finite helper commands only on user actions. There are no
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
