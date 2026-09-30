import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../code/output.js" as Output

ColumnLayout {
    id: panel
    required property var sink
    property bool activeView: true
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property var battery: null
    property string localeName: Qt.locale().name
    property bool helpOpen: false
    property bool effectsOpen: false
    readonly property bool detailOpen: effectsOpen || helpOpen
    property var audioController: audio
    property var headsetController: headset
    signal settingsRequested()
    signal pairingRequested()
    signal powerOffRequested()
    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: detailOpen ? Math.min(Kirigami.Units.gridUnit * 20, panel.Layout.preferredHeight)
        : panel.Layout.preferredHeight
    Layout.preferredHeight: helpOpen ? Kirigami.Units.gridUnit * 24
        : effectsOpen ? Math.min(Kirigami.Units.gridUnit * 24,
            navigation.implicitHeight + effects.contentHeight + spacing + Kirigami.Units.largeSpacing * 2)
        : overview.implicitHeight + Kirigami.Units.largeSpacing * 2
    // Fit short pages to their content; longer effects pages scroll within the cap.
    Layout.maximumHeight: helpOpen ? Infinity : panel.Layout.preferredHeight
    onActiveViewChanged: {
        if (!activeView) {
            effectsOpen = false;
            helpOpen = false;
        }
    }
    function openEffects() {
        helpOpen = false;
        effectsOpen = true;
        if (!audioController.response && !audioController.busy)
            audioController.request({op: "status"});
        if (!headsetController.busy)
            headsetController.request({op: "status"});
    }
    AudioController { id: audio; objectName: "audioController" }
    HeadsetController {
        id: headset
        objectName: "headsetController"
        sink: panel.sink
        activeView: panel.effectsOpen && !panel.helpOpen
    }
    RowLayout {
        id: navigation
        visible: panel.detailOpen
        Layout.fillWidth: true
        PC3.ToolButton {
            objectName: "backToOutput"
            icon.name: "go-previous"
            text: Output.text("Back", "Volver", panel.localeName)
            onClicked: { panel.effectsOpen = false; panel.helpOpen = false; }
        }
        PC3.Label {
            Layout.fillWidth: true
            text: panel.helpOpen ? Output.text("Help", "Ayuda", panel.localeName)
                : Output.text("Headset settings", "Ajustes del auricular", panel.localeName)
            font.bold: true
        }
        PC3.ToolButton {
            objectName: "effectsHelpButton"
            visible: !panel.helpOpen
            icon.name: "help-contents"
            text: Output.text("Help", "Ayuda", panel.localeName)
            onClicked: panel.helpOpen = true
        }
    }
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: panel.helpOpen ? 2 : panel.effectsOpen ? 1 : 0
        PC3.ScrollView {
            id: overviewScroll
            implicitWidth: 0
            PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
            PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
            // Keep wrapping stable while the vertical scrollbar changes visibility.
            contentWidth: width
            OutputSummary {
                id: overview
                objectName: "outputOverview"
                width: overviewScroll.width
                sink: panel.sink
                activeView: panel.activeView && !panel.detailOpen
                localeName: panel.localeName
                pairingBusy: panel.pairingBusy
                pairingError: panel.pairingError
                pairingResult: panel.pairingResult
                powerBusy: panel.powerBusy
                powerError: panel.powerError
                powerResult: panel.powerResult
                battery: panel.battery
                onSettingsRequested: panel.settingsRequested()
                onPairingRequested: panel.pairingRequested()
                onPowerOffRequested: panel.powerOffRequested()
                onEffectsRequested: panel.openEffects()
                onHelpRequested: panel.helpOpen = true
            }
        }
        HeadsetSettings {
            id: effects
            localeName: panel.localeName
            controller: panel.headsetController
            audioController: panel.audioController
        }
        HelpPage { localeName: panel.localeName }
    }
}
