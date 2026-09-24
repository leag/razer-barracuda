#!/usr/bin/env python3
"""KDE tray monitor for the Razer Barracuda X 2.4 GHz dongle."""
from pathlib import Path
import os
import queue

from .audio_router import AudioRouter
from .i18n import tr, set_language
from . import pairing
from .pairing import find_hidraw
import argparse
import select
import signal
import sys
import time

from PyQt6.QtCore import QThread, QTimer, pyqtSignal, Qt
from PyQt6.QtGui import QAction, QIcon, QPainter, QPixmap
from PyQt6.QtWidgets import QApplication, QMenu, QMessageBox, QSystemTrayIcon

STATUS_OFFSET = 16  # report ID at 0, status is payload byte 15
ICON_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "icons/barracuda-status"
UNKNOWN = "unknown"


def parse_report(report):
    """Accept the validated transition and E3 connection frames only."""
    if (len(report) >= 15
            and report[:6] == bytes.fromhex("01 80 0c 50 49 0e")
            and report[11:14] == bytes.fromhex("02 00 e3")
            and report[14] in (0, 1)):
        return bool(report[14])
    if (len(report) > STATUS_OFFSET
            and report[:5] == bytes.fromhex("01 80 0e 50 49")
            and report[11:16] == bytes.fromhex("04 00 20 02 01")
            and report[STATUS_OFFSET] in (0, 1)):
        return bool(report[STATUS_OFFSET])
    return UNKNOWN


def status_icon(emblem):
    name = {"emblem-ok": "connected", "emblem-warning": "disconnected",
            "emblem-error": "missing", "dialog-question": "unknown"}[emblem]
    for directory in (Path(__file__).resolve().parent / "assets", ICON_DIR):
        path = directory / f"barracuda-{name}.svg"
        if not path.is_file():
            continue
        icon = QIcon(str(path))
        if not icon.isNull():
            return icon
    base = QIcon.fromTheme("audio-headphones", QIcon.fromTheme("headphones"))
    base_pixmap = base.pixmap(32, 32)
    overlay = QIcon.fromTheme(emblem).pixmap(16, 16)
    result = QPixmap(32, 32)
    result.fill(Qt.GlobalColor.transparent)
    painter = QPainter(result)
    painter.drawPixmap(0, 0, base_pixmap)
    painter.drawPixmap(16, 16, overlay)
    painter.end()
    return QIcon(result)


class HidReader(QThread):
    status_changed = pyqtSignal(object)
    error = pyqtSignal(str)

    QUERY_INTERVAL = 2.0
    QUERY_ATTEMPTS = 3

    def open_device(self, device):
        try:
            return os.open(device, os.O_RDWR | os.O_NONBLOCK), True
        except PermissionError:
            # Preserve passive monitoring when only read permission is available.
            return os.open(device, os.O_RDONLY | os.O_NONBLOCK), False

    def monitor(self, fd, writable):
        attempts = 0
        next_query = 0.0
        confirmed = False
        while not self.isInterruptionRequested():
            if (writable and not confirmed and attempts < self.QUERY_ATTEMPTS
                    and time.monotonic() >= next_query):
                attempts += 1
                packet = bytes([1, 0x80, 6, 0x50, 0x41, 0x0e,
                                attempts, 1, 0xe3]).ljust(64, b"\0")
                try:
                    if os.write(fd, packet) != len(packet):
                        writable = False
                except OSError:
                    # Failed queries are not evidence of a lost wireless link.
                    writable = False
                next_query = time.monotonic() + self.QUERY_INTERVAL
            if not select.select([fd], [], [], 0.25)[0]:
                continue
            try:
                report = os.read(fd, 64)
            except BlockingIOError:
                continue
            if not report:
                raise OSError(tr("The adapter stopped responding"))
            linked = parse_report(report)
            if linked != UNKNOWN:
                confirmed = True
                self.status_changed.emit(linked)

    def run(self):
        while not self.isInterruptionRequested():
            device = find_hidraw()
            if device is None:
                self.status_changed.emit(None)
            else:
                self.status_changed.emit(UNKNOWN)
                try:
                    fd, writable = self.open_device(device)
                    try:
                        self.monitor(fd, writable)
                    finally:
                        os.close(fd)
                except OSError as exc:
                    self.status_changed.emit(UNKNOWN)
                    self.error.emit(str(exc))
            for _ in range(8):
                if self.isInterruptionRequested():
                    return
                self.msleep(250)



class PairWorker(QThread):
    """Run the pairing sequence off the GUI thread; cancelled on quit."""
    finished_with = pyqtSignal(bool, str)

    def run(self):
        messages = []
        device = find_hidraw()
        if device is None:
            self.finished_with.emit(False, tr("Adapter not detected"))
            return
        try:
            transport = pairing.HidrawTransport(device)
        except PermissionError:
            self.finished_with.emit(False, tr("HID permission denied"))
            return
        except OSError as exc:
            self.finished_with.emit(False, tr("Pairing failed: {error}", error=exc))
            return
        try:
            session = pairing.PairingSession(transport, log=messages.append,
                                             cancelled=self.isInterruptionRequested)
            code = pairing.run(session, scan_only=False, address=None, timeout=60)
            self.finished_with.emit(code == 0, messages[-1] if messages else "")
        except (pairing.PairingError, OSError) as exc:
            self.finished_with.emit(False, tr("Pairing failed: {error}", error=exc))
        finally:
            transport.close()


