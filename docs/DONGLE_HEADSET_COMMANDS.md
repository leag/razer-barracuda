# Dongle-to-headset command inventory

This is an offline static analysis of the visible application commands that the Barracuda X (2022) dongle,
USB `1532:0552`, can transmit to the headset over its Bluetooth link. No device
was opened and no command was sent while preparing it. It complements the
[firmware findings](FIRMWARE_ANALYSIS.md), the
[command review](COMMAND_REVIEW.md) and the
[installed headset ROM analysis](LIVE_ROM_ANALYSIS.md).

None of the commands below is used by the CLI, the plasmoid or the driver unless
those documents say so. Listing a command here does not make it safe to send.

## Scope and evidence

| Image | Role | Notes |
| --- | --- | --- |
| T3 dongle companion, SHA-256 `81f5485feb54fcc8b026762c8901cef557879fa9a31ac140961bdb81e23535b4` | Sender | NDS32 XIP at `0x1fc00000` (file `0x15d10`), patch at `0x1ffc0000` (file `0x6090`), GP `0x20002000`. Build tag `PRU281A_3.100.2.1.14.1_beta36s01`. |
| Installed headset MCU patch and ROM | Receiver | Patch `0x1ffb0000`, ROM `0x1ff00000..0x1ffb0000` with its EX9 table; see [installed ROM analysis](LIVE_ROM_ANALYSIS.md). ROM tag `PRU279C_2.2.0.1.36.1`. |
| `AWToolLIB2.dll` | Naming only | SDK names for tunnel families and host commands. |

The dongle runs a PRU281A ROM that is not part of any available image. The
captured headset ROM is a different PRU279C build, so it does not resolve the
dongle's ROM calls or its EX9 table (`ITB 0x1ff0aea0`). Consequently:

- The Bluetooth stack (L2CAP, RFCOMM sessions, AVDTP, AVRCP, LMP) is mostly
  invisible on the dongle side. This inventory covers the application layer in
  the XIP and patch images and the RFCOMM framing they call.
