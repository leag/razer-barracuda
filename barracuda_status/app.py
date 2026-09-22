#!/usr/bin/env python3
"""KDE tray monitor for the Razer Barracuda X 2.4 GHz dongle."""
from pathlib import Path
import os
import queue

from .audio_router import AudioRouter
from .i18n import tr, set_language
import argparse
import select
import signal
import sys

from PyQt6.QtCore import QThread, QTimer, pyqtSignal, Qt
from PyQt6.QtGui import QAction, QColor, QIcon, QPainter, QPen, QPixmap
from PyQt6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

VID_PID = "0003:00001532:00000552"
STATUS_OFFSET = 16  # report ID at 0, status is payload byte 15
ICON_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "icons/barracuda-status"
UNKNOWN = "unknown"


def parse_report(report):
    """Accept only the observed link-status frame, never media/other reports."""
    if (len(report) > STATUS_OFFSET
            and report[:5] == bytes.fromhex("01 80 0e 50 49")
            and report[11:16] == bytes.fromhex("04 00 20 02 01")
            and report[STATUS_OFFSET] in (0, 1)):
        return bool(report[STATUS_OFFSET])
    return UNKNOWN


def find_hidraw():
    for path in sorted(Path("/sys/class/hidraw").glob("hidraw*")):
        try:
            props = (path / "device" / "uevent").read_text()
        except OSError:
            continue
        if f"HID_ID={VID_PID}" in props:
            return Path("/dev") / path.name
    return None


def status_icon(emblem):
    name = {"emblem-ok": "connected", "emblem-warning": "disconnected",
            "emblem-error": "missing", "dialog-question": "unknown"}[emblem]
    for directory in (Path(__file__).resolve().parent.parent / "private/razer", ICON_DIR):
        official = directory / "razer-official.ico"
        if not official.is_file():
            continue
        base = QIcon(str(official))
        if base.pixmap(32, 32).isNull():
            continue
        icon = QIcon()
        for size in (16, 22, 24, 32, 48, 64):
            pixmap = base.pixmap(size, size)
            painter = QPainter(pixmap)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.scale(pixmap.width() / 32, pixmap.height() / 32)
            painter.setPen(QPen(QColor("#202020"), 2))
            painter.setBrush(QColor({"connected": "#35c759", "disconnected": "#f0a000",
                                    "missing": "#e33b3b", "unknown": "#aab2bd"}[name]))
            painter.drawEllipse(18, 18, 13, 13)
            painter.setPen(QPen(QColor("#202020"), 2))
            if name == "connected":
                painter.drawLine(21, 24, 24, 27)
                painter.drawLine(24, 27, 28, 22)
            elif name == "disconnected":
                painter.drawLine(21, 25, 28, 25)
            elif name == "missing":
                painter.drawLine(22, 22, 27, 27)
                painter.drawLine(27, 22, 22, 27)
            else:
                painter.drawLine(25, 21, 25, 25)
                painter.drawPoint(25, 28)
            painter.end()
            icon.addPixmap(pixmap)
        return icon
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

    def run(self):
        while not self.isInterruptionRequested():
            device = find_hidraw()
            if device is None:
                self.status_changed.emit(None)
                self.msleep(2000)
                continue
            self.status_changed.emit(UNKNOWN)
            try:
                fd = os.open(device, os.O_RDONLY | os.O_NONBLOCK)
                try:
                    while not self.isInterruptionRequested():
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
                            self.status_changed.emit(linked)
                finally:
                    os.close(fd)
            except OSError as exc:
                self.error.emit(str(exc))
                for _ in range(8):
                    if self.isInterruptionRequested():
                        return
                    self.msleep(250)



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
            tooltip = tr("Razer Barracuda X: waiting for a report; turn the headset off and on")
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

    def close(self):
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
