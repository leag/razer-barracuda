# Additional command implementation review

## Scope and evidence

This review inventories named commands in the analyzed AudioWise host SDK and
cross-checks the recovered dongle/headset firmware dispatchers and existing live
captures for USB `1532:0552`. A name in a shared SDK is not proof that this model
implements it. Host wrappers, wire commands and MMI events are different layers;
overloads and aliases must not be counted as distinct hardware features.
Unidentified dispatch paths and external ROM calls remain unresolved. This is
not a claim that every possible firmware command has been decoded.

The inventory was initially static. A subsequently user-authorized native
sidetone probe is recorded below. The earlier explicit power-off experiment
remains the only new control with user-confirmed physical effect.
See [protocol](PROTOCOL.md) and [firmware evidence](FIRMWARE_ANALYSIS.md).
The [gaming-mode investigation](GAMING_MODE.md) separates SDK candidates,
Bluetooth app support and the unresolved firmware mapping.
An explicitly authorized USB remote-route gaming test returned correlated
`07 SS 08 00 00` replies for ON and OFF. The original probe mistook operation
`08` for rejection; SDK comparison confirms zero status/result. The observation
interval did not run, so physical effect remains unverified. See that
investigation and the [Android analysis](ANDROID_ANALYSIS.md) for the corrected
interpretation, real Bluetooth getters and confirmed route/driver restoration.

## Implementation decisions

Subsequent Android-derived USB testing validated the EQ preset GET (`13`) and
SET (`93`): Default `00` changed to Game `07`, read back correctly, and restored
to `00`. The user confirmed an audible sound change over 2.4 GHz. This makes
Default/Game native preset control a hardware-validated candidate, distinct
from the generic MMI EQ enable events and custom coefficient writes. See
[Android evidence](ANDROID_ANALYSIS.md) for framing, capture and test limits.
Gaming GET (`14`) also returned `00`, compatible with the Android disabled-state
map; its setter and physical latency effect have not yet been validated.

| Command group | Evidence and limitation | Decision |
| --- | --- | --- |
| Family 7 MMI `08 00 02`: headset power off | Physical shutdown confirmed by the user; valid disconnect frames; no correlated family-7 acknowledgment observed | Implemented as an explicit one-shot driver sysfs action under the battery route mutex; new driver entry point requires live validation |
| Family 6 `70`, `71`, `72`: sidetone enable, set gain, get gain | Named SDK constants and matching handlers; GET returned `00`, enable returned accepted OTA status `01`; physical effect, gain scale and bounds unresolved | Best next native audio candidate; validate GET first, then bounded setters only after semantics are established |
| Family 6 `34`: image version; `43`: MP identity reads | Firmware/SDK paths; model-ID read already observed, other identity fields not established | Optional explicit diagnostic reads, individually validated; no polling or speculative ID sweep |
| Family 6 `32`: RSSI | Existing protocol analysis; raw value meaning and units unresolved | Diagnostic raw value only; no dBm claim or signal-quality bar |
| Family 8 customer GET | Several responses captured, most parameter meanings unknown | Preserve raw research evidence; no user-facing controls or corresponding SET until semantics are validated |
| MMI gaming mode, tone, voice prompt and language | Shared SDK events, no Barracuda-specific effect confirmed | Research candidates, not implementation-ready; language changes may persist |
| MMI microphone mute, volume, media and call controls | Generic Bluetooth/MMI definitions, no model-specific validation | Do not duplicate desktop controls; physical microphone effects need separate validation |
| DSP EQ, mic NR, mic selection, ANC, hear-through, surround and profiles | Generic SDK support does not establish hardware capability or payload semantics | No native implementation yet; keep current software effects separate |
| Link disconnect, advertising, BLE, GRS/handover, DUT and RF tests | Can disturb links or enter test modes; many target different hardware | Exclude from ordinary UI; existing documented pairing remains explicit |
| GPIO, LED, I2C, ATB and register access | Peripheral addresses, electrical effects and read side effects unresolved | Exclude from application; even GET is not automatically harmless |
| MP/NVDS/identity writes, pairing deletion and factory reset | Persistent manufacturing/configuration or pairing changes | Exclude |
| OTA/storage writes, erase, load/update, reboot and power-on reboot | Firmware or boot-state manipulation | Exclude under repository protocol invariants |
| Storage/filesystem/NVDS reads, CRC and echo | Primarily maintenance paths; framing and operating-mode preconditions incomplete | No production feature; read-only names do not establish safe invocation |
| Legacy LQ family-14 queries `02`..`05` | Recovered local dispatcher accepts only `E0`..`F1` | Not supported by that recovered dispatcher; do not implement as dongle queries |
| USB firmware/reboot host wrappers | Wrapper branches target Holtek or MXIC bridge variants, not the identified AWTXhm path | Do not reuse these wrappers for this dongle |

