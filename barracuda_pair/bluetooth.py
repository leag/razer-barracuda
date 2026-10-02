"""Bounded native customer commands over the paired headset's Bluetooth SPP."""
import errno
import json
from pathlib import Path
import re
import socket
import struct
import subprocess
import time


MAX_REPLY = 258  # Three customer header bytes plus an eight-bit payload length.
NAMES = ('Razer Barracuda X (BT)', 'Razer Barracuda X (2022)')
ADDRESS = re.compile(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')


def invalid(message):
    return OSError(errno.EPROTO, message)


def sdp_element(data, offset=0, depth=0):
    """Parse bounded SDP data elements, retaining integer/UUID type identity."""
    if depth > 8 or offset >= len(data):
        raise invalid('Malformed SDP element')
    tag = data[offset]
    offset += 1
    kind, size_code = tag >> 3, tag & 7
    if size_code <= 4:
        size = 1 << size_code
    else:
        width = 1 << (size_code - 5)
        if offset + width > len(data):
            raise invalid('Truncated SDP length')
        size = int.from_bytes(data[offset:offset + width], 'big')
        offset += width
    end = offset + size
    if end > len(data):
        raise invalid('Truncated SDP value')
    if kind in (6, 7):
        value = []
        while offset < end:
            node, offset = sdp_element(data[:end], offset, depth + 1)
            value.append(node)
    elif kind in (1, 3):
        value = int.from_bytes(data[offset:end], 'big')
    else:
        value = data[offset:end]
    return (kind, value), end


def spp_channel(address):
    """Discover the advertised channel; never assume the observed channel 6."""
    if not hasattr(socket, 'AF_BLUETOOTH'):
        raise OSError(errno.EAFNOSUPPORT, 'Python lacks Linux Bluetooth socket support')
    with socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET,
                       socket.BTPROTO_L2CAP) as conn:
        conn.settimeout(3)
        conn.connect((address, 1))
        continuation, attributes = b'\0', b''
        for transaction in range(1, 5):
            params = bytes.fromhex('35 03 19 11 01 04 00 35 05 0a 00 00 ff ff') + continuation
            conn.sendall(struct.pack('>BHH', 6, transaction, len(params)) + params)
            reply = conn.recv(2048)
            if len(reply) < 8:
                raise invalid('Truncated SDP reply')
            opcode, seq, length = struct.unpack_from('>BHH', reply)
            if opcode != 7 or seq != transaction or length != len(reply) - 5:
                raise invalid('Unrelated SDP reply')
            count = int.from_bytes(reply[5:7], 'big')
            if 7 + count >= len(reply):
                raise invalid('Invalid SDP attribute length')
            attributes += reply[7:7 + count]
            continuation = reply[7 + count:]
            if len(continuation) != 1 + continuation[0] or len(attributes) > 4096:
                raise invalid('Invalid SDP continuation')
            if continuation == b'\0':
                break
        else:
            raise invalid('SDP continuation limit reached')
    node, consumed = sdp_element(attributes)
    if consumed != len(attributes) or node[0] != 6:
        raise invalid('Invalid SDP record list')
    channels = set()
    for kind, values in node[1]:
        if kind != 6 or len(values) % 2:
            raise invalid('Invalid SDP record')
        for index in range(0, len(values), 2):
            if values[index] != (1, 4):
                continue
            descriptors = values[index + 1]
            if descriptors[0] != 6:
                raise invalid('Invalid SDP protocol list')
            for descriptor_kind, entries in descriptors[1]:
                if descriptor_kind == 6 and len(entries) >= 2 and entries[0] == (3, 3):
                    channel_kind, channel = entries[1]
                    if channel_kind != 1 or not 1 <= channel <= 30:
                        raise invalid('Invalid RFCOMM channel')
                    channels.add(channel)
    if len(channels) != 1:
        raise OSError(errno.EOPNOTSUPP, 'No unique Bluetooth serial service')
    return channels.pop()


