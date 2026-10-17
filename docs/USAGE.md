# Usage

## Pairing

`barracuda-pair` replays the validated vendor pairing sequence. It requires
write access to the matching USB dongle and aborts on unexpected replies.

```bash
barracuda-pair --scan
barracuda-pair
barracuda-pair --language es
barracuda-pair --address AA:BB:CC:DD:EE:FF --yes
```

Scanning lists nearby Bluetooth devices without replacing pairing. Normal pairing
asks for confirmation; `--yes` explicitly skips that prompt. Pairing replaces
the dongle's existing headset pairing. Put the headset
in pairing mode first, then power it off and on after success. Without an explicit
address, the tool matches Barracuda names and the validated Bluetooth classes.
See [protocol observations](PROTOCOL.md#pairing).

The CLI defaults to English regardless of desktop locale. It exits when done;
there is no tray monitor, graphical pairing dialog or background audio router.

## Barracuda Headset widget

The system tray is the widget's main place. It enables **Barracuda Headset**
(**Auricular Barracuda**) by itself the first time it finds it, at the next
Plasma start, and remembers if you disable it in **Configure System Tray… →
Entries**. You can also add it to a panel or the desktop; installing does not
change any panel. A widget already added by an earlier version keeps working
after an update. The widget needs Plasma 6.7 or later.

In the system tray the icon stays visible in every state, including a
disconnected headset or a missing USB dongle, so pairing stays reachable. A low
battery asks for attention. The tray's own visibility settings override this.

Panel and tray icons use the theme's symbolic headset glyph, recolored like the
neighboring icons. It is drawn at full opacity while the headset link is
confirmed and dimmed otherwise. A small corner emblem shows a question mark when
the link is not confirmed or the status is unavailable, and a warning at 10%
battery or less while not charging. The tooltip is one line, for example
*Connected · USB dongle · 80% Battery*. Text follows the desktop locale
(English/Spanish). The icon has no button frame on pointer hover; keyboard
navigation retains the theme's focus indicator.

Click opens the popup, 24 by 24 grid units in a panel and in the tray. Every
function has one place and one visual form, taken from Plasma's own applets:
the commands in the heading, the headset and its settings in the popup, and how
it sounds and when it turns itself off in the configuration window. No colour is
added; states are told apart by their words, artwork, opacity and emblems.

### Heading and commands

The heading shows the widget's name, **+** (**Pair Headset…**), **More
actions** (☰) and a configure button (the gear), as in KDE's Bluetooth applet.
In the system tray, Plasma draws this heading itself from the widget's actions;
in a panel or on the desktop the widget draws the same row. **More actions**
holds **Turn Off Headset…** and, after a separator, **Configure Audio
Devices…**, which opens KDE's audio settings. The gear opens the widget's
configuration window. The right-click menu shows the same commands together
with Plasma's own.

**Pair Headset…** and **Turn Off Headset…** each ask first in a dialog over the
popup, titled with a question, whose focused default is **Cancel**; Escape
cancels too. The dialog closes by itself when its command stops being possible,
for example when the USB dongle is unplugged or the popup closes. Both commands
go through the USB dongle and are disabled, still visible, only while the driver
reports that no dongle is connected or while one of them runs; an unknown or
unavailable state never disables them. **Up** and **Down** move between the
heading and the popup's controls.

### With a confirmed link

- The **headset card**: Breeze's detailed headset artwork with a USB or
  Bluetooth glyph beside it (both when both links are confirmed), the state and
  battery percentage, a battery bar, and a line with the transport and the
  charge state when it adds something (**Charging**, **Fully charged**, **Low
  battery**). Click the card for its details: whether the USB dongle is
  detected, the 2.4 GHz link, the paired Bluetooth connection, a discharging
  battery, and, while the dongle link is confirmed, the charging cable and
  battery voltage last reported by the driver. While the headset turns off, the
  card reads **Turning off…**.
- **Modes**: the **Do not disturb** and **Bluetooth gaming mode** switches (see
  [below](#modes-and-bluetooth-devices)).
- **Bluetooth Devices**: the Bluetooth sources the headset knows.

One message slot under the card holds the outcome or problem of the last
command or reading, in plain words, with **Try Again** where it helps; it can be
closed. The cause of a failed pairing or power-off goes to the journal, not to
the popup. The popup scrolls when its content is taller than the popup.

### Without a confirmed link

One message replaces the popup's body, with its own artwork treatment for each
state, so the states stay distinct:

- **Disconnected**: turn on the headset. The message offers **Pair Headset…**,
  the same command as the **+**. Without the USB dongle it asks you to turn on
  the headset or plug in the dongle, and the button waits, greyed, for the
  dongle.
- **Link not confirmed**: the headset may still be on, and the last battery
  reading is named when there is one; an unconfirmed link is never shown as a
  disconnection. More than one dongle, or a missing driver, is named instead.
- **USB dongle not detected**: plug in the dongle, or use the headset over
  Bluetooth.
- **Status unavailable**: install or update the `barracuda-pair` package.
- **Checking…** while the first status is read, and **Pairing…** while pairing
  runs.

The state comes from `barracuda-headset --request '{"op":"link"}'`, a finite,
read-only query. It reads the driver's USB `wireless_status` attribute and
power-supply values from sysfs, and the paired headset's connection from BlueZ.
It never opens HID and never sends anything to the dongle or headset. The widget
runs it on load, every 5 seconds while the popup is open, when a Barracuda
battery appears or disappears in KDE (the driver registers it only on a confirmed
link change), when the default output changes, and after pairing or power-off.
There is no background process. Without an updated `barracuda-headset` on
`PATH`, the widget shows **Status unavailable** and keeps its commands.

The default output is not link evidence. It only selects the native-control
transport when both or neither link is confirmed; otherwise headset settings
follow the confirmed USB or Bluetooth link.

The popup's detailed artwork is read from
`/usr/share/icons/breeze/devices/64/audio-headset.svg` (and
`drive-removable-media-usb.svg` for a missing dongle), supplied by
`breeze-icons`; no icons are bundled or copied. The tray sizes its own icons; a
panel icon outside the tray is centered and capped at KDE's small-medium icon
size, shrinking to fit smaller panels.

The battery comes from KDE's power-management service, or from the driver's
published value when KDE does not list it. It is the last reported percentage
and charging state. The widget matches the Barracuda model and headset battery
type, excluding computer and mouse batteries. It sends no battery queries.
Unknown charging state remains unknown; a connected cable does not by itself
prove that charging has completed. The card writes the percentage as each
language does (80% in English, 80 % in Spanish) and never colours the bar; a
low battery is a word and the tray's attention state. Without telemetry the
card says **Battery unavailable**, which does not establish the wireless link
state.

**Pair Headset…** asks before replacing the dongle's pairing. Put the headset
in pairing mode and choose **Pair**, or **Cancel** to leave the pairing
unchanged. Only after confirmation does the widget run
`barracuda-pair --yes --timeout 60`, in the desktop language (English fallback).
Install the optional CLI and ensure it is on `PATH`. No terminal is needed. The
popup shows **Pairing…** while the CLI runs; the current backend returns its
result at completion, not live scan stages. The search lasts up to a minute,
followed by connection and cleanup. Once started, let the operation finish;
closing the popup does not cancel it. The widget prevents a second launch from
the same instance while busy. Success asks you to power-cycle the headset; a
failure says what to check and offers **Try Again**, and the CLI's output goes
to the journal. Closing the popup dismisses a pending confirmation and previous
result messages, while an active pairing operation continues. Pairing is
specific to Barracuda X (2022), not a generic Bluetooth pairing interface.

The widget never writes audio state. Only explicitly launched pairing accesses
raw HID; power-off uses the serialized driver interface. **Configure Audio
Devices…** opens KDE's audio controls; keep KDE's volume widget for volume and device
selection, which this widget does not replace.

The WirePlumber rule still advertises `audio-headphones` to other audio clients.
That property and the plasmoid's choice of headset artwork are separate.
If an update is not visible, follow the
[Plasma reload instructions](TROUBLESHOOTING.md#widget-update-not-visible).

WirePlumber handles automatic routing based on the driver's availability reports.
There is no application-level previous-output restoration or routing fallback.
To keep playback going when an output disappears, see
[disabling WirePlumber's automatic pause](TROUBLESHOOTING.md#playback-pauses-when-the-headset-turns-off).
This is a separate audio-policy preference for all outputs in your WirePlumber
session, not a widget option.

Help follows KDE's standard pattern: an **ⓘ** button explains on hover or
click, with at most one per view. In the popup it sits in the **Modes** heading
and covers Do not disturb, Bluetooth gaming mode and Bluetooth Devices; on the
**Headset** page it sits next to **Sound profile** and explains the bands and
Apply. The text follows the desktop language (English or Spanish). Opening Help
does not query or change headset settings.

## Modes and Bluetooth devices

Each time the popup is shown with a confirmed link, including the desktop's
inline view, it reads the headset settings once; the same status read also
returns the Bluetooth devices, so no extra query is made. It reads them again if
the link returns or its transport changes while the popup is shown.

**Do not disturb** keeps calls from a phone connected by Bluetooth from
interrupting the dongle audio; it does not affect desktop notifications.
**Bluetooth gaming mode** lowers Bluetooth audio delay and is not the Game sound
profile. Each is a full-width switch row with the value the headset reported; a
click anywhere on the row asks for the change, and the switch keeps showing the
reported value until the headset's reply confirms it. Without a reading the row
draws no switch and says **Reading…** or **Unknown**, so an unknown value never
looks Off, and nothing is shown as current without a confirmed link. While its
own change runs, the row shows a busy indicator; every row is disabled while
any request, pairing or power-off runs. Bluetooth gaming mode is read through
either transport but can be changed only over Bluetooth: while the settings are
read through the USB dongle, its switch is disabled and the row says **Only over
Bluetooth**. With both links confirmed, the settings follow the default output,
so this can happen while Bluetooth is connected too.

A failed change is named in the message slot with the headset's reason. When
the headset certainly did not apply it, for example a rejected change, the
switch stays at the confirmed value to try again; when the change may have
happened, for example without an answer, nothing stays known and **Try Again**
reads the headset. A setting the reading could not return is named, with
**Try Again**; when nothing could be read, the sections are hidden and the
message says so. There is no success notice.

**Bluetooth Devices** (Razer Quick Connect) moves the headset's Bluetooth
connection to a device it already knows, which may interrupt audio. The active
device is shown in bold as **Connected**; every other device has **Connect**,
and shows **Connecting…** while its request runs. Switching needs Bluetooth
gaming mode known to be off: while it is on or unknown, **Connect** is disabled
and a note under the heading says why. Through the USB dongle gaming mode cannot
be turned off, so switching then needs Bluetooth. The active device changes only
when a reading says so; open the popup again to read the headset again. A list
the reading could not return is hidden, and the message names it.

## Headset settings

The gear in the popup heading opens the widget's configuration window; so does
**Configure Barracuda Headset…** in the right-click menu, which uses Plasma's
own name for it. The window has one **Headset** page for what the headset
stores: the **Sound profile** with its custom bands, and **Turn off when idle**.
The page reads the headset when it opens, with a loading message meanwhile, and
shows **Settings not read** with **Try Again** when nothing could be read. Every
change waits for the window's **Apply** or **OK**, which send it, and **Cancel**
discards it; a profile is therefore heard only after **Apply**.

The **Sound profile** selector shows the profile stored on the headset until you
choose another. Choose **Custom** to reveal its ten **Bands**, which start from
the curve stored on the headset; **Reset Bands** returns them to 0. **Apply**
sends the profile first, then the edited bands, then idle shutdown, and stops at
the first failure. Plasma closes the page as soon as **OK** is pressed or
another category opens, so the changes are sent by a background process that
finishes on its own. When a send fails, the page says the changes were not
applied and keeps your choices for another **Apply**. A setting the reading
could not return is shown as a disabled selector saying **Unknown**, and the
message at the top of the page names it, with **Try Again**. Preset names follow
the desktop language (English or Spanish). Session buffer and sample-rate tuning
are no longer exposed in the plasmoid. Software EQ and sidetone are removed.
See [audio effects](AUDIO_EFFECTS.md) for native control details, dependencies and CLI-only Linux tuning.
Use KDE Sound settings for microphone mute and volume.

## Play/pause

A short press of the headset's power/play button sends a standard HID media key.
Linux and the desktop forward it to the selected media player; neither the CLI
nor widget intercepts it. Only single-press play/pause has been validated.

## Headset power-off

Choose **Turn Off Headset…** in the popup's **More actions** menu (☰) or the
right-click menu, then **Turn Off** in the dialog. The headset card reads
**Turning off…** while the request runs; success shows in the next status
reading, and a failure says to check the USB dongle and offers **Try Again**.
The action always goes through the USB dongle and addresses the Barracuda
headset, independently of the desktop's default output.
The CLI equivalent is:

```bash
barracuda-power --off
barracuda-power --off --language es
```

`--yes` skips the interactive prompt for callers that already confirmed the
action. Power-on requires the headset's physical button. Success means the
power-off request was sent; it does not synthesize a disconnected state or claim
physical shutdown was observed. An acknowledgment may be lost as the radio turns
off, so the command is never automatically repeated.

This requires the driver from all three HID patches and
`packaging/99-barracuda-power.rules`. The rule grants the `audio` group write
access to the driver's `headset_poweroff` attribute on the matching HID device.
Installing the driver and rule requires administrator access once; normal use
requires no sudo for members of that group. An older driver produces an explicit
update message; the CLI never falls back to unsynchronized raw HID writes.
Closing the popup does not cancel a started request. Pairing and power actions
from the same user share an XDG state lock. Driver battery queries and power-off
share the kernel route mutex; a busy operation can be retried manually.

The battery indicator also accepts the `Razer Barracuda X (BT)` battery
reported by KDE/UPower. If both transports report a battery, the current audio
output determines which reading is preferred. Bluetooth charge state may be
unknown even when the percentage is available. Missing battery data is not
connection evidence.

Native effects also work when the Barracuda is the Bluetooth output. The helper
uses the paired headset's discovered serial service and confirms changes by
reading them back. It does not require the USB dongle for Bluetooth controls.
See [Bluetooth controls](BLUETOOTH_CONTROLS.md) for validation and dependencies.
