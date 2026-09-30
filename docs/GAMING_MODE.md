# Gaming mode investigation

## Result and scope

The current local utility includes the Android family-8 GET/SET path through
the serialized driver mailbox. A live USB reproduction with the installed
driver returned SET result `00` for `94 00 01 01`, but five GETs remained `00`
over approximately two seconds. Restoring the original disabled state returned
`00`, and a subsequent GET remained disabled. Acknowledgment did not establish
activation. The UI therefore marks Gaming experimental and reports
`gaming-not-applied` when the readback disagrees, without resending the setter.
The capture is retained in ignored `private/native-controls/gaming-transaction.json`.
Bluetooth activation and the firmware condition preventing this USB change
remain unverified. The Game EQ preset is a separate control.

The following sections describe the earlier investigation stages.

The later [installed ROM analysis](LIVE_ROM_ANALYSIS.md) establishes the
state-changing handler behind events `84/85`. It also finds that GET `14`
reads a separate reported-state byte, so the USB readback mismatch does not
yet distinguish an unapplied event from stale reporting. Runtime mode and
guard meanings remain unresolved.

The shared AudioWise SDK names three gaming-mode MMI commands. The Barracuda X
(2022) manufacturer guide also documents gaming-mode control in Razer Audio.
The SDK names and guide alone do not establish USB support or a change to
2.4 GHz latency. The initial investigation was static. A later
user-authorized USB experiment, recorded below, received replies compatible
with SDK success for both candidates; its initial parser misclassified them. No production gaming control was
installed.

The [Razer-authored 2022 master guide, reproduced here](https://manuals.plus/razer/rz04-04430100-r3m1-barracuda-x-2022-wireless-stereo-gaming-headset-manual)
lists gaming mode among the mobile app controls. It requires a Bluetooth-only
connection to the mobile device for app use and says the app disconnects when
switching to dongle audio. This establishes an official Bluetooth control path,
not a USB command, a latency figure or the mode's scope across both radios.

## SDK candidates

`TwsTester/MMI_Commands_279.cs` defines:

| Name | Decimal | Hex | Candidate family-7 payload |
| --- | --- | --- | --- |
| `APP_MMI_GAMING_MODE_ON` | 132 | `84` | `08 00 84` |
| `APP_MMI_GAMING_MODE_OFF` | 133 | `85` | `08 00 85` |
| `APP_MMI_GAMING_MODE_TOGGLE` | 134 | `86` | `08 00 86` |

Applying `DeviceObj.send_MMI_command` and the existing USB envelope gives the
candidate report `01 80 08 50 41 07 SS 03 08 00 EVENT`, padded to 64 bytes.
These are derived candidates, not hardware-validated reports. The legacy
267 enum has no corresponding gaming names. No gaming-state getter or
model-specific use of these constants was found in the recovered SDK.

The SDK matches byte 13 of the PI message against zero and tests byte 14 for
zero. In the observed five-byte MMI data these are status and result; byte 12
is the echoed operation `08`, unlike the OTA acknowledgment layout.
Even an accepted acknowledgment would not establish an audible effect, current
mode, persistence or latency reduction. Any eventual implementation needs
sequence-correlated replies and must use the serialized driver route rather
than competing with battery queries through hidraw. Toggle is unsuitable for a
stateful UI without trustworthy readback.

## Firmware boundary and numeric namespace trap

The recovered XIP/patch images belong to the dongle. Its family-7 route can
forward requests to the headset when remote routing is enabled. The local
dispatcher handles operation `08` at `0x1fc2c27e`, then reaches a patch
trampoline at `0x1ffc0098` and external ROM at `0x1ffb1172`. That ROM body and
the remote headset implementation are absent from this analysis. The mapping
from these SDK events to actual gaming behavior cannot be completed here.

Separately, the local firmware queues internal events 132 and 133. Those
numbers must not be interpreted using the SDK MMI enum: the internal event
table routes 132 to `0x1fc13048`, which can reach `0x1fc1302a` and select the
PAIRING state through `0x1fc12d3c`. Internal events 133 and 134 likewise have
connection-state handlers. Matching numeric values across these namespaces
was a false lead, not evidence of a gaming-mode handler. No new family-14
command is validated by this observation.

## Other gaming-related names

`AW_ENTER_LL_TEST_MODE` explicitly supports only `VendorType.AWTXh`, whereas
this dongle uses the identified `AWTXhm` bridge path. Its implementation calls
`ystech_LL_Test_Mode`, a different HID format with command `82`, value `01`
for entry and `02` for exit. The name does not establish what LL means or that
it is a consumer low-latency mode. Do not reuse it for this device.

The generic DSP EQ definitions include shooter and driving-game preset names.
Those are distinct from the gaming MMI events and do not prove native EQ
support on this model. Software EQ presets and PipeWire buffering likewise do
not confirm or control the headset's native gaming mode.

## Remaining evidence needed

The most useful next evidence is a Bluetooth protocol capture of the official
app enabling and disabling gaming mode on this exact model, including any
state query. That can establish event mapping and readback before considering
a separately authorized USB experiment. Persistence and effect on each radio
need independent verification; a 2.4 GHz latency claim requires measurement.
Keep these candidates out of the CLI, driver and plasmoid until then.

## Authorized USB experiment

The user authorized the ON/OFF test and the temporary HID driver change. The
Barracuda driver was unloaded, the matching HID interface bound to hid-generic,
and the probe ran as the desktop user under the existing control lock. The
audio interface was not rebound and no audio settings were changed.

Validated queries returned local route `E0 00`, connected link `E3 01`, and
transport status `E6 1b`. After remote-route selection and the acknowledged
READ_MAX_LEN setup, `E0 01` confirmed the selected route. Exactly one ON and one
OFF candidate were sent; no toggle, local gaming command or retry was sent.

| Request | Sequence | Correlated family-7 response data | Result |
| --- | --- | --- | --- |
| `08 00 84` | `47` | `07 c7 08 00 00` | Operation `08`, status `00`, result `00` |
| `08 00 85` | `48` | `07 c8 08 00 00` | Operation `08`, status `00`, result `00` |

The original generic probe treated data byte 2 as an acknowledgment status,
borrowing the family-6 layout. That incorrectly labeled `08` as rejection.
The SDK's `send_MMI_command` matcher checks PI offsets 10 and 13 (family `07`
and status `00`), then offset 14 for result `00`; `isMMICmdOK` also checks
that final result byte. The captured replies satisfy these conditions. The
five data bytes therefore decode as family, echoed sequence, operation `08`,
status `00`, and result `00`. This correction is verified against the retained
raw capture by the new hardware-free probe regression test.

Because of the parser error, ON was followed immediately by OFF, about 14 ms
apart. The intended observation interval never ran. Both replies are compatible
with acceptance, but no physical effect, state getter or latency improvement was
verified. Do not interpret the old capture's script-generated `error` or
`off_error` fields as current protocol conclusions. Raw bytes are preserved.
The next candidate is the Android app's real gaming getter, documented in
[Android analysis](ANDROID_ANALYSIS.md), or a separately authorized repeat of
the MMI observation with the corrected parser.
Cleanup acknowledged `E1 00`; readback confirmed `E0 00` and `E3 01`. The
original `razer-barracuda` driver was restored and its binding checked. No
latency measurement or user-confirmed physical gaming-mode effect was obtained.
Probe scripts and the timestamped raw capture are retained in ignored
`private/scratch/`, not distributed with the application.
