# Control separation feasibility record

Status: step 0 investigated; step 1 has a reproducible ownership counterexample.
The production migration is blocked at the interface gate. Steps 2–7 are not
implemented. Existing controls and the upstream patch series remain in place.

This record accompanies the [implementation plan](CONTROL_SEPARATION_PLAN.md)
and [specification](CONTROL_SEPARATION_SPEC.md). It does not establish that
userspace controls are impossible; it establishes that the proposed unmodified
Steam-style callbacks do not supply the required ownership contract.

## Baseline and traffic inventory

Repository baseline: `1bff657`, with the implementation-plan documentation in
the working tree. The hardware-independent suite passed all 104 tests, and
`compileall` passed for `barracuda_pair` and `scripts` before implementation.

There are two direct kernel output sites, both `hid_hw_output_report`:

| Path | Serialization and reply handling | Timing and cleanup |
| --- | --- | --- |
| `barracuda_link_query` | Startup worker; outside `route_lock`; sends E3, with validated link input processed separately | Up to three attempts, two-second delay; initial scheduling after one second; current code reschedules only after a full output write; no route change |
| `barracuda_request` | Caller must hold `route_lock`; installs matcher under spinlock; sequence-echoing ACK for route requests, no separate family-8 GET ACK | Two-second reply timeout; interruptible except bounded route restoration |
| `barracuda_refresh` | Holds `route_lock`; E6, E0, E1 remote, battery/cable GETs, voltage GET | Link/cable-triggered refresh, 360-second polling; always calls route cleanup after possible selection |
| `headset_settings_store` | Trylocks `route_lock`; fresh E3, route setup, READ_MAX_LEN, allowlisted settings command | Busy sends nothing; cleanup after possible route selection; response mailbox reads issue no command |
| `headset_poweroff_store` | Trylocks `route_lock`; fresh E3, route setup, READ_MAX_LEN, single MMI power-off | Sent request is not retried on timeout/interruption; route cleanup still runs |
| `barracuda_route_end` | Runs under caller's `route_lock`; E1 local followed by E0 verification | Two restoration attempts; records route failure |

The current driver's route-failure flag is cleared by a confirmed link. The
new specification requires verified local-route recovery before reopening
ownership; retaining that old reset would violate the new contract.

Userspace output originates in `HidrawTransport.write` for pairing/scan, or
sysfs writes in `headset.exchange` and `control.request_poweroff`. Pairing's
handshake, READ_MAX_LEN, model read, inquiry start/stop, E5 connect, E6 polling
and E1 local cleanup share one process's session but have no kernel lease.
`PairingSession.request` waits up to three seconds; inquiry restarts every two
seconds. At this baseline, its reply path permitted data before a matching ACK. The
subsequent incremental hardening fixes that matcher without introducing a shared
USB ownership session. Pairing reads are
synchronous; there is no reader worker to join in that implementation.

The per-user control lock does not serialize raw pairing with kernel output.
The migration must cover scan and pairing as well as settings and power-off.
`headset.dispatch(op='link')` is passive; settings `op='status'` performs active
queries. These must remain separate in the UI and backend selection.

The installer currently creates pairing, power and headset launchers; its
installation test expects all three. The pairing-only description in AGENTS,
README and the spec differs from this behavior. No installer change was made;
resolve this contract before packaging migration, preserving current behavior
until then.

## Kernel source examined

The probe used Linux commit
`145c2b2e9a5c0f794fb4009bcb072ab19f8ccfcd`, the kernel revision already recorded
in UPSTREAM.md. Sources were kept outside the repository. Findings apply to
this revision; a later HID API must be inspected and tested again.

