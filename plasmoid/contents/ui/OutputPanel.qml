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
    property var battery: null
    signal settingsRequested()
    signal pairingRequested()
    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredWidth: Kirigami.Units.gridUnit * 30
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30
    onActiveViewChanged: {
        if (!activeView)
            effects.restartConfirmation = false;
    }
    AudioController { id: audio; objectName: "audioController" }
    PC3.TabBar {
        id: tabs
        objectName: "audioTabs"
        Layout.fillWidth: true
        PC3.TabButton { text: Output.text("Output", "Salida", Qt.locale().name) }
        PC3.TabButton { text: Output.text("Equalizer", "Ecualizador", Qt.locale().name) }
        PC3.TabButton { text: Output.text("Microphone", "Micrófono", Qt.locale().name) }
        PC3.TabButton { text: Output.text("System", "Sistema", Qt.locale().name) }
        onCurrentIndexChanged: {
            if (currentIndex > 0 && !audio.response && !audio.busy)
                audio.request({op: "status"});
        }
    }
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabs.currentIndex === 0 ? 0 : 1
        PC3.ScrollView {
            id: overviewScroll
            PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
            PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AlwaysOn
            contentWidth: availableWidth
            OutputSummary {
                width: overviewScroll.availableWidth
                sink: panel.sink
                activeView: panel.activeView && tabs.currentIndex === 0
                pairingBusy: panel.pairingBusy
                pairingError: panel.pairingError
                pairingResult: panel.pairingResult
                battery: panel.battery
                onSettingsRequested: panel.settingsRequested()
                onPairingRequested: panel.pairingRequested()
            }
        }
        AudioSettings {
            id: effects
            controller: audio
            section: tabs.currentIndex === 2 ? "microphone" : tabs.currentIndex === 3 ? "system" : "output"
        }
    }
}
