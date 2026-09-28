# Jack detection (experimental)

The DKMS driver reports the wireless link as `SW_HEADPHONE_INSERT` and
`SW_MICROPHONE_INSERT`. The official `snd-usb-audio` does not yet turn these into
ALSA jack controls for `1532:0552`; this needs a two-line quirk like the Sony
DualSense's. With such a module loaded, PipeWire marks the headset output
unavailable when the headset is off; WirePlumber handles output switching.
Neither the pairing CLI nor the plasmoid changes the default output.

To load such a module, install it as a DKMS package for the running kernel. The
installer downloads `sound/usb` for the matching upstream stable version (GPL-2.0,
not stored here), applies `kernel/snd-usb-audio/*.patch` only if it applies
cleanly, and restricts the package to that exact kernel release:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py          # then reboot
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove
```

The Arch driver package installs this automatically for all kernels with headers,
including on kernel header upgrades. It requires internet access to download sources.
Automatic installation (`--all-kernels`) first checks the installed PipeWire ALSA
plugin for `wireless_status` support and skips the quirk when present. This checks
the capability rather than a version threshold, so distribution backports work
too. Missing or unreadable plugins retain the quirk fallback. The pacman hook also
rechecks when the ALSA plugin is upgraded, including downgrades without support.
Use `--all-kernels --force` to override the check; explicit single-kernel installs
remain available. This check does not require a plugged-in dongle or running audio
session. Native switching still needs the HID driver to expose `wireless_status`.
To retry a failed hook, run `sudo barracuda-snd-usb-audio-quirk --all-kernels`.
The package already provides the profile set described below. Removing it also
removes the quirk builds created by the hook. Installation never reloads modules
or restarts audio; reboot to activate the new module.

With a manual checkout installation, rerun the installer after a kernel update.
If headers are missing or the build fails, the new kernel uses the official module
and automatic switching may not work. There is no application-level routing fallback.
The upstream stable `sound/usb` is used, so distribution changes to it (for
example in CachyOS kernels) are not included.

The installer also installs an ALSA card profile set for the dongle
(`packaging/razer-barracuda.conf`, selected by a udev rule). PipeWire's default
set gives the card S/PDIF and AC3 profiles, which play the same stereo stream
but have no jack-aware port, and a microphone port bound to no jack because the
stock headset-mic path expects a differently named mixer element. The
Barracuda set offers only the analog profiles and one microphone port that
follows the `Headset Mic Jack`, so both the output and the microphone become
unavailable while the headset is off. It applies after the reboot.

Select the Barracuda once as your output and input. WirePlumber falls back to
other devices while the headset is off and returns to them when it reconnects.
Earlier versions used a WirePlumber rule (`51-barracuda-analog-only.conf`) for
the profiles; remove it from `~/.config/wireplumber/wireplumber.conf.d/`, since
it overrides the profile set.

## When PipeWire handles wireless_status

The DKMS driver sets the standard USB `wireless_status` attribute.
PipeWire's upstream commit `03f894b` ("alsa-udev: Add wireless device status
monitoring", March 2026, not in the 1.6 series) hides a USB card while its
dongle reports `disconnected`. With such a PipeWire, WirePlumber falls back
and returns without the snd-usb-audio quirk or the profile set.
The installer detects this capability in PipeWire's ALSA plugin.

Check whether the installed PipeWire supports it:

```bash
grep -c wireless_status /usr/lib/spa-0.2/alsa/libspa-alsa.so
```

Once it does and switching works with the headset off and on, the quirk and
the profile set can be removed:

The automatic check leaves previously installed quirk builds in place. For builds
managed by the Arch hook, remove them with
`sudo barracuda-snd-usb-audio-quirk --all-kernels --remove` and reboot. The ALSA
profile files remain owned by the package. For a manual checkout installation:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove   # then reboot
```
