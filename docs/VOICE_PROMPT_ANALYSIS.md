# Headset voice-prompt analysis

This completes the documentation of the retained offline voice-prompt work.
It uses the seven AD language images from the [published headset update](HEADSET_FIRMWARE_ANALYSIS.md)
and the existing [installed flash backup](LIVE_ROM_ANALYSIS.md). No device
commands or firmware installation were performed during this analysis.
Extracted clips, decoded audio, vendor images and research tools remain ignored
under `private/voice-extraction/`; they are not distributed with this project.

## Extraction and image identity

The parser follows the vendor SDK's `AudioDataReader` and media-file-system
structures. Bounds checks and source-slice comparisons cover every extracted
clip. The eight sources contain 175 nonempty clips and 10,221 audio frames;
Chinese has 21 clips and each other source has 22.

The AD container uses an `AWDC` header and sub-blocks for events, tones,
numbers, audio and language codes. Header and body checksums are the low
16 bits of CRC-32/MPEG-2. Rebuilding with the SDK writer's clip deduplication,
four-byte `ff` alignment and length/checksum rules reproduces all eight input
images byte for byte. This verifies serialization of these inputs, rather than
device acceptance of a modified image.

The installed image has the same body and clips as `AD_EN`; its customer
version (`0x01070000`) and header CRC differ. Language ID is byte 0 of
`customer_version`: English 0, Chinese 1, French 2, German 3, Japanese 4,
Korean 5 and Spanish 6. Embedded language-code blocks contain en/zh/en in
every package and cannot identify the actual language.

Prompt event names come from the exact `CUST_2_2_74_0_17_0.xml` schema described
in [parameter analysis](DSP_PARAMETER_ANALYSIS.md). Voice-prompt event IDs are
a separate namespace from MMI commands: Gaming prompts use `14/15`, while
Gaming MMI commands use `84/85`. Generic `USER2_10/11` slots occur next to
Bluetooth/dongle audio-mode MMI call sites; this does not assign a spoken label
to every generic or unreferenced clip. Spanish reuses the English clips for
those two slots. All language images share the volume-limit beeps.

## Recovered codec and validation

Each native clip has a six-byte header followed by 60-byte frames. The SDK's
byte permutation gives header words `0000`, `0005` and the frame-byte count.
Its sample-rate marker is zero for every clip, selecting 16 kHz. Frame data
uses MSB-first bits packed into little-endian 24-bit native words.

The recovered codec is a G.722.1 variant: 24 kbit/s, 16 kHz mono, 20 ms per
frame, with 16 MLT regions (320 coefficients, 0–8 kHz) instead of the standard
14 regions. It retains the 16 kHz categorization parameters: four control bits
and 16 possibilities. Standard G.722.1/Siren decoding did not fit these clips.

Retained offline checks establish:

- Both patched float and fixed-point libg7221 decoders report zero frame
  errors across all 10,221 frames; the standard 14-region decoder reports
  7,558 errors.
- The vendor silence frame matches both patched encoders exactly.
- Re-encoding and decoding all 175 clips gives zero frame errors and median
  SNR of 31.3 dB for float and 28.0 dB for fixed point. Lossy re-encoding does
  not reproduce every original frame byte for byte.
- Each codec pass introduces one frame (320 samples, 20 ms) of delay.

These are codec and file checks. The decoded WAVs have not been compared by
ear with the physical headset's prompts, and their playback level on the
headset has not been measured.

## Offline tooling and reproduction

Run from the checkout with the retained private inputs:

```sh
python private/voice-extraction/extract.py
sh private/voice-extraction/codec/build.sh
python private/voice-extraction/codec/decode.py
python -m unittest discover -s private/voice-extraction/tool -v
```

The codec build uses the retained `freeswitch/libg7221` revision `7d35574`
(LGPL-2.1) and the local 16-region patch. Decoding verifies native hashes and
header lengths, checks both decoders and writes a WAV manifest containing
frame counts, errors and output hashes. Image verification and reconstruction
scripts run from `private/voice-extraction/image/`. These commands require
private research inputs; they are not available from a public checkout alone.

Documentation verification passed all 23 offline tool tests and confirmed
byte-for-byte reconstruction of all eight images. The retained WAV manifest
also confirms the 175-clip, 10,221-frame totals and zero errors in both decoders.

`tool/vptool.py` provides file-only `info`, `export`, `installed` and `replace`
operations. Installed-image extraction follows the flash's WIXP `AUDIO_DATA`
entry rather than selecting a staged image by signature. Replacement writes a
new copy, checks clip/event targets and shared references, and refuses input
aliases or unintended overwrites. It re-parses the result to verify checksums,
layout and clip data. Unknown or non-reproducible layouts are refused.

Replacement matches the original active audio level by default, checks decoded
peaks with both decoders and appends a silent frame to flush codec delay.
The 16-bit clip header limits frame data to 65,520 bytes (21.84 seconds,
including the flush frame); input duration is limited to 21.82 seconds.
Lengths beyond the longest stock prompt, 2.58 seconds, have not been tested on
hardware. The current flash layout reserves 114,688 bytes at `0x7a000` for
`AUDIO_DATA`, ending at `0x96000`; this is specific to the captured layout.
DSP playback limits remain unresolved.

Producing a valid file does not establish a supported prompt or language
installation procedure. Installing it would write firmware/audio data and is
outside the application's command set. The pristine backup and source images
remain unchanged; no restoration or modified-prompt playback was validated.
