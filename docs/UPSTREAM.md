# Submitting the driver to the kernel

The driver has not been submitted yet. `upstream/` holds the series,
generated with `git format-patch` against the HID tree's `for-next` branch
(`base-commit` in each patch):

| Path | Content | To |
| --- | --- | --- |
| `upstream/hid/0000-cover-letter.patch` | Cover letter | linux-input |
| `upstream/hid/0001-*.patch` | The driver: link query, passive battery and cable reports, `wireless_status`, jack switches, KUnit tests | linux-input |
| `upstream/hid/0002-*.patch` | Battery, cable and voltage queries over the remote diagnostic route | linux-input |
| `upstream/hid/0003-*.patch` | Explicit serialized headset power-off and sysfs ABI | linux-input |
| `upstream/hid/0004-*.patch` | Explicit bounded native headset settings mailbox | linux-input |
| `upstream/alsa/0001-*.patch` | snd-usb-audio jack quirk | linux-sound, once the HID driver is accepted |

The pairing CLI and Plasma widget are userspace components, not part of this
kernel submission. Module/package renames or widget artwork changes do not by
themselves change the HID/ALSA patch series or its validation history.

`scripts/get_maintainer.pl` lists Jiri Kosina and Benjamin Tissoires for the
HID patches, and Jaroslav Kysela and Takashi Iwai for the ALSA patch.

The sources in `kernel/hid-razer-barracuda/` are the driver as it stands
after patch 4. The DKMS build is the same file; the only DKMS-specific file is
a small `hid-ids.h` with the two IDs, because kernel header packages do not
ship `drivers/hid/hid-ids.h`. `tests/test_upstream.py` fails if the series and
the sources differ, or if a patch already has a `Signed-off-by`.

## Working on the series

```bash
git clone --depth 1 -b for-next \
  https://git.kernel.org/pub/scm/linux/kernel/git/hid/hid.git linux
cd linux
git am /path/to/this/repo/upstream/hid/000[1234]-*.patch
```

Make changes as fixups to the patch they belong to, then regenerate the
series and copy the sources back:

```bash
git rebase -i --autosquash HEAD~4
git format-patch --cover-letter --base=HEAD~4 -o /path/to/this/repo/upstream/hid HEAD~4
cp drivers/hid/hid-razer-barracuda*.c /path/to/this/repo/kernel/hid-razer-barracuda/
```

`format-patch` writes a new cover letter template; keep the existing text.
Patches 3 and 4 use the battery route mutex added by patch 2. Patch 1 must build and pass its own tests without patch 2.

## Checks

Run each of these after every change, and on each patch of the series:

```bash
# KUnit under QEMU with KASAN, UBSAN and lockdep (needs qemu-system-x86_64 and bc)
./tools/testing/kunit/kunit.py run --arch=x86_64 \
  --kunitconfig=/path/to/this/repo/upstream/.kunitconfig

# W=1 and sparse, built-in and as a module
make W=1 C=2 drivers/hid/hid-razer-barracuda.o

./scripts/checkpatch.pl --strict -g HEAD~4..HEAD
```

On 2026-09-25, against `for-next` at `145c2b2e9`: KUnit passed 13 tests after
patch 1 and 18 after patch 2 under QEMU with KASAN and UBSAN, checkpatch
reported only the missing `Signed-off-by`, and the DKMS build against
7.2.7-1-cachyos with Clang was clean at `W=1`. Sparse was not rerun.

On 2026-09-24, against `for-next` at `d72f75f1d` (v7.3-rc4): KUnit passed
13 tests after patch 1 and 18 after patch 2, with no KASAN, UBSAN or lockdep
report. The W=1 and sparse builds were clean, built-in and as a module, and so
was the DKMS build against 7.2.6-1-cachyos with Clang. The only checkpatch
error was the missing `Signed-off-by`.

## Before sending

1. **Test this version on hardware.** The tests above do not cover the
   device. Install it with `sudo python3 scripts/install_dkms.py --activate`
   and check headset power cycles, cable changes, battery and voltage in
   `/sys/class/power_supply/razer-barracuda-*/uevent`, UPower, and
   suspend/resume. Then update the "Hardware" paragraph of the cover letter,
   which currently describes the out-of-tree predecessor.
2. **Review every line.** Per `Documentation/process/generated-content.rst`
   you must understand the whole submission and be able to answer review
   comments. Adjust the "Tool use" paragraph of the cover letter so that it
   describes how the code was written.
3. **Rebase** onto the current `for-next` and rerun the checks.
4. **Sign off.** Only you can certify the Developer Certificate of Origin:
   `git rebase --signoff HEAD~4`. Keep the `Assisted-by` tags
   (`Documentation/process/coding-assistants.rst`).
5. **Send** with `git send-email`, to the maintainers and lists from
   `scripts/get_maintainer.pl`, in plain text.

After the HID driver is accepted, rebase the ALSA patch onto the sound tree
(`git://git.kernel.org/pub/scm/linux/kernel/git/tiwai/sound.git`, `for-next`),
add a `Link:` to the accepted HID series, sign it off and send it.

The explicit power-off addition passed the isolated Python/QML suite (81 tests),
KUnit on patch 1 (13), patch 2 (18) and the full series (21), with KASAN, UBSAN
and lockdep. W=1/C=2 checks passed for each patch and the DKMS module. Strict
checkpatch reported only the intentionally missing user DCO sign-off. These
checks do not replace physical validation of the new sysfs action.

The native settings addition passes the isolated Python/QML suite (90 tests),
the full KUnit run (23 tests including KUnit framework tests), the DKMS W=1
build and the built-in W=1/C=2 check. Strict checkpatch reports only the missing
user DCO sign-off. The new mailbox and the remaining setters still need
physical validation; the raw-HID Default/Game EQ comparison was audible.

## Current driver hardening validation

On 2026-10-05, against `145c2b2e9`, the regenerated series passed KUnit
under QEMU x86_64 with KASAN, UBSAN and lockdep: 13 tests after patch 1,
21 after patch 2, 24 after patch 3 and 26 after patch 4 (including framework
tests). Every patch prefix passed built-in and module `W=1 C=2` object builds.
The DKMS source built at `W=1` against `7.2.9-1-cachyos`. Strict checkpatch
reported only the intentionally missing user DCO sign-offs. The Python/QML
suite passed 105 tests, and Python syntax compilation passed.

The changes serialize startup E3 with other driver transactions, retain bounded
startup retries after output failure, reject new normal requests during stopping,
and require verified local mode before clearing a route-restoration failure.
Fake transport tests exercise the real reply matcher and cleanup paths. Pairing
now ignores route data received before its matching ACK, but raw pairing still
has no kernel arbitration. These checks do not establish concurrent pairing
safety or physical-device behavior. These isolated checks preceded deployment.

The same source was subsequently installed through DKMS as local build
`0.5.1.local1` on `7.2.9-1-cachyos`, and the loaded module identity matched the
installed build. After the HID reload, native telemetry reported 76% and
4.020 V, with no driver errors observed in the recent kernel log. The user
reported that the new version appeared to work. The previous LTS installation
was retained. This confirms basic startup/telemetry recovery only; suspension,
all setters, power-off and concurrent pairing have not been physically validated.

The pairing ACK fix was also deployed as local Arch package `barracuda-pair
0.5.1-1.1`. All 17 pairing tests passed against the installed Python module
using a fake dongle, and its source matched the checkout. The installed passive
link helper reported a connected USB headset and 76% battery. This deployment
did not reload the driver or perform a physical pairing operation.
