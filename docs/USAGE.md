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
Entries**. You can also add it to a Plasma 6 panel or desktop; installing does
not change any panel. A widget already added by an earlier version keeps working
after an update.

In the system tray the icon stays visible in every state, including a
disconnected headset or a missing USB dongle, so the pairing controls stay
reachable. A low battery asks for attention. The tray's own visibility settings
override this.

Panel and tray icons use the theme's symbolic headset glyph, recolored like the
neighboring icons. It is drawn at full opacity while the headset link is
confirmed and dimmed otherwise. A thin red diagonal slash, cut into the glyph
like Breeze's `camera-off` icon, marks a disconnected headset or a missing
USB dongle; with Qt Quick's software renderer the slash is drawn over the uncut
glyph. A small corner emblem
shows a question mark when the link is not confirmed, and a warning at 10%
battery or less while not charging. Hover shows the connection state and battery. Text
follows the desktop locale (English/Spanish). The icon has no button frame on
pointer hover; keyboard navigation retains the theme's focus indicator.

Click opens the popup. Every function has one place, chosen by what it is: the
popup holds the headset and its connections, the configuration window how it
sounds and when it turns itself off, and **Configure Audio Devices…** in the
heading the way out to KDE's audio settings.

The heading shows the widget's name, **More actions** (☰) and a configure
button (the gear). In the system tray, Plasma draws this heading itself; in a
panel or on the desktop the widget draws one like it. **More actions** holds
only **Configure Audio Devices…**, which opens KDE's audio settings, and the gear
opens the widget's configuration window. In the system tray before Plasma 6.8,
Plasma shows that single action as a button with its own icon instead of
**More actions**; the widget's own heading always shows the menu. The
right-click menu shows the same two entries together with Plasma's own. Below
the heading, from top to bottom:

- **State and battery**, beside the headset artwork: Connected (USB dongle,
  Bluetooth, or both), Disconnected, Link not confirmed, USB dongle not
  detected, or Status unavailable, with a short hint; below it the battery
  percentage and charging state. A connected state shows a USB dongle icon, or
  a Bluetooth icon when only Bluetooth is linked.
- **Pair USB Dongle…** and **Turn Off Headset…**, always shown. Each asks for
  confirmation right below it, and its progress and result appear there too.
  Both are disabled while either runs and when the driver reports that no USB
  dongle is connected; an unknown or unavailable state never disables them.
