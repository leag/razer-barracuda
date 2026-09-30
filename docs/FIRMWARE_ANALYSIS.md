# Firmware and protocol findings

These are reverse-engineering observations for Barracuda X (2022), USB
`1532:0552`, not an official protocol specification. The USB bridge uses
8051/MCS-51 code; its companion uses Andes NDS32. Addresses below are specific
to the analyzed build and must not be assumed valid for other revisions.

References to the monitor in historical experiments describe the former tray
application. The current userspace components are the `barracuda-pair` CLI
(`barracuda_pair` module) and a read-only Plasma output widget. The widget
sends no HID commands. UI/package changes do not alter these recorded captures
or authorize additional queries; see [architecture](ARCHITECTURE.md).

## Current application and driver behavior and validation

The driver sends the E3 connection query when binding
the dongle, at most three
times two seconds apart, stopping after a valid status. Failed queries leave
status unknown and passive reading continues. The battery queries documented in
[DKMS.md](DKMS.md) are the driver's only other commands. No firmware, pairing,
memory-write or restart commands are used by the driver. The separate CLI pairs
only on explicit request; see [the pairing sequence](PROTOCOL.md#pairing).

| Query | Headset on | Headset off |
| --- | --- | --- |
| E3 | `01` | `00` |
| E6 | `1b` | `00` |

Both queries returned in approximately 7–8 ms during hardware validation,
without requiring a new power transition during each capture. The driver uses E3;
individual E6 bit meanings remain unresolved. Startup was also checked after
installation. USB replug and alternate Bluetooth-mode semantics still require
broader hardware validation. The USB RSSI getter returns changing signed values
when directed to the headset, while the local dongle route returns fixed values.
See the RSSI investigation below for validation and remaining limits.

The reconstructed E3 request is a 64-byte HID report:

```text
01 80 06 50 41 0e SS 01 e3 <zero padding>
```

`SS` is the request sequence. A valid response contains the PI type-14 payload
`e3 00` or `e3 01`; acknowledgments alone do not establish connection state.
See [protocol observations](PROTOCOL.md) for exact validation offsets.

## Headset power-off through the vendor MMI channel

Static review of the vendor library identified `AW_POWER_OFF(true)`, which
routes to the headset and sends family `07`, payload `08 00 02`
(`APP_MMI_POWER_OFF_PRESS`). An explicitly authorized physical test subsequently
confirmed power-off on the Barracuda X (2022), with user observation and validated
link-loss reports. No command acknowledgment arrived. The local diagnostic route
was restored and verified afterwards. See [the exact sequence and validation
limits](PROTOCOL.md#explicit-headset-power-off-diagnostic).

This establishes the observed command's effect, not a complete static trace of
its companion-firmware handler. The library also exposes reboot, pairing-data
clear and factory-reset operations; they were not executed or validated by this
test and remain outside the application and driver command set.

## Static research coverage

All ten entries of the analyzed bridge's outer dispatch table were identified.
The complete tunneled protocol and radio transport have not been decoded.
The following sections record static findings; statements about unconfirmed
fields do not supersede the E3/E6 hardware results above.

## HID reports

The normal descriptor is at bridge offset `0x5d64`, length `0x67` (103 bytes),
SHA-256 `b381e314320ff7377067b739d9dfda8d30f407856d533fb52b32739ab11b37f2`.
A second 40-byte vendor-only descriptor starts at `0x1ced`; it is a separate
configuration, not the normal combined vendor/media descriptor.

| Report ID | Direction | Payload excluding report ID |
| --- | --- | --- |
| `1` | Input and output | 63 vendor-defined bytes |
| `2` | Input | 4 bytes of consumer-control bits |

Report 2 assigns bits 0..2 of the first payload byte to volume up, volume down
and mute. Bits 0..2 of its second byte represent scan previous track,
play/pause and scan next track. Bit 0 of its third byte represents voice command;
remaining descriptor bits are padding. These are descriptor semantics, not a
claim that every headset gesture generates every listed usage.

For report 1, define `q` as the **63-byte payload after the report-ID byte**:

```text
Linux buffer:  [01] [q0: opcode] [q1: length] [q2 ... q62: data]
```

The dispatcher uses `q0`. The receive callback at `0x50bb` checks report ID 1 at
an internal event offset `+6`, then passes the payload at `+7` to `0x26e7`.
These event-structure offsets are not additional bytes to put on the USB wire.
Ordinary outer replies are queued with report ID 1 and 63 payload bytes by
`0x298d -> 0x41ed`. The tunnel command `0x80` is explicitly excluded from that
immediate-reply path.

## Complete outer dispatch table for this build

The table starts at **`0x26f7`** and terminates with default handler `0x2976`.
Names in the following table are analyst descriptions, not original symbols.

| Opcode | Handler | Statically established behavior |
| --- | --- | --- |
| `0x01` | `0x2719` | Fixed identification/version-like reply: `q1=3`, `q2..4=01 02 18`. Meaning of the three version-like bytes is not established. |
| `0x40` | `0x2736` | Fixed reply: `q1=1`, `q2=1`. This is not evidence of a wireless-link query. |
| `0x41` | `0x2744` | If request `q2==0`, sets XDATA `0xc12b=1`; replies with `q1=0`. The main loop can subsequently select mode `0x48` and restart the bridge. |
| `0x42` | `0x2783` | Uses `q2` as a Boolean to disable/enable internal audio/control paths and modify interrupt/peripheral flags. Replies with `q1=0`. Exact user-facing mode semantics remain unknown. |
| `0x43` | `0x27ed` | Returns a 28-byte snapshot of bridge RAM flags and peripheral registers (`q1=0x1c`); layout below. |
| `0x44` | `0x2898` | Replies with `q1=0`, then schedules timer/event 8 with count `0x14`; event 8 calls the restart routine `0x4f6c`. Timing units are unconfirmed. |
| `0x80` | `0x2756` | Queues `q1` bytes beginning at `q2` for the companion processor. No ordinary immediate reply; separate flow-control and input-report paths apply. |
| `0xc2` | `0x28ab` | Reads XDATA starting at little-endian address `q2 | q3<<8`; requested count in `q4`, accepted up to 61 bytes. Replaces `q2...` with bytes read and sets `q1` to the count; larger requests return count zero. |
| `0xd1` | `0x28ff` | Writes `q4` to XDATA address `q2 | q3<<8` only when the address high byte is at least `0xf0`; returns `q1=1`, `q2=readback`. Rejected address returns count zero. |
| `0xd2` | `0x2947` | Reads one byte at the same address format/range check; returns `q1=1`, `q2=value`, or count zero for a rejected address. |

An unrecognized opcode reaches `0x2976`, which returns:

```text
q0 = FE, q1 = 01, q2 = original opcode
```

The trailing bytes of fixed-size replies are not necessarily cleared by each
handler. Consumers must use the returned length rather than interpret padding.
No checksum validation is visible in this outer dispatcher. That does not establish
checksum requirements for protocols carried inside the `0x80` tunnel.

The memory/register commands and restart paths above are **not suitable for
speculative live probing**. Even register reads may have hardware side effects.
The static analysis did not invoke any of them.

### Opcode 0x43 snapshot layout

Offsets here refer to `q`, excluding the report ID:

| Payload offset | Source |
| --- | --- |
| `q2` | Internal RAM byte `0x15` |
| `q3`, `q4` | Internal RAM `0x09`, `0x0a` |
| `q5`, `q6` | Internal RAM `0x0d`, `0x0e` |
| `q7` | Internal RAM `0x14` |
| `q8..23` | XDATA `0xc000..0xc00f` |
| `q24`, `q25` | Registers `0xfc21`, `0xfc22` |
| `q26`, `q27` | XDATA `0xc193`, `0xc192` |
| `q28`, `q29` | XDATA `0xc215`, `0xc214` |

There is no demonstrated mapping from one of these fields to the headset's current
wireless link. Do not replace the app's or the driver's unknown state with an inference from them.

## Tunnel and flow control

### Host to companion processor

Handler `0x2756` passes the payload to `0x52fc`, which writes a 256-byte ring at
XDATA `0xc91d + index`. `0xcbd3` is the producer index and `0xcb7f` the consumer.
Routine `0x4ee1` drains it to the peripheral register at `0xf400` when status
register `0xf405` permits transmission. The peripheral behaves like a serial FIFO;
its exact hardware name is not required to establish the forwarding behavior.

The bridge records `0x42` (`B`) if fewer than 62 ring slots are free, otherwise
`0x4f` (`O`), and marks a pending flow-control response. The transport has at most
61 inner-data bytes per normal 64-byte HID report. There is no visible length
clamp in the tunnel handler itself; this is not permission to send longer frames.

### Why HIDIOCGINPUT returned zeros

At `0x3606`, the USB setup path special-cases request type `0xa1`, request `1`
(GET_REPORT), and input-report type `1`, dispatching to **`0x5035`**.
That routine places one of these values in the first returned byte:

- `00`: no pending flow-control result;
- `42` (`B`): bridge transmit ring is busy;
- `4f` (`O`): ring has room.

The pending flag is cleared after a non-busy result. The return length is capped
at 64 bytes. This path does **not** rebuild a normal asynchronous headset-state
report; the rest of its buffer must not be interpreted as such.
This explains the earlier zero-filled `HIDIOCGINPUT(64)` observation without
requiring a broken device or a missing HID permission.

### Companion processor to host

Routine **`0x2b8a`** parses the incoming serial stream. It synchronizes on `50 49`
(`PI`). For ordinary frames it buffers a 10-byte header and takes a little-endian
payload length from inner offsets 8 and 9. Those bytes and the following payload
are forwarded through a ring via `0x56c3`. Type `0x11` takes a separate internal
control path; it is not equivalent to the observed headset-status frames.
A particular type-1 response with first payload byte `0x11` is also consumed
internally instead of forwarded by the ordinary path.

Routine **`0x3f87`** drains the host-facing ring into reports:

```text
01 80 N <N inner-stream bytes> <zero padding>
```

`N` is at most 61. Thus a long inner message can span reports, and a short read
may contain stream chunks rather than exactly one semantic message. A general
protocol decoder needs reassembly; the driver's stream decoder reassembles
chunks before validating messages, while the app recognizes short observed
status frames only.

For the previously captured link report:

```text
01 80 0E 50 49 08 F9 BD 92 5C 03 04 00 20 02 01 00
         |----------------- 14 inner bytes ----------------|
```

The bridge establishes `0x0e = 10-byte header + 4-byte inner payload`. The final
inner payload is `20 02 01 00`; repeated physical transitions associated its final
byte with link state. The bridge itself does not assign it link semantics.
The other observed report (`PI`, type `0x0e`, length 2, payload `e3 01`/`e3 00`)
uses the same outer tunnel but a different inner message type.

The inner header's bytes 3..7 are preserved by the bridge; naming them sequence
or timestamp requires companion-firmware evidence. They must not be treated as
confirmed link fields from bridge analysis alone.

## Link state and retained development diagnostics

The companion image retains the diagnostic format string
`MMI STATE :%s ->%s , bt_link_connected=0x%02x` at file offset `0x44124`
(XIP address `0x1fc2e414`). This is more than an isolated string: the state-change
routine at `0x1fc12d3c` loads its address and passes the old state, new state and
connection byte to a logging routine at `0x1ff98898` (call at `0x1fc12d6c`).
The logging destination and whether output is enabled on production hardware
remain unresolved; this does not establish a USB-accessible debug console.

The six-pointer table at file offset `0x44190` (`0x1fc2e480`) gives these state
names in index order:

| Value | Firmware name |
| --- | --- |
| 0 | OFF |
| 1 | CONNECTABLE |
| 2 | PAIRING |
| 3 | LINKBACK |
| 4 | CONNECTED |
| 5 | STREAMING |

The state byte is accessed relative to the NDS32 global pointer at `GP + 80428`
(`GP + 0x13a2c`). The logged `bt_link_connected` byte is at `GP + 80432`
(`GP + 0x13a30`). These are **displacements, not absolute memory addresses**, and
are in the companion processor, not the bridge's XDATA address space.

Routine `0x1fc12acc` establishes that the connection byte is a **bitmask**:
when event byte `+5` equals 2 it sets bit `1 << event[4]`; when it equals 0 it
clears that bit. It is not a signal-strength measurement. The relationship of each
bit to Bluetooth profiles, peers or the headset's wireless link has
not been established. Do not equate this mask directly with the observed HID
`20 02 01 <state>` notification.

On a state change, the code stores the new state at `0x1fc12d88` and calls
`0x1fc155fc`, which allocates an internal message, stores the state at message
byte `+4`, and queues it. Following that queue and the tunneled command handlers
is a useful next step toward determining whether the host can retrieve state.
No complete HID request for these variables has been recovered.

### Signal strength: what was and was not found

Searches of the T3 companion image's ASCII and UTF-16 strings did not locate
`RSSI`, `rssi`, `Rssi`, `link_quality`, `tx_power`, `RX_POWER` or `dBm` labels.
This is negative search evidence, **not proof that radio telemetry is absent**:
measurements could be unnamed, stripped, handled by ROM, or contained in the DSP
image whose architecture remains unresolved.

The string `signal` at file offset `0x45660` occurs beside `call`, `roam`,
`service`, `battchg` and other hands-free-profile indicators. That context does
not support interpreting it as the dongle-to-headset radio strength.

Bridge command `0x43` exposes internal diagnostics, but none of its 28 bytes is
confirmed RSSI or link quality. The final pairs (`0xc192/0xc193` and
`0xc214/0xc215`) also occur in the USB audio-control request path around `0x301a`,
including control-selector 2 handling. This supports an audio-control/volume
interpretation, not a radio-strength label; complete field semantics remain open.

### USB RSSI getter: static trace and authorized hardware test

On 2026-09-22, further analysis of the vendor host library and the T3 companion
located an implemented RSSI getter. This supersedes the earlier uncertainty about
whether any RSSI-related command exists on this USB path. It does **not** yet
establish usable radio measurements.

The analyzed `AWToolLIB2.dll` has SHA-256
`8b313d47472fb5f8113571912fbf2f7d6355ec2132652bb767e9b706b3c89f32`.
Its `DeviceObj.send_OTA_CMD_GET_RSSI` sends family `6`, selector `0x32`,
and interprets four response bytes as signed values named `Left_AP_RSSI`,
`Right_AP_RSSI`, `Left_PTP_RSSI`, and `Right_PTP_RSSI`. These are SDK names;
their physical meaning for a single Barracuda headset is not established.

Static trace in the analyzed firmware:

1. The family-6 branch at `0x1ffc94b0` takes the local route through
   `0x1ffc1e8c` to `0x1fc2ba48`, subject to the existing routing mode.
2. Selector `0x32` reaches `0x1fc2bc08`, calling `0x1fc2affa`.
3. That getter initializes its four-byte result from `0x1fc2fd30`
   (`80 80 80 80`), then reads a structure returned by
   `0x1ffc1e18 -> 0x1fc07480`
   (base `GP + 45380`). Depending on bit 0 of `GP + 47480`, it reads offsets
   109, 111, 108 and 110, or duplicates offset 109 into the first two fields.
   Some byte stores still use unresolved EX9 instructions.
4. It passes four result bytes and success status zero to `0x1fc2a480`.
   That serializer places status at inner offset 12 and data at offset 13.

The user explicitly authorized diagnostic queries after static review. The exact
getter sent was this 64-byte, zero-padded HID report:

```text
01 80 07 50 41 06 SS 01 00 32 <zero padding>
```

Unlike family 14, family 6 uses a **two-byte little-endian payload length**
(`01 00`). The live response, with sequence/header fields abbreviated, was:

```text
01 80 11 50 49 01 HH TT TT TT TT 07 00 06 RR 00 00 00 80 80
                                             |  |-----------|
                                          status four values
```

Here `RR == SS | 0x80`. The inner PI message has type 1 and payload length 7:
family, correlated sequence, status, then four data bytes. Validate all these
fields and the complete declared length before decoding. An ordinary three-byte
acknowledgment is not an RSSI result.

Three initial queries, three seconds apart, returned success and the identical
data `00 00 80 80` in approximately 5 ms. Signed decoding gives
`0, 0, -128, -128`. These must **not** be displayed as measured dBm or converted
into signal bars: sentinel/default values are a hypothesis, and calibration,
freshness and correspondence to the active headset link remain unverified.
The routing getter `E0` returned `00` (local); no routing setter was sent.
E3 reported connected before and after these queries.

A follow-up capture took 20 further readings at three-second intervals while
the user moved away from the dongle and returned. All 20 correlated replies
contained the same `00 00 80 80`; E3 confirmed connection at both ends and no
link-transition report was captured. Distance and exact movement times were not
measured, so this is an informal physical test, not a calibrated attenuation
experiment. It provides no evidence that these fields track the active link's
strength in the current local mode. The `80` initialization supports, but does
not prove, the unavailable/default-value interpretation.

These initial tests used only the local route. The remote-route test below
supersedes the hypothesis that the same fixed values would apply to the headset.
The complete producers and freshness conditions of the structure fields,
including external ROM/EX9 code, remain unresolved.

For comparison, family-14 `LQ_GET_QUALTY` (selector `03`, vendor spelling)
returned only its correlated success acknowledgment, with no quality event in
the three-second observation window. That matches its exclusion from the
recovered `0xe0..0xf1` selector table at `0x1fc1cd8c`; it cannot supply RSSI
merely because the generic SDK implements a decoder for it.

During those local tests the monitor was not restarted or modified, and no mode, pairing, firmware, register or audio-setting
command was sent. Raw captures and vendor-derived artifacts remain outside the
public source tree. This research does not add RSSI polling to the monitor or the driver.

### Remote headset route: changing RSSI values

The vendor `AW_HID_OTA.AW_GET_RSSI(bool is_headset)` selects the diagnostic
destination before issuing the getter. Thus the initial local reads did not
measure the headset's own RSSI fields. A subsequent authorized experiment
selected the headset destination briefly and restored the original route.

Static review established the scope of the destination selector:

- Family-14 `E1` at `0x1fc1ce1a..0x1fc1ce44` stores the requested byte in
  volatile `GP + 76962` if `GP + 76960 == 2`, otherwise stores zero; its
  remaining visible work is diagnostic logging and common cleanup.
- The family-6 dispatcher checks that byte and the existing connection state
  at `0x1ffc94b4..0x1ffc94be`; with a remote destination it forwards through
  `0x1fc1cd7a` instead of calling the local getter.
- Family 14 itself stays local, allowing `E0` to verify the destination and
  `E1 00` to restore it without a working remote reply.
- The host library only needs to create a connection when the existing remote
  transport is unavailable. The test required E6 bit `0x08` already set and
  never sent connection-creation commands or the library's extra IOCTL setup.

The destination reports, padded to 64 bytes, are:

```text
01 80 07 50 41 0e SS 02 e1 01 <padding>  select remote diagnostics
01 80 07 50 41 0e SS 02 e1 00 <padding>  restore local diagnostics
```

This is a **temporary diagnostic destination change**, not a read-only query.
The test used a fixed command allowlist, correlated responses, bounded timeouts
and a `finally` restoration path, then checked E0 readback and E3 link state.
This alone does not authorize adding mode changes to the monitor or the driver.

Physical-device results on 2026-09-22:

| Stage | Result |
| --- | --- |
| Before test | E0 `00`, E3 `01`, E6 `1b` |
| Local RSSI | `00 00 80 80` |
| Remote selection readback | E0 `01` |
| Three remote RSSI replies | `c8 c8 80 80`, `cc cc 80 80`, `ce ce 80 80` |
| Signed first two fields | `-56`, `-52`, `-50` respectively |
| Restored destination | E0 `00` |
| After restoration | Local RSSI `00 00 80 80`, E3 `01` |

All three remote results were complete, successful, sequence-correlated
family-6 responses, arriving approximately 12–14 ms after their requests.
One local response in this capture was split into tunnel chunks of 16 and 1
bytes. The probe reassembled the PI stream before checking lengths or fields;
even short responses must not be assumed to fit a single HID report.
The first two fields changed, while the last two remained
`80`. Equal first/second fields do not prove two separate antennas or radio
measurements: the SDK supports stereo products, and the analyzed local getter
can duplicate a single field. Units, calibration and update cadence have not
been established, so report signed RSSI values without labeling them calibrated
dBm. No firmware, pairing, register, audio-profile or volume changes were made.

### Remote RSSI during a walk through the home

The user then explicitly started a walk through the home while a bounded capture
took 30 remote RSSI readings at approximately two-second intervals. This used
the same preflight checks, temporary destination selection and verified
restoration as the preceding test.

| Observation | Result |
| --- | --- |
| Successful correlated remote readings | 30 of 30 |
| Signed RSSI range, first two fields | -93 to -74 |
| Median signed RSSI | -85 |
| Last two fields | `80 80` throughout |
| Query response latency | Approximately 10–275 ms |
| E3 before and after | `01` (connected) |
| Final E0 readback | `00` (original local destination restored) |
| Local RSSI after restoration | `00 00 80 80` |

The earlier short remote test returned -56, -52 and -50. The substantially more
negative, varying readings during the walk support interpreting the remote
fields as live received-signal telemetry rather than fixed placeholders.
This was not a calibrated distance test: positions, obstacles, orientation and
return time were not recorded. It does not establish an absolute dBm scale,
distance conversion, audio-dropout threshold, or RSSI update cadence. Query
latency is diagnostic round-trip latency, not audio latency.

Raw reports and a reassembly-validated numerical summary are retained in the
ignored research directory. No application or driver behavior was changed.

## Battery voltage, percentage and charging research

The same authorized remote-destination procedure was used for family-6
`CMD_GET_BATTERY` (`0x31`). The host API names this value `AW_GET_BAT_VOLTAGE`
and decodes the first two data bytes as an unsigned little-endian integer.
The SDK's percentage-conversion routine takes this value as millivolts.
The local firmware branch at `0x1fc2bbfc` calls getter `0x1fc2af7e`, which
obtains a value from `0x1ff9fa24` and returns a four-byte result. The remote
headset replies also contained four bytes, with the last two zero in these tests.

```text
01 80 07 50 41 06 SS 01 00 31 <padding to 64 bytes>
```

With the cable reported disconnected, three remote readings returned
`fa 0e 00 00`, `fa 0e 00 00`, and `f7 0e 00 00`: 3834, 3834 and 3831 mV.
After the user connected the cable, readings were `4a 10 00 00` and twice
`47 10 00 00`: 4186 and 4183 mV. These are voltage measurements, not direct
percentages or independent proof of charger status. Local dongle readings
were 309 or 150, demonstrating why the diagnostic destination matters.
Each active test restored E0 to `00` and verified E3 `01` afterward.

### Device-specific voltage table

A read-only family-6 `CMD_READ_CUST_INFO` (`0x40`), ID `05`, returned a
104-byte battery-settings block from the headset. The vendor SDK takes ten
little-endian 16-bit voltage points from offsets 44..63 for its 279/281/327
layouts. The returned points were:

```text
3301 3380 3466 3549 3715 3798 3881 3964 4047 4130  (mV)
```

The query is:

```text
01 80 08 50 41 06 SS 02 00 40 05 <padding to 64 bytes>
```

The SDK linearly interpolates each interval in ten-percentage-point steps;
3831–3834 mV maps to approximately 54 by that algorithm. Its generic routine
returns a special negative result above the top point, rather than a valid
percentage. Do not invent a 100% endpoint, extrapolate, or use the elevated
charging voltage as an immediate percentage. Prefer the headset's own battery
notification when available. The firmware's settings-read branch at
`0x1fc2b5e8` locates and copies the requested configuration block into a response;
no settings-write command was sent.

### Passive notifications when the charging cable was connected

A separate read-only HID capture observed these PI type-8 payloads when the
user connected the charging cable, while diagnostic routing was still local:

```text
2a 02 01 01
21 02 01 36
```

The second payload's final byte is decimal 54, matching the independently read
voltage table estimate. Subsequent reports increased to 55, 56, 57 and 58 during
the cable-connected observation, paired with `2a 02 01 01`. This supports
identifying `21 02 01 <value>` as reported battery percentage and
`2a 02 01 <value>` as a charging/power-related indication. When the user removed
the cable, the capture received `2a 02 01 00` at elapsed 113.203 seconds,
following repeated `01` reports while plugged in. This validates the observed
plugged/unplugged transition, but does not yet distinguish active charging from
external power at full charge. The final percentage report was 58.
These are not the
SDK's generic MMI family-7 charger-state messages; do not reuse those enums.

### Candidate charge-complete field in the vendor SDK

Static inspection of the vendor host library found a separate PI type-7 MMI
decoder. For its 279-family layout, subtype `09` at inner offset 10 carries a
charger-state byte at offset 11; value `05` is named `TR_CHARGER_COMPLETE`.
Its all-state decoder also reads a charger-state byte at inner offset 21.
The analyzed T3 companion has a type-7, 37-byte snapshot producer at
`0x1fc17216`, but its exact charger field and safe trigger are unconfirmed.
The candidate trigger path calls external routines with unknown effects, so this
is not a validated read-only query for the Barracuda.

At the headset's green full-charge LED, a 150-second read-only capture across
two charging-cable cycles received only PI type-8 `2a 02 01 00` and
`2a 02 01 01` messages. It received no type-7 MMI message or new battery
percentage. Earlier passive charging captures at 54–58% also contained no
type-7 message. Thus no observed dongle field distinguishes charge completion
from cable presence. A future passive capture spanning the actual LED change
could test whether a type-7 event appears at that transition; the SDK enum alone
cannot justify reporting 100% or a full-charge status.

### Why the reported percentage may stop at 99

The analyzed dongle images contain no producer for the `21` (percentage) or
`2a` (cable) type-8 payloads. The three 4-byte type-8 producers found in the T3
companion (`0x1fc161e6`, `0x1fc16292`, `0x1fc162c4`) include the `20` link
notification, whose value comes from `GP + 76499`; none loads `0x21` or `0x2a`.
The `0x21`/`0x2a` immediates at `0x1ffc21ea`/`0x1ffc22b0` in the patch image are
indices in a ROM-patch registration table, and the `battchg` string is a
Bluetooth HFP indicator name. The percentage is therefore most likely computed
by the headset firmware and relayed by the dongle. The package contains no
headset image, so that computation could not be inspected.

The vendor SDK's 279/281/327 conversion (`Cust_Image.getBatteryPercent`) maps
the ten voltage points to 0, 10, …, 90%, not 10..100%. Above the top point it
returns `-2` (out of range) rather than 100. With this headset's table, 4130 mV
is 90%, and 3831 mV interpolates to 54%, matching the observed notification.
The final 90–100% must come from other headset logic. Holding 99% until charge
termination would fit the observations, but it is unconfirmed.

The separate 2024 generic-dongle image (`Barracuda X USB`, same vendor SDK, not
T3) contains an external-charger state machine: `EXT_CHG` with `ADPT_IO` and
`EXT_IO` inputs and states `CHG_ST_IDLE`, `CHG_ST_CHARGE`, `CHG_ST_COMPLETE`.
This suggests the SDK tracks charge completion as a distinct state, consistent
with the green LED and `TR_CHARGER_COMPLETE`. The observed `2a 02 01 VV`
payload carries only 0/1 and has not been seen to encode completion.

### Charge-transition capture (in progress)

On 2026-09-23 at 02:06:41 UTC, a read-only capture of the Barracuda hidraw node
was started with the headset charging (LED blinking red) after a brief
discharge. It logs every input report and samples the driver's sysfs status and
capacity every 30 seconds; it performs no HID writes or audio commands. At
start the driver exposed `Charging` and a retained 99%. During the first six
minutes no input report arrived: the brief discharge did not produce a new
percentage notification, and the 99% remained the last observed value.

The LED transition time was not recorded, so the test should be repeated:

1. Start the capture with the cable connected and the LED blinking red.
2. Record the wall-clock time the LED turns green.
3. Compare reports near that time: a new percentage (99 or 100), a type-7
   message, or a change in the `2a` value.
4. A few minutes after green, remove the cable and keep capturing to see whether
   a percentage report follows.

Only a report observed at the LED transition could justify a full-charge status.

These payloads are not connection reports and must never change link state.

## Practical value of the discoveries

| Discovery | What it enables | Boundary before using it in the driver |
| --- | --- | --- |
| Package branch, sizes and image hashes | Reproduce the analysis on the same firmware and avoid mixing the 2024 and T3 images. | The running device's revision is not established. |
| 8051 bridge and NDS32 companion | Select correct disassemblers and follow USB versus application code separately. | DSP and external ROM code remain unresolved. |
| Matching HID descriptor | Confirm report sizes and media-control bit layout for the observed interface. | Descriptor identity does not prove complete firmware identity. |
| Ten outer command handlers | Classify fixed replies, forwarding, diagnostics, memory access and restart operations. | Static handler recovery is not hardware validation or a complete inner protocol. |
| Fixed reply to `0x40` | Rule out that reply as evidence of headset connectivity. | It must not be used to turn unknown status into connected. |
| `0x43` diagnostic snapshot | Provide exact field sources for future static tracing and comparison with existing captures. | No RSSI field or dependable link query has been identified. |
| Tunnel `0x80` and `PI` framing | Build a future offline decoder with lengths and stream reassembly. | Inner header bytes and most message meanings are still unknown. |
| GET_REPORT flow-control path | Explain the zero-filled startup query and distinguish transport readiness from wireless state. | It cannot solve initial unknown status by itself. |
| Observed four-byte link notification | Keep the driver tied to the frame validated by physical transitions. | Other tunneled frames cannot reuse its byte offsets blindly. |
| MMI state names and live logging call | Locate a concrete state machine and an internal event producer for further analysis. | Debug transport and host access are unconfirmed. |
| `bt_link_connected` bitmask updates | Distinguish connection membership from an RSSI/quality measurement. | Individual bit meanings and relation to the wireless link remain unresolved. |
| Family-6 `0x32` RSSI getter with remote diagnostic routing | Retrieve changing signed RSSI fields from the headset through USB. | Local results are fixed; physical units, freshness and production-safe routing coordination remain unvalidated. |
| Register writes and restart handlers | Recognize commands that could alter or interrupt the device. | No register-write or restart command was executed. |

## Additional command inventory and native sidetone

See [the command implementation review](COMMAND_REVIEW.md) for the named SDK
command inventory, implementation boundaries and recovered sidetone handlers.
An explicitly authorized live probe returned family-6 `72` gain `00` and a
correlated OTA status `01` for `70 01` (enable). The SDK accepts OTA statuses
`00` and `01`. An acknowledgment does not establish audible operation; gain
units, bounds and persistence remain unvalidated. The user reported no audible
effect; a subsequent `70 00` disable returned accepted OTA status `01`. Local routing
was restored and verified after each probe; no gain setter was sent.
