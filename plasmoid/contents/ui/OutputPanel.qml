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
    property bool effectsOpen: false
    property var audioController: audio
    property var headsetController: headset
    signal settingsRequested()
    signal pairingRequested()
    signal powerOffRequested()
    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: effectsOpen ? Kirigami.Units.gridUnit * 24 : panel.Layout.preferredHeight
    Layout.preferredHeight: effectsOpen ? Kirigami.Units.gridUnit * 30
        : Math.max(Kirigami.Units.gridUnit * 12, overview.implicitHeight + Kirigami.Units.largeSpacing * 2)
    // Keep the overview fitted to its content, including action messages.
    Layout.maximumHeight: effectsOpen ? Infinity : panel.Layout.preferredHeight
    onActiveViewChanged: {
        if (!activeView)
            effectsOpen = false;
    }
    function openEffects() {
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
        activeView: panel.effectsOpen
    }
    RowLayout {
        visible: panel.effectsOpen
        Layout.fillWidth: true
        PC3.ToolButton {
            objectName: "backToOutput"
            icon.name: "go-previous"
            text: Output.text("Back", "Volver", Qt.locale().name)
            onClicked: panel.effectsOpen = false
        }
        PC3.Label {
            Layout.fillWidth: true
            text: Output.text("Audio effects", "Efectos de audio", Qt.locale().name)
            font.bold: true
        }
    }
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: panel.effectsOpen ? 1 : 0
        PC3.ScrollView {
            id: overviewScroll
            PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
            PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
            // Keep wrapping stable while the vertical scrollbar changes visibility.
            contentWidth: width
            OutputSummary {
                id: overview
                objectName: "outputOverview"
                width: overviewScroll.width
                sink: panel.sink
                activeView: panel.activeView && !panel.effectsOpen
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
            }
        }
        HeadsetSettings {
            controller: panel.headsetController
            audioController: panel.audioController
        }
    }
}
