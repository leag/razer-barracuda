"""Explicit native headset settings over serialized USB or Bluetooth sessions."""
import argparse
from contextlib import ExitStack
import errno
import json
from pathlib import Path
import secrets

from .control import adapters, control_lock, power_attribute
from .bluetooth import BluetoothSession, headset_presence

FEATURES = {'preset': 0x13, 'gaming': 0x14, 'bands': 0x15,
            'dnd': 0x27, 'standby': 0x2c, 'devices': 0x2d}
PRESETS = [0, 7, 8, 9, 255]
STANDBY = [0, 5, 15, 30, 45, 60]


class HeadsetError(Exception):
    def __init__(self, code, detail=''):
        self.code, self.detail = code, detail
        super().__init__(code)


def attribute():
    # Reuse exact USB/interface matching; the power attribute is not written.
    path = power_attribute().with_name('headset_settings')
    if not path.exists():
        raise HeadsetError('driver-required')
    return path


def exchange(path, payload):
    if isinstance(path, BluetoothSession):
        return path.exchange(payload)
    token = secrets.token_hex(4)
    request = token + ' ' + payload.hex() + '\n'
    with path.open('w') as stream:
        if stream.write(request) != len(request):
            raise HeadsetError('short-write')
    result = path.read_text().rstrip('\n').split(' ', 1)
    if len(result) != 2 or result[0] != token:
        raise HeadsetError('reply-conflict')
    try:
        return bytes.fromhex(result[1])
    except ValueError as exc:
        raise HeadsetError('invalid-response') from exc


def quick_devices(data):
    """Parse the app's bounded length-prefixed device records, without retries."""
    result, offset = [], 0
    while offset < len(data):
        size = data[offset]
        offset += 1
        if size < 8 or offset + size > len(data):
            raise HeadsetError('invalid-response')
        record = data[offset:offset + size]
        if record[0] not in (0, 1) or record[-1] != 0:
            raise HeadsetError('invalid-response')
        result.append({'address': record[1:7].hex(), 'active': record[0] == 1,
                       'name': record[7:-1].decode('utf-8', errors='replace')})
        offset += size
    return result


def read(path, feature):
    data = exchange(path, bytes([FEATURES[feature], 0, 0]))
    if feature == 'devices':
        return quick_devices(data)
    if feature == 'bands':
        if len(data) != 10 or any(v > 10 for v in data):
            raise HeadsetError('unsupported-value')
        return [v - 5 for v in data]
    if len(data) != 1:
        raise HeadsetError('invalid-response')
    value = data[0]
    allowed = PRESETS if feature == 'preset' else STANDBY if feature == 'standby' else [0, 1]
    if value not in allowed:
        raise HeadsetError('unsupported-value')
    return bool(value) if feature in ('gaming', 'dnd') else value


def payload(feature, value):
    if feature in ('gaming', 'dnd'):
        if type(value) is not bool:
            raise HeadsetError('invalid-request')
        data = bytes([int(value)])
    elif feature in ('preset', 'standby'):
        if type(value) is not int or value not in (PRESETS if feature == 'preset' else STANDBY):
            raise HeadsetError('invalid-request')
        data = bytes([value])
    elif feature == 'bands':
        if (not isinstance(value, list) or len(value) != 10
                or any(type(v) is not int or not -5 <= v <= 5 for v in value)):
            raise HeadsetError('invalid-request')
        data = bytes(v + 5 for v in value)
    elif feature == 'devices':
        if not isinstance(value, str) or len(value) != 12:
            raise HeadsetError('invalid-request')
        try:
            data = bytes.fromhex(value)
        except ValueError as exc:
            raise HeadsetError('invalid-request') from exc
        if len(data) != 6 or not any(data):
            raise HeadsetError('invalid-request')
    else:
        raise HeadsetError('invalid-request')
    return bytes([FEATURES[feature] | 0x80, 0, len(data)]) + data


def error_code(exc):
    if isinstance(exc, HeadsetError):
        return exc.code
    if isinstance(exc, TimeoutError):
        return 'timeout'
    return {errno.ENODEV: 'missing-adapter', errno.ENOTCONN: 'unknown-link',
            errno.ENOSYS: 'driver-required', errno.ENOENT: 'missing-adapter',
            errno.EACCES: 'permission-denied', errno.EPERM: 'permission-denied',
            errno.EBUSY: 'busy', errno.EAGAIN: 'busy',
            errno.ETIMEDOUT: 'timeout', errno.EREMOTEIO: 'rejected',
            errno.EIO: 'route-failed', errno.EPROTO: 'invalid-response',
            errno.EAFNOSUPPORT: 'bluetooth-runtime-unavailable',
            errno.EOPNOTSUPP: 'bluetooth-unsupported', errno.ECONNRESET: 'unknown-link',
            errno.ECONNREFUSED: 'bluetooth-unavailable'}.get(exc.errno, 'device-error')


