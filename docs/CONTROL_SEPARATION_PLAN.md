# Control separation implementation plan

Status: deferred in favor of incremental hardening of the current driver.
The [feasibility record](CONTROL_SEPARATION_FEASIBILITY.md) documents why the
migration gate remains open. Production separation steps 2–7 have not started.

## Selected incremental alternative

Keep the existing settings and power-off interfaces. Serialize startup E3 with
telemetry and controls, preserve the three-attempt budget and retry spacing,
require verified local-route state after restoration failure, and allow only
cleanup requests once suspension/removal begins. Pairing's raw-HID arbitration
remains unresolved; strengthen its ACK matching without claiming exclusivity.
The incremental changes and helper deployment are complete. See
[DKMS behavior](DKMS.md) for the implemented boundaries and
[validation results](UPSTREAM.md#current-driver-hardening-validation) for the
unit, build and limited physical checks.

The stages below remain the deferred migration plan, not prerequisites for
these driver fixes.

This plan implements [CONTROL_SEPARATION_SPEC.md](CONTROL_SEPARATION_SPEC.md).
The specification defines the contract; this document defines the work order,
reviewable deliverables and evidence required to advance. A successful prototype
is not evidence of upstream acceptance or physical-device validation.

## Delivery order and gates

| Step | Deliverable | Depends on | Exit gate |
| --- | --- | --- | --- |
| 0 | Baseline and output-path inventory | Existing implementation | Current behavior and compatibility boundaries recorded |
| 1 | Arbitration feasibility prototype and decision record | 0 | Exclusive ownership, lifecycle and reply isolation demonstrated |
| 2 | Shared userspace protocol/session foundation | 1 and interface review | Fake transport tests pass; no unleased output path |
| 3 | Production kernel arbitration in the patch series | 1 and interface review | Every output path participates; per-patch kernel checks pass |
| 4 | Settings, power-off and pairing migration | 2, 3 | All explicit USB operations use the selected backend safely |
| 5 | Compatibility, packaging and UI integration | 4 | Mixed-version and temporary installation checks pass |
| 6 | Authorized physical validation | 5 | Recorded hardware evidence meets the specification |
| 7 | Retire kernel control implementation | 6 and compatibility decision | Regenerated series, documentation and release artifacts agree |

Steps 2 and 3 can be developed independently against the agreed interface, but
must pass integration tests together before step 4 is considered complete.
If step 1 cannot satisfy the contract, stop migration and retain the existing
serialized kernel controls. Maintainer feedback is an external gate: record it
when supplied; do not send patches or messages as part of this plan.

## 0. Establish the baseline

Inspect and record these implementation boundaries before editing code:

| Area | Existing files and entry points | Work to preserve or replace |
| --- | --- | --- |
| USB protocol and pairing | `barracuda_pair/pairing.py`: `Reassembler`, `HidrawTransport`, `PairingSession`, `find_hidraw` | Reuse validated framing and captured pairing sequence; strengthen reply matching and ownership |
| Settings | `barracuda_pair/headset.py`: `attribute`, `exchange`, `dispatch` | Keep validation and JSON behavior; replace USB sysfs transport |
| Power-off | `barracuda_pair/control.py`: `adapters`, `control_lock`, `request_poweroff` | Preserve confirmation and finite CLI; replace USB action transport |
| Kernel traffic | `barracuda_link_query`, `barracuda_request`, route helpers, refresh and sysfs stores | Establish one device-wide arbitration boundary |
| Kernel lifecycle | `barracuda_probe`, `barracuda_stop`, suspend/resume/remove | Coordinate recovery, work cancellation and device lifetime |
| Distribution | `scripts/install.py`, `packaging/arch/PKGBUILD`, udev rules | Install dependencies and permissions for the selected backend |
| Patch integrity | `upstream/hid/`, `tests/test_upstream.py` | Preserve source equivalence and independently valid patch prefixes |

Inventory every output call, its lock, response matcher, timeout, cancellation
path and cleanup responsibility. Include handshake, READ_MAX_LEN, startup E3,
telemetry, settings, power-off, scan, pairing and recovery. Record existing
timeouts and retry budgets rather than inventing new values during extraction.

Resolve two documentation/behavior distinctions explicitly:

- `headset.dispatch(op='link')` is passive; `op='status'` reads device settings
  and currently performs USB transactions. Preserve this distinction so widget
  link/battery polling never opens a control session.
- The specification describes a pairing-only default installer, but the current
  `scripts/install.py` also installs power/settings modules and launchers, and
  `tests/test_distribution.py` expects them. Record the discrepancy and settle
  the intended installation contract before step 5. Do not silently remove
  existing launchers as part of transport extraction.

Run the existing hardware-independent suite and syntax checks as an implementation
baseline. Record failures or skips separately from regressions. No installation,
module reload or physical command is needed for this step.

## 1. Prove the ownership interface

Prototype layered hidraw first using the specification's `hid-steam` reference.
Inspect the selected kernel tree's HID core and hidraw open, release, write and
ioctl paths. Record the kernel commit used for the investigation.

The decision record must answer:

1. Do callbacks run per independent open or only on aggregate lifecycle changes?
   Can they distinguish independent clients and associate writes with an owner?
2. How are a second process, a second user, duplicated descriptors, fork and
   exec handled? Can an already open descriptor bypass ownership or revocation?
3. Does a read-only capture pause telemetry? How does the helper discover the
   correct client endpoint and its physical interface-3 parent?
4. Are both output reports and raw requests gated? Can another exposed endpoint
   reach the physical device without arbitration?
5. Can suspend revoke a session and finish bounded recovery while its file
   descriptor remains open? Can remove free state while callbacks still use it?
6. How are responses from the last kernel transaction kept out of the next
   userspace transaction, and vice versa, including delayed family-8 replies?

Build a minimal concurrency/lifecycle harness, using a simulated HID device or
kernel test seam where practical. Exercise two independent opens, cross-user
access, duplicate/final close, process death, blocked writes, suspend, unplug,
input forwarding and callback lifetime. KUnit state tests alone cannot prove
hidraw file ownership semantics; include tests through the actual endpoint.

Do not accept an open counter as proof of exclusivity. If existing layered HID
callbacks cannot enforce the contract, document the limitation and evaluate the
specification's separate lease endpoint. Specify its cooperative enforcement
limits and suspend behavior. Identify any required HID core changes explicitly.
If neither approach meets the contract, stop at this gate.

Deliver a decision record with the chosen interface, capability discovery,
identity matching, error semantics, state transitions, lock order, bounded
recovery policy, test evidence and unresolved upstream questions. Obtain the
interface review required by the spec before production migration. Do not
assign permanent ioctl numbers or advertise a stable ABI before that decision.

## 2. Extract the shared userspace session

Proposed modules are `barracuda_pair/usb_protocol.py` for framing/parsing and
`barracuda_pair/usb_session.py` for discovery, ownership, reading and cleanup.
Names may change during review; keep Bluetooth independent of this USB session.

First extract reusable pure framing and reassembly with existing pairing tests
still passing. Then implement `UsbControlSession` against an injectable transport,
clock and ownership adapter so faults can be exercised without hardware.

The session must:

- Resolve exactly one supported adapter, validate interface and endpoint identity,
  acquire ownership before any output and use close-on-exec descriptors.
- Bound and interrupt reads, assemble fragments and reject malformed/oversized
  input. Own and join any reader worker before releasing ownership.
- Require the matching ACK before accepting route-command data. The current
  pairing request loop can return a data reply without requiring an ACK; do not
  preserve that behavior in the shared matcher. Data counters are not host
  sequences; family-8 GET has no separate ACK.
- Match selector, operation and length; distinguish notifications from replies.
  Test queued and late replies, sequence wrap and identical repeated requests.
  If a timeout makes reply attribution ambiguous, fail the session rather than
  treating a drain or sequence increment as proof of freshness. Define recovery
  or reacquisition limits in the step-1 decision record.
- Track possible remote-route selection before waiting for its ACK. Cleanup
  attempts E1 local restoration and E0 verification on partial failure as well
  as success, preserving both the original error and cleanup error.
- Expose only the existing supported operations to helpers; provide no generic
  raw-command CLI and no firmware operations.

Add focused `tests/test_usb_protocol.py` and `tests/test_usb_session.py` with
scripted input/output traces and fault injection at each transaction boundary.
Keep the legacy settings/power backend available until integration passes.

## 3. Implement kernel arbitration and recovery

Make C changes through the upstream series, then synchronize the DKMS sources.
Use an explicit state model covering idle, kernel transaction, acquiring,
userspace ownership, recovering, failed recovery, suspended and removed states.
The exact representation follows step 1; document which lock protects each
transition and which contexts may sleep.

Bring startup E3 under the same output boundary as telemetry, recovery and
legacy controls. Acquisition waits interruptibly for a current transaction to
finish and for a verified local route; nonblocking acquisition returns busy
without application output. Legacy sysfs operations must also respect ownership
while both backends exist.

During ownership, keep passive parsing, media keys, power-supply work and jack
reporting active. Defer and coalesce output work without resetting the E3
three-attempt budget or violating its two-second spacing. Do not hold locks
needed by input completion while waiting for a reply, or wait for work while
holding a lock that work needs.

On final close or revocation, gate new writes and perform bounded kernel route
recovery before resuming traffic. Failed recovery blocks new controls and remote
telemetry until the selected recovery boundary; link notifications alone cannot
clear it. Suspend/remove must wake callers, cancel/join work and preserve object
lifetime until all callbacks finish. Recovery never replays SET or power-off.

Extend `hid-razer-barracuda-test.c` for state transitions and fault paths, then
run the endpoint harness from step 1 against the actual implementation. Include
no-output assertions for power-supply reads and unknown-state battery behavior.

Keep patch 1 independently buildable and tested. Place shared prerequisites
before their consumers; do not make patch 1 depend on patch 2's route helpers.
Choose the final arbitration patch position only after the dependency split is
known. Preserve legacy patches 3 and 4 until step 7. Update patch-count assumptions
in `tests/test_upstream.py` whenever the series shape changes, while retaining
source-equivalence and attribution checks.

## 4. Migrate explicit USB operations

Use separate reviewable changes for each operation, followed by integration:

1. **Settings:** adapt `headset.py` to select one USB backend per operation.
   Preserve GET/SET allowlists and value bounds. Require fresh E3 link, E6
   transport, E0 local route, E1 remote and READ_MAX_LEN before controls.
   Verify setters by GET without retrying SET. Preserve Quick Connect's address
   and gaming checks and its uncertain completion semantics.
2. **Power-off:** adapt `control.py` to the shared session. Send the family-7
   `08 00 02` report once, distinguish unsent from sent-but-unconfirmed and
   report cleanup failure separately. An ACK timeout, signal or backend error
   after a successful write must never cause a replay.
3. **Scan and pairing:** adapt `PairingSession` and discovery to the same
   ownership/session mechanism, including handshake and scan setup. Preserve
   captured command ordering, explicit confirmation and post-pairing power cycle.
   Test cancellation during inquiry and route cleanup. Do not leave the old
   direct hidraw path usable concurrently with the new driver.

Extend `test_headset.py`, `test_control.py` and `test_pairing.py` plus shared
session tests. Verify that Bluetooth requests keep their existing transport,
passive link/status polling sends nothing, and no command is replayed on a
second backend after partial execution.

## 5. Integrate compatibility, permissions and packaging

Define and test this capability matrix before changing the default backend:

| Helper / driver combination | Required behavior |
| --- | --- |
| New helper + arbitration-capable driver | Use the agreed userspace backend |
| New helper + legacy sysfs driver | Settings/power may select legacy once, before output |
| New helper + no recognized control capability | Clear unavailable error; no raw-HID fallback |
| Old helper + transitional driver | Legacy controls remain serialized; assess old raw pairing explicitly |
| Old helper + final driver without control sysfs | Clear incompatibility; no claim of supported controls |

Define scan/pairing policy separately for older drivers: legacy sysfs controls
do not serialize raw pairing. Missing arbitration must not silently choose an
unsafe scan/pairing path. Document any resulting compatibility restriction.

Update `i18n.py`, CLI/JSON error mappings and widget handling for busy,
unavailable, revoked, ambiguous adapter and cleanup failure. Test English and
Spanish; distinguish protocol uncertainty from confirmed disconnection.

Match udev permissions to the selected endpoint and physical device, including
interface identity and any virtual-device ancestry. Verify access for intended
users and denial outside that policy. Review existing broad hidraw permissions;
new sysfs permissions alone cannot authorize the replacement. Normal operations
must not require sudo.

Update installer module lists and package contents after resolving step 0's
installation contract. Test temporary HOME/XDG installations, mixed versions and
package archives. Keep DKMS version fields synchronized if changed. Update
README, INSTALL, DKMS, USAGE, TROUBLESHOOTING and UPSTREAM as appropriate without
claiming hardware validation before step 6.

## 6. Collect physical validation evidence

After explicit authorization for deployment and physical operations, test:

- Settings GET and each claimed SET with readback, plus Quick Connect behavior.
- One-shot power-off and its timeout outcome; scan, pairing and required power cycle.
- Startup link resolution and normal automatic telemetry with no helper running.
- Passive link/battery/media input during ownership and deferred refresh afterward.
- Helper termination after E1 selection, verified route recovery, unplug and
  suspend/resume with an active session.
- Playback and media keys while WirePlumber retains routing responsibility;
  Bluetooth regressions separately.

Group authorized runtime updates into one restart where possible. Keep captures
outside tracked files. Record kernel/helper revisions, observed traffic, tested
setters, failures and untested cases. Do not infer physical success from a fake
transport or a compiled module. A failed gate blocks retirement of legacy controls.

## 7. Retire controls and finalize the series

After all gates pass, remove the kernel settings mailbox and explicit power-off
implementation, their obsolete ABI documentation and udev rules. Retain the
validated commands needed for native telemetry and bounded route recovery.
Document the supported helper/driver upgrade combination and rollback to a
matching legacy pair; never use rollback to replay a pending control operation.

Regenerate the HID series and cover letter, synchronize DKMS C sources, update
series tests and UPSTREAM instructions, and validate each remaining patch prefix.
The ALSA jack quirk remains independent of userspace control semantics. Preserve
`Assisted-by: LLM [tools]` attribution; only the user can add DCO sign-off.

## Validation checklist and completion record

For functional changes run:

```bash
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_pair scripts
```

For C changes also run:

```bash
make -C kernel/hid-razer-barracuda W=1
```

Run KUnit with the repository configuration, built-in/module `W=1 C=2` and
`checkpatch.pl --strict` for every patch prefix in an external kernel checkout,
as described in [UPSTREAM.md](UPSTREAM.md). Do not store downloaded kernel trees
or build artifacts in this repository. Report the intentionally absent user
DCO sign-off separately from actionable checkpatch errors.

Use fake audio commands and offscreen Qt for UI tests. The final completion
record must separate unit tests, real endpoint concurrency tests, compiled kernel
checks, temporary installation/package checks and physical-device observations.
List skipped checks and remaining limitations. Mark migration complete only when
finite userspace controls and automatic native telemetry coexist safely, all
failure paths recover or block accurately, and the final series matches DKMS.
