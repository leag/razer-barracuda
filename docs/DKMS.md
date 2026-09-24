# Native headset battery through DKMS

The optional `hid-barracuda` driver binds the physical Barracuda X (2022)
USB HID interface (`1532:0552`, interface 3). It registers a device-scoped
Linux `power_supply`, which UPower and KDE can discover. It is an independent,
experimental driver, not an official Razer driver or an upstream kernel module.
USB audio remains managed by `snd-usb-audio`; hidraw and media keys are preserved.

## Installation

Install DKMS, the headers matching your kernel, and its compiler toolchain.
The Makefile selects LLVM for kernels configured with Clang. From this checkout:

```bash
sudo python3 scripts/install_dkms.py --activate
```

This copies only module sources to `/usr/src/hid-barracuda-0.1.7`, builds and
installs for the running kernel, and rebinds only the matching HID interface.
Without `--activate`, reconnect the dongle to activate the installed driver.
DKMS rebuilds for subsequent kernels through the distribution's DKMS hooks.
The installer also installs `99-barracuda-battery.rules`, identifying the
USB sound card as a headset for UPower/KDE. It does not restart the tray app
or issue audio commands.
A changed source tree cannot overwrite an already installed version silently.
When upgrading an already loaded module, reload it once after installation:
`sudo modprobe -r hid-barracuda && sudo modprobe hid-barracuda`. This clears
telemetry until fresh notifications arrive.

## Readings and limitations

The driver sends the validated E3 connection query, at most three times,
two seconds apart. Battery percentage and cable state come from passive,
validated notifications. Firmware commands are never sent.