def headset_presence():
    """Paired headset as BlueZ reports it; opens no channel to the headset.

    Returns None when no Barracuda is paired or BlueZ is not running, and an
    unknown state when its answer cannot be read: an unreadable answer is not a
    disconnected headset.
    """
    try:
        reply = subprocess.run(['busctl', '--system', '--json=short', 'call', 'org.bluez', '/',
                                'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects'],
                               capture_output=True, text=True, timeout=3, check=True)
    except subprocess.CalledProcessError:
        return None
    except (OSError, subprocess.SubprocessError):
        return {'state': 'unknown'}
    try:
        objects = json.loads(reply.stdout)['data'][0]
        devices = [interfaces.get('org.bluez.Device1') for interfaces in objects.values()]
    except (ValueError, KeyError, IndexError, TypeError, AttributeError):
        return {'state': 'unknown'}
    found = []
    for device in devices:
        if not isinstance(device, dict):
            continue
        def value(name):
            entry = device.get(name)
            return entry.get('data') if isinstance(entry, dict) else None
        address = value('Address')
        if value('Name') not in NAMES or value('Paired') is not True \
                or not isinstance(address, str) or not ADDRESS.fullmatch(address):
            continue
        found.append({'state': 'connected' if value('Connected') is True else 'disconnected',
                      'address': address.upper()})
    found.sort(key=lambda device: device['state'] != 'connected')
    return found[0] if found else None


def paired_headset(address):
    """Confirm BlueZ identity and connection before opening a serial channel."""
    if not isinstance(address, str) or not ADDRESS.fullmatch(address):
        raise ValueError('Invalid Bluetooth address')
    address = address.upper()
    for adapter in sorted(Path('/sys/class/bluetooth').glob('hci*')):
        if not re.fullmatch(r'hci\d+', adapter.name):
            continue
        path = f'/org/bluez/{adapter.name}/dev_{address.replace(":", "_")}'
        def property_value(name):
            reply = subprocess.run(['busctl', '--system', '--json=short', 'get-property',
                                    'org.bluez', path, 'org.bluez.Device1', name],
                                   capture_output=True, text=True, timeout=3, check=True)
            return json.loads(reply.stdout)['data']
        try:
            name = property_value('Name')
            if name not in NAMES:
                raise OSError(errno.ENODEV, 'Not a supported Barracuda headset')
            if property_value('Connected') is True and property_value('Paired') is True:
                return address
        except subprocess.TimeoutExpired as exc:
            raise OSError(errno.ETIMEDOUT, 'BlueZ identity check timed out') from exc
        except subprocess.CalledProcessError:
            continue
    raise OSError(errno.ENOTCONN, 'Paired Bluetooth headset is not connected')


class BluetoothSession:
    """One serialized, interruptible request session; no worker or reconnect loop."""
    def __init__(self, address):
        self.address = address
        self.conn = None
        self.sequence = 0x40
        self.buffer = b''

    def __enter__(self):
        try:
            address = paired_headset(self.address)
            channel = spp_channel(address)
            self.conn = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM,
                                      socket.BTPROTO_RFCOMM)
            self.conn.settimeout(3)
            self.conn.connect((address, channel))
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.conn is not None:
            self.conn.close()
            self.conn = None

    def __exit__(self, *_):
        self.close()

    def exchange(self, payload):
        if len(payload) < 3 or payload[0] & 0x7f not in (0x13, 0x14, 0x15, 0x27, 0x2c, 0x2d) \
                or payload[1] != 0 or payload[2] != len(payload) - 3:
            raise ValueError('Invalid customer request')
        self.sequence = (self.sequence + 1) & 0x7f
        self.conn.sendall(b'PA' + bytes([8, self.sequence, len(payload)]) + payload)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            while len(self.buffer) >= 10:
                if self.buffer[:2] != b'PI':
                    raise invalid('Invalid serial frame prefix')
                size = int.from_bytes(self.buffer[8:10], 'little')
                if size > MAX_REPLY:
                    raise invalid('Serial frame exceeds reply bound')
                if len(self.buffer) < 10 + size:
                    break
                frame, self.buffer = self.buffer[:10 + size], self.buffer[10 + size:]
                data = frame[10:]
                if frame[2] != 8 or not data or data[0] != payload[0]:
                    continue
                if len(data) < 3 or data[1] != 1:
                    continue  # Unsolicited reports are not query replies.
                if data[2] != len(data) - 3:
                    raise invalid('Invalid customer reply length')
                return data[3:]
            self.conn.settimeout(max(.01, deadline - time.monotonic()))
            raw = self.conn.recv(2048)
            if not raw:
                raise OSError(errno.ENOTCONN, 'Bluetooth serial channel closed')
            self.buffer += raw
            if len(self.buffer) > 4096:
                raise invalid('Serial receive buffer exceeded')
        raise OSError(errno.ETIMEDOUT, 'Bluetooth command response timed out')
