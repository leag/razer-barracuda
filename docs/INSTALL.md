# Installation

## Packages on Arch Linux / CachyOS

The split package now produces:

- `barracuda-pair`: Python 3.10+ CLI and hidraw access rule; no Qt dependency.
- `hid-razer-barracuda-dkms`: driver, battery rules, ALSA profiles, WirePlumber
  headphones-icon rule and automatic jack-quirk installer.
- `plasma6-applets-barracuda`: Plasma 6 widget; requires `plasma-pa` and `breeze-icons`.

This layout starts with v0.4.0. Release builds fetch the matching GitHub tag, not
uncommitted checkout changes. See [releasing](RELEASING.md) before building
with `packaging/arch/build.sh`.
Download release assets from [GitHub releases](https://github.com/leag/razer-barracuda/releases).
Use a directory containing only the selected package versions when running the
wildcard installation command below. Checkout changes after a tag are not included
in that tag's packages; see [change history](CHANGELOG.md).

Install the resulting packages together with headers for your kernel:

```bash
sudo pacman -S --needed dkms linux-headers
sudo pacman -U barracuda-pair-*.pkg.tar.zst hid-razer-barracuda-dkms-*.pkg.tar.zst plasma6-applets-barracuda-*.pkg.tar.zst
```

The old `barracuda-status` package must be removed first; no automatic upgrade
migration is provided. Stop any old tray instance and remove its session autostart
entry. Retained user-installed copies are independent of pacman.

The driver package builds the jack quirk for installed kernels with headers unless
the installed PipeWire ALSA plugin supports USB `wireless_status`, including
backports. This needs internet access. If its hook fails, retry:

```bash
sudo barracuda-snd-usb-audio-quirk --all-kernels
```

Reboot to load the module. Installation does not reload modules or restart audio.
Reconnect the dongle after installing udev rules. Log in again for the WirePlumber
icon rule. Select the Barracuda output once; WirePlumber handles subsequent
availability changes. See [jack detection](JACK_DETECTION.md).

## Building Arch packages locally

From a clean checkout of the release you intend to build, install the build
tools and run the helper as your ordinary user:

```bash
sudo pacman -S --needed base-devel git uv python-build python-installer python-setuptools python-wheel dkms pacman-contrib namcap
packaging/arch/build.sh
namcap packaging/arch/PKGBUILD packaging/arch/*.pkg.tar.zst
```

Install the header package matching your kernel as well: `linux-headers` in the
example above is for Arch's standard `linux` kernel, not every CachyOS kernel.
Review build and package-check results before installing the three matching
archives with `pacman -U`. Do not mix older archives left in the output directory.

The helper clears the generated `dist/` directory, creates a Python source
archive, and refreshes PKGBUILD checksums. **The Arch package source is still the
GitHub tag configured in PKGBUILD**, not that local Python archive. This command
does not package uncommitted or post-tag changes; a local package-release number
alone does not change the source. Use the checkout installation instructions
below to try unreleased CLI/widget changes, and the
[release guide](RELEASING.md) for tagged/container builds.

## Pairing CLI from a checkout

No third-party Python runtime dependencies are needed:

```bash
python3 scripts/install.py
sudo install -Dm644 packaging/99-razer-barracuda.rules /etc/udev/rules.d/99-razer-barracuda.rules
sudo udevadm control --reload-rules
~/.local/bin/barracuda-pair --help
```

Reconnect the dongle. The user installer copies only the pairing modules under
`$XDG_DATA_HOME/barracuda-pair` (default `~/.local/share/barracuda-pair`) and
creates `~/.local/bin/barracuda-pair`. Keep its Python interpreter available.
Use `--language es` when installing to default to Spanish. No desktop entries,
autostart, audio configuration or running processes are changed.

Alternatively use `uv run barracuda-pair` from the checkout, or build a wheel
with `uv build` and install it with `uv tool install dist/barracuda_pair-*-py3-none-any.whl`.
HID permissions remain separate.

## Plasma widget from a checkout

Requires Plasma 6, `plasma-pa`, and Breeze icons installed under
`/usr/share/icons/breeze/devices/64/` (Arch package `breeze-icons`):

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

For an existing user installation use `--upgrade plasmoid` instead.
Add **Current Audio Output** from the panel's **Add Widgets** menu. Installing
does not alter your panel layout. Plasma can cache QML even after removing and
re-adding a widget; follow the [reload instructions](TROUBLESHOOTING.md#widget-update-not-visible)
after upgrading. Do not install both a user copy and the Arch widget package.

To preview without installing or adding it to the panel, run from the repository:

```bash
plasmawindowed "$PWD/plasmoid"
```

Close the preview when done. It does not need to run for the panel widget to work.

The widget uses KDE's private volume QML API, tested with Plasma 6.7.4. It may need
adjustment for future Plasma releases. It does not require the pairing CLI or
driver to show other sound devices; the driver is needed for Barracuda's native
wireless availability/battery integration.
The optional **Pair Barracuda…** action requires `barracuda-pair`
on the desktop session's `PATH`. The user CLI installer does not add its
`~/.local/bin` directory to `PATH`; add it to your session environment if needed.

## Optional audio controls

`python scripts/install.py --audio-controls` also installs `barracuda-audio` without
enabling effects or restarting audio. The Python wheel includes both CLIs.
See [audio effects](AUDIO_EFFECTS.md) for dependencies and persistent configuration.
