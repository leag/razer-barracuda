"""Pair the Barracuda X dongle with a headset, replaying the vendor utility's sequence.

Only the commands captured from the official pairing utility and identified in its
decompiled HID library are sent, in the same order; see docs/PROTOCOL.md. Every reply is validated
and anything unexpected aborts before the connect command.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
import select
import struct
import sys
from pathlib import Path
import time

from .i18n import set_language, tr

VID_PID = "0003:00001532:00000552"

REPORT_SIZE = 64
HANDSHAKE = bytes([0x01, 0x40]).ljust(REPORT_SIZE, b"\0")
HANDSHAKE_REPLY = bytes([0x01, 0x40, 0x01, 0x01])
CLASS_ACK, CLASS_OTA, CLASS_LINK = 0x01, 0x06, 0x0E
CMD_GET_MODE, CMD_SET_MODE, CMD_CONNECT, CMD_STATUS, CMD_SCAN = 0xE0, 0xE1, 0xE5, 0xE6, 0xF0
# OTA_CMD_IOCTL READ_MAX_LEN: ioctl key 0x5A5A1234, value 1, 240-byte reads.
READ_MAX_LEN = bytes.fromhex("25 34 12 5a 5a 01 00 00 00 f0 00 00 00")
# OTA_CMD_READ_MP_DATA for id 0xC4, the model identifier.
READ_MODEL_ID = bytes.fromhex("43 c4")
# Device classes accepted by the vendor utility for Barracuda headsets.
HEADSET_CLASSES = frozenset({0x200418, 0x240404, 0x240410})
SCAN_RESTART = 2.0
REPLY_TIMEOUT = 3.0


class PairingError(Exception):
    pass


def find_hidraw():
    for path in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        try:
            props = (path / "device" / "uevent").read_text()
        except OSError:
            continue
        if f"HID_ID={VID_PID}" in props:
            return Path("/dev") / path.name
    return None


@dataclass(frozen=True)
class Message:
    klass: int
    seq: int
    data: bytes


@dataclass(frozen=True)
class Headset:
    address: bytes  # little-endian, as sent back in the connect command
    device_class: int
    rssi: int
    name: str

    @property
    def label(self):
        return ":".join(f"{byte:02X}" for byte in reversed(self.address))

    @property
    def eligible(self):
        return self.device_class in HEADSET_CLASSES and "BARRACUDA" in self.name.upper()


def build_report(frame):
    if len(frame) > REPORT_SIZE - 3:
        raise ValueError("frame does not fit in one report")
    return bytes([0x01, 0x80, len(frame)]) + frame.ljust(REPORT_SIZE - 3, b"\0")


def link_frame(seq, command, *args):
    return b"PA" + bytes([CLASS_LINK, seq, len(args) + 1, command, *args])


def ota_frame(seq, payload):
    return b"PA" + bytes([CLASS_OTA, seq]) + struct.pack("<H", len(payload)) + payload


def parse_address(text):
    parts = text.replace("-", ":").split(":")
    if len(parts) != 6:
        raise ValueError(text)
    return bytes(int(part, 16) for part in reversed(parts))


def parse_headset(data):
    """Decode a T_GAP_INQUIRY_RESULT_INFO payload that starts with 0xF0."""
    if len(data) < 14 or data[0] != CMD_SCAN:
        return None
    device_class = struct.unpack_from("<I", data, 9)[0]
    rssi = struct.unpack_from("b", data, 13)[0]
    name = data[14:54].split(b"\0", 1)[0].decode("utf-8", "replace")
    return Headset(bytes(data[1:7]), device_class, rssi, name)


class Reassembler:
    """Join `01 80 LEN` reports into `PI` messages that span several reports."""

    def __init__(self):
        self.pending = b""
        self.expected = 0

    def feed(self, report):
        if len(report) < 3 or report[:2] != b"\x01\x80":
            return None
        chunk = bytes(report[3:3 + report[2]])
        if self.pending:
            self.pending += chunk[:self.expected - len(self.pending)]
        elif len(chunk) >= 10 and chunk[:2] == b"PI":
            self.expected = 10 + struct.unpack_from("<H", chunk, 8)[0]
            self.pending = chunk[:self.expected]
        else:
            return None
        if len(self.pending) < self.expected:
            return None
        message, self.pending = self.pending, b""
        return Message(message[2], message[3], message[10:])


class HidrawTransport:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)

    def write(self, report):
        if os.write(self.fd, report) != len(report):
            raise PairingError(tr("Short write to the adapter"))

    def read(self, timeout):
        if not select.select([self.fd], [], [], max(timeout, 0))[0]:
            return None
        try:
            return os.read(self.fd, REPORT_SIZE)
        except BlockingIOError:
            return None

    def close(self):
        os.close(self.fd)


class PairingSession:
    def __init__(self, transport, clock=time.monotonic, sleep=time.sleep, log=print,
                 cancelled=lambda: False):
        self.transport = transport
        self.cancelled = cancelled
        self.clock = clock
        self.sleep = sleep
        self.log = log
        self.reassembler = Reassembler()
        self.seq = 0
        self.headsets = {}
        self.link_status = None

    def next_seq(self):
        # Acknowledgments echo seq | 0x80, so sequence numbers stay below 0x80.
        self.seq = self.seq % 0x7F + 1
        return self.seq

    def poll(self, timeout):
        """Read one report and return a complete message, recording side events."""
        report = self.transport.read(timeout)
        if report is None:
            return None
        message = self.reassembler.feed(report)
        if message is None or message.klass != CLASS_LINK or not message.data:
            return message
        headset = parse_headset(message.data) if message.data[0] == CMD_SCAN else None
        if headset is not None:
            if headset.address not in self.headsets:
                self.log(tr("Found {name} {address} (class 0x{device_class:06X}, {rssi} dBm)",
                            name=headset.name or "?", address=headset.label,
                            device_class=headset.device_class, rssi=headset.rssi))
            self.headsets[headset.address] = headset
        elif message.data[0] == 0xE3 and len(message.data) >= 2 and message.data[1] in (0, 1):
            self.link_status = bool(message.data[1])
        return message

    def handshake(self):
        self.transport.write(HANDSHAKE)
        deadline = self.clock() + REPLY_TIMEOUT
        while self.clock() < deadline:
            report = self.transport.read(deadline - self.clock())
            if report is not None and report[:2] == HANDSHAKE[:2]:
                if report[:4] != HANDSHAKE_REPLY:
                    raise PairingError(tr("Unexpected handshake reply: {reply}",
                                          reply=report[:4].hex(" ")))
                return
        raise PairingError(tr("The adapter did not answer the handshake"))

    def request(self, klass, seq, frame, reply_command=None):
        """Send a frame, check its acknowledgment and optionally wait for a reply."""
        self.transport.write(build_report(frame))
        ack = reply = None
        deadline = self.clock() + REPLY_TIMEOUT
        while self.clock() < deadline:
            message = self.poll(deadline - self.clock())
            if message is None:
                continue
            if (message.klass == CLASS_ACK and len(message.data) >= 3
                    and message.data[0] == klass and message.data[1] == seq | 0x80):
                if message.data[2] != 0:
                    raise PairingError(tr("The adapter rejected command {frame}",
                                          frame=frame.hex(" ")))
                ack = message.data[3:]
            elif (reply_command is not None and message.klass == CLASS_LINK
                  and message.data[:1] == bytes([reply_command])):
                reply = message.data[1:]
            if reply_command is None and ack is not None:
                return ack
            if reply is not None:
                return reply
        raise PairingError(tr("No response to command {frame}", frame=frame.hex(" ")))

    def link_command(self, command, *args, reply=False):
        seq = self.next_seq()
        return self.request(CLASS_LINK, seq, link_frame(seq, command, *args),
                            command if reply else None)

    def ota_command(self, payload):
        seq = self.next_seq()
        return self.request(CLASS_OTA, seq, ota_frame(seq, payload))

    def prepare(self):
        self.handshake()
        self.ota_command(READ_MAX_LEN)
        mode = self.link_command(CMD_GET_MODE, reply=True)
        if mode[:1] != b"\x00":
            # The captured session ran in local mode; remote mode is unverified.
            raise PairingError(tr("The adapter is not in local mode ({mode}); aborting",
                                  mode=mode.hex(" ")))
        model = self.ota_command(READ_MODEL_ID)
        self.log(tr("Adapter model data: {model}", model=model.hex(" ") or "-"))

    def check_cancelled(self):
        if self.cancelled():
            raise PairingError(tr("Pairing cancelled"))

    def set_scan(self, enabled):
        self.link_command(CMD_SCAN, int(enabled))

    def scan(self, duration, want=None):
        """Scan like the vendor utility, restarting the inquiry every two seconds.

        Returns the first headset accepted by `want`, leaving the inquiry running
        as the utility does, or None after `duration` seconds.
        """
        self.set_scan(True)
        deadline = self.clock() + duration
        restart = self.clock() + SCAN_RESTART
        while self.clock() < deadline:
            self.check_cancelled()
            if want is not None:
                for headset in self.headsets.values():
                    if want(headset):
                        return headset
            if self.clock() >= restart:
                self.set_scan(False)
                self.set_scan(True)
                restart = self.clock() + SCAN_RESTART
            self.poll(min(restart, deadline) - self.clock())
        return None

    def connected(self):
        status = self.link_command(CMD_STATUS, reply=True)
        if status[:1] and status[0] & 0x1F:
            self.log(tr("Connection status: 0x{status:02X}", status=status[0]))
            return True
        return False

    def connect(self, headset, timeout=10.0, interval=0.5):
        """Connect and wait until the dongle reports the link like the utility saw.

        In the capture an unsolicited `E3 01` arrived about two seconds after the
        connect command and before E6 reported profiles; finishing earlier left
        the headset in pairing mode.
        """
        self.link_status = None
        self.link_command(CMD_CONNECT, 0x00, 0xFF, *headset.address)
        deadline = self.clock() + timeout
        while self.clock() < deadline:
            self.check_cancelled()
            self.poll(min(interval, max(deadline - self.clock(), 0)))
            if self.link_status and self.connected():
                return True
        return False


def run(session, *, scan_only, address, timeout):
    session.prepare()
    scanning = True
    try:
        if scan_only:
            session.scan(timeout)
            if not session.headsets:
                session.log(tr("No Bluetooth devices were found"))
            return 0
        if address is None:
            session.log(tr("Put the headset in pairing mode now"))
        want = ((lambda h: h.address == address) if address is not None
                else (lambda h: h.eligible))
        headset = session.scan(timeout, want)
        if headset is None:
            session.log(tr("No Barracuda headset in pairing mode was found"))
            return 1
        session.log(tr("Pairing with {name} {address}…", name=headset.name or "?",
                       address=headset.label))
        if session.connect(headset):
            # Finish like the vendor utility: stop the inquiry, then REMOTE_SET_MODE
            # back to local mode.
            session.set_scan(False)
            scanning = False
            session.link_command(CMD_SET_MODE, 0x00)
            session.log(tr("Paired. Turn the headset off and on to start the link"))
            return 0
        session.log(tr("The headset did not connect"))
        return 1
    finally:
        if scanning:
            session.set_scan(False)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Pair a Razer Barracuda X headset with its 2.4 GHz dongle")
    parser.add_argument("--scan", action="store_true",
                        help="only list nearby Bluetooth devices; do not pair")
    parser.add_argument("--address", help="pair only with this headset address (AA:BB:CC:DD:EE:FF)")
    parser.add_argument("--timeout", type=float, default=60.0,
                        help="seconds to scan (default: 60)")
    parser.add_argument("--device", help="hidraw node (default: auto-detect 1532:0552)")
    parser.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    parser.add_argument("--language", choices=("en", "es"), default="en",
                        help="Interface language (default: en)")
    args = parser.parse_args(argv)
    set_language(args.language)
    try:
        address = parse_address(args.address) if args.address else None
    except ValueError:
        parser.error(f"invalid address: {args.address}")
    device = args.device or find_hidraw()
    if device is None:
        print(tr("Adapter not detected"), file=sys.stderr)
        return 1
    if not args.scan and not args.yes:
        answer = input(tr("Pair the dongle with a headset? This replaces its current pairing. [y/N] "))
        if answer.strip().lower() not in ("y", "yes", "s", "si", "sí"):
            return 1
    try:
        transport = HidrawTransport(device)
    except PermissionError:
        print(tr("HID permission denied"), file=sys.stderr)
        return 1
    try:
        return run(PairingSession(transport), scan_only=args.scan,
                   address=address, timeout=args.timeout)
    except (PairingError, OSError) as exc:
        print(tr("Pairing failed: {error}", error=exc), file=sys.stderr)
        return 1
    finally:
        transport.close()


if __name__ == "__main__":
    raise SystemExit(main())
