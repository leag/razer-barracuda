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

Add **Barracuda Headset** (**Auricular Barracuda**) to a Plasma 6 panel or
desktop. A widget already added by an earlier version keeps working after an update.
The panel shows KDE Breeze's detailed headset artwork. It is drawn at full
opacity while the headset link is confirmed and dimmed otherwise. A thin red
diagonal slash, cut into the artwork like Breeze's `camera-off` icon, marks a
disconnected headset or a missing adapter; with Qt Quick's software renderer the
slash is drawn over the uncut artwork. A small corner emblem
shows a question mark when the link is not confirmed, and a warning at 10%
battery or less while not charging. Hover shows the connection state and battery. Text
follows the desktop locale (English/Spanish). The icon has no button frame on
pointer hover; keyboard navigation retains the theme's focus indicator.

Click opens the connection summary:

- **State**: Connected (USB dongle, Bluetooth, or both), Disconnected, Link not
  confirmed, Adapter not detected, or Status unavailable, with a short hint.
- **Details**: whether the USB dongle is detected, the 2.4 GHz link, the paired
  Bluetooth connection, and while the dongle link is confirmed the charging
  cable and battery voltage last reported by the driver.
- **Battery**: percentage and charging state.

The state comes from `barracuda-headset --request '{"op":"link"}'`, a finite,
read-only query. It reads the driver's USB `wireless_status` attribute and
power-supply values from sysfs, and the paired headset's connection from BlueZ.
It never opens HID and never sends anything to the dongle or headset. The widget
runs it on load, every 5 seconds while the popup is open, when a Barracuda
battery appears or disappears in KDE (the driver registers it only on a confirmed
link change), when the default output changes, and after pairing or power-off.
There is no background process. Unknown, disconnected and missing-adapter states
stay distinct: an unconfirmed link is never shown as a disconnection.
Without an updated `barracuda-headset` on `PATH`, the widget shows
**Status unavailable** and keeps its other actions.

The default output is not link evidence. It only selects the native-control
transport when both or neither link is confirmed; otherwise headset settings
follow the confirmed USB or Bluetooth link.

Artwork is read from `/usr/share/icons/breeze/devices/64/audio-headset.svg`,
supplied by `breeze-icons`; no icons are bundled or copied. This deliberately
bypasses the theme's small monochrome variants. The icon is centered and capped
at KDE's medium icon size (32 logical pixels), shrinking to fit smaller panels.

The battery comes from KDE's power-management service, or from the driver's
published value when KDE does not list it. It is the last reported percentage
and charging state. The widget matches the Barracuda model and headset battery
type, excluding computer and mouse batteries. It sends no battery queries.
Unknown charging state remains unknown; a connected cable does not by itself
prove that charging has completed.

**More actions → Pair Barracuda…** opens a native confirmation inside the widget. Connect the
Barracuda dongle, put the headset in pairing mode, and choose **Pair** to confirm
replacing the current pairing, or **Cancel** to leave it unchanged. Only after
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
raw HID; power-off uses the serialized driver interface. **Sound settings…**
opens KDE's audio controls; keep KDE's volume widget for volume and device
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

Choose **More actions → Help** for explanations of the widget and headset
controls, including Do Not Disturb. Help is also available from the headset settings
view and follows the desktop language (English or Spanish). Opening Help does
not query or change headset settings.

## Headset settings

Choose **Headset settings…** to open the native headset EQ directly. The applied
preset is shown in the **Profile** selector. Selecting a profile applies it
immediately; the selector updates after headset confirmation. Choose **Custom**
to reveal its bands, then use **Apply changes** to save adjustments. **More settings**
contains Gaming, DND, idle shutdown and Bluetooth Quick Connect. Unknown or failed
values disable their controls; click Refresh to read again. Session buffer and
sample-rate tuning are no longer exposed in the plasmoid. Software EQ and
sidetone are removed.
If legacy filters are enabled or loaded, use the explicit cleanup button; it
briefly restarts audio before native EQ can be used.
See [audio effects](AUDIO_EFFECTS.md) for activation, dependencies and how to revert.
Use KDE Sound settings for microphone mute and volume.

## Play/pause

A short press of the headset's power/play button sends a standard HID media key.
Linux and the desktop forward it to the selected media player; neither the CLI
nor widget intercepts it. Only single-press play/pause has been validated.

The compact overview shows the connection state, its details and a battery row. Sound settings
and **Headset settings…** are at the bottom; pairing is under **More actions**.
Pairing displays an inline confirmation and progress message. **Back** returns
from effects to the overview while preserving pending edits.
The effects editor marks unsaved changes above its Apply button; preset names
follow the desktop language (English or Spanish).

The headset battery uses Plasma's native BatteryIcon component, a percentage and
a state label for charging, full charge or an unknown charge state. A normal
discharging state needs no extra label. Missing telemetry shows Unknown.
Charging does not imply a full battery, and unavailable telemetry does not
establish wireless link state.

## Headset power-off

Choose **More actions → Turn off headset…**, then **Turn off**. The action always
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
