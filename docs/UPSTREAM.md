# Submitting the driver to the kernel

The driver has not been submitted yet. `upstream/` holds the series,
generated with `git format-patch` against the HID tree's `for-next` branch
(`base-commit` in each patch):

| Path | Content | To |
| --- | --- | --- |
| `upstream/hid/0000-cover-letter.patch` | Cover letter | linux-input |
| `upstream/hid/0001-*.patch` | The driver: link query, passive battery and cable reports, `wireless_status`, jack switches, KUnit tests | linux-input |
| `upstream/hid/0002-*.patch` | Battery, cable and voltage queries over the remote diagnostic route | linux-input |
| `upstream/alsa/0001-*.patch` | snd-usb-audio jack quirk | linux-sound, once the HID driver is accepted |

`scripts/get_maintainer.pl` lists Jiri Kosina and Benjamin Tissoires for the
HID patches, and Jaroslav Kysela and Takashi Iwai for the ALSA patch.

The sources in `kernel/hid-razer-barracuda/` are the driver as it stands
after patch 2. The DKMS build is the same file; the only DKMS-specific file is
a small `hid-ids.h` with the two IDs, because kernel header packages do not
ship `drivers/hid/hid-ids.h`. `tests/test_upstream.py` fails if the series and
the sources differ, or if a patch already has a `Signed-off-by`.

## Working on the series

```bash
git clone --depth 1 -b for-next \
  https://git.kernel.org/pub/scm/linux/kernel/git/hid/hid.git linux
cd linux
git am /path/to/this/repo/upstream/hid/000[12]-*.patch
```

Make changes as fixups to the patch they belong to, then regenerate the
series and copy the sources back:

```bash
git rebase -i --autosquash HEAD~2
git format-patch --cover-letter --base=HEAD~2 -o /path/to/this/repo/upstream/hid HEAD~2
cp drivers/hid/hid-razer-barracuda*.c /path/to/this/repo/kernel/hid-razer-barracuda/
```

`format-patch` writes a new cover letter template; keep the existing text.
Patch 1 must build and pass its own tests without patch 2.

## Checks

Run each of these after every change, and on each patch of the series:

```bash
# KUnit under QEMU with KASAN, UBSAN and lockdep (needs qemu-system-x86_64 and bc)
./tools/testing/kunit/kunit.py run --arch=x86_64 \
  --kunitconfig=/path/to/this/repo/upstream/.kunitconfig

# W=1 and sparse, built-in and as a module
make W=1 C=2 drivers/hid/hid-razer-barracuda.o

./scripts/checkpatch.pl --strict -g HEAD~2..HEAD
```

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
   `git rebase --signoff HEAD~2`. Keep the `Assisted-by` tags
   (`Documentation/process/coding-assistants.rst`).
5. **Send** with `git send-email`, to the maintainers and lists from
   `scripts/get_maintainer.pl`, in plain text.

After the HID driver is accepted, rebase the ALSA patch onto the sound tree
(`git://git.kernel.org/pub/scm/linux/kernel/git/tiwai/sound.git`, `for-next`),
add a `Link:` to the accepted HID series, sign it off and send it.
