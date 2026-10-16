"""Package and isolated QML checks, without connecting to the audio server."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = shutil.which('qmltestrunner6') or '/usr/lib/qt6/bin/qmltestrunner'
HELPERS = ('barracuda-headset', 'barracuda-pair', 'barracuda-power')
QML_WARNINGS = ('Binding loop', 'TypeError', 'ReferenceError', 'Unable to assign')


def run_qml(path):
    """Run one QML suite offscreen, without an audio server or real helpers.

    Fake helpers come first on PATH and record every call, so a suite that
    launches one fails instead of reaching the headset.
    """
    with tempfile.TemporaryDirectory() as directory:
        fakes = Path(directory)
        for name in HELPERS:
            helper = fakes / name
            helper.write_text('#!/bin/sh\n'
                              f'echo "{name} $*" >> "{fakes / "calls.log"}"\n'
                              'echo \'{"ok": false, "error": "test"}\'\n'
                              'exit 1\n')
            helper.chmod(0o755)
        result = subprocess.run(
            [RUNNER, '-input', str(path)],
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                 'PULSE_SERVER': 'unix:/nonexistent/barracuda-test',
                 'PATH': str(fakes) + os.pathsep + os.environ.get('PATH', '')},
            capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
        log = fakes / 'calls.log'
        calls = log.read_text() if log.exists() else ''
    return result, calls


class PlasmoidTests(unittest.TestCase):
    def test_metadata_and_version(self):
        metadata = json.loads((ROOT / 'plasmoid/metadata.json').read_text())
        self.assertEqual(metadata['KPackageStructure'], 'Plasma/Applet')
        from barracuda_pair import __version__
        self.assertEqual(metadata['KPlugin']['Version'], __version__)

    def test_tray_can_expand_the_applet(self):
        # The system tray opens its popup only for applets without a preferred
        # representation; forcing the compact one leaves left clicks inert.
        metadata = json.loads((ROOT / 'plasmoid/metadata.json').read_text())
        self.assertEqual(metadata['X-Plasma-NotificationArea'], 'true')
        # The system tray enables the entry once, when it first finds it.
        self.assertIs(metadata['KPlugin']['EnabledByDefault'], True)
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        binding = re.search(r'\n    preferredRepresentation:(.*?)\n    \S', source, re.S).group(1)
        self.assertEqual(' '.join(binding.split()),
                         'Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : null')

    def test_arch_package(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            from barracuda_pair import __version__
            (base / f'razer-barracuda-{__version__}').symlink_to(ROOT)
            dest = base / 'pkg'
            subprocess.run(['bash', '-c', 'source "$1"; pkgdir="$2"; '
                            'pkgname=plasma6-applets-barracuda; '
                            'package_plasma6-applets-barracuda', 'bash',
                            str(ROOT / 'packaging/arch/PKGBUILD'), str(dest)],
                           cwd=base, check=True)
            installed = dest / 'usr/share/plasma/plasmoids/org.razer.barracuda.output'
            for source in (ROOT / 'plasmoid').rglob('*'):
                if source.is_file():
                    self.assertEqual(source.read_bytes(),
                                     (installed / source.relative_to(ROOT / 'plasmoid')).read_bytes())

    @unittest.skipUnless(Path(RUNNER).is_file(), 'Qt 6 QML test runner not installed')
    def test_qml_logic(self):
        self.assertQmlSuitePasses(ROOT / 'tests/tst_output.qml')

    def assertQmlSuitePasses(self, path):
        result, calls = run_qml(path)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        for warning in QML_WARNINGS:
            self.assertNotIn(warning, output)
        # A helper killed before it logs still leaves this warning.
        self.assertNotIn('QProcess: Destroyed', output)
        self.assertEqual(calls, '', 'a QML test launched a helper')

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file()
                         and Path('/usr/share/icons/breeze/devices/64/audio-headset.svg').is_file(),
                         'Plasma components and Breeze icons required')
    def test_panel_geometry_and_artwork(self):
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        compact = source.split('compactRepresentation: ', 1)[1].split('    fullRepresentation:', 1)[0]
        compact = compact.replace('PC3.ToolButton {', 'PC3.ToolButton {\n id: button\n width: 32\n height: 32', 1)
        compact = compact.replace('Plasmoid.formFactor', 'root.formFactor')
        harness = """
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import "UI_DIR"
Item {
    id: root
    property int formFactor: PlasmaCore.Types.Horizontal
    property bool inTray: false
    property string statusText: "Test"
    property bool connected: false
    property bool slashed: false
    property string emblem: ""
    property bool expanded: false
    function openSettings() {}
    COMPONENT
    TestCase {
        name: "PanelRendering"
        when: windowShown
        function test_hover_and_keyboard_focus() {
            mouseMove(button, button.width / 2, button.height / 2)
            tryCompare(button, "hovered", true)
            verify(!button.background.visible)
            mouseClick(button)
            verify(root.expanded)
            mouseClick(button)
            verify(!root.expanded)
            button.forceActiveFocus(Qt.TabFocusReason)
            tryCompare(button, "visualFocus", true)
            verify(button.background.visible)
            button.focus = false
            verify(!button.background.visible)
        }
        function test_sizes_and_icons() {
            for (const tray of [false, true])
            for (const direction of [PlasmaCore.Types.Horizontal, PlasmaCore.Types.Vertical]) {
                root.formFactor = direction
                root.inTray = tray
                for (const size of [22, 32, 48]) {
                    button.width = size
                    button.height = size
                    compare(button.contentItem.width, size)
                    compare(button.contentItem.height, size)
                    const artwork = button.contentItem.children[0]
                    // The tray sizes its icons; a loose panel icon is capped.
                    compare(artwork.width, tray ? size : Math.min(size, Kirigami.Units.iconSizes.smallMedium))
                    compare(artwork.height, artwork.width)
                    compare(artwork.x, (size - artwork.width) / 2)
                    compare(artwork.y, (size - artwork.height) / 2)
                    verify(button.implicitWidth > 0)
                    verify(button.implicitHeight > 0)
                }
            }
            root.inTray = false
            button.width = 22
            button.height = 22
            const artwork = button.contentItem.children[0]
            const glyph = findChild(artwork, "headsetGlyph")
            const picture = findChild(artwork, "headsetPicture")
            const symbol = findChild(artwork, "headsetSymbol")
            const slash = findChild(artwork, "disconnectedSlash")
            const badge = findChild(artwork, "connectionEmblem")
            // Panel and tray icons use the theme's symbolic glyph, not the
            // detailed artwork.
            verify(artwork.symbolic)
            compare(symbol.source, "audio-headset-symbolic")
            verify(symbol.visible)
            verify(!picture.visible)
            compare(String(picture.source), "")
            for (const state of [{connected: true, slashed: false, emblem: ""},
                                 {connected: false, slashed: true, emblem: ""},
                                 {connected: false, slashed: false, emblem: "emblem-question"},
                                 {connected: true, slashed: false, emblem: "emblem-warning"}]) {
                root.connected = state.connected
                root.slashed = state.slashed
                root.emblem = state.emblem
                compare(symbol.opacity, state.connected ? 1 : 0.5)
                compare(slash.visible, state.slashed)
                // The software scene graph used by these tests cannot cut the
                // gap, so the glyph must stay visible and unlayered.
                verify(glyph.visible)
                verify(!glyph.layer.enabled)
                compare(badge.visible, state.emblem !== "")
                verify(badge.width <= symbol.width / 2)
                // Breeze's proportions: inside the artwork, at least 1 px wide.
                const reach = (slash.width * Math.SQRT1_2 + slash.height * Math.SQRT1_2) / 2
                verify(reach <= artwork.width / 2)
                verify(slash.height >= 1)
                verify(slash.height <= Math.max(1, artwork.width / 22) + 0.001)
            }
            compare(button.Accessible.description, "Test")
        }
    }
}
""".replace('COMPONENT', compact).replace('UI_DIR', (ROOT / 'plasmoid/contents/ui').as_uri())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tst_panel.qml'
            path.write_text(harness)
            self.assertQmlSuitePasses(path)

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file(),
                         'Qt 6 and Plasma components required')
    def test_generic_summary(self):
        self.assertQmlSuitePasses(ROOT / 'tests/tst_summary.qml')

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file(),
                         'Qt 6 and Plasma components required')
    def test_audio_settings(self):
        self.assertQmlSuitePasses(ROOT / 'tests/tst_audio.qml')
