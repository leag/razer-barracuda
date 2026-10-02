"""Explicit headset power control through the driver's serialized interface."""
import argparse
from contextlib import contextmanager
import errno
import fcntl
import os
from pathlib import Path
import sys

from .i18n import set_language, tr

IDENTITY = 'HID_ID=0003:00001532:00000552'


@contextmanager
def control_lock():
    """Serialize this user's pairing and power actions without a daemon."""
    base = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
    directory = base / 'barracuda-pair'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / 'control.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def adapters(sysfs=Path('/sys/bus/hid/devices')):
    """HID interface 3 of each connected dongle, matched by exact USB identity."""
    devices = []
    for device in sorted(sysfs.iterdir()):
        try:
            if IDENTITY not in (device / 'uevent').read_text().splitlines():
                continue
            if (device.resolve().parent / 'bInterfaceNumber').read_text().strip() != '03':
                continue
            devices.append(device)
        except OSError:
            continue
    return devices


def power_attribute(sysfs=Path('/sys/bus/hid/devices')):
    devices = adapters(sysfs)
    if not devices:
        raise OSError(errno.ENODEV, tr('Adapter not detected'))
    if len(devices) != 1:
        raise OSError(errno.EINVAL, tr('More than one Barracuda adapter is connected'))
    attribute = devices[0] / 'headset_poweroff'
    if not attribute.exists():
        raise OSError(errno.ENOSYS, tr('Update the Barracuda driver to enable headset power-off'))
    return attribute


def request_poweroff():
    """Never fall back to unsynchronized raw HID writes or retry shutdown."""
    with control_lock():
        with power_attribute().open('w') as stream:
            if stream.write('1\n') != 2:
                raise OSError(errno.EIO, 'Short sysfs write')


def error_text(exc):
    messages = {
        errno.EACCES: 'Power-off permission denied; install the power-control udev rule',
        errno.EPERM: 'Power-off permission denied; install the power-control udev rule',
        errno.EBUSY: 'Another headset operation is in progress; try again shortly',
        errno.EAGAIN: 'Another headset operation is in progress; try again shortly',
        errno.ENOTCONN: 'The headset link is not confirmed; no power-off command was sent',
        errno.ETIMEDOUT: 'The adapter did not answer; headset state is unknown',
        errno.EIO: 'Power control failed; inspect the headset and reconnect the dongle if needed',
    }
    return tr(messages[exc.errno]) if exc.errno in messages else str(exc)


def main(argv=None):
    parser = argparse.ArgumentParser(prog='barracuda-power', description=__doc__)
    parser.add_argument('--off', action='store_true', required=True,
                        help='request headset power-off; physical button required to power on')
    parser.add_argument('--yes', action='store_true', help='skip the interactive confirmation')
    parser.add_argument('--language', choices=('en', 'es'), default='en')
    args = parser.parse_args(argv)
    set_language(args.language)
    if not args.yes:
        try:
            answer = input(tr('Turn off the Barracuda headset? Use its button to turn it on again. [y/N] '))
        except (EOFError, KeyboardInterrupt):
            return 1
        if answer.strip().lower() not in ('y', 'yes', 's', 'si', 'sí'):
            print(tr('Power-off cancelled'))
            return 1
    try:
        request_poweroff()
    except OSError as exc:
        print(error_text(exc), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(tr('Power control interrupted; check the headset state before trying again'), file=sys.stderr)
        return 1
    print(tr('Power-off request sent. Use the headset button to turn it on again.'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
