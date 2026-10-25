# Change history

## Unreleased

- Make kernel upgrades more robust for the driver package. Installing or
  upgrading `hid-razer-barracuda-dkms` (and `scripts/install_dkms.py`)
  unregisters other DKMS versions of the driver, which install the same module
  path and made DKMS abort for new kernels. The jack quirk retries its source
  download and falls back to the kernel.org mirror; a build that still fails
  is retried at the next boot by `barracuda-quirk-retry.service`. Quirk builds
  for removed kernels are cleaned up, and git no longer prints detached-HEAD
  advice during the hook.
- Give the Modes rows monochrome icons and lay them out like the Bluetooth
  device rows (icon column, title column, switch on the trailing edge, reason as
  a second line). Bluetooth device rows use the monochrome Bluetooth icon.
- Fix the **Equalizer** page showing every custom band at 0: the headset's
  stored curve now reaches the sliders, so pressing Apply no longer overwrites
  it with a flat curve.
- Make the system tray the widget's main place: the plugin is enabled by default,
  so the tray shows it without configuration. The tray icon no longer hides when
  the headset is disconnected or the USB dongle is missing. Pairing and
  power-off are disabled only while the driver reports that no USB dongle is
  connected.
- Rebuild the popup in the structure of Plasma's own system applets, with one
  visual form per kind of thing. The commands live in the heading, as in the
  Bluetooth applet: **+** is **Pair Headset…**, and **More actions** holds
  **Turn Off Headset…** and **Configure Audio Devices…**; the system tray
  draws the same row, on every supported Plasma version, and the right-click
  menu lists the same commands. **Pair Headset…** and **Turn Off Headset…**
  ask first in a dialog whose default is **Cancel** and which closes by itself
  when the command stops being possible. With a confirmed link the popup shows
  a headset card (artwork with transport glyphs, state, percentage, battery
  bar, transport and charge state, and expandable details), **Modes** with
  **Do not disturb** and **Bluetooth gaming mode** switch rows (no switch for
  an unknown value, which reads Reading… or Unknown; Only over Bluetooth as a
  second line; a busy indicator while a change runs) and **Bluetooth Devices** (Quick Connect)
  with **Connect** rows. Every state without a confirmed link, pairing, and a
  power-off started without a confirmed link replace the body with one message
  with its own artwork; **Disconnected** offers **Pair Headset…**. One
  closable message slot holds outcomes and problems in plain words, with **Try
  Again** where it helps; helper output goes to the journal. No colour is
  added. The tooltip is one line, and the tray icon spins while a command
  runs. The desktop view reads the headset settings too.
- Merge the configuration window into one **Headset** page: the sound profile
  with its custom bands, and idle shutdown. Changes wait for Apply or OK, which
  send them as one chain that stops at the first failure and finishes even
  when the window closes, and Cancel discards them. A setting the headset did
  not return reads **Unknown** instead of an older value, and the page has a
  loading state and a **Settings not read** state with **Try Again**.
- Word headset errors in plain language, without helper names, `PATH` or HID
  details. A change the headset certainly did not apply keeps its last
  confirmed value.
- Name the widget by its title everywhere it names itself, write USB dongle
  rather than adapter (**USB dongle not detected**), and use title case for
  English commands. Spanish uses *auricular* and *dongle USB* throughout.
- The widget now requires Plasma 6.7 or later.
- Keep the QML tests from launching the real helpers: the suites run with
  recording fake helpers and fail if one is started.
- Remove the legacy software-effects cleanup. The widget no longer runs
  `barracuda-audio`, and headset settings no longer wait for it.
  `barracuda-audio` drops `remove_effects`/`remove_eq`, legacy filter detection
  and stored software EQ/sidetone data, and stops managing
  `90-barracuda-effects.conf`. Linux tuning and microphone requests remain.

## v0.6.0

- Make the widget a system tray entry and move native headset settings to its
  configuration window: **Equalizer** (profiles with icons and a vertical
  graphic EQ sent with the window's Apply), **Power saving** (idle shutdown) and
  **Quick Connect** (known Bluetooth sources with formatted addresses and an
  explanation when gaming mode blocks switching). Do Not Disturb and Bluetooth
  gaming mode are in the popup; the separate help page is replaced by contextual
  help buttons.
- Serialize startup E3 exchanges with telemetry and explicit kernel controls,
  retaining up to three attempts at least two seconds apart and unknown link
  state after failures.
- Require verified local route state before clearing a restoration failure;
  reconnection alone no longer clears it. Reject new normal requests during
  suspension/removal while allowing bounded cleanup to finish.
- Require the matching ACK before accepting a pairing route-command reply.
  Raw pairing still lacks arbitration with automatic driver queries.
- Retain the existing kernel control interfaces and defer userspace separation;
  document the hidraw ownership limitation and a reproducible source probe.


## v0.5.1

- Turn the Plasma widget into **Barracuda Headset**, focused on the headset
  connection instead of the default output. It shows connected (USB dongle,
  Bluetooth or both), disconnected, unconfirmed, missing-adapter and unavailable
  states, with details for the dongle, 2.4 GHz link, Bluetooth, charging cable and
  battery voltage. The widget ID is unchanged; all existing actions remain.
- Add the read-only `barracuda-headset --request '{"op":"link"}'` query. It reads
  the driver's `wireless_status` and power-supply values and BlueZ, without the
  control lock and without sending anything to the hardware.
- Strike the panel icon through with a red slash when the headset is disconnected
  or the adapter is missing, mark unconfirmed and low-battery states with an
  emblem, and use the driver's battery reading when KDE does not list it.
- Native headset settings follow the confirmed USB or Bluetooth link, using the
  default output only when both or neither is confirmed.

- Size the panel headset artwork with Breeze's `smallMedium` icon size.
- Complete the static research documentation for dongle-to-headset commands
  and voice prompts, with an evidence index and explicit unresolved fields.

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
