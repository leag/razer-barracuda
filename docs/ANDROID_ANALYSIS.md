# Razer Audio Android static analysis

## Artifact and limits

The user supplied Razer Audio `30.0.0.1787212728`, package
`com.razer.audiocompanion`, as an APKPure XAPK. The package corresponds to the
[user-identified Google Play listing](https://play.google.com/store/apps/details?id=com.razer.audiocompanion).
The supplied XAPK SHA-256 is
`85f02a8837377e0564cd5ff22e8dcc4a66891f914c58fbf15c8f00d460c49ff9`.
Its manifest and the decoded base APK agree on package and version. The signing
certificate has not been independently authenticated against an official copy.

The archive, extracted APKs, provenance hashes and JADX output remain in ignored
`private/android-analysis/`. No APK was installed or executed. JADX 1.5.6
processed 15,397 classes and reported 236 decompilation errors. The findings below
come from identifiable constants, wiring and successfully readable methods;
this is not complete recovery of every method, native library or server feature.
The generated Java includes Kotlin coroutine and synthetic-constructor artifacts
and must not be treated as compilable original source.

## Select the correct model path

`DeviceManagerKey` identifies `BARRACUDA_X` as ID 202, `mabel_t3`; the factory
selects `BarracudaXDeviceManager` from `impl/barracuda/t3`. It separately maps
`BARRACUDA_X_V2` to ID 900, `mabel_t3c`, and a Chroma-capable manager. The T3
name agrees with the recovered dongle image; this model association is stronger
than searching all app classes for feature names. A cloud-manifest/device match
has not been observed live in this investigation.

The T3 manager declares EQ, Gaming Mode, Do Not Disturb and Quick Connect on its
dashboard, plus auto standby and voice-prompt language in settings. These are
model-specific declared features, subject to runtime readback/support checks.
It does not wire a microphone/sidetone provider. Such classes elsewhere in the
app, including Airoha SDK controls and other Barracuda managers, must not be
attributed to Barracuda X. This does not prove that its firmware lacks sidetone,
only that this app path does not establish its gain scale or control support.

## Bluetooth transport

The factory creates `AudioWiseHeadsetBleProviderImpl` for service UUID
`0000fd65-0000-1000-8000-00805f9b34fb`. Its base-class defaults supply write UUID
`416d0000-2d52-617a-6572-424c4501f40a` and notification UUID
`416d0001-2d52-617a-6572-424c4501f40a`, with `ProtocolType.RAZER_V3`.
`RazerBaseBleProviderImpl` assigns these respectively to service, write and
notification characteristics.

`V3CommonWriteBytesCommand` supplies these byte arrays to the BLE writer.
`RazerBleProviderImpl` writes the command bytes directly as GATT characteristic
data and waits for notifications. Its V3 response filter matches the command
identifier and response byte 1 equal to `01` or `02`. Several simple mappers
consume value byte 3. This is Bluetooth framing; it does not contain the USB
`01 80 ... PA` envelope or family-7 MMI operation `08 00 EVENT`.

## Model-specific commands

All values in this table are hexadecimal Bluetooth characteristic payloads,
not validated USB reports. SETs are evidence only and were not sent.

| Function | GET | SET | Evidence |
| --- | --- | --- | --- |
| Gaming Mode | `14 00 00` | `94 00 01 VV` | `P3GameModeReaderImpl`/`WriterImpl`; `VV=00` disabled, `01` enabled |
| EQ preset | `13 00 00` | `93 00 01 PP` | `P3EqualizerReaderImpl`/`WriterImpl`; T3 preset map below |
| Custom EQ bands | `15 00 00` | `95 00 0a` followed by ten bytes | `P3CustomEqualizerReaderImpl`/`WriterImpl`; T3 ten-band configuration |
| Do Not Disturb | `27 00 00` | `a7 00 01 VV` | `P3DNDModeReaderImpl`/`WriterImpl`; `VV=00/01` |
| Shutdown after idle time | `2c 00 00` | `ac 00 01 TT` | `AmeliaAutoStandByReaderImpl`/`WriterImpl`; time-based mode |
| Quick Connect | `2d 00 00` | `ad 00 06` followed by six MAC-address bytes | `P3QuickConnectReaderImpl`/`WriterImpl`; known-source list and selection |
| Version information | `02 00 00` | No setter used by version reader | `MultiFirmwareVersionReaderImpl`; also used to infer installed prompt language |

The T3 EQ enum uses native IDs `00` default, `07` game, `08` music, `09` movie,
and `ff` custom. The enum also stores separate presentation IDs; the EQ provider
passes the native `id`, not `pid`, to the writer. Game EQ is distinct from Gaming
Mode. The ten band labels are 31, 63, 125, 250, 500 Hz, and 1, 2, 4, 8, 16 kHz;
the configuration initializes all raw values to `05`. This alone does not
establish dB units, safe USB SET semantics or effect on the 2.4 GHz audio path.

The time-based standby enum offers `00` never, `05` five minutes, `0f` fifteen,
`1e` thirty, `2d` forty-five, and `3c` sixty. Do not confuse these minutes with
the index-based/seconds-based standby enums used by other models.

Quick Connect is Bluetooth source selection, not dongle pairing. The reader
parses source addresses, names and active/list-update flags. Its dashboard
control is disabled when Gaming Mode is enabled or the source list is empty;
that is observed UI logic, not a measured latency or radio-behavior explanation.

## Voice-prompt language installs firmware

`AudioWiseVoicePromptLanguageReaderImpl` derives the language from the final
byte of the returned version packet. In the T3 manager, selecting a language
calls `DfuUIAction.InstallVoicePrompt`. The wired DFU provider calls `installVP`
and uses firmware-loading machinery. This is not evidence for a simple,
reversible MMI language change on this model. Do not implement or probe this
path: firmware writes/erase/reboot are excluded by repository invariants.
Independent tone/voice-prompt enable-state getters are not established here.

The supplied XAPK does not contain an identifiable headset firmware package in
its base APK or three splits. Its assets are fonts, barcode models, a public
suffix list and Android compilation metadata; `DebugProbesKt.bin` is a Kotlin
debugging artifact, not headset firmware. The T3 path downloads firmware:
`FirmwareManagerRepositoryImpl` reads the package URL from the downloaded
`JsonFirmwareManifestEntity`, `FirmwareDownloaderRepositoryImpl` retrieves the
URL using OkHttp and writes a local file, and
`ZipFileFirmwareManagerRepositoryImpl` unpacks the downloaded archive.
`installVP` selects `FirmwareType.AD` (audio data) from this firmware machinery.
Existing local files can be reused through the manager's cache checks. The
exact current model-specific download URL and package contents have not been
retrieved here; the APK alone supplies the download logic, not that firmware.

## Consequences for the pending tests

The previous [gaming experiment](GAMING_MODE.md) received accepted-format MMI
ON/OFF replies, but the original parser mistook the echoed operation `08` for
an error and skipped the observation interval. A regression test against that
raw capture corrects the classification. Physical MMI effect remains unknown;
the app also uses a different command path for Bluetooth Gaming Mode. The app provides a real state getter and
explicit setters, unlike the generic MMI toggle proposal. It does not establish
that Gaming Mode lowers 2.4 GHz latency.

The app payload shape resembles existing USB family-8 customer GETs. That is a
mapping hypothesis, not proof that the headset routes or interprets them the
same way. Local research probes now offer one explicit family-8 GET per case
for Gaming Mode, EQ preset/bands, DND, standby and Quick Connect. A separate
opt-in EQ-profile experiment snapshots a known native preset, requests Game
(or Default if already Game), requires readback, then restores and verifies the
original preset. This is a prepared research probe, not a validated USB control.
No Gaming/DND/standby/Quick Connect SET was added. Validate raw GET responses
and physical state before selecting any state experiment or production control. Existing captures of another family-8 ID must
not be retroactively relabeled without this mapping evidence.

The independent microphone mute, tones, EQ-enable and mic-NR MMI experiments
remain generic SDK candidates. Native sidetone raw `00 -> 01 -> 00` is a
separately reviewed experiment, not a validated gain range. Read diagnostics
first; do not batch speculative writes or expose them in the plasmoid.

## Reproducibility and local evidence

The exact retained source root is `private/android-analysis/jadx/sources/`.
The key evidence paths below are relative to `com/razer/` under that root:

- `common/domain/model/DeviceManagerKey.java`
- `device/manager/impl/BarracudaDeviceManagerFactory.java`
- `device/manager/impl/barracuda/t3/BarracudaXDeviceManager.java`
- `bluetooth/data/datasource/chipset/audiowise/hammerhead/AudioWiseBaseBleProviderImpl.java`
- `bluetooth/data/datasource/common/RazerBaseBleProviderImpl.java` and `RazerBleProviderImpl.java`
- `device/manager/gamemode/P3GameModeReaderImpl.java` and `P3GameModeWriterImpl.java`
- `device/manager/equalizer/P3EqualizerReaderImpl.java` and `P3EqualizerWriterImpl.java`
- `bluetooth/data/datasource/common/reader/EqualizerSealedClass.java`
- `device/manager/customequalizer/P3CustomEqualizerReaderImpl.java` and `P3CustomEqualizerWriterImpl.java`
- `device/manager/donotdisturb/P3DNDModeReaderImpl.java` and `P3DNDModeWriterImpl.java`
- `bluetooth/data/datasource/common/reader/AmeliaAutoStandByReaderImpl.java` and `AutoStandBySealedClass.java`
- `device/manager/autostandby/AmeliaAutoStandByWriterImpl.java` and `AutoStandByWriterImpl.java`
- `device/manager/quickconnect/P3QuickConnectReaderImpl.java`, `P3QuickConnectWriterImpl.java` and `QuickConnectProviderImpl.java`
- `device/manager/voiceprompt/AudioWiseVoicePromptLanguageReaderImpl.java`
- `device/manager/impl/common/dfu/AmeliaT2V2AudioWiseCfuAndDfuProviderImpl.java`

Hardware-free research checks compare the pending GET payloads with these
retained app definitions, exercise malformed/fragmented replies, rejection,
timeouts, interrupt cleanup and route restoration using a fake transport.
They validate the probe implementation, not hardware support or latency.

## Downloaded headset firmware

The production cloud descriptor was subsequently retrieved and its firmware
manifest led to the official T3BT `01.06.00.00` ZIP. The package includes MCU,
DSP-related components and seven separate voice-language images. Static tracing
confirmed the app command handlers, the Gaming SET to MMI `84/85` mapping and
the ten-band custom EQ neutral offset. See
[headset firmware analysis](HEADSET_FIRMWARE_ANALYSIS.md) for hashes, addresses,
conditional branches and the remaining ROM limitations. No firmware was installed
and no new device commands were sent during that investigation.

## Initial authorized USB GET tests

The user subsequently requested starting the prepared tests. With the battery
driver temporarily replaced by hid-generic, one remote-route family-8 GET was
sent per session. Both queries returned matching customer data:

| Query | Response data | Interpretation from the Android model |
| --- | --- | --- |
| `14 00 00` | `14 01 01 00` | Gaming disabled (`00`) |
| `13 00 00` | `13 01 01 00` | Default EQ preset (`00`) |

These are successful initial USB readbacks compatible with the Android state
map. No state setter or latency/audio comparison was performed in these two
sessions. Each session verified remote-route setup, restored and verified local
routing, obtained final E3 `01`, and restored the original HID driver. Raw
timestamped captures remain in `private/probes/captures/`. A future state
experiment must demonstrate the expected change and restored readback before
treating this as a validated control.

The following explicitly authorized EQ experiment read preset `00`, sent
`93 00 01 07`, and received `93 01 01 00`. GET `13 00 00` then returned
`13 01 01 07`, confirming Game selection. After a 20-second observation window,
`93 00 01 00` returned `93 01 01 00`; GET returned `13 01 01 00`, confirming
restoration to Default. Cleanup verified local routing and E3 `01`, and the HID
driver was restored. The user had audio playing during this trial and confirmed
that the sound changed. Together, the correlated parameter readbacks and user
listening observation validate native Default/Game preset selection through USB
with an audible effect on the 2.4 GHz audio path. This was a subjective listening
test, not a frequency-response measurement; Music, Movie and Custom have not
been exercised, and the custom band's gain scale remains unresolved.
