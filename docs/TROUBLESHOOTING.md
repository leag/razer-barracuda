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

## The icon is still a speaker

KDE's stock volume widget uses a volume icon. Add this project's **Current Audio
Output** widget separately; it does not patch KDE's widget. Hover verifies which
default device it is showing. Per-application output overrides can differ.

If the widget fails to load, verify `plasma-pa` is installed and inspect
`journalctl --user -b` for QML import errors. The private KDE API is tested on
Plasma 6.7.4. Remove/re-add the widget after a QML upgrade. User-installed copies
under the XDG data directory can shadow the system package.

## Old tray installations

Stop any former tray instance and disable its session autostart entry.
A manually created `barracuda-status.service` can be stopped with
`systemctl --user stop barracuda-status.service`; this project supplies no
permanent service. Remove the old pacman package before installing the new CLI.
No migration is performed automatically.

For checkout installs, review old `~/.local/bin/barracuda-status`, the
`barracuda-status` directory under XDG data, and the old
`org.razer.BarracudaStatus.desktop` application/autostart entries.
Remove only copies you installed. Old routing state is no longer read.

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
