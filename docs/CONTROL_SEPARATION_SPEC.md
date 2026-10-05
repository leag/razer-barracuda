# Separating headset controls from the kernel driver

Status: deferred design. Current work hardens the existing driver interfaces;
no userspace control separation or new arbitration ABI is implemented.

Execution order, dependencies and delivery gates are tracked in the
[implementation plan](CONTROL_SEPARATION_PLAN.md). The
[feasibility record](CONTROL_SEPARATION_FEASIBILITY.md) documents the ownership
limitation found in the first prototype; no production interface is selected.

## Objective

Move USB headset settings and explicit power-off from the Barracuda HID driver
into finite userspace helpers, while preserving native link, battery and jack
reporting. Keep the existing CLI and Plasma workflows and the Bluetooth backend.
The kernel should own Linux device integration; userspace should own explicit
vendor control transactions.

This specification does not claim that a new arbitration ABI will be accepted
upstream. Its feasibility and maintainer review are implementation gates.

## Scope and ownership

| Responsibility | Owner after migration |
| --- | --- |
| Validated wireless-link parsing and initial E3 query | HID driver |
| Passive battery/cable reports and native `power_supply` updates | HID driver |
| Automatic battery, cable and voltage refresh | HID driver |
| Jack availability and sound integration | HID/ALSA drivers; WirePlumber owns routing |
| USB EQ, gaming, DND, standby and Quick Connect | Finite userspace control session |
| Explicit USB power-off | Finite userspace control session |
| Explicit dongle pairing | Existing CLI using the same USB arbitration mechanism |
| Bluetooth settings | Existing userspace Bluetooth session |
| Status display | Existing read-only helper and Plasma widget |

No daemon, autostart entry or background Python monitor is introduced. No changes
to volume, microphone, audio profiles or desktop routing are in scope. Firmware
write, erase, reboot, reset and other unverified commands remain excluded.

## Why a direct hidraw replacement is insufficient

The current `headset_settings` and `headset_poweroff` sysfs operations share
`route_lock` with the driver's telemetry worker. All can select the remote
headset route with E1 and restore the local dongle route afterwards. Uncoordinated
userspace writes could overlap a telemetry request, restore the wrong route or
cause one caller to accept another caller's reply.

The XDG `control_lock` only coordinates cooperating processes for one user. It
cannot exclude a kernel worker or another user. Pairing already uses raw HID;
its interaction with driver requests must also be covered by the migration.

The initial feasibility baseline had startup E3 outside `route_lock`. The
incremental driver hardening now serializes that exchange as well. This fixes
interleaving among kernel transactions, but raw userspace output still bypasses
the mutex; a future migration must cover both paths.

## Existing kernel/userspace precedents

### Logitech HID++ and libratbag

The kernel's `hid-logitech-hidpp` driver implements input integration and native
battery reporting. Libratbag's HID++ backend uses hidraw for device
configuration, including profiles, buttons and DPI. Its source documents the
kernel support needed to transfer HID++ reports through Logitech DJ devices.
This is an established example of a specific HID driver coexisting with
userspace configuration; it does not establish transaction exclusion for the
Barracuda's shared diagnostic route.

