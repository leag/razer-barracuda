# Installed dongle flash read

On 2026-10-18, a Barracuda X (2022) USB receiver (`1532:0552`) returned a
complete 1 MiB image through its HID diagnostic tunnel. The private source of
record is `private/firmware-analysis/live-dongle-2026-10-18/flash-00000000.bin`.
It is a raw address-space read, starting at flash address zero, rather than a
firmware file extracted from a host updater. The private directory also retains
the acquisition script and a manifest. Neither the binary nor the script is
distributed with this repository.

| Observation | Value |
| --- | --- |
| Address range | `0x00000000`–`0x000fffff` |
| Size | 1,048,576 bytes |
| SHA-256 | `4ab93db338a1aae0f5458493eb56352b37080e3ddfc94640dd03f27585e8d5d8` |
| Consistency | Two independent full reads matched byte for byte |
| Flash ID reply | `1c 30 14 00` |
| Route query after acquisition | `E0` returned `00` (local dongle route) |

## How the read works

The Linux host opens the receiver's `hidraw` node and sends 64-byte output
reports. Each report starts `01 80 LENGTH`, followed by a `50 41` (`PA`)
frame. The 8051 USB bridge forwards the `0x80` tunnel payload to its companion
processor; the companion interprets family `06` and serves the storage data.
This path does not use the host's USB mass-storage protocol. Family `06`
carries the diagnostic storage command:

```text
50 41 06 SEQ 0a 00 23 01 ADDRESS_LE32 COUNT_LE32
```

`23` is `CMD_STORAGE_READ`. The `01` immediately after it is required for the
local storage read in the analyzed vendor library; omitting it yielded zero
data in the initial experiment. The address and count are little-endian,
four-byte aligned; the acquisition used at most 240 bytes per request. A
successful storage-read acknowledgment is followed by a separate request for
the result:

```text
50 41 06 SEQ 01 00 24
```

`24` is `CMD_MORE_FRAME`. Its reply may span several HID input reports. The
reader appends only the `LENGTH` bytes from each `01 80 LENGTH` envelope,
reassembles the `50 49` (`PI`) frame using its 16-bit payload length, checks
the echoed request sequence and status, then takes exactly the requested
number of result bytes. It repeats this across the 1 MiB range, writes two
separate passes, compares them and hashes the retained copy. These commands
read storage; the acquisition did not erase, write or reboot the dongle.

## What the image contains

The raw image begins with a `WIXP` header at offset `0x4`. The private
packaged `T3_Dongle.bin` has a 32-byte updater wrapper before a 1 MiB payload.
After removing that wrapper, 1,045,330 bytes of the live image match the
packaged payload; 3,246 bytes differ, confined to 4 KiB sectors 0, 1, 153,
235, 241 and 242. This close match supports identifying the read as dongle
storage rather than the headset image. Sector 0 differs in two header bytes;
sector 1 is `MP_DATA`, sector 153 is its identical local mirror, and sectors
241–242 start with `NVDS` signatures and contain paired-device state. Sector
235 differs only in its final 16 bytes, whose meaning remains unresolved.
The MP data includes a device identifier and radio settings in addition to
the address below; those fields have not been fully classified. No write-back
image has been prepared from this capture.

## Receiver address in MP_DATA

The installed image has an `MP_DATA` block at `0x1000`, with an identical 4 KiB
copy at `0x99000`. At offsets `0x105c` and `0x9905c`, respectively, a TLV entry
starts `01 06 00`: vendor type `MP_IDS_BD` and a six-byte value. The vendor
`MP_Struct` parser reads that value as `_bd_addr`, and its display formatter
reverses the stored byte order. The full address and raw bytes are in the
private acquisition manifest; they are omitted here because they uniquely
identify the user's receiver.

The packaged dongle image has a different value in the same field. The live
flash also holds a separate six-byte address twice in NVDS, matching the
previously captured *headset* address from remote GET `0x2e`. The MP_DATA value
is therefore the supported candidate for the receiver's own Bluetooth
address; a live radio-side read has not yet independently confirmed it.

The route response and packaged-image comparison identify the target as the
USB receiver. The capture covers the storage range exposed by this command;
it does not establish that internal 8051 bridge ROM, volatile state or any
inaccessible flash region was included. See [firmware findings](FIRMWARE_ANALYSIS.md)
and [the tunnel protocol](PROTOCOL.md) for the larger device architecture.
