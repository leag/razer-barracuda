# Installed headset ROM analysis

This investigation uses the previously authorized, captured headset memory and
flash backup. The analysis itself is offline: no additional device commands,
firmware writes, driver reloads or audio changes were performed. Addresses below
belong to the installed headset code, not the downloaded update or dongle code.

## Inputs and reproduction

The ignored `private/rom-research/` directory retains the backup, raw frames,
verification samples and static evidence. The pristine backup is unchanged.

| Input | Address / extent | Bytes |
| --- | --- | ---: |
| Captured MCU ROM address range | `0x1ff00000..0x1ffb0000` | 720896 |
| Complete installed MCU patch extracted from flash | `0x1ffb0000` | 319216 |
| Raw headset flash | Offset zero | 1048576 |
| Captured EX9 instruction table | `0x1ff0bb54`, 512 entries | 2048 |

Installed MCU patch SHA-256:
`80ffbe7df45157eb1edff19e45bd8fc4a56fa135988d475a92171cc35baee80d`.
ROM capture SHA-256:
`038d915302f822e85ad7605cf3d53d83caab5389929e01e982bc9a8fc7ed3f4c`.

The MCU patch differs from the published image, which contains 318704 code
bytes. Addresses from [the downloaded image analysis](HEADSET_FIRMWARE_ANALYSIS.md)
must therefore be retraced. Size and content differences establish different
images, not an exact installed marketing version.

The installed DSP container occupies the flash slot at offset 348160. Its
142900 declared bytes differ from downloaded `DC.img` only at offsets 14, 15
and 52, all before the code payload. The 142772-byte DSP payload starting at
offset 128 is byte-for-byte identical. Installed DSP container SHA-256:
`89334304758128ae07df85580485962a5cf2d30ac6863ff328de47cdb315076e`.

Radare2 NDS32 listings are retained as `static/rom-listing.txt` and
`static/live-patch-listing.txt`. `static/analyze_live.py` verifies input hashes,
expands EX9 using the captured table, corrects oversized negative branch
targets to 32 bits, decodes the Gaming jump-table entries, checks DSP identity
and generates focused evidence. Run from the checkout:

```sh
python private/rom-research/static/analyze_live.py
```

This script reads existing files only. Its evidence and extracted DSP files
remain private. Linear disassembly contains data and jump tables; those bytes
must not be interpreted as executed instructions. Some short-instruction
operands are poorly rendered by the decoder, so unidentified bitfields are
not assigned speculative names.

## Gaming: a writer exists, but GET reads a separate state

The installed family-8 SET `94` branch at `0x1ffb7438` passes request byte 3
to `0x1ffb558a`. Nonzero becomes MMI event `84`, zero becomes `85`. Neither
branch directly writes the byte returned by GET `14`.

The event follows these calls:

```text
1ffb558a -> 1ffb24d8 -> 1ffe9446 -> 1ffb20a8 -> 1ffd4ed6
```

The dispatcher first calls `0x1ffd4d8a`, which can forward events according to
the state at GP+26697 and the mode at GP+26696. Events 132 and 133 are included
in both mode-specific accepted ranges. When the forwarding handler returns
zero, the dispatcher calls `0x1ffb20ac`; its ROM target `0x1ff83154` simply
returns zero, allowing fallback to `0x1ffd3b58`.

That fallback uses signed little-endian halfword offsets in a jump table at
`0x1ffd3b8c`, indexed by event minus one:

| Event | Target | Call |
| --- | --- | --- |
| ON `84` | `0x1ffd477a` | `1ffd3548(1, 1, 0)` |
| OFF `85` | `0x1ffd4788` | `1ffd3548(0, 1, 0)` |
| Toggle `86` | `0x1ffd4796` | Chooses ON/OFF from the internal flag |

The common routine has an early conditional return involving GP-27526 and a
per-entry field selected through GP+26716. After that guard, ON sets bit 2 of
the word at GP+26720, and OFF clears it. Additional mode, notification and
event paths follow. This is real state-changing code; the command is not
merely a generic enum with no headset implementation.