- **Do Not Disturb** and **Bluetooth Gaming Mode** switches, each with one line
  that explains it (see [below](#connection-modes-and-quick-connect)).
- **Quick Connect**: the Bluetooth sources the headset knows, with a **Switch**
  button for each inactive one.
- **Details**, folded by default: whether the USB dongle is detected, the
  2.4 GHz link, the paired Bluetooth connection, and while the dongle link is
  confirmed the charging cable and battery voltage last reported by the driver.

Feedback appears under the control that caused it. The system tray gives all its
applets one popup size, which you can change by dragging the popup edge; the
popup scrolls when its content is taller and keeps the free space at the bottom.

The state comes from `barracuda-headset --request '{"op":"link"}'`, a finite,
read-only query. It reads the driver's USB `wireless_status` attribute and
power-supply values from sysfs, and the paired headset's connection from BlueZ.
It never opens HID and never sends anything to the dongle or headset. The widget
runs it on load, every 5 seconds while the popup is open, when a Barracuda
battery appears or disappears in KDE (the driver registers it only on a confirmed
link change), when the default output changes, and after pairing or power-off.
There is no background process. Unknown, disconnected and missing-dongle states
stay distinct: an unconfirmed link is never shown as a disconnection.
Without an updated `barracuda-headset` on `PATH`, the widget shows
**Status unavailable** and keeps its other actions.

The default output is not link evidence. It only selects the native-control
transport when both or neither link is confirmed; otherwise headset settings
follow the confirmed USB or Bluetooth link.

The popup's detailed artwork is read from
`/usr/share/icons/breeze/devices/64/audio-headset.svg`, supplied by
`breeze-icons`; no icons are bundled or copied. The tray sizes its own icons; a
panel icon outside the tray is centered and capped at KDE's small-medium icon
size, shrinking to fit smaller panels.

The battery comes from KDE's power-management service, or from the driver's
published value when KDE does not list it. It is the last reported percentage
and charging state. The widget matches the Barracuda model and headset battery
type, excluding computer and mouse batteries. It sends no battery queries.
Unknown charging state remains unknown; a connected cable does not by itself
prove that charging has completed.

**Pair USB Dongle…** in the popup opens a native confirmation right below it.
Connect the USB dongle, put the headset in pairing mode, and choose **Pair** to
confirm replacing the current pairing, or **Cancel** to leave it unchanged. Only after
confirmation does the widget run `barracuda-pair --yes --timeout 60`, in the desktop
language (English fallback). Install the optional CLI and ensure it is on `PATH`.
No terminal is needed. An activity indicator remains visible while the CLI runs;
the current backend returns diagnostic output at completion, not live scan stages.
The search lasts up to a minute, followed by connection and cleanup. Once started,
let the operation finish; closing the popup does not cancel it. The widget prevents
a second launch from the same instance while busy. Success instructs you to
power-cycle the headset; errors remain visible in a scrollable area. Closing the
popup dismisses pending confirmation and previous result messages, while an active
pairing operation continues. Pairing is
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
click, with at most one per view. In the popup it sits next to the connection
state and also covers the battery; on the **Equalizer** page it sits next to
**Sound profile** and explains custom EQ and Apply. Other controls carry a short
description instead. The text follows the desktop language (English or
Spanish). Opening Help does not query or change headset settings.

## Connection modes and Quick Connect

Each time the popup is shown with a confirmed link, including the desktop's
inline view, it reads the headset settings once; the same status read also
returns the Quick Connect devices, so no extra query is made. It reads them
again if the link returns or its transport changes while the popup is shown.

**Do Not Disturb** keeps calls from a phone connected by Bluetooth from
interrupting the dongle audio; it does not affect desktop notifications.
**Bluetooth Gaming Mode** lowers Bluetooth audio delay and is not the Game sound
profile. Each row shows a switch with the value the headset reported. Without a
reading the switch gives way to **Reading…** or **Unknown**, so an unknown value
never looks Off, and nothing is shown as current without a confirmed link. A
click sends the change; the switch keeps showing the reported value until the
headset confirms it. Switches are disabled while any request, pairing or
power-off runs. Bluetooth Gaming Mode is read through either transport but can
be changed only over Bluetooth: while the settings are read through the USB
dongle, its switch is disabled and its line says so. With both links confirmed,
the settings follow the default output, so this can happen while Bluetooth is
connected too. A failed request or read appears right under the switches as a
warning with **Refresh**; there is no success notice.

**Quick Connect** moves the headset's Bluetooth connection to a device it already
knows, which may interrupt audio. The active source has a check mark; every other
device has a **Switch** button. Switching needs Bluetooth Gaming Mode known to be
off: while it is on or unknown, the buttons are disabled and a line points to
its switch above. Through the USB dongle gaming mode cannot be turned off, so
switching then needs Bluetooth. A switch request shows **Connection switch
requested** with **Refresh** under the list; the active marker moves only when a
new reading confirms it. Errors, such as a device the headset no longer lists,
appear in the same place.

## Headset settings

The gear in the popup heading opens the widget's configuration window; so does
**Configure Barracuda Headset…** in the right-click menu, which uses Plasma's
own name for it. The window holds how the headset sounds and when it turns
itself off: it opens on **Equalizer**, and **Power Saving** holds idle shutdown.
Each page reads the headset when it opens. Every change on a page waits for the
window's **Apply** or **OK**, which send it, and **Cancel** discards it; a
profile is therefore heard only after **Apply**.

On the **Equalizer** page, the **Sound profile** selector shows the profile
stored on the headset until you choose another, which **Apply** or **OK** then
sends. Choose **Custom** to reveal its bands, which start from the curve
stored on the headset; **Reset Bands** returns them to 0. **Apply** sends the
profile first and then the edited bands, and stops at the first failure. Plasma
closes the page as soon as **OK** is pressed or another category opens, so the
changes are sent by a background process that finishes on its own. When a send
fails, the choices stay on the page for another **Apply**. Messages about
reading, sending, errors and confirmed changes appear at the top of each page,
and every message that asks for **Refresh** offers it. Unknown or failed values
disable their controls. Session buffer and sample-rate tuning are no longer
exposed in the plasmoid. Software EQ and sidetone are removed.
See [audio effects](AUDIO_EFFECTS.md) for native control details, dependencies and CLI-only Linux tuning.
Use KDE Sound settings for microphone mute and volume.

## Play/pause

A short press of the headset's power/play button sends a standard HID media key.
Linux and the desktop forward it to the selected media player; neither the CLI
nor widget intercepts it. Only single-press play/pause has been validated.

Pairing and power-off are buttons in the popup; each displays an inline
confirmation and progress message.
Preset names in the headset settings follow the desktop language (English or
Spanish).

The headset battery uses Plasma's native BatteryIcon component, a percentage and
a state label for charging, full charge or an unknown charge state. A normal
discharging state needs no extra label. Missing telemetry shows Unknown.
Charging does not imply a full battery, and unavailable telemetry does not
establish wireless link state.

## Headset power-off

Choose **Turn Off Headset…** in the popup, then **Turn Off** in the
confirmation right below it. The action always goes through the USB dongle and
addresses the Barracuda headset, independently of the desktop's default output.
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