- [hidraw.c](https://github.com/torvalds/linux/blob/145c2b2e9a5c0f794fb4009bcb072ab19f8ccfcd/drivers/hid/hidraw.c): `hidraw_open`, `drop_ref`, `hidraw_send_report`, `hidraw_get_report`.
- [hid-core.c](https://github.com/torvalds/linux/blob/145c2b2e9a5c0f794fb4009bcb072ab19f8ccfcd/drivers/hid/hid-core.c): `hid_hw_open`, `hid_hw_close`, `__hid_hw_raw_request`, `__hid_hw_output_report`.
- [hid.h](https://github.com/torvalds/linux/blob/145c2b2e9a5c0f794fb4009bcb072ab19f8ccfcd/include/linux/hid.h): `struct hid_ll_driver` callback signatures.
- [hid-steam.c](https://github.com/torvalds/linux/blob/145c2b2e9a5c0f794fb4009bcb072ab19f8ccfcd/drivers/hid/hid-steam.c): `steam_client_ll_*` forwarding and lifecycle callbacks.

## Layered hidraw result

`hidraw_open` increments the hidraw open count and calls `hid_hw_open` only for
the first open. A second independent file description is accepted without
consulting the low-level callback. HID core also aggregates hardware opens.
Rejecting an additional owner inside `steam_client_ll_open` therefore cannot
reject that second file description.

Normal close reaches the low-level close callback only after all independent
clients have closed. If the first client dies while another keeps its descriptor,
the callback cannot identify that the intended owner died or begin its recovery.
A duplicated descriptor additionally shares its original open file description;
PID checks would neither model this lifetime nor solve inherited descriptors.
Read-only opens use the same hidraw lifecycle, so a capture can keep aggregate
ownership active and defer telemetry indefinitely in a direct Steam-style port.

Raw/output callbacks receive a HID device and report arguments, not the owning
file description. Hidraw passes a `source` value into HID core, but the examined
core passes it to HID-BPF dispatch and not to `hid_ll_driver` callbacks. A
Barracuda low-level callback cannot use that argument to distinguish clients.
A global recovering/revoked flag could reject all forwarded writes, but cannot
choose one authorized client among several accepted opens.

Keeping the physical endpoint hidden and forwarding passive input would still
be necessary, but does not fix the exclusive-owner failure. No Barracuda layered
endpoint was implemented or advertised as supported.

## Reproducible source probe

Run with a trusted external checkout at the revision above:

```bash
uv run python scripts/research/probe_hidraw_ownership.py /path/to/linux
```

The script extracts the checkout's unmodified `hidraw_open` and `drop_ref`
functions and compiles them in a temporary directory with minimal stubs. The
stub hardware-open callback rejects a second owner with EBUSY. Assertions prove
that the second independent open bypasses that callback anyway, that closing
the first client does not invoke recovery, and that disconnect closes hardware
while an open client remains. The program produced:

```text
Second independent open accepted; driver open callbacks: 1
First owner closes; driver close callbacks: 0
Last independent client closes; driver close callbacks: 1
Disconnect closes hardware with a client still open
RESULT: aggregate callbacks do not enforce an exclusive file owner
```

This sequential counterexample is enough to reject exclusivity based solely on
these callbacks. Locks and allocations are stubbed; it does not test kernel
concurrency, cross-user permissions, file duplication, suspend, media input or
real endpoint lifetime. The local UHID endpoint was not accessible to the
unprivileged session, so no simulated endpoint was created. No physical dongle
was opened, module reloaded or audio state changed.

## Separate lease endpoint assessment

A separate character device could give cooperating helpers exclusive ownership
bound to an open file description. Its final release could schedule recovery,
and its acquire path could wait for kernel traffic to finish. That solves
cooperative acquisition but does not automatically control the hidraw descriptor.

Consider a helper that selects E1 remote, then is stopped before processing a
revocation signal. Releasing or revoking its lease does not revoke its separately
open hidraw descriptor. If suspend recovery resumes kernel work, that helper can
later resume and send its queued command. Waiting for its acknowledgement of
revocation has no finite bound when the process remains stopped. The same issue
exists when the lease descriptor closes while another reference to hidraw survives.

A cooperative-only endpoint therefore needs a specified fail-closed policy for
these cases, or a mechanism that gates every output by the actual file owner.
The former may prevent suspend/recovery or keep telemetry disabled; its
acceptability has not been established. A source probe for aggregate opens
cannot demonstrate this alternative safe. No separate ABI is selected yet.

## Decision and work required to reopen the gate

Do not proceed to production migration using an aggregate client counter or a
separate lease assumed to revoke hidraw writes. Retain existing controls as the
specification requires when the ownership contract is not established.

The next design revision must choose and review one of these concrete directions:

1. Extend HID/hidraw ownership hooks with per-open identity, exclusive admission
   and output/revocation enforcement, including raw-request ioctls. This requires
   HID core API design and maintainer review, not just a Barracuda driver change.
2. Develop the separate lease's cooperative failure policy, explicitly deciding
   what happens to suspend, telemetry and reacquisition when a client fails to
   acknowledge revocation. Demonstrate that it satisfies the spec, or revise
   the spec to state the reduced guarantees before implementing it.

For either direction, define capability discovery, USB-parent identity, lock
ordering and lifetime, bounded cleanup, duplicate/fork/exec behavior, and how
stale responses are excluded across ownership changes. In particular, a late
family-8 response lacks a host transaction ID; draining a queue does not prove
that the next response belongs to the next owner.

Required evidence still outstanding: a real simulated-endpoint concurrency and
lifecycle harness, cross-user permissions, suspend/unplug recovery, response
isolation, and interface review. Hardware validation remains a later independent
gate. No upstream acceptance or full implementation is claimed by this record.
