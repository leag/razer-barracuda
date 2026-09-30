# Native controls over Bluetooth

An explicitly requested test against the paired Barracuda X (BT) confirmed
native customer GETs over its Bluetooth Classic serial service. This is separate
from the [Android BLE transport](ANDROID_ANALYSIS.md#bluetooth-transport) and the
USB dongle's HID envelope. The initial probe sent no setter. Subsequent authorized checks confirmed
reversible setters for EQ preset, Gaming, DND, idle shutdown and custom bands,
restoring their original values. No firmware command, pairing operation,
profile change or audio restart was sent during these Bluetooth checks.

## Transport evidence

BlueZ reports Serial Port service UUID `00001101-0000-1000-8000-00805f9b34fb`.
An SDP ServiceSearchAttributeRequest for that service returned a protocol list
containing RFCOMM channel 6. The request and response were validated and saved
under ignored `private/bluetooth-controls/`. Channel 6 is the observed device's
advertised channel, not a general hardcoded production assumption. SDP discovery
follows the [Bluetooth SIG SDP specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-62/out/en/host/service-discovery-protocol--sdp--specification.html).

The recovered SDK's `DeviceObj.openSPP2` connects to `BluetoothService.SerialPort`
and selects `enableNetworkStreamMode`. Its `write` method sends the command
bytes directly to the network stream. `send_Customer_Data_Channel` constructs
`PA 08 SEQ LEN8 PAYLOAD`. Accordingly, the probe opens an unprivileged RFCOMM
socket on the discovered channel and sends that framing, without the USB
report ID, length prefix or 64-byte padding.

## Validated GETs

| Setting | Customer payload | Observed value |
| --- | --- | --- |
| EQ preset | `13 00 00` | `00`, Default |
| Gaming | `14 00 00` | `00`, off |
| Do Not Disturb | `27 00 00` | `00`, off |
| Idle shutdown | `2c 00 00` | `00`, disabled |

The first complete request was `50 41 08 40 03 13 00 00`.
Its reply was a PI class-8 frame carrying `13 01 01 00`. The other replies
carried their corresponding command IDs, operation 1, length 1 and value 0.
The response counter is independent of the request sequence; the probe matches
the customer command and validates its operation and length. It processes
bounded, possibly fragmented stream responses and stops on a failed query.

Reproduction with a currently paired, connected device address:

```sh
python private/bluetooth-controls/discover_spp.py DEVICE_ADDRESS
python private/bluetooth-controls/read_native.py DEVICE_ADDRESS
```

The scripts, device address and raw frames remain private. They close their
sockets on exit and do not keep a background monitor. `spp-discovery.json` and
`native-get-results.json` preserve the physical-device evidence.

## Limits and plasmoid presentation

The production helper now supports all six UI features over Bluetooth SPP,
including ten custom bands and the known-device list. The plasmoid selects the
transport and Bluetooth address from the current output; it does not use a fixed
sink index or personal address. BlueZ must confirm the supported product name,
paired state and active connection before SDP/channel discovery. Each request
uses the existing user control lock, bounded reads and a socket closed on exit.
There is no background process, reconnect loop or fallback to raw USB HID.

The five setters were physically validated by SET acknowledgment and matching
GET, then restored with matching GET. Original and final snapshots matched.
This establishes applied settings, not measured Gaming latency reduction or
an audible frequency-response measurement. Quick Connect checks that the target
is in the known-source list and Gaming is off; its destination setter was not
physically tested because selecting another host would interrupt this session.
Its UI reports a requested switch rather than a completed connection.

Synthetic tests cover SDP channel discovery, fragmented replies, unsolicited
report rejection, malformed lengths, disconnects, identity restrictions and
absence of USB access on Bluetooth requests. CLI and QML tests cover bounded
setters, readback mismatch, transport/address selection and output changes.
Bluetooth requires Linux Python with Bluetooth socket support and `busctl`.
Use `/usr/bin/python scripts/install.py --audio-controls` for the local helper;
some managed Python distributions omit Bluetooth socket support.

Bluetooth battery reporting already works independently: BlueZ/UPower exposes
`Razer Barracuda X (BT)`, and the KDE power engine reports a connected Headset
battery with percentage 60 and state `NoCharge`. The widget accepts this exact
product name as well as the dongle's product name, preferring the transport of
the current output when both readings exist. Charge state remains unknown for
that Bluetooth sample; the compact row shows its percentage without claiming
charging or full-charge status. Source removal drops the reading.

The Bluetooth overview uses the detailed headset icon, a clean device name and
a Bluetooth transport label. Dongle pairing/power actions remain accessible under More actions for a
Bluetooth output, with labels identifying the required USB dongle. These two
actions still use the dongle transport. These presentation choices do not establish physical
connectivity; battery data and default audio selection remain distinct.

## Bluetooth power-off probe

An explicitly authorized one-shot probe opened the discovered serial service
and sent `50 41 07 42 03 08 00 02`: SDK family 7, MMI operation `08 00`
and `APP_MMI_POWER_OFF_PRESS` (`02`). The SDK sends this frame directly over
SPP; it is not a firmware reboot or erase command. Two preceding attempts
stopped before sending power-off because the EQ preflight query timed out.

The actual power-off frame was sent once. No reply or socket closure was
observed during the four-second observation window, and BlueZ still reported
Connected afterward. Physical power-off was not confirmed by the user, so
Bluetooth shutdown remains unverified and is not exposed by the production
helper. Captures remain under ignored `private/bluetooth-controls/`.
