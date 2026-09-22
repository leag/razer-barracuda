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

This copies only module sources to `/usr/src/hid-barracuda-0.1.1`, builds and
installs for the running kernel, and rebinds only the matching HID interface.
Without `--activate`, reconnect the dongle to activate the installed driver.
DKMS rebuilds for subsequent kernels through the distribution's DKMS hooks.
The installer also installs `99-barracuda-battery.rules`, identifying the
USB sound card as a headset for UPower/KDE. It does not restart the tray app
or issue audio commands.
A changed source tree cannot overwrite an already installed version silently.

## Readings and limitations

The driver sends only the validated E3 connection query, at most three times,
two seconds apart. Battery percentage and cable state come from passive,
validated notifications. No remote diagnostic or firmware commands are sent.

Until both connection and percentage are known, the battery is reported absent
and capacity is unavailable. A cable connection or battery change may provide
the first reading; installing the driver does not guarantee an immediate value.
Telemetry expires after ten minutes without a fresh notification. A silent
adapter never establishes disconnection. Disconnect and suspend clear readings.
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
first precise percentage; the battery remains absent during that interval.
UPower may present its own placeholder percentage while absent, and may infer
fully charged from 100% even though the driver does not claim charge termination.

UPower/KDE presentation depends on the desktop version and available readings.
The battery has device scope and does not represent the computer's own battery.
The tray application still handles connection indicators and audio routing.

## Removal

Disconnect the dongle, then run:

```bash
sudo modprobe -r hid-barracuda
sudo dkms remove hid-barracuda/0.1.1 --all
sudo rm -r /usr/src/hid-barracuda-0.1.1
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