- Some dongle EX9 entries were inferred from repeated use in the same builder
  pattern; they are listed under [inferred EX9 entries](#inferred-dongle-ex9-entries).
  Byte positions that depend on an uninferred entry are marked as unknown.
- The installed headset patch, captured ROM range and EX9 table allow receiver
  cross-checks. Their availability does not establish that every receiver or
  downstream DSP effect has been decoded.

Addresses are specific to these builds. Confidence labels are:
**established** (both sender and receiver decoded, or sender plus a hardware
capture), **probable** (one side decoded and the other consistent) and
**candidate** (a decoded encoder without a producer found in these images).

## Transport overview

On the USB `1532:0552` path, the host reaches the headset through the dongle. The 8051 bridge forwards the
`01 80 LEN` tunnel to the NDS32 companion, which owns the Bluetooth link. The SPP senders below converge on the
RFCOMM UIH builder at `0x1fc02492`:

| Address | Function |
| --- | --- |
| `0x1fc02492` | RFCOMM UIH frame: address byte with DLCI, control `0xEF`, two length octets, payload, FCS. Credit-based; seven DLC records of 38 bytes at `GP+78144`. |
| `0x1fc1b934` | SPP application send with credit check and deferred remainder; slots of 16 bytes at `GP+80948`. |
| `0x1fc1bb50` | SPP_Audio link send: link 0 or 1 at `GP+80980` (18-byte records). |
| `0x1fc1c94e` | Tunnel re-framing for relayed host commands on the slot in `GP+76961`. |
| `0x1fc1a154` | HFP AT channel writer (see [channels not used](#channels-examined-and-not-established)). |
| `0x1fc252a0` | OBEX writer for the PBAP client (same section). |

Two RFCOMM channels carry dongle traffic to the headset:

1. The **vendor tunnel channel**, used for host commands routed to the
   headset with `E1 01`. The dongle relays the host's
   frames on it on the selected SPP slot; autonomous SPP_Audio builders are separate.
2. The **SPP_Audio channel**, opened automatically on connection. The dongle
   originates its own control and stream messages on it.

Bluetooth link procedures (paging, profile connection and disconnection) are a
third, lower-level category handled mostly by the missing dongle ROM.

### E6 connection mask

The handler at `0x1fc1ce94` initializes a result byte and combines these sources:

| Source | Visible test | Result-bit confidence |
| --- | --- | --- |
| `GP+46111` (link record `+59`) | Bit 0 | Sets result bit `01` explicitly at `0x1fc1cea8` |
| Same byte | Bit 1 | EX9 416 combines a result bit; likely `02` by branch order |
| Same byte | Short bit-mask instruction at `0x1fc1cebe` | EX9 161 combines a result bit; likely `04` by branch order |
| `GP+76960` | Equals 2 | EX9 244 combines a result bit; likely `08` |
| `GP+80980` (first SPP_Audio record) | Equals 2 | EX9 238 combines a result bit; likely `10` |

Only the first result mask is explicit in the available listing. The remaining
assignments are **probable**, not decoded dongle EX9 instructions. Observed E6
`1b` with a connected headset is consistent with this ordering but does not
prove individual bit meanings. The route sender independently checks
`GP+76960 == 2`; the SPP_Audio sender independently checks its record state
against 2. These tests support the transport interpretation, not using E6 as
wireless-link evidence. Production link state still requires validated E3 or
transition frames as specified in [PROTOCOL.md](PROTOCOL.md).

## Relayed host commands

The relay at `0x1fc1c94e` checks the diagnostic connection state and rebuilds
the outgoing request. Its selector test admits inner families 2 through 9,
with family 6 using a separate two-byte length layout. The visible stores yield:

```text
Family 6:     50 41 06 SEQ LEN_LO LEN_HI PAYLOAD
Other family: 50 41 FAMILY SEQ LEN8 PAYLOAD
```

The initial `50` depends on inferred EX9 503; `41`, family, sequence and length
stores are explicit. The payload is copied from the internal input at `+12`,
with its length calculated from the internal buffer length minus 12. These
internal offsets are not extra bytes to add to a USB report. The completed
buffer is handed to `0x1fc1b934` on the slot held at `GP+76961`.

This recovers forwarding capacity, not a safe allowlist. Family-6 includes
firmware and memory operations as well as getters. Family-7 MMI and family-8
settings can alter headset state. Existing validated USB sequences and their
route restoration requirements remain documented in [PROTOCOL.md](PROTOCOL.md).
Family-14 route commands stay on the dongle rather than taking this relay.

## Autonomous SPP_Audio messages

Offsets in the following table start at the **SPP application payload**, without
HID, PA/PI or RFCOMM headers. `??` means a byte whose store or source remains
unresolved. These opcodes are a separate namespace from family-8 selectors:
SPP `21` below is not the USB battery-percentage GET `21`.

| Payload / length | Dongle builder or producer | Receiver cross-check and confidence |
| --- | --- | --- |
| `01 41 57 69 73 65 10 ...` / 16 bytes | Connection callback `0x1fc1bde6`, send at `0x1fc1bea8` | Headset branch `0x1ffed18c` checks `AWise`, then `+6 == 10`, and reads configuration words at `+12/+14`. **Probable** complete prefix; several dongle byte stores are EX9. |
| `06 00 01 ??` / 4 bytes | `0x1fc1bd40`, send at `0x1fc1bda8` | Headset `0x1ffed484` stores payload byte 1 into per-link record `+2`. **Established** first three sender bytes and receiver store; final byte unknown. |
| `06 01 01 ??` / 4 bytes | `0x1fc1c6cc`, send at `0x1fc1c760` | Same receiver branch; dongle updates its own per-link state before sending. **Established** first three bytes; final byte unknown. |
| Likely `02` / `03` plus arguments / 4 bytes | Alternate paths at `0x1fc1c732` and `0x1fc1bdae` | Opcode store uses EX9 109; exact bytes are not established here. Keep separate from the explicit `06` branches. |
| Likely `10` plus four state bytes / 5 bytes | `0x1fc134b2` and `0x1fc135c4` | Receiver `0x1ffed4d2` uses byte 4 and invokes `0x1ffd7ba0`. Sender opcode depends on EX9; **probable**, without a complete semantic mapping. |
| `21 VV_LO VV_HI` / 3 bytes | `0x1fc1c7d2`; callers include `0x1fc12038`, `0x1fc1374c`, `0x1fc1613e` | Headset `0x1ffed662` combines a 16-bit value and searches its stored volume table. **Probable** layout due to EX9 320/367; not a dB scale. |
| `2e A_LO A_HI B_LO B_HI` / 5 bytes | `0x1fc1c7ac`; callers include `0x1fc120bc`, `0x1fc1213e`, `0x1fc1372c`, `0x1fc16132` | All five sender stores are explicit. Receiver `0x1ffed4f6` processes two 16-bit values through volume tables. **Established** layout and table lookup; physical channel mapping remains untested. |
| `2b VV` / 2 bytes | `0x1fc1c7ea`, called at `0x1fc11f52` | Receiver `0x1ffed7c2` conditionally stores byte 1 at record `+12`, otherwise zero. **Probable** Boolean/control layout; it is not independently established as microphone mute. |
| `31 VV` / 2 bytes | `0x1fc1c7fe`, called at `0x1fc11f88` | Receiver `0x1ffedad6` queues a six-byte family-7 message carrying the opcode and argument. **Probable** layout; downstream effect unresolved. |
| Likely `24 VV` / 2 bytes, sent to both links | `0x1fc1c814`, called at `0x1fc1f5c8` after storing `GP+75774` | Receiver `0x1ffed8dc` stores byte 1 in record `+7` and conditionally calls `0x1ffec120`. **Probable**; opcode and argument stores use EX9. |
| `26 ?? ??` / 3 bytes, sent to both links | `0x1fc1c832`, called at `0x1fc0f21e` | Receiver `0x1ffed90c` packs bytes 1/2 into record `+17`, with conditional work afterwards. **Probable** parameter layout; both argument stores use EX9. |
| Likely `2a 00` / 2 bytes, sent to both links | `0x1fc1c854`, called at `0x1fc15758` | Receiver `0x1ffed87c` stores byte 1 at record `+16` and can invoke a callback. **Probable**; it is not USB cable telemetry. |
| `80 ID_LO ID_HI DATA` / `3 + data length` | `0x1fc1c766`, called by `0x1fc1dac2` | Sender layout is explicit. Observed static callers use IDs `1000` and `1001` on state-mask transitions. Receiver/effect remains unresolved in this inventory. |

The SPP_Audio sender at `0x1fc1bb50` returns without transmitting unless the
selected 18-byte link record and its underlying SPP slot both have state 2.
A global state at `GP+46245 == 2` also inhibits this path. Some builders
broadcast to links 0 and 1, while others use the selected link at `GP+76508`.
None of those slot numbers is a Linux audio sink index.

### Stream packets

The stream producer at `0x1fc1bb9e` accumulates input into a buffer held at
`GP+76940`, then sends through `0x1fc1bb50` at `0x1fc1bc58`. It updates a
packet count, accumulated byte count and a separate 16-bit counter; the visible
code uses a 12-byte prefix before appending data. EX9-dependent stores and the
receiver's stream path prevent a complete packet specification here.

This establishes an application data stream on SPP_Audio. It does not establish
the codec, effective latency, retransmission policy or a way for Linux to inject
that stream. Do not conflate the stream counters with USB query sequences.

### Additional event encoder

The encoder at `0x1fc1c042` maps internal event numbers to outgoing payloads.
Visible immediate opcode loads include `21`, `22`, `23`, `25`, `27`, `28`,
`29`, `51`, `c0`, `c2`, `d0`, `f0` and `f1`. Most opcode stores use EX9 349, so this
is **probable encoder coverage**, not proof that each message has a reachable
producer in normal Barracuda operation. The `f0/f1` paths explicitly copy a
variable payload and send to each link with a nonzero handle; the receiver
branches at `0x1ffedabe`/`0x1ffedaca` forward their contents to
`0x1ffee4cc`/`0x1ffee4ea`.

Notable receiver branches include `2d` saving the current gain values and
substituting `-96` on a nonzero argument, then restoring them on zero
(`0x1ffed9de`), and `c2` calling `0x1ffecfd0` (`0x1ffedab2`). A receiver
branch alone is not evidence that the dongle normally produces that opcode.
These observations do not propose host mute, firmware or diagnostic controls.

## Inferred dongle EX9 entries

The headset's captured table must not be substituted for the dongle's table.
The following interpretations fit repeated builder patterns but remain inferred:

| Dongle EX9 entry | Proposed instruction | Basis |
| --- | --- | --- |
| 320 | `sbi a1, [sp + 5]` | Used after an explicit opcode store at `sp+4` in `21`, `2b` and `31` builders |
| 367 | `sbi a1, [sp + 6]` | Follows shifting the 16-bit argument by 8 in the three-byte `21` builder |
| 349 | `sbi a0, [sp + 16]` | Repeated after opcode loads in the event encoder, before sending from `sp+16` |
| 496 | `sbi a0, [sp + 17]` | Follows loads of argument byte 0 in the same encoder |
| 503 | `movi a1, 80` | Followed by storing `a1` as the first byte of a PA relay frame |

These hypotheses are sufficient to describe probable formats with uncertainty
labels. They do not recover the missing instruction table or prove arbitrary
EX9 expansions elsewhere in the image.

## Channels examined and not established

The HFP writer at `0x1fc1a154` and PBAP/OBEX writer at `0x1fc252a0` are separate
profile paths. The latter also reaches the RFCOMM UIH builder. Their presence
in a generic SDK build does not prove those profiles exchange commands with
this paired headset during USB audio use. No HFP AT or OBEX payload is proposed
as an alternative headset control.

The generic SPP submission paths at `0x1fc21748`, `0x1fc21754`, `0x1fc21d4a`
and `0x1fc226cc` can send buffers supplied by higher layers. They prevent
claiming that direct opcode builders alone exhaust all possible traffic.
Indirect calls, ROM-owned Bluetooth procedures and externally supplied payloads
remain outside a finite inventory of hard-coded XIP commands.

## Reproduction and validation boundary

The retained inputs are the hashed T3 dongle image and the installed headset
backup identified above. The focused sender evidence is in
`private/firmware-analysis/mcu-xip-disassembly.txt`; the installed receiver
listing expands EX9 using the captured headset table. For example:

```sh
python private/rom-research/static/query.py range 0x1ffed03a 0xae0
python private/rom-research/static/query.py range 0x1ffed662 0x90
python private/rom-research/static/query.py range 0x1ffed9de 0x90
```

Dongle listings sometimes render negative branch targets with an extra leading
hexadecimal digit; use the low 32 bits for cross-references. Linear disassembly
also includes tables and data. Searches for direct calls cannot demonstrate the
absence of indirect or ROM producers. All reproduction requires retained
private inputs, which are excluded from public releases.

The unfinished worktree draft stopped inside its E6 table. This completed record
preserves its transport leads, cross-checks visible sender and installed receiver
branches, and marks unrecovered fields explicitly. It does not claim complete
Bluetooth-stack recovery. Remaining research is the dongle's own ROM/EX9 table,
indirect producers, full stream decoding and active receiver/DSP behavior.
Validation for this documentation checked that its code addresses occur in the
retained listings and that its local documentation links resolve. This is static
cross-checking, not a compiled driver test or a physical-device check.
No device was opened to close these gaps, and no production command changed.
