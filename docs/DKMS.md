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

This copies only module sources to `/usr/src/hid-barracuda-0.1.3`, builds and
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

The driver sends only the validated E3 connection query, at most three times,
two seconds apart. Battery percentage and cable state come from passive,
validated notifications. No remote diagnostic or firmware commands are sent.

Battery presence follows the validated wireless link, independently of whether
a percentage is available. A missing percentage remains unknown. A cable
connection or battery change may provide the first reading; installing the
driver does not guarantee an immediate value.
The percentage is the last observed reading, retained without a time limit until
a new report replaces it or dongle removal/module reload clears it. It may be
outdated after a long disconnection; it is not a fresh measurement on reconnect.
Silence never establishes disconnection or invalidates an observed reading.
Disconnect and suspend clear cable state; suspend also makes the link unknown,
while preserving the last percentage. Reconnection alone does not confirm charging.
Cable-present below 100% is exposed as charging; cable-absent as discharging.
At 100% with the cable connected, status remains unknown because charge
termination has not been validated. Missing cable state also means unknown.

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
marked as unknown (which consumers must ignore), and may infer
fully charged from 100% even though the driver does not claim charge termination.

UPower/KDE presentation depends on the desktop version and available readings.
The battery has device scope and does not represent the computer's own battery.
The tray application still handles connection indicators and audio routing.

## Removal

Disconnect the dongle, then run:

```bash
sudo modprobe -r hid-barracuda
sudo dkms remove hid-barracuda/0.1.3 --all
sudo rm -r /usr/src/hid-barracuda-0.1.3
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
