# Usage

## Pairing

`barracuda-pair` replays the validated vendor pairing sequence. It requires
write access to the matching USB dongle and aborts on unexpected replies.

```bash
barracuda-pair --scan
barracuda-pair
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
the commands in the heading, and the headset, how it sounds and its battery on
three tabs under it. No colour is added; states are told apart by their words,
artwork, opacity and emblems.

### Heading and commands

The heading shows the widget's name, **+** (**Pair Headset…**) and **More
actions** (☰), as in KDE's Bluetooth applet. In the system tray, Plasma draws
this row itself from the widget's actions; in a panel or on the desktop the
widget draws the same row. **More actions** holds **Turn Off Headset…** and,
after a separator, **Configure Audio Devices…**, which opens KDE's audio
settings. The right-click menu shows the same commands together with Plasma's
own. There is no configuration window: everything the headset stores is in the
popup.

With a confirmed link, three tabs sit under that row, as **Devices** and
**Applications** do in KDE's volume applet: **Headset**, **Sound** and
**Power**. The popup always opens on **Headset**. Without a confirmed link, and
while pairing, there are no tabs and one message fills the popup.

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
  battery**). Click the card for its connection details: whether the USB dongle
  is detected, the 2.4 GHz link and the paired Bluetooth connection; the
  battery readings are on the **Power** tab. While the headset turns off, the
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
- **Checking…** while the first status is read, **Pairing…** while pairing
  runs, and **Turning off…** while a power-off started without a confirmed link
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
to the journal. Under **Disconnected**, the message's **Pair Headset…** just
above the failure is the way to try again, so the failure has no button of its
own. Closing the popup dismisses a pending confirmation and previous
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
click, with at most one per tab. On **Headset** it sits in the **Modes** heading
and covers Do not disturb, Bluetooth gaming mode and Bluetooth Devices; on
**Sound** it sits in the **Equalizer** heading and explains the profiles and
bands. The text follows the desktop language (English or Spanish). Opening Help
does not query or change headset settings.

## Modes and Bluetooth devices

These are on the **Headset** tab. Each time the popup is shown with a confirmed
link, including the desktop's inline view, it reads the headset settings once;
the same status read also returns the Bluetooth devices and what the **Sound**
and **Power** tabs show, so no extra query is made. It reads them again if
the link returns or its transport changes while the popup is shown.

**Do not disturb** keeps calls from a phone connected by Bluetooth from
interrupting the dongle audio; it does not affect desktop notifications.
**Bluetooth gaming mode** lowers Bluetooth audio delay and is not the Game sound
profile. Each is a full-width row laid out like the device rows below it: a
monochrome icon, the name, and the switch on the right with the value the
headset reported. A click anywhere on the row asks for the change, and the switch keeps showing the
reported value until the headset's reply confirms it. Without a reading the row
draws no switch and says **Reading…** or **Unknown**, so an unknown value never
looks Off, and nothing is shown as current without a confirmed link. While its
own change runs, the row shows a busy indicator; every row is disabled while
any request, pairing or power-off runs. Bluetooth gaming mode can be changed
only over Bluetooth and turns off whenever the headset does, so its row is shown
only while the settings are read over Bluetooth; through the USB dongle
**Modes** holds **Do not disturb** alone. With both links confirmed, the
settings follow the default output, so the row can be hidden while Bluetooth is
connected too. Through the dongle the value is still read: when it is on,
**Connect** stays disabled and the note under **Bluetooth Devices** says to turn
it off from a device connected over Bluetooth.

When the headset certainly did not apply a change, for example a rejected
one, the message slot names the change with the headset's reason and the switch
stays at the confirmed value to try again. When the change may have happened,
for example without an answer, nothing stays known: the sections are hidden,
the message says the headset could not be read, and **Try Again** reads it. A setting the reading could not return is named, with
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

## Sound and Power

The **Sound** tab holds the **Sound profile** and, with **Custom**, its ten
bands; the **Power** tab holds the **Battery** readings and **Turn off when
idle**. Both come from the popup's one settings read, and every change is sent
to the headset at once: there is no **Apply** and nothing to cancel, so a
profile is heard as soon as you choose it.

Each setting is a row like the Modes rows, with its selector on the right
showing the value the headset reported. Choosing another value asks for it; the
selector keeps showing the reported value, with a busy indicator beside it,
until the headset's reply confirms it. Scrolling over a selector and the arrow
keys never change it; **Space** opens it. A setting the reading could not
return is shown as a disabled selector saying **Unknown**, and the message slot
names it, with **Try Again**.

Choose **Custom** to reveal its ten bands, which show the curve stored on the
headset; levels are relative, from −5 to +5, and 0 is neutral. A band follows
the pointer while you drag it. Once you let go and the levels rest for a
moment, the whole curve is sent as one request; edits made while a request
runs wait for it and are then sent together, latest levels only. **Reset
Bands** returns every band to 0 and is sent the same way. When the headset
does not apply a change, the bands return to the stored curve and the message
says so. Edits still waiting when the profile stops being **Custom** are
dropped.

**Battery** shows the charge with its state, and through the USB dongle the
charging cable and the battery voltage the driver reports; it needs no headset
request. Over Bluetooth alone only the charge is shown. **Turn off when idle**
is the headset's own idle shutdown: **Never** or 5 to 60 minutes. Preset names
follow the desktop language (English or Spanish). Session buffer and
sample-rate tuning are no longer exposed in the plasmoid. Software EQ and
sidetone are removed. See [audio effects](AUDIO_EFFECTS.md) for native control
details, dependencies and CLI-only Linux tuning. Use KDE Sound settings for
microphone mute and volume.

## Play/pause

A short press of the headset's power/play button sends a standard HID media key.
Linux and the desktop forward it to the selected media player; neither the CLI
nor widget intercepts it. Only single-press play/pause has been validated.

## Headset power-off

Choose **Turn Off Headset…** in the popup's **More actions** menu (☰) or the
right-click menu, then **Turn Off** in the dialog. The headset card reads
**Turning off…** while the request runs, or, without a confirmed link, the
message that replaces the popup's body does; success shows in the next status
reading, and a failure says to check the USB dongle and offers **Try Again**.
The action always goes through the USB dongle and addresses the Barracuda
headset, independently of the desktop's default output.
The CLI equivalent is:

```bash
barracuda-power --off
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
