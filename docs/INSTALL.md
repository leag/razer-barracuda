# Installation

## Requirements

- Linux, Python 3.10+, uv and a system tray (tested on KDE Plasma).
- PyQt6 is installed into the project environment by uv.
- PipeWire with PulseAudio compatibility, or PulseAudio, and `pactl`.
- Read/write access to the dongle's HID device (read-only access supports passive monitoring).

On Arch/CachyOS, install the dependencies (the package also declares
`pipewire-alsa` for the PipeWire ALSA integration):

```bash
sudo pacman -S python uv libpulse pipewire-alsa
```

## Install

### Arch Linux and CachyOS

Each [GitHub release](https://github.com/leag/razer-barracuda/releases) carries
two packages built in a clean Arch container. Download and install them:

```bash
sudo pacman -S --needed dkms linux-headers   # or the headers package for your kernel
sudo pacman -U barracuda-status-*.pkg.tar.zst hid-razer-barracuda-dkms-*.pkg.tar.zst
```

To build the same packages from a checkout instead:

```bash
sudo pacman -S --needed python-build python-installer pacman-contrib
packaging/arch/build.sh
sudo pacman -U packaging/arch/barracuda-status-*.pkg.tar.zst packaging/arch/hid-razer-barracuda-dkms-*.pkg.tar.zst
```

`barracuda-status` installs the tray app, `barracuda-pair`, the desktop entry
and the hidraw udev rule. `hid-razer-barracuda-dkms` installs the driver for
every installed kernel through DKMS, the battery udev rule, the dongle's ALSA
card profile set, and automatically builds the [jack detection](JACK_DETECTION.md)
module for each installed kernel with headers. A pacman hook repeats this after
kernel header, PipeWire ALSA plugin or driver package upgrades. It skips the build
when the installed PipeWire ALSA plugin supports USB `wireless_status`, including
distribution backports. Otherwise it downloads matching upstream sources,
so internet access is required during installation. Reboot to load the module.
If a download or build fails, pacman reports the hook failure; retry with
`sudo barracuda-snd-usb-audio-quirk --all-kernels`.
Removing the driver package removes the quirk builds managed by its hook. Add
Barracuda Status to your session's autostart from the desktop settings.
Reconnect the dongle once after installing the udev rules. Upgrading is
`pacman -U` with the newer packages; removing is `pacman -R barracuda-status
hid-razer-barracuda-dkms`.

Installing the package does not restart the user's PipeWire session. After
installing or upgrading, log out and back in, or restart the user services
with `systemctl --user restart pipewire pipewire-pulse wireplumber` when no
audio playback is active. Then reconnect the dongle and select its output once.

### From a checkout without packages (other distributions)

```bash
uv sync --locked
uv run python scripts/install.py --autostart
sudo install -Dm644 packaging/99-razer-barracuda.rules /etc/udev/rules.d/99-razer-barracuda.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Reconnect the dongle if permission errors persist. Run as your desktop user,
not root. Launch from your application menu or:

```bash
~/.local/bin/barracuda-status
```

Keep the checkout and its `.venv` available: the installed launcher uses that
virtual environment. Reinstall after moving the checkout.

The installer copies the package to your user data directory and creates a launcher
in `~/.local/bin`. It uses the Python interpreter that ran the installer, so keep
that interpreter available. It does not restart an existing instance.
`--autostart` creates a KDE/session autostart entry, not a permanent systemd unit.
Run only one instance to avoid competing audio changes. Stop an older instance
before launching an updated copy.

To install with Spanish as the launch language:

```bash
uv run python scripts/install.py --autostart --language es
```

For development without installation:

```bash
uv run barracuda-status                 # English
uv run barracuda-status --language es   # Español
```

Build release archives with `uv build`. To install the built wheel in a separate,
persistent environment, use `uv tool install dist/barracuda_status-*-py3-none-any.whl`.
This creates the CLI only; HID permissions and desktop integration remain separate.
Do not mix install methods unless you manage their paths.
