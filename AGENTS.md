# Agent guide

## Scope and language

This provides a pairing CLI, kernel driver and Plasma output widget for
Barracuda X (2022), USB `1532:0552`. WirePlumber handles audio routing. Documentation and code comments are English.
The CLI supports English (default) and Spanish via `--language es`.
The plasmoid follows the desktop locale with English fallback. Respond to the
user in their conversation language. Read README.md and docs/PROTOCOL.md first.

## Layout

- plasmoid/: read-only Plasma 6 default-output widget and icon selection.
  Detailed headset/speaker artwork is loaded from the installed KDE Breeze theme.
- barracuda_pair/pairing.py: pairing sequence, `barracuda-pair` CLI and hidraw lookup.
- barracuda_pair/i18n.py: explicit UI translations.
- tests/: hardware-independent unittest suite.
- scripts/install.py and packaging/: CLI user installation, udev rules and
  the ALSA card profile set for the jack quirk.
- kernel/hid-razer-barracuda/: the DKMS driver and its KUnit tests, exactly as in
  the upstream series, plus dkms.conf, the DKMS Makefile and an `hid-ids.h`
  used only by the DKMS build.
- upstream/: the `git format-patch` series for the HID and sound trees, and the
  `.kunitconfig` used to test it (docs/UPSTREAM.md).
- kernel/snd-usb-audio/: the GPL-2.0 jack patch and the Makefile for the
  downloaded `sound/usb` tree.
- scripts/install_dkms.py, scripts/install_snd_usb_audio_quirk.py: DKMS installers.
- packaging/arch/: the split PKGBUILD (`barracuda-pair`,
  `hid-razer-barracuda-dkms`, `plasma6-applets-barracuda`),
  `build.sh` for local builds and `build-in-container.sh`, which the release
  workflow runs on `v*` tags (docs/RELEASING.md). tests/test_packaging.py keeps
  `pkgver` equal to every other version field.

## Protocol invariants

The driver sends the hardware-validated E3 connection query on binding
USB 1532:0552: `01 80 06 50 41 0e SS 01 e3`, padded to 64 bytes. Limit to three
attempts two seconds apart, stopping after a valid status. Failed queries leave the link unknown. The driver never pairs. Pairing runs
only on explicit user request through `barracuda-pair` in
barracuda_pair/pairing.py, which
replays the captured vendor sequence documented in docs/PROTOCOL.md. The DKMS
driver may additionally, on each confirmed link, cable change,
every 360 s while linked, query battery, cable and voltage (E6, E0, `E1 01`, family-8
GET `0x21` and `0x2a`, family-6 `0x31`, then always `E1 00` and E0
verification) as documented in docs/DKMS.md. Never introduce firmware (OTA write, erase, reboot) or other
unverified output commands.
USB presence does not confirm connectivity.
Validate transition bytes 0..4 (`01 80 0E 50 49`) and 11..15 (`04 00 20 02 01`)
before interpreting byte 16 as 00/01. For E3 validate bytes 0..5
(`01 80 0C 50 49 0E`) and 11..13 (`02 00 E3`), then read byte 14 as 00/01.
E6, acknowledgments, malformed and unknown values are not link evidence.
Keep unknown, disconnected and missing-adapter states distinct. In the driver,
an unknown link neither creates nor removes the battery; never register the
battery or notify UPower from the HID event path, and never send a query from a
power-supply property read. Data responses carry a device counter, not the query
sequence; match a route query's acknowledgment (which echoes the sequence) before
accepting its data response; family-8 GET replies have no acknowledgment. A silent dongle
is not a disconnected headset. Reads must be interruptible and workers joined.

## Audio invariants

Leave routing to WirePlumber. The plasmoid reads KDE's default sink and never
changes audio state. Match device properties rather than fixed sink indices.
Default-output selection and device icons are not physical link evidence.
Do not change microphone, volume or card profile unless explicitly in scope.
Preserve XDG support; do not introduce a background Python monitor.

## snd-usb-audio patch

Do not store downloaded kernel sources in the repository. The installer must
refuse to build unless every patch applies cleanly, and must restrict the DKMS
package to the exact kernel release.

## Kernel submission rules

Write the driver as in-tree code: no `LINUX_VERSION_CODE`, no module
parameters, no `MODULE_VERSION`, SPDX `GPL-2.0-only OR MIT`, kernel coding
style. Keep dates and development history out of code comments. Change the
driver through the series in upstream/ (docs/UPSTREAM.md) and keep patch 1
building and passing its tests without patch 2. Never add `Signed-off-by`
to a patch: only the user can certify the DCO. Mark AI assistance with
`Assisted-by: LLM [tools]` as Documentation/process/coding-assistants.rst
describes, and never send patches by email.

## Validation

Run `uv run python -m unittest discover -s tests -v` for functional changes.
Run `uv run python -m compileall -q barracuda_pair scripts` for syntax validation.
Use fake audio commands and offscreen Qt; tests must not mutate real audio.
Cover link frames, unknown states, missing outputs and default-device changes
when affected. Documentation-only edits do not need audio tests.
After C changes, build the module with `make -C kernel/hid-razer-barracuda W=1`,
and run KUnit, `W=1 C=2` and `checkpatch.pl --strict` in a kernel tree
(docs/UPSTREAM.md). Keep `PACKAGE_VERSION` in dkms.conf and `VERSION` in
scripts/install_dkms.py in sync. Installer tests use temporary directories and
mocked commands; they must not change real devices.
Test installation in temporary HOME/XDG directories. Inspect built archives for
private files. Distinguish unit tests, compiled builds, live routing and physical-device checks.

## Distribution and local deployment

Never force-add ignored files. Keep build artifacts, captures and vendor-derived
files out of the tree. Do not bundle theme icons: the plasmoid uses the
`breeze-icons` dependency and its detailed `audio-headset.svg`/`audio-speakers.svg`.
Keep all public docs in English, and ensure default English and Spanish strings
are tested. Do not introduce personal absolute paths into tracked files.

Repository edits do not update an installed copy automatically. The user installer
copies only the pairing modules and creates the CLI launcher. It does not create
desktop/autostart entries. Installing the plasmoid does not modify panel layouts.
Plasma may cache QML across widget removal/re-addition. An authorized shell
restart can refresh it without restarting audio; inspect logs for binding errors.
A legacy local barracuda-status.service may exist as a transient user service;
it is not a permanent unit supplied by this project. Avoid duplicate instances.
Do not turn session autostart into a permanent service as a side effect.
Do not reload the kernel module on the user's machine without authorization.
Group authorized runtime updates into one restart: restarting clears observed HID
state until a valid query response or transition arrives. A query timeout must
not be reported as a disconnection. Publication preparation alone
does not require restarting the user's audio session.
