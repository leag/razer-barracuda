# Jack detection (experimental)

The DKMS driver reports the wireless link as `SW_HEADPHONE_INSERT` and
`SW_MICROPHONE_INSERT`. The official `snd-usb-audio` does not yet turn these into
ALSA jack controls for `1532:0552`; this needs a two-line quirk like the Sony
DualSense's. With such a module loaded, PipeWire marks the headset output
unavailable when the headset is off and switches outputs itself. The tray
detects this through the card's port availability group and stops changing the
default output, which would otherwise overwrite the output you configured.

To load such a module, install it as a DKMS package for the running kernel. The
installer downloads `sound/usb` for the matching upstream stable version (GPL-2.0,
not stored here), applies `kernel/snd-usb-audio/*.patch` only if it applies
cleanly, and restricts the package to that exact kernel release:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py          # then reboot
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove
```

With the Arch package, run `sudo barracuda-snd-usb-audio-quirk` instead; the
package already provides the profile set described below.

After a kernel update the package does not build, the official module loads,
and the tray routes outputs itself again. Rerun the installer for the new kernel.
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
and returns without the snd-usb-audio quirk or the profile set. The tray
detects this, from `wireless_status` in PipeWire's ALSA plugin and on the
dongle, and leaves output switching to PipeWire.

Check whether the installed PipeWire supports it:

```bash
grep -c wireless_status /usr/lib/spa-0.2/alsa/libspa-alsa.so
```

Once it does and switching works with the headset off and on, the quirk and
the profile set can be removed:

```bash
sudo python3 scripts/install_snd_usb_audio_quirk.py --remove   # then reboot
```

