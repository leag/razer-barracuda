import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The popup holds only the connection summary and its explicit actions, sized to
// its content. The headset settings open in the widget's configuration
// window, so the popup never switches pages or jumps in height.
ColumnLayout {
    id: panel
    property var status: null
    property var target: ({transport: "usb"})
    property bool activeView: true
    property bool showHeader: true
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property var battery: null
    property var dndState: null
    property var gamingState: null
    property bool gamingSettable: false
    property string configureText: ""
    property bool settingsBusy: false
    property string localeName: Qt.locale().name
    // A one-shot confirmation requested from the applet's actions: "pairing" or
    // "power-off". The summary asks before anything runs.
    property string request: ""
    signal requestHandled()
    signal settingsRequested()
    signal headsetSettingsRequested()
    signal pairingRequested()
    signal powerOffRequested()
    signal settingChangeRequested(string feature, bool enabled)
    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: overview.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumHeight: panel.Layout.preferredHeight
    // A panel popup fits its content; the system tray gives every applet the
    // same size, which the summary fills.
    Layout.maximumHeight: showHeader ? panel.Layout.preferredHeight : Infinity

    function applyRequest() {
        if (request === "")
            return;
        overview.confirm(request);
        // Clearing the request rewrites this binding's source; do it after the
        // current change has been handled.
        Qt.callLater(panel.requestHandled);
    }
    onRequestChanged: applyRequest()
    // The popup may be created by the same action that made the request.
    Component.onCompleted: applyRequest()

    PC3.ScrollView {
        id: overviewScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitWidth: 0
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
        // Keep wrapping stable while the vertical scrollbar changes visibility.
        contentWidth: width
        ConnectionSummary {
            id: overview
            objectName: "connectionOverview"
            width: overviewScroll.width
            // Fill a taller popup (the system tray's fixed size) without
            // making the content scroll.
            height: Math.max(implicitHeight, overviewScroll.availableHeight)
            status: panel.status
            target: panel.target
            activeView: panel.activeView
            showHeader: panel.showHeader
            localeName: panel.localeName
            pairingBusy: panel.pairingBusy
            pairingError: panel.pairingError
            pairingResult: panel.pairingResult
            powerBusy: panel.powerBusy
            powerError: panel.powerError
            powerResult: panel.powerResult
            battery: panel.battery
            dndState: panel.dndState
            gamingState: panel.gamingState
            gamingSettable: panel.gamingSettable
            configureText: panel.configureText
            settingsBusy: panel.settingsBusy
            onSettingsRequested: panel.settingsRequested()
            onHeadsetSettingsRequested: panel.headsetSettingsRequested()
            onPairingRequested: panel.pairingRequested()
            onPowerOffRequested: panel.powerOffRequested()
            onSettingChangeRequested: (feature, enabled) => panel.settingChangeRequested(feature, enabled)
        }
    }
}