## Sidetone evidence

The official headset T3BT `01.06.00.00` image was subsequently obtained and
analyzed offline. It confirms native app handlers for EQ, Gaming, custom EQ,
DND, standby and Quick Connect. Gaming SET maps to MMI `84/85`; sidetone
setters still delegate their final effect to absent ROM. See
[headset firmware analysis](HEADSET_FIRMWARE_ANALYSIS.md). These findings reduce
the need for exploratory probes but do not validate every USB setter or effect.

The family-6 dispatcher at `0x1fc2ba48` routes `70`, `71`, and `72`
to handlers `0x1fc2b7b6`, `0x1fc2b7e2`, and `0x1fc2b80e`.
The two setters consume one payload byte and call `0x1fc0e1ce` and
`0x1fc0e1e0`; the getter calls external ROM at `0x1ff9be24` with selector
11 and two output locations, then serializes one byte from one location.
This supports a one-byte gain result, not a confirmed gain scale, enabled-state
readback or persistence behavior. The ROM implementation is not recovered here.
The disassembler sometimes prints an extra leading `1` in XIP call targets;
the addresses above follow the mapped image used by the existing analysis.
Remote routing must be established before treating this as a headset command.

The SDK method named `AW_MMI_RESET_SIDE_TONE` is **not** the gain setter:
it reads NVDS ID 236 and issues a tracer NVDS write using Bluetooth/link-key
information. Its name is insufficient justification to expose it as a sidetone
reset. It belongs to the excluded persistent-write category.

## Customer parameters already observed

Existing family-8 GET captures contain responses for parameters
`12`, `17`, `1e`, `20`, `21`, `25`, `2a`, `33`, `55`, `56`, `57`,
`92`, `93`, `94`, `96`, `97`, `98`, `99`, and `ac` (hexadecimal).
Only previously validated battery/cable interpretations should be retained.
Other replies prove that a value was returned, not what it measures or whether
an identically numbered setter is safe. Parameter numbers are family-specific.

## Production prerequisites

A new command needs strict request/response validation, bounded interruptible
reads, and guaranteed `E1 00` restoration with `E0` verification after remote
routing. Sequence separation alone does not synchronize userspace routing with
the driver's battery worker; route coordination must be solved before shipping
controls. A missing acknowledgment after power-off must not be treated as proof
that the action failed or trigger an automatic resend. Power-on from an already
powered-off radio is not established by a POWER_ON event in a generic enum.

The recommended order is explicit power-off, sidetone readback research, then
identity diagnostics. The inventory itself authorizes no live experiments and adds no
unverified output commands to the application or driver. Validated power-off is
now an explicit serialized action; experimental sidetone remains uninstalled.

## Named OTA commands (family 6)

All identifiers below are inventory evidence; only the decisions above establish
implementation readiness. SDK constants can exist without a matching handler.

