# Troubleshooting

## Pairing permissions or missing adapter

Check `lsusb -d 1532:0552` and the udev rule
`/usr/lib/udev/rules.d/99-razer-barracuda.rules` (or `/etc/udev/rules.d` for
checkout installs). Reconnect the dongle after installing rules. Run pairing as
your desktop user, not root. After successful pairing, power-cycle the headset.

USB presence alone does not confirm a wireless link. A silent dongle remains
unknown, not disconnected. See [protocol notes](PROTOCOL.md).

## Audio does not switch

There is no longer a Python routing fallback. Check the native stack:

```bash
pactl get-default-sink
pactl list cards
pactl list sinks
dkms status
journalctl --user -u wireplumber -b
```

Select the headset once in KDE Sound settings. Verify the driver and jack quirk
are loaded after reboot; see [jack detection](JACK_DETECTION.md). The quirk
installer does not reload the running audio module.

Applications that open ALSA hardware directly (for example `hw:` or `plughw:`)
bypass PipeWire's routing. Changing the desktop default does not move those
streams. Select a PipeWire/PulseAudio backend in the application, if available,
or select its output there. The plasmoid only reports the desktop default; it
cannot report or move a direct ALSA stream.

## Analog versus digital profiles

"Analog Stereo" is an audio-server profile name: the dongle's USB transport is
digital. The pairing CLI and widget do not change profiles or volumes.

During hardware validation, the dongle exposed one playback format (16-bit
stereo, 48 kHz) and one capture format (16-bit mono, 48 kHz), each with a single
alternate setting and Speaker/Microphone terminals, not a digital output terminal.
The extra IEC958/S/PDIF and AC3 profiles came from generic Linux configuration,
not evidence of additional physical outputs:

1. PipeWire's ACP default profile set tries ALSA mappings such as `front:`,
   `iec958:` and `a52:` when no UCM profile is used, offering mappings it can open.
2. In the alsa-lib configuration examined during validation,
   `/usr/share/alsa/cards/USB-Audio.conf` mapped USB `iec958` to `hw:CARD,0`
   unless the card name appeared in `USB-Audio.pcm.iec958_device`. Some headsets
   used the sentinel `999` to disable it; `Razer Barracuda X 2.4` was not listed.
   Thus IEC958 opened the same PCM as the stereo mapping, without a separate
   digital output or a jack-aware port.
3. The `a52` plugin adds software AC3 encoding on top of IEC958. AC3 playback was
   not tested here; an offered profile does not establish that the headset can
   decode it. It should not be treated as another usable headset output.

With the jack quirk, a jack-less output can remain available while the headset
is off and be selected by WirePlumber. The supplied
[`razer-barracuda.conf`](../packaging/razer-barracuda.conf) therefore offers only
the analog mappings, selected by `89-razer-barracuda-acp.rules`.
The custom [microphone path](../packaging/analog-input-headset-mic-razer-barracuda.conf)
binds the card's `Mic` mixer element to `Headset Mic Jack`. The stock headset
path expected `Headset Mic`; the generic microphone path had no jack binding,
leaving a microphone port available even with the headset off.

An old `51-barracuda-analog-only.conf` WirePlumber rule can override the udev
profile selection. Review and remove that obsolete user rule as described in
[jack detection](JACK_DETECTION.md). Do not delete package-owned profile files.
An alsa-lib card-table fix could suppress the false IEC958 mapping upstream;
a local override of that table has not been tested by this project.

## Playback pauses when the headset turns off