class AudioWorker(QThread):
    result = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        self.events = queue.Queue()
        state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        self.router = AudioRouter(state_home / "barracuda-status/audio.json")

    def run(self):
        pending = UNKNOWN
        while not self.isInterruptionRequested():
            try:
                pending = self.events.get(timeout=1)
                while not self.events.empty():
                    pending = self.events.get_nowait()
            except queue.Empty:
                pass
            if self.isInterruptionRequested():
                return
            try:
                self.router.update(pending)
                self.result.emit(tr("Automatic audio switching enabled"))
            except Exception as exc:
                self.result.emit(tr("Could not switch output: {error}", error=exc))


class Tray(QSystemTrayIcon):
    def __init__(self):
        super().__init__()
        self.setIcon(status_icon("dialog-question"))
        self.setToolTip(tr("Razer Barracuda X: waiting for link status"))
        self.menu = QMenu()
        self.status_action = QAction(tr("Checking…"), self)
        self.status_action.setEnabled(False)
        self.menu.addAction(self.status_action)
        self.audio_action = QAction(tr("Automatic audio switching enabled"), self)
        self.audio_action.setEnabled(False)
        self.menu.addAction(self.audio_action)
        self.audio = AudioWorker()
        self.audio.result.connect(self.audio_action.setText)
        self.audio.start()
        self.menu.addSeparator()
        self.pair_action = QAction(tr("Pair headset…"), self)
        self.pair_action.triggered.connect(self.start_pairing)
        self.menu.addAction(self.pair_action)
        self.pairer = PairWorker()
        self.pairer.finished_with.connect(self.pairing_finished)
        quit_action = QAction(tr("Quit"), self)
        quit_action.triggered.connect(QApplication.quit)
        self.menu.addAction(quit_action)
        self.setContextMenu(self.menu)
        self.reader = HidReader()
        self.reader.status_changed.connect(self.update_status)
        self.reader.error.connect(self.show_error)
        self.reader.start()

    def update_status(self, linked):
        self.audio.events.put(linked)
        if linked is None:
            self.setIcon(status_icon("emblem-error"))
            text, tooltip = tr("Adapter not detected"), tr("Razer Barracuda X: adapter not detected")
        elif linked == UNKNOWN:
            self.setIcon(status_icon("dialog-question"))
            text = tr("Adapter connected; link unconfirmed")
            tooltip = tr("Razer Barracuda X: waiting for a valid connection response")
        elif linked:
            self.setIcon(status_icon("emblem-ok"))
            text, tooltip = tr("Connected"), tr("Razer Barracuda X: headset connected")
        else:
            self.setIcon(status_icon("emblem-warning"))
            text, tooltip = tr("Disconnected"), tr("Razer Barracuda X: headset disconnected")
        self.status_action.setText(text)
        self.setToolTip(tooltip)

    def show_error(self, message):
        self.setIcon(status_icon("emblem-error"))
        self.status_action.setText(tr("Could not read the adapter"))
        self.setToolTip(f"Razer Barracuda X: {message}")
        if "Permission denied" in message:
            self.status_action.setText(tr("HID permission denied"))
            self.setToolTip(tr("Install the included udev rule and log in again"))

    def start_pairing(self):
        if self.pairer.isRunning():
            return
        answer = QMessageBox.question(
            None, tr("Pair headset"),
            tr("This replaces the dongle's current pairing. Put the headset in pairing "
               "mode, then press Yes. Scanning lasts up to 60 seconds."))
        if answer != QMessageBox.StandardButton.Yes:
            return
        self.pair_action.setEnabled(False)
        self.pair_action.setText(tr("Pairing…"))
        self.pairer.start()

    def pairing_finished(self, success, message):
        self.pair_action.setEnabled(True)
        self.pair_action.setText(tr("Pair headset…"))
        icon = (QSystemTrayIcon.MessageIcon.Information if success
                else QSystemTrayIcon.MessageIcon.Warning)
        self.showMessage(tr("Pair headset"), message, icon)

    def close(self):
        self.pairer.requestInterruption()
        self.pairer.wait()
        self.audio.requestInterruption()
        self.audio.events.put(UNKNOWN)
        self.audio.wait()
        self.reader.requestInterruption()
        self.reader.wait()
        super().hide()


def main():
    parser = argparse.ArgumentParser(description="Barracuda X link status and automatic audio routing")
    parser.add_argument("--language", choices=("en", "es"), default="en",
                        help="Interface language (default: en)")
    args = parser.parse_args()
    set_language(args.language)
    app = QApplication([sys.argv[0]])
    app.setQuitOnLastWindowClosed(False)
    if not QSystemTrayIcon.isSystemTrayAvailable():
        print(tr("No system tray is available"), file=sys.stderr)
        return 1
    tray = Tray()
    app.aboutToQuit.connect(tray.close)
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    timer = QTimer()
    timer.timeout.connect(lambda: None)
    timer.start(250)
    tray.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
