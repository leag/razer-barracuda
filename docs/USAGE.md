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

## Current Audio Output widget

Add **Current Audio Output** (**Salida de audio actual**) to a Plasma 6 panel
or desktop. The panel shows the default output's icon, with a small mute badge
when muted. Hover shows its name; the desktop representation includes the name.
Click opens a summary showing the default output's name, volume and mute state.
It follows speakers, HDMI monitors and other audio outputs even without a Barracuda.
Missing outputs and unavailable volume are shown explicitly. Sound settings are
available as a secondary action. Text follows the desktop locale (English/Spanish).
The icon has no button frame on pointer hover. Keyboard navigation retains the
active Plasma theme's focus indicator.

Barracuda USB identity, headphone/headset form factors and active headphone ports
use the headset-with-microphone icon. This is a presentation choice; it does not
mean the microphone is recording. Other outputs use their advertised icon, with a speaker
fallback. Missing/dummy output uses an audio-card icon and “No audio output”.

Headsets and speakers use KDE Breeze's detailed 64-pixel artwork
(`audio-headset.svg` and `audio-speakers.svg`), scaled to the panel size.
The widget reads these SVGs from
`/usr/share/icons/breeze/devices/64/`, supplied by `breeze-icons`; no icons are
bundled or copied. This deliberately bypasses the theme's small monochrome variants.
The icon is centered and capped at KDE's medium icon size (32 logical pixels),
shrinking to fit smaller panels. The full button remains clickable, while the
drawing retains the proportions and margins of KDE's artwork.

The headset icon is a checkout change after v0.4.0; the published v0.4.0 packages
use `audio-headphones.svg`. See [change history](CHANGELOG.md).

The Barracuda section shows its last reported battery percentage and charging
state from KDE's power-management service, also included in the tooltip when
available. This is independent of the selected audio output. Missing battery data
is shown as unavailable, never as proof of a disconnected headset. The widget
matches the Barracuda model and headset battery type, excluding computer and mouse
batteries. It sends no battery queries. Unknown charging state remains unknown;
a connected cable does not by itself prove that charging has completed.

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

The icon describes the default device, not proof of a physical wireless link.
It does not show which output each individual application uses. Selecting another
default in KDE updates the widget. The summary does not poll or write audio state;
only explicitly launched pairing accesses raw HID; power-off uses the serialized driver interface. Keep KDE's volume widget if you want its volume and device controls;
this widget does not replace those controls.

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

The compact overview shows the current output and a battery row. Sound settings
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
