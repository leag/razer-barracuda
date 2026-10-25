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

    def test_plasma_minimum_matches_the_package(self):
        # PlasmaExtras.ContextualHelpButton, used by the popup, is new in
        # Plasma 6.7; the package asks for the same version.
        metadata = json.loads((ROOT / 'plasmoid/metadata.json').read_text())
        self.assertEqual(metadata['X-Plasma-API-Minimum-Version'], '6.7')
        pkgbuild = (ROOT / 'packaging/arch/PKGBUILD').read_text()
        package = pkgbuild.split('package_plasma6-applets-barracuda() {', 1)[1].split('\n}', 1)[0]
        self.assertIn("depends=('plasma-workspace>=6.7' ", package)
        srcinfo = (ROOT / 'packaging/arch/.SRCINFO').read_text()
        applet = srcinfo.split('pkgname = plasma6-applets-barracuda', 1)[1]
        self.assertIn('\tdepends = plasma-workspace>=6.7\n', applet)
        source = '\n'.join(path.read_text() for path in (ROOT / 'plasmoid/contents/ui').glob('*.qml'))
        self.assertIn('PlasmaExtras.ContextualHelpButton', source)

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

    def test_commands_live_in_the_heading(self):
        # Pairing is the heading's '+' (high priority); More actions holds
        # Turn Off, a separator and KDE's audio settings. Plasma copies them
        # into the right-click menu; each command asks in the popup first.
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        actions = re.search(r'\n    Plasmoid\.contextualActions: \[(.*?)\n    \]', source, re.S).group(1)
        entries = re.split(r'\n        PlasmaCore\.Action \{', actions)[1:]
        self.assertEqual(len(entries), 4)
        pair, power, separator, audio = entries
        self.assertIn('text: root.label("Pair Headset…", "Emparejar auricular…")', pair)
        self.assertIn('icon.name: "list-add-symbolic"', pair)
        self.assertIn('priority: PlasmaCore.Action.HighPriority', pair)
        self.assertIn('text: root.label("Turn Off Headset…", "Apagar auricular…")', power)
        self.assertIn('icon.name: "system-shutdown-symbolic"', power)
        for command, name in ((pair, '"pair"'), (power, '"power-off"')):
            # Greyed only by the shared rule, and checked again when triggered.
            self.assertIn('enabled: root.commandsEnabled', command)
            self.assertIn('if (root.commandsEnabled)\n                    root.askInPopup(' + name + ');', command)
            self.assertNotIn('openPairing', command)
            self.assertNotIn('turnOffHeadset', command)
        self.assertIn('priority: PlasmaCore.Action.NormalPriority', power)
        self.assertIn('isSeparator: true', separator)
        self.assertIn('priority: PlasmaCore.Action.NormalPriority', separator)
        self.assertIn('root.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")', audio)
        self.assertIn('priority: PlasmaCore.Action.NormalPriority', audio)
        self.assertIn('onTriggered: root.openSettings()', audio)
        self.assertIn('KCMLauncher.openSystemSettings("kcm_pulseaudio")', source)
        # Three entries always make the tray draw a menu, on every version.
        self.assertNotIn('alwaysShowAsMenu', source)
        # Only a confirmed missing dongle or a running command disables them.
        self.assertIn('readonly property bool commandsEnabled: !pairingBusy && !powerBusy '
                      '&& !Output.adapterMissing(linkStatus)', source)
        for function in ('openPairing', 'turnOffHeadset'):
            body = source.split(f'function {function}() {{', 1)[1].split('\n    }', 1)[0]
            self.assertIn('if (!commandsEnabled)\n            return;', body)
        # The question is asked in the popup once its view exists.
        ask = source.split('function showAskedCommand() {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('view.confirmPairing();', ask)
        self.assertIn('view.confirmPowerOff();', ask)
        self.assertIn('onFullRepresentationItemChanged: Qt.callLater(showAskedCommand)', source)
        for removed in ('dndAction', 'gamingAction', 'menuActions', 'HeadsetPanel', 'powerResult'):
            self.assertNotIn(removed, source)
        # The name comes from metadata, as in Plasma's own heading.
        self.assertIn('toolTipMainText: Plasmoid.title', source)
        self.assertIn('toolTipSubText: Output.toolTip(connection, battery, Qt.locale().name)', source)
        self.assertNotIn('"Razer Barracuda X"', source)
        # The tray icon never hides; a low battery asks for attention, and
        # it spins while a command runs on the headset.
        self.assertNotIn('PassiveStatus', source)
        self.assertIn('NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus', source)
        self.assertIn('Plasmoid.busy: pairingBusy || powerBusy', source)
        # Failures go to the journal in full and to the popup in plain words.
        self.assertEqual(source.count('console.warn(outcome.details);'), 2)
        # Settings are read with a confirmed link whenever the full view is
        # shown, including the desktop, which never expands.
        self.assertIn('readonly property bool viewShown: root.expanded || '
                      'Plasmoid.formFactor === PlasmaCore.Types.Planar', source)
        self.assertIn('readonly property bool settingsWanted: viewShown && connected', source)
        self.assertIn('activeView: root.settingsWanted', source)
        # Closing the popup clears the previous results and a pending question.
        shown = source.split('onViewShownChanged: {', 1)[1].split('\n    }', 1)[0]
        for field in ('pairingError', 'pairingResult', 'powerError', 'askedCommand'):
            self.assertIn(f'{field} = "";', shown)

    def test_popup_requests_reach_the_settings_controller(self):
        source = (ROOT / 'plasmoid/contents/ui/main.qml').read_text()
        view = source.split('fullRepresentation: HeadsetView {', 1)[1]
        for line in ('settings: settingsController', 'actions: Plasmoid.contextualActions', 'title: Plasmoid.title',
                     'inTray: root.inTray', 'activeView: root.viewShown',
                     'onPairingConfirmed: root.openPairing()', 'onPowerOffConfirmed: root.turnOffHeadset()',
                     'onSettingChangeRequested: (feature, value) => root.setSetting(feature, value)',
                     'onSettingsRefreshRequested: root.readSettings()'):
            self.assertIn(line, view)
        # Settings are sent only with a confirmed link and while nothing runs.
        set_setting = source.split('function setSetting(feature, value) {', 1)[1].split('\n    }', 1)[0]
        self.assertIn('connected && !settingsController.busy && !pairingBusy && !powerBusy', set_setting)
        self.assertIn('settingsController.request({op: "set", feature: feature, value: value})', set_setting)
        # The popup's tabs replaced the configuration window; there is no
        # Apply, so no chain of changes either.
        self.assertNotIn('configureAction', view)
        self.assertNotIn('requestChain', '\n'.join(path.read_text() for path in (ROOT / 'plasmoid').rglob('*.*')))
        self.assertFalse((ROOT / 'plasmoid/contents/config').exists())
        for removed in ('ConnectionSummary.qml', 'HeadsetPanel.qml', 'SettingRow.qml',
                        'ConfigEqualizer.qml', 'ConfigPowerSaving.qml', 'ConfigHeadset.qml',
                        'HeadsetConfigPage.qml', 'HeadsetSettings.qml'):
            self.assertFalse((ROOT / 'plasmoid/contents/ui' / removed).exists(), removed)

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
            const symbol = findChild(artwork, "artworkIcon")
            const badge = findChild(artwork, "artworkEmblem")
            // Panel and tray icons use the theme's symbolic glyph, not the
            // detailed artwork, drawn at the icon's own size.
            verify(artwork.symbolic)
            compare(symbol.source, "audio-headset-symbolic")
            compare(artwork.iconSize, artwork.width)
            compare(symbol.width, artwork.width)
            compare(findChild(artwork, "artworkTransport").visible, false)
            for (const state of [{connected: true, emblem: ""},
                                 {connected: false, emblem: ""},
                                 {connected: false, emblem: "emblem-question"},
                                 {connected: true, emblem: "emblem-warning"}]) {
                root.connected = state.connected
                root.emblem = state.emblem
                // Dimmed without a confirmed link; no colour is added.
                tryCompare(symbol, "opacity", state.connected ? 1 : 0.5)
                compare(badge.visible, state.emblem !== "")
                if (state.emblem !== "") {
                    compare(badge.source, state.emblem)
                    // Over the bottom-right corner, at most half the glyph.
                    verify(badge.width <= symbol.width / 2)
                    compare(badge.x + badge.width, symbol.width)
                    compare(badge.y + badge.height, symbol.height)
                }
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
    def test_popup_view(self):
        self.assertQmlSuitePasses(ROOT / 'tests/tst_summary.qml')

    @unittest.skipUnless(Path(RUNNER).is_file()
                         and Path('/usr/lib/qt6/qml/org/kde/plasma/components/ToolButton.qml').is_file(),
                         'Qt 6 and Plasma components required')
    def test_audio_settings(self):
        self.assertQmlSuitePasses(ROOT / 'tests/tst_audio.qml')
