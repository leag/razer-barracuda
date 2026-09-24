"""Pairing sequence checks against a fake dongle; no hardware is touched."""
import struct
import unittest
from unittest.mock import patch

from barracuda_status import pairing

HEADSET = bytes.fromhex("11 22 33 44 55 66")
OTHER = bytes.fromhex("aa bb cc dd ee ff")


def pi_reports(klass, seq, data, sizes=(18, 37)):
    """Split a PI message into `01 80 LEN` reports, like the dongle does."""
    chunk = b"PI" + bytes([klass, seq, 0, 0, 0, 0]) + struct.pack("<H", len(data)) + data
    reports = []
    for size in sizes:
        if chunk:
            reports.append(chunk[:size])
            chunk = chunk[size:]
    while chunk:
        reports.append(chunk[:61])
        chunk = chunk[61:]
    return [(bytes([1, 0x80, len(part)]) + part).ljust(64, b"\0") for part in reports]


def inquiry(address, device_class, rssi, name):
    data = (bytes([0xF0]) + address + b"\0\0" + struct.pack("<Ib", device_class, rssi)
            + name.encode().ljust(40, b"\0") + b"\0\0\0")
    return data


class FakeDongle:
    def __init__(self, *, mode=0, results=(), status=(0x19,), reject=None,
                 handshake=b"\x01\x40\x01\x01", link_event=True):
        self.mode, self.results, self.status = mode, list(results), list(status)
        self.link_event, self.linked = link_event, False
        self.reject, self.handshake_reply = reject, handshake
        self.now, self.queue, self.written, self.rx = 0.0, [], [], 0xC0

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds

    def read(self, timeout):
        if getattr(self, "link_at", None) is not None and self.now >= self.link_at:
            # Unsolicited E3 01, about two seconds after the connect as captured.
            self.link_at = None
            self.send(pairing.CLASS_LINK, bytes([0xE3, 0x01]))
        if self.queue:
            return self.queue.pop(0)
        self.now += max(timeout, 0.001)
        return None

    def send(self, klass, data):
        self.rx = (self.rx + 1) & 0xFF
        self.queue.extend(pi_reports(klass, self.rx, data))

    def write(self, report):
        self.written.append(report)
        if report[:2] == b"\x01\x40":
            self.queue.append(self.handshake_reply.ljust(64, b"\0"))
            return
        frame = report[3:3 + report[2]]
        klass, seq = frame[2], frame[3]
        command = frame[5] if klass == pairing.CLASS_LINK else frame[6]
        status = 1 if command == self.reject else 0
        extra = {0x25: b"\xf0", 0x43: b"00"}.get(command, b"") if klass == pairing.CLASS_OTA else b""
        self.send(pairing.CLASS_ACK, bytes([klass, seq | 0x80, status]) + extra)
        if command == 0xE0:
            self.send(pairing.CLASS_LINK, bytes([0xE0, self.mode]))
        elif command == 0xE5 and self.link_event:
            self.link_at = self.now + 2.0
        elif command == 0xE6:
            value = self.status.pop(0) if len(self.status) > 1 else self.status[0]
            self.send(pairing.CLASS_LINK, bytes([0xE6, value]))
        elif command == 0xF0 and frame[6] == 1:
            for result in self.results:
                self.send(pairing.CLASS_LINK, result)
            self.results = []

    def commands(self):
        """(class, command, args) for every non-handshake report written."""
        found = []
        for report in self.written:
            if report[:2] == b"\x01\x80":
                frame = report[3:3 + report[2]]
                if frame[2] == pairing.CLASS_LINK:
                    found.append((frame[2], frame[5], bytes(frame[6:5 + frame[4]])))
                else:
                    found.append((frame[2], frame[6], bytes(frame[7:])))
        return found


def run(dongle, **options):
    session = pairing.PairingSession(dongle, clock=dongle.clock, sleep=dongle.sleep,
                                     log=lambda message: None)
    options = {"scan_only": False, "address": None, "timeout": 30, **options}
    return pairing.run(session, **options), session