When the headset's output sink is removed, WirePlumber can pause media players
using MPRIS. This is controlled by `linking.pause-playback`, enabled by default;
neither the pairing CLI nor the plasmoid sends pause commands.
See [WirePlumber's settings documentation](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/settings.html#linking-pause-playback).

Inspect the setting and disable it for the current session:

```bash
wpctl settings linking.pause-playback
wpctl settings linking.pause-playback false
```

To disable it persistently across WirePlumber restarts:

```bash
wpctl settings --save linking.pause-playback false
```

To enable automatic pausing again and save that choice:

```bash
wpctl settings --save linking.pause-playback true
```

No service restart is required. This setting affects all removed output sinks,
not only Barracuda. With pausing disabled, playback may continue through the
fallback speakers; consider privacy before changing it. Applications may also
implement their own pause-on-disconnect behavior.

## The icon is still a speaker

KDE's stock volume widget uses a volume icon. Add this project's **Current Audio
Output** widget separately; it does not patch KDE's widget. Hover verifies which
default device it is showing. Per-application output overrides can differ.

If the widget fails to load, verify `plasma-pa` is installed. The private KDE API
is tested on Plasma 6.7.4. It is a project widget, not an official KDE applet.

## Widget update not visible

On Arch/CachyOS, check the installed package and the widget path:

```bash
pacman -Q plasma6-applets-barracuda
pacman -Qkk plasma6-applets-barracuda
kpackagetool6 --type Plasma/Applet --show org.razer.barracuda.output
```

The system package lives under
`/usr/share/plasma/plasmoids/org.razer.barracuda.output/`. A user installation
under `$XDG_DATA_HOME/plasma/plasmoids/` can shadow it. Remove only the copy you
intend to replace; do not mix installation methods.

Plasma can retain old QML in memory even when the installed files are correct.
Removing and re-adding the widget is not always sufficient. On sessions managed
by `plasma-plasmashell.service`, reload only the desktop shell:

```bash
systemctl --user restart plasma-plasmashell.service
systemctl --user is-active plasma-plasmashell.service
```

The panel and desktop briefly disappear. This does not restart PipeWire or
WirePlumber. If the session has no such service, save your work and log out/in.
Do not reload the kernel module to refresh widget artwork.

## Icon missing or too small

Check that the detailed KDE artwork is installed:

```bash
ls /usr/share/icons/breeze/devices/64/audio-headset.svg
ls /usr/share/icons/breeze/devices/64/audio-speakers.svg
journalctl --user -u plasma-plasmashell.service -b --since "5 minutes ago"
```

On Arch/CachyOS these files belong to `breeze-icons`. The published v0.4.0
widget uses `audio-headphones.svg`; the headset artwork is a newer checkout
change. Icons scale with the panel's available size. Unexpectedly tiny or absent
icons can also be caused by a QML binding loop; inspect recent log entries rather
than assuming another restart will fix it. The rendering test covers both panel
orientations and 22, 32 and 48 pixel button sizes.

## Old tray installations

Stop any former tray instance and disable its session autostart entry.
A manually created `barracuda-status.service` can be stopped with
`systemctl --user stop barracuda-status.service`; this project supplies no
permanent service. Remove the old pacman package before installing the new CLI.
No migration is performed automatically.

For checkout installs, review these legacy paths. The defaults below assume
that the corresponding XDG variables are unset:

| Legacy item | Default path |
| --- | --- |
| Tray launchers | `~/.local/bin/barracuda-status`, `~/.local/bin/barracuda-status.py` |
| Copied application | `~/.local/share/barracuda-status/` |
| Application entry | `~/.local/share/applications/org.razer.BarracudaStatus.desktop` |
| Session autostart | `~/.config/autostart/org.razer.BarracudaStatus.desktop` |
| Old application icon | `~/.local/share/icons/hicolor/scalable/apps/barracuda-status.svg` |
| Saved routing state | `~/.local/state/barracuda-status/audio.json` |

Use `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME` and `$XDG_STATE_HOME` respectively if
set. Remove only confirmed legacy copies you installed, not entire XDG or
configuration directories. The saved routing state is no longer read; it is
not evidence of the current wireless connection.

A user-installed pairing launcher can also shadow the new packaged command:

```bash
type -a barracuda-pair
pacman -Qo /usr/bin/barracuda-pair
```

Review `~/.local/bin/barracuda-pair` before removing it: it may be your intended
current checkout installation. Use pacman to remove package-owned files rather
than deleting them by hand. Old user WirePlumber rules can take precedence over
system rules with the same name; review those separately, especially the obsolete
`51-barracuda-analog-only.conf` mentioned above.

## Uninstall

Remove the new Arch packages with:

```bash
sudo pacman -R barracuda-pair plasma6-applets-barracuda hid-razer-barracuda-dkms
```

Removing the driver also removes quirk builds managed by its pacman hook; reboot
to stop using an already loaded module. Independently installed quirks need
their own installer removal command.

For a user-installed widget:
`kpackagetool6 --type Plasma/Applet --remove org.razer.barracuda.output`.
For the user CLI, remove its launcher and `barracuda-pair` XDG data directory.