On each confirmed link (dongle plug-in, headset power-on, resume), when the
cable state changes, and every `poll_interval` seconds while linked, the driver
asks the headset for its battery percentage, cable state and voltage. Both are
then known without waiting for a change. `poll_interval` defaults to 360 s, like
`bq27xxx_battery`, with a 30 s minimum; 0 disables periodic refreshes:
`echo 600 | sudo tee /sys/module/hid_barracuda/parameters/poll_interval`.
UPower does not show `voltage_now` for this peripheral; read it from
`/sys/class/power_supply/barracuda-*/uevent`. The dongle answers these family-8 GETs only on the
temporary remote diagnostic route, validated on 2026-09-24 (frame layout from
[razer-barracuda-2.4-linux](https://github.com/TarikTopalovic/razer-barracuda-2.4-linux);
see [battery and cable queries](PROTOCOL.md#battery-and-cable-queries)):
- E6 must show the existing headset transport (bit `0x08`), and E0 must read `00`.
- It sends `E1 01` and verifies E0 `01`.
- It sends GET `0x21` (battery) and GET `0x2a` (cable): `PA 08 SEQ 03 PARAM 00 00`.
- It reads the voltage with family-6 `0x31`, exposed as `voltage_now`.
- It always restores `E1 00` and verifies E0 `00`, retrying once. If that fails,
  periodic refreshes stop until the next link.

Replies are `PARAM 01 01 VALUE` and are decoded like the headset's own
`PARAM 02 01 VALUE` reports. The GET returned 100% on a fully charged headset,
whose unsolicited reports had stopped at 99.

Battery presence follows the validated wireless link, independently of whether
a percentage is available. A missing percentage remains unknown. A cable
connection or battery change may provide the first reading; installing the
driver does not guarantee an immediate value.
The percentage is the last observed reading, retained without a time limit until
a new report replaces it or dongle removal/module reload clears it. It may be
outdated after a long disconnection; it is not a fresh measurement on reconnect.
At the headset's green full-charge LED, a live cable removal and reconnection
produced cable-state reports but no new percentage during the remainder of a
three-minute read-only capture. Version 0.1.3 therefore continued exposing the last
reported 99%; it cannot infer 100% from the cable report, and the LED state is
not available through the validated dongle messages.
Silence never establishes disconnection or invalidates an observed reading.
Disconnect and suspend clear cable state; suspend also makes the link unknown,
while preserving the last percentage. Reconnection alone does not confirm charging.
Cable-present below 100% is exposed as charging; cable-absent as discharging.
At 100% with the cable connected, status is full. This is a presentation choice:
the headset never reports termination, and at the green full-charge LED it
held 99. On 2026-09-24, charging while powered on, the LED kept
blinking red for over 15 minutes with the voltage constant at 4200 mV and no
current measurable at the power supply, so the green LED may only appear with
the headset off. Missing cable state means unknown.

Inspect the native device and desktop view with:

```bash
cat /sys/class/power_supply/barracuda-*/uevent
upower --enumerate
upower --dump
dkms status
```

An unknown coarse capacity level keeps UPower discovery available before the
first precise percentage. KDE exposes unknown charge as -1 rather than hiding
a confirmed connected headset. UPower may expose a placeholder percentage
marked as unknown (which consumers must ignore).

UPower/KDE presentation depends on the desktop version and available readings.
The battery has device scope and does not represent the computer's own battery.
The tray application still handles connection indicators and audio routing.

## Removal

Disconnect the dongle, then run:

```bash
sudo modprobe -r hid-barracuda
sudo dkms remove hid-barracuda/0.1.7 --all
sudo rm -r /usr/src/hid-barracuda-0.1.7
sudo rm /etc/udev/rules.d/99-barracuda-battery.rules
sudo udevadm control --reload-rules
```

Reconnect the dongle; the generic HID driver resumes handling its HID interface.

## Validation

The regular unittest suite compiles and runs the actual stream decoder with
AddressSanitizer and UndefinedBehaviorSanitizer. Installer tests use temporary
files and mocked commands, without changing real devices. Compile the module:

```bash
make -C kernel/hid-barracuda
```

Compilation and simulated protocol tests do not establish hardware behavior.
Physical battery reports were validated separately; complete charge behavior
and notification timing remain open questions. See [protocol observations](PROTOCOL.md).

Physical validation on 2026-09-22 with module 0.1.1 and kernel
7.2.6-1-cachyos confirmed discovery while the initial percentage was unknown,
then 68% and discharging after the user unplugged the charging cable.
KDE Solid reported `HeadsetBattery`, present, chargePercent 68, and Discharging.
An earlier build also received 68–69% and charging with the cable attached.
The USB audio interface retained `snd-usb-audio`; the tray process was not restarted.
Suspend/resume, full charge, and future kernel versions have not been physically tested.

Version 0.1.2 separates wireless presence from percentage availability. A passive
power-cycle capture showed valid disconnect/reconnect reports without battery
notifications. Regression tests cover this sequence, retained capacity, cleared
cable state, and connected devices with missing percentage. Live KDE Solid
confirmed presence with unknown percentage after loading the correction.
After loading 0.1.2, holding the charging cable connected produced a fresh 72%
notification. KDE Solid then reported chargePercent 72 and Charging. Briefly
toggling the cable had not produced a percentage report, so cable transitions
must not be treated as a guaranteed request for battery telemetry.
A subsequent user power cycle confirmed absent while off, then present with the
retained 72% after reconnect. KDE Solid also reported 72%. Charging state stayed
unknown until another cable-state notification, as intended; reconnection alone
does not prove that the cable or charging state is unchanged.

Version 0.1.3 removes the arbitrary ten-minute expiry and its periodic worker.
Regression tests cover retained percentage across disconnect and suspend,
replacement by new telemetry, and clearing on driver state initialization.

Version 0.1.7 avoids the deprecated `system_wq` warning on kernel 7.2 when a
cable change brings a refresh forward.

Version 0.1.6 adds `voltage_now`, periodic refreshes (`poll_interval`) and a
refresh after cable changes. A cable report only counts as a change against a
known previous state, so the driver's own GET reply does not re-trigger it.

Version 0.1.5 queries battery and cable state on each confirmed link and shows
full at 100% with the cable connected. Physical GETs returned `21 01 01 64`
(100%) with `2a 01 01 00` unplugged and `2a 01 01 01` plugged in, with the local
route restored each time. Tests cover op-01 replies for battery and cable, the
rejection of op-01 link values, and reply correlation.