| Hex ID | SDK identifier |
| --- | --- |
| `22` | `CMD_STORAGE_WRITE` |
| `23` | `CMD_STORAGE_READ` |
| `24` | `CMD_MORE_FRAME` |
| `25` | `CMD_IOCTL` |
| `34` | `CMD_GET_IMAGE_VERSION` |
| `31` | `CMD_GET_BATTERY` |
| `32` | `CMD_GET_RSSI` |
| `33` | `CMD_GET_GRS_STATUS` |
| `30` | `CMD_OTA_MODE` |
| `35` | `CMD_ERASE_LOAD_REGION` |
| `36` | `CMD_SET_LOAD_INFO` |
| `37` | `CMD_LOAD_MORE` |
| `38` | `CMD_CALC_LOAD_REGION_CRC` |
| `39` | `CMD_UPDATE` |
| `3a` | `CMD_HANDOVER` |
| `3b` | `CMD_GET_FILESYSTEM_TABLE` |
| `3c` | `CMD_REBOOT` |
| `42` | `CMD_REBOOT_AND_POWERON` |
| `43` | `CMD_READ_MP_DATA_BY_ID` |
| `44` | `CMD_WRITE_MP_DATA_BY_ID` |
| `45` | `CMD_GET_ATB_VALUE` |
| `46` | `CMD_READ_NVDS_DATA_BY_ID` |
| `48` | `CMD_ENABLE_ADVERTISING` |
| `49` | `CMD_GET_FILESYSTEM_INDEX` |
| `40` | `CMD_READ_CUST_INFO` |
| `7f` | `CMD_SET_OTA_STATUS` |
| `60` | `CMD_SET_BLE` |
| `61` | `CMD_TEST_MODE` |
| `62` | `CMD_SET_LED` |
| `63` | `CMD_GET_IO_LEVEL` |
| `66` | `CMD_SET_IO_LEVEL` |
| `64` | `CMD_SET_LED_CURRENT` |
| `65` | `CMD_SET_LED_PWM` |
| `67` | `CMD_WRITE_I2C` |
| `68` | `CMD_READ_I2C` |
| `70` | `CMD_SIDETONE_ENABLE` |
| `71` | `CMD_SET_SIDETONE_GAIN` |
| `72` | `CMD_GET_SIDETONE_GAIN` |
| `3d` | `CMD_CALC_LOAD_REGION_CRC32` |
| `fe` | `CMD_ECHO` |

## Named MMI events (279 variant)

Except for validated power-off, these are unverified generic events. The legacy
267 variant is a different encoding and must not be substituted. Events `f1` and
above are dispatched by the host tool through serial RTS/DTR operations, not
ordinary headset USB MMI commands.

