#!/usr/bin/env python3
"""Offline extraction and structural inspection of the known T3 USB bridge image.

Reads .NET ResourceWriter v2 primitive resources without loading assemblies or
opening devices. Outputs should be kept outside tracked source.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

BRIDGE_SHA256 = '2c63052c168eae1e7e2236fd8a1e59a0df3e3156df8e8da3112757ebdc4077de'


class Resources:
    def __init__(self, data):
        self.data = data
        if self.integer(0) != 0xBEEFCACE or self.integer(4) != 1:
            raise ValueError('Unsupported .NET resource header')
        cursor = 12 + self.integer(8)
        version, count, types = struct.unpack('<III', self.read(cursor, 12))
        if version != 2 or types:
            raise ValueError('Only v2 primitive resources are supported')
        cursor = (cursor + 12 + 7) & ~7
        self.read(cursor, count * 8 + 4)
        self.data_start = self.integer(cursor + count * 8)
        names_start = cursor + count * 8 + 4
        if not names_start <= self.data_start <= len(data):
            raise ValueError('Invalid resource data section')
        self.entries = {}
        for index in range(count):
            offset = self.integer(cursor + count * 4 + index * 4)
            length, name_start = self.varint(names_start + offset)
            if name_start + length + 4 > self.data_start:
                raise ValueError('Resource name outside name section')
            name = self.read(name_start, length).decode('utf-16le')
            value_offset = self.data_start + self.integer(name_start + length)
            if name in self.entries:
                raise ValueError('Duplicate resource name')
            self.entries[name] = value_offset

    def read(self, offset, length):
        if offset < 0 or length < 0 or offset + length > len(self.data):
            raise ValueError('Truncated or invalid resource data')
        return self.data[offset:offset + length]

    def integer(self, offset):
        return struct.unpack('<I', self.read(offset, 4))[0]

    def varint(self, offset):
        value = 0
        for shift in range(0, 35, 7):
            byte = self.read(offset, 1)[0]
            offset += 1
            value |= (byte & 0x7f) << shift
            if byte < 128:
                return value, offset
        raise ValueError('Invalid 7-bit integer')

    def get(self, name):
        kind, offset = self.varint(self.entries[name])
        if kind == 8:
            return struct.unpack('<i', self.read(offset, 4))[0]
        if kind == 10:
            return struct.unpack('<q', self.read(offset, 8))[0]
        if kind in (32, 33):
            return self.read(offset + 4, self.integer(offset))
        raise ValueError(f'Unsupported primitive type {kind} for {name}')

    def image(self, prefix):
        size = self.get(prefix + 'FileSize')
        if not isinstance(size, int) or not 0 < size <= len(self.data):
            raise ValueError('Invalid declared image size')
        parts, total, index = [], 0, 0
        while total < size:
            part = self.get(prefix + 'Sector' + str(index))
            if not isinstance(part, bytes) or not part:
                raise ValueError('Missing or empty image sector')
            parts.append(part)
            total += len(part)
            index += 1
        if total != size:
            raise ValueError('Sector sum does not match declared size')
        return b''.join(parts), index


def switch_table(data, offset):
    """Decode Keil C51 switch helper 0x2337: BE16 target, U8 case."""
    entries = []
    for _ in range(256):
        if offset + 4 > len(data):
            raise ValueError('Truncated switch table')
        target = int.from_bytes(data[offset:offset + 2], 'big')
        if not target:
            return entries, int.from_bytes(data[offset + 2:offset + 4], 'big')
        entries.append({'opcode': f'0x{data[offset + 2]:02x}', 'handler': f'0x{target:04x}'})
        offset += 3
    raise ValueError('Unterminated switch table')


def inspect_bridge(data):
    digest = hashlib.sha256(data).hexdigest()
    if digest != BRIDGE_SHA256:
        raise ValueError('Unknown bridge image: fixed offsets must not be applied to another build')
    commands, fallback = switch_table(data, 0x26f7)
    requests, request_fallback = switch_table(data, 0x45a6)
    descriptor = data[0x5d64:0x5dcb]
    return {
        'sha256': digest, 'size': len(data), 'architecture': '8051 / MCS-51',
        'reset_target': '0x03f3', 'build_date_ascii': data[0x1ee0:0x1eeb].decode('ascii'),
        'hid_descriptor_offset': '0x5d64', 'hid_descriptor_size': len(descriptor),
        'hid_descriptor_sha256': hashlib.sha256(descriptor).hexdigest(),
        'hid_descriptor_hex': descriptor.hex(' '),
        'outer_commands': commands, 'unknown_command_handler': f'0x{fallback:04x}',
        'class_request_dispatch': requests, 'class_request_fallback': f'0x{request_fallback:04x}',
        'caveat': 'Replacement firmware from a host package, not a dump of the attached device.'}



COMPANION_SHA256 = '81f5485feb54fcc8b026762c8901cef557879fa9a31ac140961bdb81e23535b4'


def inspect_companion(data):
    """Recover the build-specific link-family table, without opening a device."""
    if hashlib.sha256(data).hexdigest() != COMPANION_SHA256:
        raise ValueError('Unknown companion image: refusing fixed-offset analysis')
    table_address = 0x1fc1cde8
    table_offset = 0x15d10 + 0x1cde8
    offsets = struct.unpack_from('<18H', data, table_offset)
    return {
        'sha256': COMPANION_SHA256,
        'family': '0x0e',
        'dispatcher': '0x1fc1cd8c',
        'table_address': hex(table_address),
        'entries': [
            {'selector': hex(0xe0 + index), 'target': hex(table_address + offset)}
            for index, offset in enumerate(offsets)
        ],
        'caveat': 'Static query candidates only; audio-link semantics not hardware-validated.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resources', type=Path, help='Extracted GenericDongleFW.resources')
    parser.add_argument('--output', type=Path, required=True,
                        help='Output directory outside tracked source')
    args = parser.parse_args()
    resource_data = args.resources.read_bytes()
    resources = Resources(resource_data)
    images = {prefix: resources.image(prefix) for prefix in ('T3_USB', 'T3_Dongle')}
    manifest = {'source_sha256': hashlib.sha256(resource_data).hexdigest(), 'images': {}}
    manifest['bridge'] = inspect_bridge(images['T3_USB'][0])
    manifest['companion'] = inspect_companion(images['T3_Dongle'][0])
    args.output.mkdir(parents=True, exist_ok=True)
    for prefix, (data, sectors) in images.items():
        (args.output / (prefix + '.bin')).write_bytes(data)
        manifest['images'][prefix] = {'size': len(data), 'sectors': sectors,
                                     'sha256': hashlib.sha256(data).hexdigest()}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
