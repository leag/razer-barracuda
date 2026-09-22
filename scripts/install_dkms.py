#!/usr/bin/env python3
"""Install the Barracuda HID battery module; optionally rebind only its HID interface."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

NAME = 'hid-barracuda'
VERSION = '0.1.1'
DRIVER = 'barracuda-battery'
FILES = ('hid-barracuda.c', 'barracuda-protocol.h', 'Makefile', 'dkms.conf')
IDENTITY = 'HID_ID=0003:00001532:00000552'


def run(*command):
    subprocess.run(command, check=True, timeout=300)


def matching_devices(sysfs=Path('/sys/bus/hid/devices')):
    devices = []
    for device in sorted(sysfs.iterdir()):
        try:
            if IDENTITY not in (device / 'uevent').read_text().splitlines():
                continue
            interface = device.resolve().parent / 'bInterfaceNumber'
            if interface.read_text().strip() == '03':
                devices.append(device)
        except (OSError, ValueError):
            continue
    return devices


def activate(devices, drivers=Path('/sys/bus/hid/drivers')):
    # Do not steal interfaces managed by another specialized HID driver.
    for device in devices:
        current = (device / 'driver').resolve().name
        if current not in ('hid-generic', DRIVER):
            raise RuntimeError(f'{device.name} is managed by {current}; no rebind performed')
    run('modprobe', NAME)
    for device in devices:
        old_driver = (device / 'driver').resolve()
        if old_driver.name == DRIVER:
            continue
        (old_driver / 'unbind').write_text(device.name)
        try:
            (drivers / DRIVER / 'bind').write_text(device.name)
            if (device / 'driver').resolve().name != DRIVER:
                raise RuntimeError(f'Binding {device.name} was not confirmed')
        except (OSError, RuntimeError):
            if not (device / 'driver').exists():
                (old_driver / 'bind').write_text(device.name)
            raise
        print(f'Bound {device.name} to {DRIVER}')


def install(source, target):
    if target.is_symlink():
        raise RuntimeError(f'Refusing symlink destination: {target}')
    if target.exists():
        if any(not (target / name).is_file() or (target / name).is_symlink()
               or (target / name).read_bytes() != (source / name).read_bytes()
               for name in FILES):
            raise RuntimeError(f'{target} differs from this checkout. Remove the old DKMS '
                               'version explicitly before installing a changed build.')
        return
    target.mkdir(mode=0o755)
    for name in FILES:
        shutil.copyfile(source / name, target / name)
        (target / name).chmod(0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--activate', action='store_true',
                        help='Rebind the matching HID interface now; USB audio stays bound')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run this installer with sudo or pkexec; it writes /usr/src and installs a kernel module')
    if not shutil.which('dkms'):
        parser.error('Install dkms and the headers for your running kernel first')
    devices = matching_devices() if args.activate else []
    source = Path(__file__).resolve().parent.parent / 'kernel' / NAME
    install(source, Path('/usr/src') / f'{NAME}-{VERSION}')
    run('dkms', 'install', '-m', NAME, '-v', VERSION, '-k', os.uname().release)
    rule = source.parent.parent / 'packaging/99-barracuda-battery.rules'
    shutil.copyfile(rule, '/etc/udev/rules.d/99-barracuda-battery.rules')
    run('udevadm', 'control', '--reload-rules')
    run('udevadm', 'trigger', '--subsystem-match=sound', '--sysname-match=card*')
    if args.activate:
        activate(devices)
    print('DKMS installation complete. No audio commands or monitor restarts were requested.')
    if not devices:
        print('Reconnect the dongle to bind the driver, or activate it when attached.')


if __name__ == '__main__':
    main()