| Hex ID | SDK identifier |
| --- | --- |
| `00` | `APP_MMI_NONE` |
| `01` | `APP_MMI_POWER_ON_PRESS` |
| `02` | `APP_MMI_POWER_OFF_PRESS` |
| `03` | `APP_MMI_POWER_ON_PAIRING_PRESS` |
| `04` | `APP_MMI_POWER_ON_RELEASE` |
| `05` | `APP_MMI_POWER_ON_PAIRING_RELEASE` |
| `06` | `APP_MMI_POWER_OFF_RELEASE` |
| `07` | `APP_MMI_LEGACY_LINK_BACK` |
| `08` | `APP_MMI_LINK_BACK_ALL` |
| `09` | `APP_MMI_ENTER_PAIRING` |
| `0d` | `APP_MMI_FORCE_POWER_OFF_FOR_OTA_REBOOT` |
| `10` | `APP_MMI_VOICE_RECONGNITION_TOGGLE` |
| `11` | `APP_MMI_LAST_NUMBER_REDIAL` |
| `12` | `APP_MMI_REJECT_INCOMING_CALL` |
| `13` | `APP_MMI_ANSWER_CALL` |
| `14` | `APP_MMI_TERMINATE_CALL` |
| `15` | `APP_MMI_CALL_TRANSFER` |
| `16` | `APP_MMI_RELEASE_HELD_OR_WAITING_CALL` |
| `17` | `APP_MMI_SWITCH_TO_SECOND_CALL` |
| `18` | `APP_MMI_RELEASE_ACTIVE_CALL_ACCEPT_HELD_OR_WAITING_CALL` |
| `19` | `APP_MMI_JOIN_TWO_CALLS` |
| `1a` | `APP_MMI_MIC_MUTE_ON` |
| `1b` | `APP_MMI_MIC_MUTE_OFF` |
| `1c` | `APP_MMI_MIC_MUTE_TOGGLE` |
| `1d` | `APP_MMI_VOL_UP` |
| `1e` | `APP_MMI_VOL_DOWN` |
| `1f` | `APP_MMI_CREATE_SCO` |
| `20` | `APP_MMI_DISC_SCO` |
| `21` | `APP_MMI_CREATE_DISC_SCO_TOGGLE` |
| `30` | `APP_MMI_PLAY` |
| `31` | `APP_MMI_PAUSE` |
| `32` | `APP_MMI_PLAY_PAUSE_TOGGLE` |
| `33` | `APP_MMI_STOP` |
| `34` | `APP_MMI_FORWARD` |
| `35` | `APP_MMI_BACKWARD` |
| `40` | `APP_MMI_GRS_ENTER_PAIRING_MODE` |
| `41` | `APP_MMI_GRS_EXIT_PAIRING_MODE` |
| `42` | `APP_MMI_GRS_PAIRING_TOGGLE` |
| `43` | `APP_MMI_GRS_CREATE_CONNECTION` |
| `44` | `APP_MMI_GRS_DISC_CONNECTION` |
| `45` | `APP_MMI_GRS_CONNECTION_TOGGLE` |
| `46` | `APP_MMI_GRS_HANDOVER` |
| `50` | `APP_MMI_DSP_SPK_NR_ON` |
| `51` | `APP_MMI_DSP_SPK_NR_OFF` |
| `52` | `APP_MMI_DSP_SPK_NR_TOGGLE` |
| `53` | `APP_MMI_DSP_MIC_NR_ON` |
| `54` | `APP_MMI_DSP_MIC_NR_OFF` |
| `55` | `APP_MMI_DSP_MIC_NR_TOGGLE` |
| `56` | `APP_MMI_DSP_ANC_ON` |
| `57` | `APP_MMI_DSP_ANC_OFF` |
| `58` | `APP_MMI_DSP_ANC_TOGGLE` |
| `59` | `APP_MMI_DSP_ANC_NEXT` |
| `5a` | `APP_MMI_DSP_ANC_LAST` |
| `5b` | `APP_MMI_DSP_AEC_ON` |
| `5c` | `APP_MMI_DSP_AEC_OFF` |
| `5d` | `APP_MMI_DSP_AEC_TOGGLE` |
| `5e` | `APP_MMI_DSP_HEAR_THROUGH_ON` |
| `5f` | `APP_MMI_DSP_HEAR_THROUGH_OFF` |
| `60` | `APP_MMI_DSP_HEAR_THROUGH_TOGGLE` |
| `61` | `APP_MMI_DSP_EQ_ON` |
| `62` | `APP_MMI_DSP_EQ_OFF` |
| `63` | `APP_MMI_DSP_EQ_TOGGLE` |
| `64` | `APP_MMI_DSP_EQ_NEXT` |
| `65` | `APP_MMI_DSP_EQ_LAST` |
| `66` | `APP_MMI_DSP_SURROUND_ON` |
| `67` | `APP_MMI_DSP_SURROUND_OFF` |
| `68` | `APP_MMI_DSP_SURROUND_TOGGLE` |
| `70` | `APP_MMI_DSP_ANC_ON_PROFILE_0` |
| `71` | `APP_MMI_DSP_ANC_ON_PROFILE_1` |
| `72` | `APP_MMI_DSP_ANC_ON_PROFILE_2` |
| `73` | `APP_MMI_DSP_ANC_ON_PROFILE_3` |
| `74` | `APP_MMI_DSP_ANC_ON_PROFILE_4` |
| `75` | `APP_MMI_DSP_ANC_ON_PROFILE_5` |
| `76` | `APP_MMI_DSP_ANC_ON_PROFILE_6` |
| `77` | `APP_MMI_DSP_ANC_ON_PROFILE_7` |
| `78` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_0` |
| `79` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_1` |
| `7a` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_2` |
| `7b` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_3` |
| `7c` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_4` |
| `7d` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_5` |
| `7e` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_6` |
| `7f` | `APP_MMI_DSP_HEAR_THROUGH_ON_PROFILE_7` |
| `80` | `APP_MMI_TONE_ENABLE` |
| `81` | `APP_MMI_TONE_DISABLE` |
| `82` | `APP_MMI_TONE_TOGGLE` |
| `83` | `APP_MMI_LANGUAGE_CHANGE` |
| `84` | `APP_MMI_GAMING_MODE_ON` |
| `85` | `APP_MMI_GAMING_MODE_OFF` |
| `86` | `APP_MMI_GAMING_MODE_TOGGLE` |
| `87` | `APP_MMI_POWERON_INCOMPLETE` |
| `e0` | `APP_MMI_CHK_FW_VERSION` |
| `e1` | `APP_MMI_ENABLE_DUT` |
| `e2` | `APP_MMI_DELETE_GRS_INFO` |
| `e3` | `APP_MMI_DELETE_PAIRED_INFO` |
| `e4` | `APP_MMI_FACTORY_RESET` |
| `f0` | `APP_MMI_VP_ENABLE` |
| `f1` | `USR_USER_POWER_ON_RTS` |
| `f2` | `USR_USER_RESET_DTR` |
| `f3` | `USR_RTS_10` |
| `f4` | `USR_DTR_10` |
| `f5` | `USR_RTS_01` |
| `f6` | `USR_DTR_01` |
| `f7` | `USR_RTS_1` |
| `f8` | `USR_DTR_1` |
| `f9` | `USR_RTS_0` |
| `fa` | `USR_DTR_0` |

## Host transport inventory

The following 109 unique `send_*` method names cover the transport
entry points found in `DeviceObj`. Some are helpers, aliases, continuations or
commands for other transports. Entries without explicit validation above remain
unverified and must not be added to the production allowlist.

- `send_ANC_TEST_Command`
- `send_ANC_TEST_Command_Data`
- `send_CMD_SET_LED_CURRENT`
- `send_CMD_SET_LED_PWM`
- `send_CT_11_DONGLE_AUDIO_CTRL`
- `send_Customer_Data_Channel`
- `send_D25_get_tpy_parameters`
- `send_D25_set_tpy_parameters`
- `send_DSP_CMD_CONFIG_WRITE_TBL`
- `send_DSP_CMD_IIR_EQ`
- `send_DSP_CMD_SPEECH_TEST`
- `send_DSP_CMD_UPDATE_IIR_EQ`
- `send_DSP_CMD_WRITE_TBL`
- `send_DSP_CMD_WRITE_TBL_imp`
- `send_DSP_Command`
- `send_DSP_Command_TRX`
- `send_DSP_Data_Query`
- `send_DSP_clock_control`
- `send_DSP_set_IIR_Gain`
- `send_GS_Headtrack_get_register`
- `send_GS_Headtrack_init`
- `send_GS_Headtrack_start_record`
- `send_HASE_Command`
- `send_HA_Command`
- `send_HA_Table`
- `send_HA_command`
- `send_HA_command_group`
- `send_HA_command_notify`
- `send_HWADbg`
- `send_HWADbg_done`
- `send_LQ_DFU_BT_INQUIRY_SCAN`
- `send_LQ_DFU_REMOTE_DISCONNECT`
- `send_LQ_GET`
- `send_LQ_GET_AFH_MAP`
- `send_LQ_GET_DEVM`
- `send_LQ_GET_LPC`
- `send_LQ_GET_Quality`
- `send_LQ_MONITOR_ENABLE`
- `send_LQ_SET_AFH_MAP`
- `send_MMI_Command_TRX`
- `send_MMI_command`
- `send_MMI_command_tool_define`
- `send_MMI_user_command`
- `send_MicCalibration`
- `send_OTA_CMD`
- `send_OTA_CMD_CALC_LOAD_REGION_CRC`
- `send_OTA_CMD_CALC_LOAD_REGION_CRC32`
- `send_OTA_CMD_ECHO`
- `send_OTA_CMD_ECHOimp`
- `send_OTA_CMD_ERASE_LOAD_REGION`
- `send_OTA_CMD_GET_ATB_VALUE`
- `send_OTA_CMD_GET_BATTERY`
- `send_OTA_CMD_GET_FILESYSTEM_INDEX`
- `send_OTA_CMD_GET_FILESYSTEM_TABLE`
- `send_OTA_CMD_GET_FILESYSTEM_TABLE_327`
- `send_OTA_CMD_GET_IMAGE_VERSION`
- `send_OTA_CMD_GET_IO_LEVEL`
- `send_OTA_CMD_GET_RSSI`
- `send_OTA_CMD_GRS_STATUS`
- `send_OTA_CMD_GRS_STATUS2`
- `send_OTA_CMD_HANDOVER`
- `send_OTA_CMD_HANDOVER_imp`
- `send_OTA_CMD_HANDOVER_try3`
- `send_OTA_CMD_IOCTL_Flash_Erase_4K`
- `send_OTA_CMD_IOCTL_Flash_Get_CRC16`
- `send_OTA_CMD_IOCTL_Flash_Get_RDID`
- `send_OTA_CMD_IOCTL_READ_MAX_LEN`
- `send_OTA_CMD_LOAD_MORE`
- `send_OTA_CMD_MORE_FRAME`
- `send_OTA_CMD_READ_CUST_INFO`
- `send_OTA_CMD_READ_I2C`
- `send_OTA_CMD_READ_MP_DATA`
- `send_OTA_CMD_READ_NVDS_DATA_BY_ID`
- `send_OTA_CMD_REBOOT`
- `send_OTA_CMD_REBOOT_AND_POWERON`
- `send_OTA_CMD_SET_IO_LEVEL`
- `send_OTA_CMD_SET_LED`
- `send_OTA_CMD_SET_LOAD_INFO`
- `send_OTA_CMD_STORAGE`
- `send_OTA_CMD_STORAGE_READ`
- `send_OTA_CMD_STORAGE_WRITE`
- `send_OTA_CMD_TEST_MODE`
- `send_OTA_CMD_UPDATE`
- `send_OTA_CMD_WRITE_I2C`
- `send_OTA_CMD_WRITE_MP_DATA`
- `send_OTA_MODE`
- `send_REMOTE_CREATE_CONNET`
- `send_REMOTE_GET_CONNECT_STATUS`
- `send_REMOTE_GET_MODE`
- `send_REMOTE_SET_MODE`
- `send_REMOTE_SET_MODE_imp`
- `send_RF_TEST_CMD_RF_FCC_TX_Test`
- `send_RF_TEST_CMD_RF_TX_TEST_END`
- `send_RF_TEST_CMD_RF_TX_TEST_START`
- `send_ReadReg`
- `send_TOUCH_command`
- `send_TX_DG_CREATE_CONNECT_EX`
- `send_TX_DG_DISCONNECT_EX`
- `send_TX_DG_GET_CONNECT_STATUS_EX`
- `send_TX_DG_GET_CONNECT_STATUS_EX_IS_SPP_Connected`
- `send_TracerLogPath`
- `send_Tracer_clock_control`
- `send_Tracer_filter`
- `send_Tracer_filter_query`
- `send_Tracer_switch`
- `send_VAD_init`
- `send_VAD_set_axis`
- `send_VAD_start_record`
- `send_WriteReg`

## Public convenience-wrapper inventory

The following 63 unique `AW_*` wrapper names were checked as a
separate layer. Their presence does not guarantee that their hardware-specific
branches accept USB `1532:0552`.

- `AW_3MIC_CTRL_ERROR_AMIC_ONLY`
- `AW_3MIC_CTRL_REFERENCE_AMIC_ONLY`
- `AW_3MIC_CTRL_TALK_DMIC_ONLY`
- `AW_ENTER_DUT_MODE`
- `AW_ENTER_LED_GPIO_TEST_MODE`
- `AW_ENTER_LL_TEST_MODE`
- `AW_GET_BAT_VOLTAGE`
- `AW_GET_CUSTOMER_CHANNEL_DATA`
- `AW_GET_CUST_VERSION`
- `AW_GET_CUST_VERSION_SMALLEST`
- `AW_GET_CUST_VERSION_SMALLEST_UINT`
- `AW_GET_CUST_VERSION_UINT`
- `AW_GET_GPIO_LEVLE`
- `AW_GET_IMAGE_FILE_VERSION_SMALLEST`
- `AW_GET_IMAGE_FILE_VERSION_SMALLEST_UINT`
- `AW_GET_REMOTE_CONNECT_STATUS`
- `AW_GET_REMOTE_MODE`
- `AW_GET_RSSI`
- `AW_GET_USB_CUST_VERSION`
- `AW_GET_USB_FW_VERSION`
- `AW_GET_USB_FW_VERSION_MXIC`
- `AW_GET_VERSION`
- `AW_HID_ENTER_DFU_MODE`
- `AW_MIC_CTRL_NORMAL_DUAL_MIC_PROCESS`
- `AW_MIC_CTRL_PRIMARY_MIC_ONLY`
- `AW_MIC_CTRL_REFERENCE_MIC_ONLY`
- `AW_MIC_NR_ENABLE`
- `AW_MMI_DELETE_PAIRED_INFO`
- `AW_MMI_FACTORY_RESET`
- `AW_MMI_HEAR_THROUGH_OFF`
- `AW_MMI_HEAR_THROUGH_ON`
- `AW_MMI_POWER_OFF`
- `AW_MMI_RESET_SIDE_TONE`
- `AW_POWER_OFF`
- `AW_READ_BD_ADDRESS`
- `AW_READ_EDITION_ID`
- `AW_READ_I2C`
- `AW_READ_MODEL_ID`
- `AW_READ_MP_DATA`
- `AW_READ_MXIC_DEVICE_INFO`
- `AW_READ_PRODUCT_TYPE`
- `AW_READ_SN`
- `AW_READ_TEST_STATION_INFO`
- `AW_REBOOT`
- `AW_RF_TX_TEST_END`
- `AW_RF_TX_TEST_START`
- `AW_SET_GPIO_LEVLE`
- `AW_SET_HID_DEVICE_NAME`
- `AW_SET_HID_PID`
- `AW_SET_HID_VID`
- `AW_SET_LED_MODE`
- `AW_SET_REMOTE_MODE`
- `AW_SPK_EQ_ON_OFF`
- `AW_USB_REBOOT`
- `AW_WRITE_BD_ADDRESS`
- `AW_WRITE_EDITION_ID`
- `AW_WRITE_I2C`
- `AW_WRITE_MODEL_ID`
- `AW_WRITE_MP_DATA`
- `AW_WRITE_MXIC_DEVICE_INFO`
- `AW_WRITE_PRODUCT_TYPE`
- `AW_WRITE_SN`
- `AW_WRITE_TEST_STATION_INFO`

## Authorized native sidetone probe

The user explicitly requested testing native sidetone with the software filter
disabled. Audio status confirmed `sidetone.enabled=false`, no loaded sidetone
filter and no pending restart. No audio restart or microphone/volume change was
needed. After validated E0/E3/E6 checks and remote-route setup, family-6 `72`
returned a correlated acknowledgment with status `00` and one-byte value `00`.
One `70 01` request returned correlated status `01`. The SDK's
`ResReadInfo.isOTACmdOK` accepts both `00` and `01`; the initial generic probe
incorrectly marked `01` as rejection. No resend was made. A subsequent GET
still returned `00`. This is gain readback, not an enable-state getter.

Both sessions restored local routing with `E1 00` and verified `E0 00`; E3
confirmed the link remained connected. The user reported no audible sidetone. A subsequent `70 00` disable request
returned accepted OTA status `01`, closing the experiment with native
disable requested and the software filter still off. No gain setter (`71`) was sent because the
gain scale and bounds are unresolved. The negative listening result does not distinguish zero gain, an inactive
audio path or a feature unsupported by this model. The setters forward internal
commands 102 and 103 to external ROM at `0x1ffb1e5a`; their gain semantics
are absent from the extracted image and SDK. Do not classify this as a
validated native sidetone implementation. None of these experimental commands is installed in the CLI,
plasmoid or driver.

### Android sidetone gain scales

A further source inspection found concrete scales, but in distinct Android
protocol implementations rather than the tested family-6 command `71`:

- `MicSidetoneVolumeWriterMapper.mapFromEntity` converts a UI percentage to
  `round(percent * 255 / 100)`. The corresponding reader converts the unsigned
  byte back with `round(raw * 100 / 255)`. P3 uses state `98 00 01` and volume
  `99 00 01`; P4 has its own protocol envelopes.
- `V2MicSidetoneProviderImpl` initializes a slider range of 0 through 15,
  remembers a nonzero value (initially 1), and handles zero according to the
  configured `SidetoneType`. This is a separate provider path.
- The BlackShark V3 volume writer rounds the UI value directly, rather than
  applying the percentage-to-byte conversion.

The Barracuda X `t3` device manager has no sidetone provider references. Neither
these UI ranges nor the generic Airoha `AirohaSidetoneInfo.level` short establish
the scale or audible support of family-6 `71` on USB 1532:0552. A prior `72`
reply of zero is gain readback, not an enable-state getter. No additional gain
setter or hardware listening test was performed during this inspection.

### Exact stored sidetone format

The offline [DSP parameter analysis](DSP_PARAMETER_ANALYSIS.md) recovered the
exact table schema and decoded the captured flash: `SideToneGain` has four bits
and stored value 9, while `SideToneEna` is 0. This establishes the stored 0..15
representation, not a decibel scale, the runtime setter range or a successful
sidetone implementation. No additional device probe was performed.

### Authorized repeat with gain 9

The user requested another native sidetone test after the exact stored DSP
schema was decoded. The software sidetone filter was absent before and after
the test, and the user confirmed readiness with the microphone unmuted.
The HID driver was temporarily paused to avoid competing route transactions;
USB audio remained bound. An attempted interface-only rebind failed before
any sidetone command and restored the original binding. The subsequent
module-pause session completed normally.

After E0 local, E3 connected and E6 diagnostic-transport checks, the test
selected the headset route, sent the validated read-length setup and queried
`72`, which returned `00`. Exactly one `71 09` gain setter and one `70 01`
enable setter each returned accepted OTA status `01`. GET `72` still returned
`00` immediately after the gain setter and after the 20-second listening
window. The user reported **no audible sidetone**.

Cleanup sent `70 00` and `71 00`, each acknowledged with accepted status `01`.
The latter restores the byte returned by the initial query; because selector
11 is unresolved and the getter can ignore internal failure, this is not proof
that the original effective DSP gain was restored. Local control routing was
verified with E0 `00`, E3 remained `01`, and the original HID driver binding
was restored. No headset power-off, firmware write or audio restart occurred.
Capture and scripts are retained under ignored `private/scratch/`, including
`sidetone-gain9-result.json`.

The stored gain hypothesis did not produce audible sidetone in this test.
Acknowledgments establish accepted requests, not an applied DSP parameter or
an active monitoring route. The result does not establish that every native
sidetone scenario is unsupported. No further gain escalation was performed.
