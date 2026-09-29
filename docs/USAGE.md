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
Click opens KDE Sound settings. Text follows the desktop locale (English/Spanish).

Barracuda USB identity, headphone/headset form factors and active headphone ports
use the headset-with-microphone icon. This is a presentation choice; it does not
mean the microphone is recording. Other outputs use their advertised icon, with a speaker
fallback. Missing/dummy output uses an audio-card icon and “No audio output”.

Headsets and speakers use KDE Breeze's detailed 64-pixel artwork
(`audio-headset.svg` and `audio-speakers.svg`), scaled to the panel size.
The widget reads these SVGs from
`/usr/share/icons/breeze/devices/64/`, supplied by `breeze-icons`; no icons are
bundled or copied. This deliberately bypasses the theme's small monochrome variants.
The icon fills the panel button's available area without the theme's button padding;
the drawing itself retains the proportions and margins of KDE's artwork.

The headset icon is a checkout change after v0.4.0; the published v0.4.0 packages
use `audio-headphones.svg`. See [change history](CHANGELOG.md).

The icon describes the default device, not proof of a physical wireless link.
It does not show which output each individual application uses. Selecting another
default in KDE updates the widget. No polling process, HID access or audio writes
are involved. Keep KDE's volume widget if you want its volume and device controls;
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

## Play/pause

A short press of the headset's power/play button sends a standard HID media key.
Linux and the desktop forward it to the selected media player; neither the CLI
nor widget intercepts it. Only single-press play/pause has been validated.