def snapshot(path):
    state, errors = {}, {}
    for feature in FEATURES:
        try:
            state[feature] = read(path, feature)
        except (HeadsetError, OSError) as exc:
            state[feature] = None
            errors[feature] = error_code(exc)
            if errors[feature] in ('unknown-link', 'missing-adapter', 'route-failed', 'busy'):
                for remaining in FEATURES.keys() - state.keys():
                    state[remaining] = None
                    errors[remaining] = errors[feature]
                break
    return {'ok': True, 'state': state, 'errors': errors,
            'transport': 'bluetooth' if isinstance(path, BluetoothSession) else 'usb'}


def uevent(path):
    values = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition('=')
        if separator:
            values[key] = value
    return values


def bounded(values, key, low, high):
    try:
        number = int(values[key])
    except (KeyError, ValueError):
        return None
    return number if low <= number <= high else None


def battery_details(device):
    """Values the driver last published; reading them sends no query."""
    for supply in sorted((device / 'power_supply').glob('razer-barracuda-*')):
        try:
            values = uevent(supply / 'uevent')
        except OSError:
            continue
        status = values.get('POWER_SUPPLY_STATUS', 'Unknown')
        voltage = bounded(values, 'POWER_SUPPLY_VOLTAGE_NOW', 1, 10_000_000)
        return {'percent': bounded(values, 'POWER_SUPPLY_CAPACITY', 0, 100),
                'status': status,
                # The driver reports cable presence as charging or full.
                'cable': {'Charging': True, 'Full': True, 'Discharging': False}.get(status),
                'voltage_mv': None if voltage is None else round(voltage / 1000)}
    return None


def usb_link(sysfs=Path('/sys/bus/hid/devices')):
    """Link state as published by the driver; USB presence alone is not a link."""
    try:
        devices = adapters(sysfs)
    except OSError:
        devices = []
    if not devices:
        return {'adapter': 'missing'}
    if len(devices) != 1:
        return {'adapter': 'multiple'}
    device = devices[0]
    try:
        driver = (device / 'driver').resolve().name == 'razer-barracuda'
    except OSError:
        driver = False
    link = 'unknown'
    if driver:
        # The attribute appears once the driver has confirmed a link state.
        try:
            reported = (device.resolve().parent / 'wireless_status').read_text().strip()
        except OSError:
            reported = ''
        if reported in ('connected', 'disconnected'):
            link = reported
    return {'adapter': 'present', 'driver': driver, 'link': link,
            'battery': battery_details(device) if driver else None}


def link_status():
    return {'ok': True, 'usb': usb_link(), 'bluetooth': headset_presence()}


def dispatch(request):
    op = request.get('op', 'status')
    if op == 'link':
        # Read-only and independent of the control lock: no hardware access.
        return link_status()
    if op not in ('status', 'set'):
        raise HeadsetError('invalid-request')
    feature, value = request.get('feature'), request.get('value')
    command = payload(feature, value) if op == 'set' else None
    transport = request.get('transport', 'usb')
    if transport not in ('usb', 'bluetooth'):
        raise HeadsetError('invalid-request')
    with control_lock(), ExitStack() as stack:
        path = stack.enter_context(BluetoothSession(request.get('address'))) if transport == 'bluetooth' else attribute()
        if command:
            # Quick Connect only accepts an address returned by the headset.
            if feature == 'devices' and value.lower() not in {d['address'] for d in read(path, 'devices')}:
                raise HeadsetError('unknown-device')
            if feature == 'devices' and read(path, 'gaming'):
                raise HeadsetError('gaming-active')
            if exchange(path, command) != b'\0':
                raise HeadsetError('rejected')
            actual = read(path, feature) if feature != 'devices' else None
            if feature != 'devices' and actual != value:
                if feature == 'gaming':
                    raise HeadsetError('gaming-not-applied')
                raise HeadsetError('unconfirmed', 'Readback differs; refresh before retrying.')
            # A connection switch may finish later; never claim it has completed.
            result = snapshot(path)
            result['sent'] = feature
            return result
        return snapshot(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', default='{"op":"status"}')
    args = parser.parse_args(argv)
    try:
        request = json.loads(args.request)
        if not isinstance(request, dict):
            raise HeadsetError('invalid-request')
        result = dispatch(request)
    except (HeadsetError, OSError) as exc:
        result = {'ok': False, 'error': error_code(exc)}
    except (ValueError, TypeError) as exc:
        result = {'ok': False, 'error': 'invalid-request', 'detail': str(exc)}
    print(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
