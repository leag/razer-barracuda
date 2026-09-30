# Installed DSP and headset configuration parameters

This is an offline extension of [the installed ROM analysis](LIVE_ROM_ANALYSIS.md).
It uses the existing headset flash backup and exact vendor schemas. No device
commands, audio changes, firmware writes or driver reloads were performed.

## Schema recovery and validation

The recovered SDK's `DownloadDspParamHTTP` and `DownloadCustXMLHTTP` classes
provide these schema archive URLs:

- `http://219.87.28.104/MMIUpdate/MMI_DB_dsp.zip`
- `http://219.87.28.104/MMIUpdate/MMI_DB_cust.zip`

The archives were downloaded into ignored `private/parameter-analysis/`.
The SDK's `AesCrypto` and `Utils.unzipDecrypt` routines describe AES-CBC followed
by gzip decompression. The exact schemas are `DSP_PARAM_28.xml.enc` (table
version 40, hexadecimal `28`) and `CUST_2_2_74_0_17_0.xml.enc` (the six CT image
version bytes). These are version matches, not nearest-version fallbacks.

Both installed DP and CT payloads are byte-for-byte identical to the downloaded
update's DP and CT payloads. Their container headers differ. This does not make
the installed MCU identical to the update's MCU.

Reproduction, from the checkout with the existing private inputs:

```sh
python private/parameter-analysis/decode_schemas.py
python private/parameter-analysis/analyze_parameters.py
```

The second script performs no network access. It follows `AudioParams`' 24-bit
DSP word packing and `Cust_Struct.ItemGroup`'s byte-padded groups of up to 32
bits. All 2307 DSP fields fit exactly into 6360 payload bytes. Of 47 CT records,
43 have schema definitions and exactly matching lengths; four remain unmapped.
Decoded DSP fields and mapped CT groups reconstruct their original bytes,
retaining unrepresented padding. Bounds, nonoverlap and payload identity checks
are enforced. Full fields, EQ metadata, input hashes and focused results are
retained in `parameters.json` and `focused-parameters.json` in that private folder.

These are **stored configuration values**, not a capture of active DSP RAM.
An available SDK field is not proof that the product implements a runtime
control or that a feature is active in the current audio scenario.

## Sidetone: a four-bit stored gain

| Exact DSP field | Word | Bit | Width | Stored value |
| --- | ---: | ---: | ---: | ---: |
| `SideToneEna` | 13 | 2 | 1 | 0 |
| `SideToneGain` | 13 | 3 | 4 | 9 |

The exact table establishes a stored representation of 0..15 for sidetone
gain. It supplies neither a decibel scale nor the gain setter's runtime range.
The [MCU route](LIVE_ROM_ANALYSIS.md#sidetone-the-missing-rom-route-reaches-dsp-parameters)
passes enable/gain to DSP SET_PARAMETER selectors 102/103. Connecting selector
103 to this stored field, including any transformation or scenario selection,
requires DSP-side analysis. QUERY selector 11 remains unresolved.

The stored gain of 9 does not contradict a runtime GET `72` result of `00`:
these are different sources of information, and the MCU getter can serialize a
byte even after an unsuccessful internal query. It also does not explain the
negative listening test by itself. No gain setter was sent in this investigation.

## Gaming configuration and the dongle guard

| Stored CT field | Value |
| --- | ---: |
| `support_gaming_mode_23` | 1 |
| `gaming_mode_switch_lowlatency_only_23` | 1 |
| `gaming_mode_surround_en_23` | 0 |
| `gm_default_enable_13` | 0 |
| `store_gm_status_13` | 0 |
| `audio_buff_time_25` | 200 ms |
| `audio_buff_time_lowlatency_25` | 60 ms |
| `audio_buff_time_lowlatency_awsbc_25` | 40 ms |
| `audio_buff_time_lowlatency_aac_25` | 80 ms |
| `support_dongle_mode_12` | 1 |

These are configured buffer durations; they are not measured end-to-end
latencies, nor proof that every value is used on the USB dongle path.

The early guard in the common Gaming routine can now be partly named:

1. CT record 12 is loaded as 32 bytes at GP-27536 by the loader at
   `0x1ffa2714`; the patched reload at `0x1fffa8b8` uses the same mapping.
   The underlying record-copy routine is `0x1ffa2b20`.
2. `support_dongle_mode_12` occupies group byte 8, bit 21, which is byte 10,
   bit 5. That maps to GP-27526, bit 5.
3. The Gaming routine at `0x1ffd354a` loads that byte and tests bit 5. When
   set, it selects a 34-byte entry using GP+26716, then tests entry byte 19,
   bit 4. A set bit returns immediately, before changing the Gaming flag.

The decoder renders the short `bmski33` immediate as a register. Raw encodings
`96ee` and `96e6` instead select immediates 5 and 4. The instruction tests
`register & (1 << immediate)`, as confirmed by the primary
[GCC NDS32 AND instruction definition](https://gnu.googlesource.com/gcc/+/2b0e81d5cc2f7e1d773f6c502bd65b097f392675/gcc/config/nds32/nds32.md)
and [binutils operand definition](https://sources.debian.org/src/binutils-gold/2.44-2/opcodes/nds32-asm.c).

Thus there is a concrete conditional rejection path associated with dongle
support and a per-entry state. The entry bit's exact meaning and its value
during the failed transaction are not established. This supports investigating
a dongle-related restriction; it does not yet prove that Gaming is universally
read-only over USB or exclusive to Bluetooth. The separate GET state and
forwarding paths described in the ROM analysis remain relevant.

## Other recovered parameters

The exact DSP table contains stored microphone gain, noise reduction and AGC
settings. The primary voice parameter group stores `V_MicGain_L/R=11`,
`MicNREna=1`, `MicNRLevel=10`, and `MicAgcEna=0`. These describe that parameter
group, not independently verified behavior of the current microphone route.
They do not justify adding unverified microphone commands to the plasmoid.

DP header metadata also contains six native EQ descriptions: user EQ (10
bands), voice microphone EQ (9), 8 kHz microphone EQ (9), and three extra audio
EQs (7, 10 and 10). The SDK defines frequency in Hz, gain in tenths of dB and
Q in units of 1/32. The private results preserve each band's filter type,
frequency, gain and Q. Header metadata has not been mapped to the application's
Default/Game/Movie/Music selections, and is not a measurement of the effective
frequency response.

CT additionally provides battery thresholds and its voltage-level table. The
stored low-battery warning threshold is 3508 mV and shutdown threshold is
3301 mV. These are factory configuration, not writable battery controls.

No production controls changed. The new evidence narrows sidetone's stored
format and part of Gaming's guard without authorizing firmware edits or
presenting unverified runtime features as supported.
