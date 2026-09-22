# Barracuda X HID observations

These are empirical observations, not an official Razer protocol specification.
The monitor supports the Barracuda X (2022) dongle identified as USB `1532:0552`
(model observed: `RZ04-04430-100`, product: `Razer Barracuda X 2.4`).

## USB and HID interfaces

The observed composite device has audio-control interface 0, audio-streaming
interfaces 1 and 2, and HID interface 3. Audio uses `snd-usb-audio`; HID uses
`usbhid`. HID interrupt endpoints are OUT `0x03` and IN `0x84`, with 64-byte
packets. The monitor sends only the validated E3 connection query to the OUT endpoint.

The HID descriptor exposes report ID 1 with 63-byte vendor-defined input/output
payloads and report ID 2 for media controls. Linux includes the report ID as byte 0
of the input buffer. Device-node numbers are not stable: find the device through
`/sys/class/hidraw/*/device/uevent` and match
`HID_ID=0003:00001532:00000552`.

## Play/pause button

Physical-device testing on 2026-09-22 confirmed that a short press of the headset's
power/play button sends HID report ID 2 through the USB dongle:

| Action | Complete observed report |
| --- | --- |
| Press | `02 00 02 00 00` |
| Release | `02 00 00 00 00` |

Three short presses produced three matching press/release pairs in a read-only
hidraw capture. Bit 1 of byte 2 (indices include the report ID) corresponds to the
descriptor's consumer Play/Pause usage. Linux exposes `KEY_PLAYPAUSE` (164) in the
device's input capabilities. End-to-end playback toggling was also confirmed by
the user on the physical headset.

The desktop handles this media key and forwards playback control to its selected
media player. Barracuda Status does not translate or inject media keys. These
report-ID-2 frames are not wireless-link evidence and are ignored by its link
parser. Capturing them requires no output command or monitor restart.

This validation covers single short presses only. Descriptor entries for other
media controls do not establish which button gestures generate them.

## Validated link report

Indices are zero-based and include the report ID:

| Buffer bytes | Observed meaning |
| --- | --- |
| 0..4 | `01 80 0E 50 49`, link-report prefix |
| 5..10 | Variable data; do not infer link state from these bytes |
| 11..15 | `04 00 20 02 01`, observed link-report marker |
| 16 | `00`: no link; `01`: link active |

Example reports (remaining bytes omitted):

```text
01 80 0E 50 49 08 F7 0D 32 69 00 04 00 20 02 01 00
01 80 0E 50 49 08 F8 4C 70 69 00 04 00 20 02 01 01
```

Later captures showed byte 10 equal to `03`, so it is not a constant.
Unknown values at byte 16 must be ignored. Validate the frame before reading it.

A different report also arrives around power transitions:

```text
01 80 0C 50 49 0E F5 00 00 00 00 02 00 E3 01 00 00
```

Its byte 16 is not the link field described above. Treating all report-ID-1 frames
as equivalent caused a connected headset to be incorrectly marked disconnected.
Later firmware and hardware analysis identified this E3 frame: its connection
value is byte 14, not byte 16. The monitor now validates and accepts this format.

## Battery and charging notifications

Physical testing on 2026-09-22 identified additional PI type-8 messages arriving
through the dongle with the headset connected. Their inner payloads are:

| Payload | Observed meaning |
| --- | --- |
| `21 02 01 VV` | Battery percentage; observed decimal 54 through 58 |
| `2a 02 01 01` | Charging cable connected during the test |
| `2a 02 01 00` | Charging cable removed during the test |

For a complete, single-report message, validate bytes 0..5
(`01 80 0e 50 49 08`), bytes 11..12 (`04 00`), and bytes 14..15 (`02 01`)
before reading selector byte 13 and value byte 16. The tunneled PI message is
14 bytes long. General handling must reassemble stream chunks first; the
research also observed other short replies split across HID reports.
Reject percentages outside 0..100 and unknown charging values. Neither message
is wireless-link evidence or an audio-routing trigger.

The initial 54% agreed with the headset's own battery-voltage table and a remote
voltage query. Connecting the cable produced `01`; removing it produced `00`.
Behavior at full charge, startup-state queries and update timing are unvalidated.
Missing notifications mean unknown/stale telemetry, not 0% or not charging.
These observations are not yet implemented in the monitor. See
[battery research](FIRMWARE_ANALYSIS.md#battery-voltage-percentage-and-charging-research)
for query framing, raw values and validation limits.

## Initial state and limitations

Repeated physical power transitions confirmed the observed `00`/`01` link field.
The dongle may emit no unsolicited report while its state remains unchanged.
A standard Linux `HIDIOCGINPUT(64)` request returned a zero-filled buffer during
local testing and did not establish initial link status. The E3 query described below now resolves startup state on the tested device.
The app starts unknown and waits for a validated response or transition.
USB presence and audio sink availability are not substitutes for link evidence.

## Read-only diagnostics

```bash
lsusb -d 1532:0552
cat /sys/class/hidraw/hidrawN/device/uevent
od -An -tx1 /sys/class/hidraw/hidrawN/device/report_descriptor
hid-recorder /dev/hidrawN
```

Replace `hidrawN` with the node matching the vendor/product identity. Keep capture
files outside tracked source, and document whether observations came from hardware
or simulated tests.

## Firmware research

See [firmware and protocol findings](FIRMWARE_ANALYSIS.md) for architectures,
outer command handlers, tunnel framing, GET_REPORT flow control and diagnostics.
E3/E6 connection queries were checked with the headset on and off. The app uses
E3 for initial status. An explicitly authorized diagnostic test also confirmed a
USB response to the family-6 RSSI getter (`0x32`). Local dongle queries returned
fixed values, while temporarily directing diagnostics to the headset returned
changing signed RSSI fields. Calibration and freshness remain unverified; see
the firmware findings for routing, restoration and capture details. This getter
and destination changes are not used by the monitor.

The powered-on test returned `e3 01` and `e6 1b`; powered-off returned `e3 00`
and `e6 00`. The monitor sends only E3 on opening the device, with a maximum of
three attempts two seconds apart, stopping after valid status. Failed writes
or timeouts leave state unknown and preserve passive monitoring. E6 is not used.
