"""Package and isolated QML checks, without connecting to the audio server."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = shutil.which('qmltestrunner6') or '/usr/lib/qt6/bin/qmltestrunner'
HELPERS = ('barracuda-headset', 'barracuda-pair', 'barracuda-power')
QML_WARNINGS = ('Binding loop', 'TypeError', 'ReferenceError', 'Unable to assign')


def run_qml(path, **env):
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
                 'PATH': str(fakes) + os.pathsep + os.environ.get('PATH', ''), **env},
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

    def test_single_action_leads_to_kde_audio_settings(self):
        # Every headset command lives in the popup; the only widget action is
        # the way out to KDE's audio settings (More actions and right-click).
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        actions = re.search(r'\n    Plasmoid\.contextualActions: \[(.*?)\n    \]', source, re.S).group(1)
        self.assertEqual(actions.count('PlasmaCore.Action {'), 1)
        self.assertIn('root.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")', actions)
        self.assertIn('priority: PlasmaCore.Action.NormalPriority', actions)
        self.assertIn('onTriggered: root.openSettings()', actions)
        # alwaysShowAsMenu is assigned only where libplasma has it (6.8+),
        # never declared, so older Plasma versions still load the widget.
        self.assertNotIn('alwaysShowAsMenu:', actions)
        self.assertIn('if ("alwaysShowAsMenu" in audioDevicesAction)', actions)
        self.assertIn('KCMLauncher.openSystemSettings("kcm_pulseaudio")', source)
        for removed in ('requestConfirmation', 'pendingRequest', 'dndAction', 'gamingAction'):
            self.assertNotIn(removed, source)
        # The name comes from metadata, as in Plasma's own heading.
        self.assertIn('toolTipMainText: Plasmoid.title', source)
        self.assertNotIn('"Razer Barracuda X"', source)
        # Settings are read with a confirmed link whenever the full view is
        # shown, including the desktop, which never expands.
        self.assertIn('readonly property bool viewShown: root.expanded || '
                      'Plasmoid.formFactor === PlasmaCore.Types.Planar', source)
        self.assertIn('readonly property bool settingsWanted: viewShown && connected', source)
        self.assertIn('activeView: root.settingsWanted', source)
        # Closing the popup clears the previous pairing and power-off results.
        shown = source.split('onViewShownChanged: {', 1)[1].split('\n    }', 1)[0]
        for field in ('pairingError', 'pairingResult', 'powerError', 'powerResult'):
            self.assertIn(f'{field} = "";', shown)

    def test_popup_requests_reach_the_settings_controller(self):
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        panel = source.split('fullRepresentation: HeadsetPanel {', 1)[1]
        self.assertIn('settings: settingsController', panel)
        self.assertIn('onSettingChangeRequested: (feature, enabled) => root.setSetting(feature, enabled)', panel)
        self.assertIn('onSourceSwitchRequested: address => root.setSetting("devices", address)', panel)
        self.assertIn('onSettingsRefreshRequested: root.readSettings()', panel)
        self.assertIn('menuActions: root.menuActions', panel)
        self.assertIn('title: Plasmoid.title', panel)
        self.assertIn('showHeader: !root.inTray', panel)
        # Settings are sent only with a confirmed link and while nothing runs.
        set_setting = source.split('function setSetting(feature, value) {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('connected && !settingsController.busy && !pairingBusy && !powerBusy', set_setting)
        self.assertIn('settingsController.request({op: "set", feature: feature, value: value})', set_setting)

    @unittest.skipUnless(Path(RUNNER).is_file() and shutil.which('sh'), 'Qt 6 QML test runner required')
    def test_configuration_chain_survives_the_closed_window(self):
        # Plasma ends a configuration page's process when OK closes the
        # window. Run the command output.js builds, with fake helpers, and
        # check that it stops at the first failure, reports the last reply and
        # finishes even when the waiting shell is killed at once.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            probe = base / 'tst_chain.qml'
            probe.write_text('import QtQuick\nimport QtTest\nimport "%s" as Output\n'
                             'TestCase { name: "Chain"; function test_print() { console.log("CHAIN " + '
                             'Output.headsetChainCommand([{op: "set", feature: "preset", value: 255}, '
                             '{op: "set", feature: "bands", value: [1,0,0,0,0,0,0,0,0,0]}], {transport: "usb"})) } }\n'
                             % (ROOT / 'plasmoid/contents/code/output.js').as_uri())
            result, _ = run_qml(probe)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            command = next(line.split('CHAIN ', 1)[1] for line in (result.stdout + result.stderr).splitlines()
                           if 'CHAIN ' in line)
            fakes = base / 'bin'
            fakes.mkdir()
            log = base / 'calls.log'
            helper = fakes / 'barracuda-headset'
            # Records each request; fails the preset step when asked to.
            helper.write_text('#!/bin/sh\n'
                              'sleep "${FAKE_DELAY:-0}"\n'
                              f'echo "$2" >> "{log}"\n'
                              'case "$2" in *preset*) if [ -n "$FAKE_FAIL" ]; then '
                              'echo \'{"ok": false, "error": "rejected"}\'; exit 1; fi;; esac\n'
                              'echo \'{"ok": true, "sent": "x"}\'\n')
            helper.chmod(0o755)
            env = {**os.environ, 'PATH': f'{fakes}{os.pathsep}{os.environ["PATH"]}',
                   'XDG_RUNTIME_DIR': str(base)}
            done = subprocess.run(['sh', '-c', command], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(done.returncode, 0)
            self.assertEqual(done.stdout, '{"ok": true, "sent": "x"}\n')
            calls = log.read_text().splitlines()
            self.assertEqual(len(calls), 2)
            self.assertIn('"feature":"preset"', calls[0])
            self.assertIn('"feature":"bands"', calls[1])
            log.unlink()
            failed = subprocess.run(['sh', '-c', command], env={**env, 'FAKE_FAIL': '1'},
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(json.loads(failed.stdout), {'ok': False, 'error': 'rejected'})
            self.assertEqual(len(log.read_text().splitlines()), 1)
            log.unlink()
            # The window closes while the first step runs: the waiting shell is
            # killed, and the chain still completes.
            waiting = subprocess.Popen(['sh', '-c', command], env={**env, 'FAKE_DELAY': '0.3'},
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.1)
            waiting.kill()
            waiting.wait(timeout=10)
            self.assertFalse(log.exists())
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and not (log.exists() and len(log.read_text().splitlines()) == 2):
                time.sleep(0.05)
            self.assertEqual(len(log.read_text().splitlines()), 2)

    @unittest.skipUnless(Path(RUNNER).is_file(), 'Qt 6 QML test runner not installed')
    def test_configuration_categories_in_both_languages(self):
        with tempfile.TemporaryDirectory() as directory:
            probe = Path(directory) / 'tst_categories.qml'
            probe.write_text('import QtQuick\nimport QtTest\nTestCase { name: "Categories"; '
                             'function test_print() { const model = Qt.createComponent("%s").createObject(null); '
                             'const names = []; for (let i = 0; i < model.count; ++i) names.push(model.get(i).name); '
                             'console.log("NAMES " + JSON.stringify(names)) } }\n'
                             % (ROOT / 'plasmoid/contents/config/config.qml').as_uri())
            for language, names in (('en_US.UTF-8', ['Equalizer', 'Power Saving']),
                                    ('es_CL.UTF-8', ['Ecualizador', 'Ahorro de energía'])):
                result, _ = run_qml(probe, LC_ALL=language, LANG=language, LANGUAGE=language.split('.')[0])
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                line = next(line for line in output.splitlines() if 'NAMES ' in line)
                self.assertEqual(json.loads(line.split('NAMES ', 1)[1]), names)

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
        compact = compact.replace('Plasmoid.formFactor', 'root.formFactor').replace('Plasmoid.title', 'root.title')
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
    property string title: "Barracuda Headset"
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
            // The widget's own title, as in Plasma's heading and tooltip.
            compare(button.Accessible.name, "Barracuda Headset")
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