Sources: [kernel HID++ driver](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-logitech-hidpp.c),
[libratbag HID++ backend](https://github.com/libratbag/libratbag/blob/master/src/driver-hidpp20.c).

### Valve Steam Controller

The in-tree `hid-steam` driver provides input and battery integration while
supporting clients that communicate through hidraw. It creates a layered HID
client device with a hidraw interface instead of exposing hidraw directly on
the underlying controller interface. Its low-level open/close callbacks count
client opens, and raw requests/output reports are forwarded to the real device.
The driver documents stopping its own commands while a client is open and
removing its input device to prevent duplicate input; input is recreated when
the client closes.

This is a concrete precedent for detecting userspace ownership through the
existing hidraw lifecycle, without a separate lease ioctl ABI. It is not an
exclusive-client lease, nor does it establish crash recovery for Barracuda E1
routing. Barracuda must retain its native link, battery and media-key handling
rather than copying Steam's input-device removal policy.

Source: [in-tree hid-steam implementation](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-steam.c),
especially `steam_client_ll_open`, `steam_client_ll_close`,
`steam_client_ll_raw_request` and `steam_client_ll_output_report`.

## Proposed architecture

A userspace `UsbControlSession` owns framing, response assembly, command
validation and the complete explicit transaction. It obtains device-wide,
file-descriptor-bound ownership before any output. The driver uses the same
arbitration boundary for its own output transactions. The term "lease" below
means this ownership contract, not a commitment to a new ioctl API.

### Preferred prototype: layered hidraw

Evaluate the `hid-steam` pattern first. A driver-managed HID client exposes the
userspace hidraw endpoint; the physical HID interface remains owned by the
Barracuda driver. Client open/close callbacks provide ownership lifecycle hooks,
and output callbacks provide a place to gate forwarding during acquisition,
recovery, suspend and disconnect.

Opening must establish quiescence before application writes are permitted.
Prototype an interruptible ownership transition that completes any active driver
transaction and verifies the local route. Closing the last client reference
initiates bounded recovery before driver queries resume. Opening a read-only
capture also reaches lifecycle hooks: explicitly evaluate whether all client
opens pause driver output and document the effect on telemetry freshness.

Steam's open counter does not itself exclude a second client or associate each
write with an exclusive owner. The prototype must demonstrate a supported way
to reject additional independent clients or provide equivalent transaction
exclusion across users. It must also verify how duplicated/inherited descriptors
and callbacks affect ownership lifetime. Do not assume low-level callbacks
provide file identity or implement these guarantees automatically.

Forward passive input to hidraw while retaining driver parsing and media-key
handling. Match the client endpoint to its physical USB parent using properties;
do not create ambiguous duplicate hidraw endpoints for the same control path.
Determine whether existing HID interfaces suffice before proposing HID core
changes or a new public ABI.

### Conditional alternative: separate lease endpoint

Only if the layered approach cannot meet the contract, evaluate a narrow
per-device character interface with acquire/release operations and a
capability/version query. It does not accept EQ payloads or forward arbitrary
vendor commands. Its naming, ioctl layout and implementation remain subject to
prototype results and maintainer review; this is not the default architecture.

With this alternative, userspace keeps both lease and hidraw descriptors open
for the operation. Ownership must follow the open file description, not a PID
or a persistent sysfs boolean, and recovery starts after its final reference
closes. For either approach, close-on-exec is mandatory and descriptors must
not be inherited by unrelated children.

### Arbitration contract

1. Acquisition verifies the USB identity `1532:0552`, HID interface 3 and the
   association between the ownership endpoint and the physical HID device. Multiple
   adapters require explicit selection or an ambiguity error.
2. Acquisition excludes other leases and waits interruptibly for an active
   driver transaction to complete and restore its route. A nonblocking request
   returns busy. The endpoint reports success only when driver writes are
   quiescent and the local route is verified; incomplete recovery rejects it.
3. While leased, all normal driver writes are deferred, including startup E3
   and telemetry refresh. Input processing, validated link parsing, media keys
   and passive battery reporting continue. Lease ownership does not establish
   connectivity or remove/create a battery.
4. Deferred refresh triggers are coalesced. Startup retries retain the existing
   maximum of three attempts two seconds apart; a lease does not reset the
   attempt budget. Resume work only after release recovery completes.
5. Userspace completes or aborts its operation, restores E1 local mode and
   verifies E0 before releasing ownership. With a separate endpoint, close
   hidraw before releasing the lease descriptor.
6. Release, including an unexpected final close, schedules bounded kernel
   recovery. Recovery excludes both new leases and normal driver writes and
   restores/verifies the local route before re-enabling work. No control SET or
   power-off command is replayed during recovery.
7. Failed recovery leaves control acquisition and remote telemetry disabled
   for that device until a documented recovery boundary, such as USB reprobe.
   Passive input and link reporting continue. It does not synthesize a link
   failure. A confirmed link alone is not sufficient to clear this new failure
   condition unless local-route recovery has also succeeded.
8. Disconnect wakes blocked callers with a device error. Suspend prevents new
   acquisitions and coordinates with the lease; the prototype must define and
   test bounded revocation/recovery before suspend completes. A revoked session
   must terminate without further application writes. Resume re-establishes
   local-route health before accepting another session.

A per-user XDG lock can remain for UI duplicate suppression, but the kernel
lease is the cross-user exclusion boundary for cooperating helpers.

### Limits and feasibility gate

The separate lease endpoint alone cannot stop unrelated programs from writing
an already open hidraw descriptor. It excludes driver traffic and cooperating project
helpers, not arbitrary raw-HID clients. Permissions and documentation must make
that scope explicit. Suspend revocation has the same limitation: a userspace
helper must actually observe revocation and stop writing.

For layered hidraw, forwarded writes must be rejected during recovery or
revocation; test that an application cannot bypass the gate through another
physical-device endpoint. For the separate endpoint, determine whether the
cooperative contract is adequate for kernel lifecycle handling. In both cases,
identify any HID core changes needed for stronger enforcement. Do not claim mandatory write exclusion without demonstrating it. Do
not unbind the driver, reload it, or disable native integration as a shortcut.

If safe arbitration or an acceptable upstream interface cannot be established,
retain the existing serialized controls and stop the migration. A replacement
sysfs flag, fixed sleep, separate userspace lock, or module parameter is not an
acceptable substitute.

## Userspace transaction requirements

### Shared USB session

- Match properties and USB interface identity; never assume a hidraw number.
- Acquire arbitration before any output, including scans, pairing setup and
  route queries. A read-only status request acquires no lease and sends nothing.
- Use a dedicated bounded report reader; support fragmented data and reject
  malformed, oversized and unrelated frames. Drain pre-existing queued input
  before starting a request without discarding driver-side notifications.
- Allocate host sequences consistently within the session. Route-command data
  uses a device counter: require the matching sequence-echoing acknowledgment
  before accepting its data reply. Family-8 GET replies have no separate ACK.
- Validate response selector, operation and length. Unsolicited op-02 settings
  notifications are not GET replies. Review stale and late replies, sequence
  wrap and reader shutdown explicitly; do not assume draining alone proves
  that a reply belongs to the current request.
- Reads are interruptible and bounded. On cancellation, stop new application
  commands, complete bounded route cleanup and join every reader worker before
  releasing ownership. Cleanup errors remain visible alongside the original
  error.
- Preserve unknown, disconnected, missing-adapter and unavailable outcomes.
  Only validated E3 or transition frames establish USB link state. E6, ACKs,
  default output, telemetry and silence do not.

### Settings

Preserve the existing allowlist and value limits from the driver and helper:
GETs `13`, `14`, `15`, `27`, `2c`, `2d`, and SETs `93`, `94`, `95`, `a7`, `ac`,
`ad`. No generic raw-command option is exposed.

Before controls, require a fresh validated E3 `01`, the existing E6 diagnostic
transport bit, and E0 local route. Select E1 remote route, perform the validated
READ_MAX_LEN setup, then execute the requested operation. Track possible route
selection before its acknowledgment so partial failure still causes cleanup.

Verify SET results with a GET without automatic setter retries. Preserve current
EQ band and preset bounds, standby choices and Quick Connect address/gaming
constraints. An acknowledged Quick Connect command does not prove a completed
transport switch. Keep USB and Bluetooth transport selection behavior consistent
with the existing helper.

### Power-off

Preserve explicit confirmation and the `barracuda-power --off` CLI. Require a
fresh confirmed link, validate transport and route, select the remote route,
perform the validated READ_MAX_LEN setup and send exactly one family-7
`08 00 02` payload. Always attempt local-route restoration and verification.

Once the report is successfully written, acknowledgment timeout or interruption
must not trigger another power-off report. Distinguish an unsent request, a sent
request with uncertain physical outcome, and failed cleanup. Do not announce
physical shutdown or synthesize disconnection; status still comes from validated
input. Power-on remains a physical-button action.

### Pairing

Reuse the existing captured sequence and confirmation behavior. Extend the same
USB session arbitration to scan and pairing without broadening discovery or
supported-device claims. The driver's input parser continues observing valid
link frames during pairing. Keep the required post-pairing headset power cycle.

## Compatibility and packaging

Preserve CLI names, English/Spanish messages, widget actions and the finite JSON
request/response interface. Add explicit errors for missing arbitration support,
busy ownership, revocation and failed cleanup; test both languages.

During migration, capability detection may select either the existing serialized
sysfs backend or the new leased userspace backend. An older driver lacking the
lease must never trigger an uncoordinated hidraw fallback. Choose the backend
once per operation; do not retry a partly executed SET or power-off on another
backend. Mixed helper/driver versions must fail clearly.

Grant the intended users access to the layered hidraw endpoint, or to both
hidraw and the separate lease endpoint if that alternative is chosen, using
matching udev rules. Review the broader capabilities granted by raw-HID access;
existing sysfs-only write permissions do not automatically authorize it. Normal
operations must not require sudo. Keep temporary HOME/XDG installation tests.

Remove obsolete power/settings sysfs rules and ABI documentation only when the
replacement is validated and the compatibility policy is documented. The pairing
user installer continues to install pairing only unless helper installation is
explicitly selected. Do not change panels or create session services.

## Implementation stages

1. Prototype layered hidraw ownership using `hid-steam` as the reference.
   Establish lifecycle feasibility, cross-user exclusion and reply isolation.
   Evaluate a separate lease ABI only if necessary, and review the chosen
   interface with kernel maintainers before proceeding.
2. Extract userspace framing/session code using only existing validated
   commands. Keep the legacy backend available during development.
3. Add driver arbitration through the upstream patch series, covering every
   output path and cleanup. Keep patch 1 independently buildable and tested.
4. Implement USB settings and power-off sessions, then migrate scan/pairing to
   the same ownership mechanism. Preserve Bluetooth and read-only status paths.
5. Validate mixed versions, permissions and failure recovery, followed by
   explicitly authorized hardware checks. Update user documentation and packages.
6. Remove patches 3 and 4's control-specific kernel implementation after the
   replacement passes all gates. Regenerate the series and synchronize DKMS
   sources. Keep automatic telemetry and its arbitration dependencies coherent.

Each stage is reviewable independently. Do not remove working control interfaces
before the replacement is ready. Repository changes do not deploy installed
copies; live driver reloads and session restarts require separate authorization.
No patches are sent by email as part of this work, and only the user can add DCO
sign-off. Preserve the required AI-assistance attribution.

## Validation and acceptance criteria

### Hardware-independent checks

- Fake HID transactions cover every allowed control, bounds, malformed and
  fragmented responses, missing/mismatched ACKs, unsolicited data, late replies,
  sequence wrap and interrupted reads. SET verification cannot accept stale data.
- Concurrent telemetry, startup E3, scan, pairing, settings and power-off cannot
  interleave output transactions among cooperating participants. Two users and
  multiple adapters are covered; a busy request sends nothing.
- Layered hidraw checks cover two independent opens, duplicated descriptors,
  read-only captures, blocked/revoked writes, input forwarding and physical
  endpoint bypass. They must demonstrate ownership rather than only count opens.
- Final descriptor close, process termination, unplug, suspend and failed route
  restoration cannot strand active workers or restart writes prematurely.
- Kernel input still handles media keys, link transitions and passive telemetry
  during a lease. Unknown state neither creates nor removes the battery.
- Power-supply reads and the widget status helper send no output. Missing
  outputs/default-device changes do not become link evidence.
- Power-off is never replayed; failed verification never retries a SET. Cleanup
  runs after route-selection timeout and cancellation.
- Qt checks run offscreen with fake audio commands. Installers use temporary
  HOME/XDG locations and mocked commands; package archives contain no private
  data, captures or vendor-derived files.

Run `uv run python -m unittest discover -s tests -v` and
`uv run python -m compileall -q barracuda_pair scripts` for implementation changes.
For C changes, build DKMS with `W=1`, run KUnit, built-in/module `W=1 C=2` and
strict checkpatch as described in [UPSTREAM.md](UPSTREAM.md). Keep versions and
patch-series/source synchronization checks passing.

### Physical-device gate

With explicit authorization, verify controls and GET readback through USB,
one-shot power-off, pairing/power cycle, normal telemetry refresh, passive
reports during control ownership, unplug and suspend/resume. Exercise helper
termination after route selection and confirm route recovery with observed
traffic. Verify normal playback and media keys without changing routing policy.
Keep captures outside tracked source and document which setters were actually
tested. Bluetooth regression checks remain separate.

Migration is complete only when normal telemetry remains functional without a
helper running, controls work through finite userspace sessions, and failure
paths recover or block further operations with an accurate error. Compiled
builds, fake-device tests and live hardware observations are reported separately.

## Alternatives

Moving all active queries into a daemon would simplify protocol ownership but
would change the project's no-monitor design and native telemetry architecture.
Removing active refresh would leave startup percentage and voltage unavailable
until sufficient passive data arrives. Both are outside this specification.

Keeping the current serialized kernel controls is the fallback if the lease
proposal fails its feasibility or upstream review gate. This spec provides no
assumption that OpenRazer integration is required for the migration.

## Related documentation

- [Architecture](ARCHITECTURE.md)
- [Protocol and validated commands](PROTOCOL.md)
- [DKMS telemetry policy](DKMS.md)
- [Native controls and validation limits](AUDIO_EFFECTS.md)
- [Kernel series workflow](UPSTREAM.md)
