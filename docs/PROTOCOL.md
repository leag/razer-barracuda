# Barracuda X HID observations

These are empirical observations, not an official Razer protocol specification.
The monitor supports the Barracuda X (2022) dongle identified as USB `1532:0552`
(model observed: `RZ04-04430-100`, product: `Razer Barracuda X 2.4`).

## USB and HID interfaces

The observed composite device has audio-control interface 0, audio-streaming
interfaces 1 and 2, and HID interface 3. Audio uses `snd-usb-audio`; HID uses
`usbhid`. HID interrupt endpoints are OUT `0x03` and IN `0x84`, with 64-byte
packets. The monitor does not write to the OUT endpoint.

The HID descriptor exposes report ID 1 with 63-byte vendor-defined input/output
payloads and report ID 2 for media controls. Linux includes the report ID as byte 0
of the input buffer. Device-node numbers are not stable: find the device through
`/sys/class/hidraw/*/device/uevent` and match
`HID_ID=0003:00001532:00000552`.

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
The monitor ignores this frame instead of guessing its meaning.

## Initial state and limitations

Repeated physical power transitions confirmed the observed `00`/`01` link field.
The dongle may emit no unsolicited report while its state remains unchanged.
A standard Linux `HIDIOCGINPUT(64)` request returned a zero-filled buffer during
local testing and did not establish initial link status. No reliable active query
has been established for this device. The app therefore starts in unknown state.
USB presence and audio sink availability are not substitutes for link evidence.

## Earlier Windows utility investigation

Static inspection of the local `RazerAudioPairingUtility_v1.12.07_r4.exe` found
`1532:0552` in an AudioWise Barracuda profile. The associated library uses Windows
HID input, output and feature-report APIs. Generic pairing/MMI commands and an OTA
channel-initialization request were found, but they are not confirmed status
queries and must not be sent by this monitor.

The native SDK exports `getAudioWirelessConnectionStatus`; another library exports
`GetWirelessConnectionStatus`. Their existence does not prove compatibility with
this dongle. The former depends on global protocol settings and device type;
its visible use in the inspected utility was for another product family.
Do not load these Windows DLLs in the Linux app or reproduce incomplete command
frames. Any future active-query work requires device-specific traffic evidence.
Proprietary binaries and local detailed research notes are excluded from Git.

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
