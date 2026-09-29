"""Package and isolated QML checks, without connecting to the audio server."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = shutil.which('qmltestrunner6') or '/usr/lib/qt6/bin/qmltestrunner'


class PlasmoidTests(unittest.TestCase):
    def test_metadata_and_version(self):
        metadata = json.loads((ROOT / 'plasmoid/metadata.json').read_text())
        self.assertEqual(metadata['KPackageStructure'], 'Plasma/Applet')
        from barracuda_pair import __version__
        self.assertEqual(metadata['KPlugin']['Version'], __version__)

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
        subprocess.run([RUNNER, '-input', str(ROOT / 'tests/tst_output.qml')],
                       env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                            'PULSE_SERVER': 'unix:/nonexistent/barracuda-test'},
                       check=True, capture_output=True, text=True, timeout=30)

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
Item {
    id: root
    property int formFactor: PlasmaCore.Types.Horizontal
    property string deviceIcon: "audio-headset"
    property string deviceArtwork: "file:///usr/share/icons/breeze/devices/64/audio-headset.svg"
    property string deviceName: "Test"
    property bool hasOutput: false
    property var sink: null
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
            for (const direction of [PlasmaCore.Types.Horizontal, PlasmaCore.Types.Vertical]) {
                root.formFactor = direction
                for (const size of [22, 32, 48]) {
                    button.width = size
                    button.height = size
                    compare(button.contentItem.width, size)
                    compare(button.contentItem.height, size)
                    const artwork = button.contentItem.children[0]
                    compare(artwork.width, Math.min(size, Kirigami.Units.iconSizes.medium))
                    compare(artwork.height, artwork.width)
                    compare(artwork.x, (size - artwork.width) / 2)
                    compare(artwork.y, (size - artwork.height) / 2)
                    verify(button.implicitWidth > 0)
                    verify(button.implicitHeight > 0)
                }
            }
            const picture = button.contentItem.children[0]
            for (const icon of ["audio-headset", "audio-speakers"]) {
                root.deviceArtwork = "file:///usr/share/icons/breeze/devices/64/" + icon + ".svg"
                tryCompare(picture, "status", Image.Ready)
                verify(picture.visible)
            }
        }
    }
}
""".replace('COMPONENT', compact)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tst_panel.qml'
            path.write_text(harness)
            result = subprocess.run(
                [RUNNER, '-input', str(path)],
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                     'PULSE_SERVER': 'unix:/nonexistent/barracuda-test'},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('Binding loop', result.stdout + result.stderr)

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file(),
                         'Qt 6 and Plasma components required')
    def test_generic_summary(self):
        result = subprocess.run(
            [RUNNER, '-input', str(ROOT / 'tests/tst_summary.qml')],
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                 'PULSE_SERVER': 'unix:/nonexistent/barracuda-test'},
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Binding loop', result.stdout + result.stderr)

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file(),
                         'Qt 6 and Plasma components required')
    def test_audio_settings(self):
        result = subprocess.run(
            [RUNNER, '-input', str(ROOT / 'tests/tst_audio.qml')],
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                 'PULSE_SERVER': 'unix:/nonexistent/barracuda-test'},
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for warning in ('Binding loop', 'TypeError', 'ReferenceError', 'Unable to assign'):
            self.assertNotIn(warning, result.stdout + result.stderr)
