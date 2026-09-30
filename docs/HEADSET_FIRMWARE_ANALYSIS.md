# Barracuda X headset firmware analysis

This is a file-only analysis of the official T3BT update selected by Razer Audio
for `mabel_t3_black`, device manager `mabel_t3` (Barracuda X). No firmware was
installed and no device commands were sent during this investigation. This
headset image is distinct from the previously analyzed T3 dongle image.

The later [installed headset ROM analysis](LIVE_ROM_ANALYSIS.md) recovers the
missing MCU routines and EX9 table from an authorized backup. It supersedes
the downstream Gaming and sidetone gaps described below, while keeping the
downloaded and installed image addresses separate.

## Retrieval and identity

The APK's production cloud configuration and device lookup lead to this chain:

1. [Production device whitelist](https://audioapp-assets.razerzone.com/Audio/android/prod/whitelist.json).
2. [Barracuda X Black descriptor](https://audioapp-assets.razerzone.com/Audio/android/prod/devices/mabel_t3_black.json),
   whose firmware field points to the T3BT manifest.
3. [Firmware manifest](https://mobileapp-assets.razerzone.com/iOS/Mabel/T3BT/firmware_update.json),
   advertising `01.06.00.00` and “Minor bug fixes”. The Android descriptor points
   to this iOS-named directory; this is not a guessed alternative package.
4. [Firmware ZIP](https://mobileapp-assets.razerzone.com/iOS/Mabel/T3BT/01.06.00.00.zip).

ZIP SHA-256:
`f62b026a0c55a5b721505864c0a112615b813d1cf171578574bf4a4d5061f9ed`.
`MC.img` SHA-256:
`f009d7a6b7da7bade4dcaaecfdec0c16a30607002a4171b3369f38e25659bdf2`.
These hashes identify the analyzed download; they do not independently verify a
vendor signature or establish the revision installed on the physical headset.

All downloaded files, URL provenance, hashes, extraction script and disassembly
remain ignored under `private/headset-firmware-analysis/`.

| File | Bytes | Evidence |
| --- | ---: | --- |
| `Version.bin` | 84 | Package version and component tags; initial version bytes `01 06 00 00` |
| `MC.img` | 335184 | MCU boot and Andes NDS32 patch/application code |
| `DC.img` | 142900 | DSP container; retained build string `PRU279C_DSP_202111251739_DONGLE_HS` |
| `D2.img` | 60312 | Additional component; retained `PRU279C_HWA_2.2.1.1.2.1_202103221441` string |
| `DP.img` | 6744 | Data container tagged `DP`; precise internal schema unresolved |
| `CT.img` | 2900 | Data container tagged `CT`; precise internal schema unresolved |
| `AD_EN/CH/FR/DE/JP/KO/ES.img` | 63676–95896 | Separate voice/audio data images; Spanish is included |

The seven AD component versions in `Version.bin` correspond to English,
Chinese, French, German, Japanese, Korean and Spanish.

## Code mapping and limits

`MC.img` has two `PXAT` headers:

| Header offset | Label | Load address | Code offset | Code bytes |
| --- | --- | --- | --- | ---: |
| `0x0000` | `NORMAL` | `0x20010000` | `0x0070` | 16272 |
| `0x4000` | `patch` | `0x1ffb0000` | `0x4060` | 318704 |

The second code range is extracted using the fixed 48-byte header plus its
declared 48-byte extension. Its runtime mapping is:
`address = MC.img offset - 0x4060 + 0x1ffb0000`.

The entry jump, internal call targets and dispatch tables support this mapping.
The startup at `0x1ffb309e` initializes GP to `0x2000deb8` and ITB to
`0x1ff0bb54`. That EX9 instruction table and substantial ROM routines are absent
from the update. Some radare2 negative jumps include an extra high digit;
32-bit targets must be corrected before tracing calls. Linear listings also
include strings and tables, which must not be interpreted as executed code.

Reproduction after downloading and extracting the ZIP:

```sh
r2 -q -a nds32 -b 32 -m 0x1ffb0000 -e scr.color=0 \
  -c 'pD 0x4dcf0; q' private/headset-firmware-analysis/mcu-code.bin \
  > private/headset-firmware-analysis/mcu-disassembly.txt
python private/headset-firmware-analysis/analyze.py
```

The retained script checks image identity, header bounds and extraction size,
and writes an inventory and focused evidence listings. It opens no device.

## Application command dispatcher

The dispatcher at `0x1ffb716c` loads the command ID from request byte 0,
prepares a response with that ID and status byte `01`, and dispatches to the
following branches. References at `0x1ffb3ca4` and `0x1ffb4cf2` call it from
separate receiving paths. A complete transport trace has not been established;
existing USB EQ observations independently establish that particular route.

Names are cross-checked against the exact T3 Android providers documented in
[Android analysis](ANDROID_ANALYSIS.md), not inferred from numeric IDs alone.

| Function | GET / SET | Handler addresses | Statically established behavior |
| --- | --- | --- | --- |
| EQ preset | `13` / `93` | `0x1ffb75a4` / `0x1ffb784c` | Converts internal presets 1/2/3 to app IDs 7/8/9 and inversely on SET; changed selection reaches the EQ application and configuration-write paths |
| Gaming | `14` / `94` | `0x1ffb75e6` / `0x1ffb7394` | GET reads GP+31708; SET consumes request byte 3 and calls `0x1ffb5542` |
| Custom EQ | `15` / `95` | `0x1ffb7238` / `0x1ffb794a` | GET returns ten bytes; SET requires length byte 10, copies ten values and reaches EQ recalculation |
| Do Not Disturb | `27` / `a7` | `0x1ffb76b6` / `0x1ffb79a4` | GET and SET share GP+31771; SET saves configuration and invokes a conditional Bluetooth-related path at `0x1ffb5858` |
| Auto standby | `2c` / `ac` | `0x1ffb776a` / `0x1ffb7b0a` | GET reads GP+31854; SET stores byte 3, schedules further processing and calls the configuration writer, with state-dependent behavior |
| Quick Connect | `2d` / `ad` | `0x1ffb7776` / `0x1ffb7b72` | GET constructs a variable device list; SET consumes six address bytes, reverses their order internally, and conditionally schedules the connection action |

The response epilogue at `0x1ffb7bf0` sends the constructed response. The
unsupported-command path at `0x1ffb7be6` emits one result byte `01`; successful
setter branches normally use result `00`. Quick Connect can emit result `ff`:
its SET checks `(GP+31856 & 0xc0)` and an internal mode at GP+26696 before
scheduling the operation. The individual flag meanings are not established.
This is not dongle pairing and does not justify USB resets.

An accepted command response alone does not establish that DSP/radio work has
finished. The Gaming setter can acknowledge before its queued MMI effect is
observable; immediate reversal can therefore make a listening trial inconclusive.

## Gaming: native SET and MMI converge

The helper at `0x1ffb5542` maps a nonzero argument to event `0x84` and zero to
`0x85`, then calls `0x1ffb24d8`. That stub jumps to `0x1ffe924a`, which forwards
the event through `0x1ffb20a8` into the downstream event path. Thus the Android
Gaming setter uses the same named MMI events as the SDK command previously
probed over USB.

This strengthens the earlier accepted-format `84/85` responses: Gaming is not
merely a generic SDK enum unused by this headset application. It does not prove
a latency reduction on 2.4 GHz, disclose the latency in milliseconds, or recover
the final radio handler. Those effects depend on downstream code and operating
mode. A latency benchmark would still be needed for a quantitative claim.

## Custom EQ: ten bytes and neutral offset

`0x1ffb4db2` returns ten stored bytes. `0x1ffb4f80` copies ten incoming bytes,
then loops over all bands and subtracts `5` before storing internal signed band
values. The default-initialization path at `0x1ffb4e02` fills these values with
`05`; the load path also subtracts five.

This establishes a neutral raw value of `05`, with `04` and `06` becoming
internal -1 and +1. It does not alone establish the physical dB step or justify
arbitrary byte values: the remaining coefficient path includes unresolved EX9
and ROM routines. Android's ten band labels remain the source for center
frequencies. The preset and custom-band routines call configuration-write
wrappers at `0x1ffb2500`; users should not assume these are temporary RAM-only
changes. Physical persistence across power cycles has not been tested.

## Sidetone: handlers exist, final effect remains unresolved

The headset family-6 dispatch region contains explicit `70`, `71`, `72` cases:

| Command | Branch | Helper | Evidence |
| --- | --- | --- | --- |
| Enable `70` | `0x1ffcf490` | `0x1ffcf136` | Consumes one byte, calls `0x1ffe9584`, then returns an accepted response |
| Gain `71` | `0x1ffcf598` | `0x1ffcf162` | Consumes one byte and calls `0x1ffe9596` |
| Read `72` | `0x1ffcf5a2` | `0x1ffcf18e` | Reads selector 11 through another helper and serializes one byte |

The enable and gain wrappers pass selectors 102/103 respectively to
`0x1ffa6706`, which is outside this image. Their return path does not report a
verified audible result from that missing routine. This explains why finding a
handler and receiving acknowledgment cannot establish working sidetone. Neither
its gain range nor whether it operates on the 2.4 GHz microphone path is resolved.
The prior user observation of no audible sidetone remains valid.

## Consequences for pending tests

Static evidence removes the need to probe merely whether the app's six controls
have handlers in this published headset build, whether Gaming uses `84/85`,
whether custom EQ has ten bands with neutral `05`, and whether changing voice
language involves a separate AD image. Language changes remain firmware/data
installation and outside project scope.

It cannot replace checking USB availability of the remaining controls on the
installed revision, physical microphone effects, latency, or sidetone. Mic mute,
tone toggles, microphone noise reduction and other generic SDK events are not
declared usable solely from this partial image. No speculative controls have
been added to the driver, CLI or widget.