However, GET `14` at `0x1ffb768a` reads **GP+31716**, not that word's bit 2.
The callback at `0x1ffb3cf2` stores its incoming byte into GP+31716; it also
inspects the internal bit for logging. Another application setter, command
`ab` at `0x1ffb7aa2`, can write GP+31716 as well. Its purpose is not established
here and it is not a proposed alternative command.

Consequences:

- A Gaming writer exists in the installed headset, refuting the narrow claim
  that the firmware contains only a getter.
- This does not prove that writing through the dongle applies Gaming in the
  current radio mode. Forwarding and the common routine have state conditions.
- A SET acknowledgment followed by GET `00` cannot distinguish an unapplied
  event from stale reported state. The captured transaction establishes a
  readback mismatch, not which of these causes occurred.
- The meanings of mode 1/2 and the per-entry guard bit are not yet independently
  established. The configuration-side guard is now mapped to dongle support in
  [the parameter analysis](DSP_PARAMETER_ANALYSIS.md). Calling them Bluetooth/2.4 GHz or declaring Gaming exclusive to
  Bluetooth from these numbers alone would exceed the evidence.
- No measured latency reduction, persistence or safe alternative activation
  method follows from this analysis. Keep the UI experimental.

## Sidetone: the missing ROM route reaches DSP parameters

The installed family-6 handlers are:

| Operation | Handler | Wrapper | Downstream request |
| --- | --- | --- | --- |
| Enable `70` | `0x1ffcf332` | `0x1ffe9780` | DSP command `08`, words `[102, value]` |
| Gain `71` | `0x1ffcf35e` | `0x1ffe9792` | DSP command `08`, words `[103, value]` |
| Read `72` | `0x1ffcf38a` | `0x1ffcf7b6` | DSP command `25`, one word `[11]` |

Enable and gain read an unsigned byte and pass it unchanged. The ROM function
`0x1ffa6706` builds two words, then `0x1ff983a8` allocates a queued message
with command 8, word count 2 and those arguments. EX9 entry 109 selects the
queue at GP-4296; `0x1ff06166` enqueues it. The worker at `0x1ffa0a26` routes
message type 6539 to `0x1ffa092e`, which calls the patched transfer function
through `0x1ffb0fd0`, targeting `0x1fffb89c`.

The recovered SDK names DSP command 8 `CMD_SET_PARAMETER` and command 37
(`25`) `CMD_QUERY`. Selectors 102/103 are arguments to SET_PARAMETER, not
standalone DSP command IDs. Their meanings come from the headset's sidetone
callers, not coincident numeric values in other SDK namespaces.

No gain clamp, percent conversion or decibel mapping occurs along this MCU
path. This establishes byte transport, **not** a supported physical gain range
of 0..255. The exact stored schema now identifies a four-bit `SideToneGain` with stored
value 9 and `SideToneEna=0`; see [the parameter analysis](DSP_PARAMETER_ANALYSIS.md).
The runtime DSP interpretation, audio scenario and resulting sidetone level
remain unresolved. Android sliders belonging to other headset implementations
do not establish that scale either.

The enable/gain handlers return the accepted OTA response after calling their
wrappers; they do not wait for a verified applied effect. Queuing the DSP
request therefore explains how a command can be accepted without proving
audible microphone monitoring.

### Getter limitations

Read `72` issues QUERY selector 11 through `0x1ffa67b4`. That function waits
for internal completion, returns an error on timeout, and copies result words
only after a successful reply. The surrounding helper ignores the return
status. The outer handler initializes the result count at stack offset 3 but
does not initialize the result buffer at stack offset 4 before querying; it
then serializes one byte regardless of the returned count or error.

Thus `00` can be a valid DSP result, but the USB response alone cannot exclude
an unsuccessful internal query with an untouched result buffer. Selector 11's
exact DSP schema is still unresolved. Read `72` must not be treated as an
enable-state getter or a reliable confirmation of applied gain.

## Remaining boundary

The missing MCU ROM routines and EX9 table are now available. The remaining
sidetone boundary is interpretation of the DSP payload and its active audio
scenario. Gaming still needs the forwarding mode, per-entry guard bit and state-reporting
paths resolved;
offline code alone does not supply their live values during the failed test.

This analysis changes no production controls. It does not justify a new gain
slider, blind Gaming retries, a speculative mode switch or firmware writes.