class PairingTests(unittest.TestCase):
    def setUp(self):
        pairing.set_language("en")

    def test_reassembles_captured_inquiry_layout(self):
        reassembler = pairing.Reassembler()
        first = bytes.fromhex("01 80 12 50 49 0e cf 00 00 00 00 39 00 f0") + HEADSET + b"\0"
        second = (bytes.fromhex("01 80 25 00 04 04 24 00 c5") + b"Razer Barracuda X (BT)"
                  + bytes(9))
        third = bytes.fromhex("01 80 0c") + bytes(12)
        self.assertIsNone(reassembler.feed(first.ljust(64, b"\0")))
        self.assertIsNone(reassembler.feed(second.ljust(64, b"\0")))
        message = reassembler.feed(third.ljust(64, b"\0"))
        headset = pairing.parse_headset(message.data)
        self.assertEqual((headset.address, headset.device_class, headset.rssi, headset.name),
                         (HEADSET, 0x240404, -59, "Razer Barracuda X (BT)"))
        self.assertTrue(headset.eligible)
        self.assertEqual(headset.label, "66:55:44:33:22:11")
        self.assertEqual(pairing.parse_address(headset.label), HEADSET)

    def test_ignores_stray_reports(self):
        reassembler = pairing.Reassembler()
        for report in (b"", b"\x01\x40\x01\x01", bytes.fromhex("01 80 02 00 00"),
                       bytes.fromhex("02 80 0c 50 49 0e")):
            self.assertIsNone(reassembler.feed(report))

    def test_pairs_with_eligible_headset_using_captured_frames(self):
        dongle = FakeDongle(results=[
            inquiry(OTHER, 0x0C043C, -85, ""),
            inquiry(HEADSET, 0x240404, -59, "Razer Barracuda X (BT)")])
        code, _ = run(dongle)
        self.assertEqual(code, 0)
        written = [report.rstrip(b"\0") for report in dongle.written]
        self.assertEqual(written[:5], [
            b"\x01\x40",
            bytes.fromhex("01 80 13 50 41 06 01 0d 00 25 34 12 5a 5a 01 00 00 00 f0"),
            bytes.fromhex("01 80 06 50 41 0e 02 01 e0"),
            bytes.fromhex("01 80 08 50 41 06 03 02 00 43 c4"),
            bytes.fromhex("01 80 07 50 41 0e 04 02 f0 01")])
        connects = [c for c in dongle.commands() if c[1] == pairing.CMD_CONNECT]
        self.assertEqual(connects, [(pairing.CLASS_LINK, 0xE5, b"\x00\xff" + HEADSET)])
        # Same ending as the vendor utility: scan off, then local mode.
        self.assertEqual(dongle.commands()[-2:], [(pairing.CLASS_LINK, 0xF0, b"\x00"),
                                                  (pairing.CLASS_LINK, 0xE1, b"\x00")])

    def test_only_documented_commands_are_sent(self):
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Razer Barracuda X (BT)")])
        run(dongle)
        allowed = {(pairing.CLASS_OTA, 0x25), (pairing.CLASS_OTA, 0x43)} | {
            (pairing.CLASS_LINK, c) for c in (0xE0, 0xE1, 0xE5, 0xE6, 0xF0)}
        self.assertLessEqual({(k, c) for k, c, _ in dongle.commands()}, allowed)
        self.assertEqual([a for _, c, a in dongle.commands() if c == 0xE1], [b"\x00"])

    def test_scan_only_never_connects(self):
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Razer Barracuda X (BT)")])
        code, session = run(dongle, scan_only=True, timeout=5)
        self.assertEqual(code, 0)
        self.assertIn(HEADSET, session.headsets)
        self.assertNotIn(pairing.CMD_CONNECT, [c for _, c, _ in dongle.commands()])
        self.assertEqual(dongle.commands()[-1], (pairing.CLASS_LINK, 0xF0, b"\x00"))

    def test_scan_restarts_every_two_seconds(self):
        dongle = FakeDongle()
        run(dongle, scan_only=True, timeout=7)
        scans = [a for _, c, a in dongle.commands() if c == 0xF0]
        self.assertEqual(scans, [b"\x01"] + [b"\x00", b"\x01"] * 3 + [b"\x00"])

    def test_ineligible_devices_are_not_paired(self):
        dongle = FakeDongle(results=[
            inquiry(OTHER, 0x0C043C, -60, "Razer Barracuda X (BT)"),
            inquiry(HEADSET, 0x240404, -60, "Some Speaker")])
        code, _ = run(dongle, timeout=5)
        self.assertEqual(code, 1)
        self.assertNotIn(pairing.CMD_CONNECT, [c for _, c, _ in dongle.commands()])
        self.assertNotIn(pairing.CMD_SET_MODE, [c for _, c, _ in dongle.commands()])
        self.assertEqual(dongle.commands()[-1], (pairing.CLASS_LINK, 0xF0, b"\x00"))

    def test_address_filter_selects_requested_headset(self):
        dongle = FakeDongle(results=[
            inquiry(OTHER, 0x240404, -50, "Razer Barracuda X (BT)"),
            inquiry(HEADSET, 0x240404, -70, "Razer Barracuda X (BT)")])
        code, _ = run(dongle, address=HEADSET)
        self.assertEqual(code, 0)
        connect = [a for _, c, a in dongle.commands() if c == pairing.CMD_CONNECT]
        self.assertEqual(connect, [b"\x00\xff" + HEADSET])

    def test_connection_confirmed_only_by_status_bits(self):
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Barracuda")],
                            status=(0x00, 0x00, 0x19))
        self.assertEqual(run(dongle)[0], 0)
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Barracuda")],
                            status=(0x00,))
        self.assertEqual(run(dongle)[0], 1)
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Barracuda")],
                            status=(0x20,))
        self.assertEqual(run(dongle)[0], 1)

    def test_waits_for_link_event_before_finishing(self):
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Barracuda")])
        self.assertEqual(run(dongle)[0], 0)
        connect_index = next(i for i, c in enumerate(dongle.commands()) if c[1] == 0xE5)
        self.assertNotIn(0xE1, [c for _, c, _ in dongle.commands()[:connect_index]])
        # Status bits without the E3 01 link event are not enough.
        dongle = FakeDongle(results=[inquiry(HEADSET, 0x240404, -59, "Barracuda")],
                            link_event=False)
        self.assertEqual(run(dongle)[0], 1)
        self.assertNotIn(0xE1, [c for _, c, _ in dongle.commands()])

    def test_remote_mode_aborts_before_scanning(self):
        dongle = FakeDongle(mode=1)
        with self.assertRaises(pairing.PairingError):
            run(dongle)
        self.assertEqual([c for _, c, _ in dongle.commands()], [0x25, 0xE0])

    def test_unexpected_handshake_aborts_before_commands(self):
        dongle = FakeDongle(handshake=b"\x01\x40\x02\x00")
        with self.assertRaises(pairing.PairingError):
            run(dongle)
        self.assertEqual(dongle.commands(), [])

    def test_rejected_or_missing_ack_aborts(self):
        dongle = FakeDongle(reject=0x25)
        with self.assertRaises(pairing.PairingError):
            run(dongle)
        self.assertEqual([c for _, c, _ in dongle.commands()], [0x25])
        dongle = FakeDongle()
        dongle.write = lambda report: dongle.written.append(report)
        with self.assertRaises(pairing.PairingError):
            run(dongle)

    def test_cancellation_stops_scan_and_disables_inquiry(self):
        dongle = FakeDongle()
        session = pairing.PairingSession(dongle, clock=dongle.clock, sleep=dongle.sleep,
                                         log=lambda message: None,
                                         cancelled=lambda: dongle.now > 3)
        with self.assertRaises(pairing.PairingError):
            pairing.run(session, scan_only=False, address=None, timeout=60)
        self.assertLess(dongle.now, 10)
        self.assertEqual(dongle.commands()[-1], (pairing.CLASS_LINK, 0xF0, b"\x00"))

    def test_sequence_numbers_stay_below_ack_bit(self):
        session = pairing.PairingSession(FakeDongle())
        values = [session.next_seq() for _ in range(300)]
        self.assertEqual(min(values), 1)
        self.assertEqual(max(values), 0x7F)

    def test_cli_requires_confirmation_and_detected_adapter(self):
        with patch.object(pairing, "find_hidraw", return_value=None):
            self.assertEqual(pairing.main(["--yes"]), 1)
        with patch.object(pairing, "find_hidraw", return_value="/dev/null"), patch(
                "builtins.input", return_value="n"), patch.object(
                pairing, "HidrawTransport") as transport:
            self.assertEqual(pairing.main([]), 1)
            transport.assert_not_called()
        with self.assertRaises(SystemExit):
            pairing.main(["--address", "nope", "--scan"])


if __name__ == "__main__":
    unittest.main()
