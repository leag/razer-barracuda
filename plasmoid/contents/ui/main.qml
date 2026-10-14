import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.volume
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kcmutils as KCMUtils
import "../code/output.js" as Output

PlasmoidItem {
    id: root
    // The default output only selects the native-control transport when the
    // link reports do not; it is never evidence of a physical link.
    readonly property var sink: Server.defaultSink
    readonly property string sinkName: sink ? String(sink.name || "") : ""
    onSinkNameChanged: linkMonitor.refresh()
    readonly property var linkStatus: linkMonitor.status
    readonly property var connection: Output.connection(linkStatus)
    readonly property bool connected: connection.state === "connected"
    readonly property string statusText: Output.connectionText(connection, Qt.locale().name)
    readonly property var target: Output.headsetTarget(sink, linkStatus)
    readonly property bool slashed: Output.slashed(connection)
    readonly property string emblem: Output.emblem(connection, battery)
    // Inside the system tray, which draws the heading and the actions menu.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints
        & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading) !== 0
    // A confirmation requested from an action, consumed by the popup.
    property string pendingRequest: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    // KDE's reading first; the driver's published value covers a missing UPower entry.
    readonly property var battery: powerSource.battery || Output.driverBattery(linkStatus)
    readonly property bool batteryAvailable: battery !== null
    onBatteryAvailableChanged: {
        if (batteryAvailable) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onConnectedChanged: {
        if (connected && root.expanded)
            readSettings();
        if (connected) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onExpandedChanged: {
        if (root.expanded) {
            linkMonitor.refresh();
            readSettings();
        }
        else {
            pairingError = "";
            pairingResult = "";
            powerError = "";
            powerResult = "";
        }
    }
    function label(english, spanish) {
        return Output.text(english, spanish, Qt.locale().name)
    }
    function openSettings() {
        KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
    }
    function openHeadsetSettings() {
        Plasmoid.internalAction("configure").trigger();
    }
    // Actions only open the popup's confirmation; nothing runs from the menu.
    function requestConfirmation(action) {
        if (pairingBusy || powerBusy)
            return;
        root.expanded = true;
        pendingRequest = action;
    }
    function openPairing() {
        if (pairingBusy || powerBusy)
            return;
        pairingError = "";
        pairingResult = "";
        pairingBusy = true;
        pairingLauncher.connectSource(Output.pairingCommand(Qt.locale().name));
    }

    function turnOffHeadset() {
        if (pairingBusy || powerBusy)
            return;
        powerError = "";
        powerResult = "";
        powerBusy = true;
        powerLauncher.connectSource(Output.powerOffCommand(Qt.locale().name));
    }
    Plasma5Support.DataSource {
        id: powerLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.powerBusy = false;
            linkMonitor.refresh();
            if (data["exit code"] === 0)
                root.powerResult = root.label(
                    "Power-off request sent. Use the headset button to turn it on again.",
                    "Solicitud de apagado enviada. Usa el botón de los auriculares para encenderlos de nuevo.");
            else
                root.powerError = root.label("Could not send the power-off request.",
                    "No se pudo enviar la solicitud de apagado.") + "\n"
                    + String(data.stderr || data.stdout || "").trim();
        }
    }

    // Do Not Disturb and Bluetooth gaming mode are read once each time the
    // popup opens with a confirmed link. Their menu actions show the last value
    // read and set the opposite.
    HeadsetController {
        id: settingsController
        target: root.target
        activeView: false
    }
    function settingState(feature) {
        const response = settingsController.response;
        return response && response.state && typeof response.state[feature] === "boolean"
            ? response.state[feature] : null;
    }
    readonly property var dndState: settingState("dnd")
    readonly property var gamingState: settingState("gaming")
    // Bluetooth gaming mode is read through either transport but set only over
    // Bluetooth.
    readonly property bool gamingSettable: settingsController.response !== null
        && settingsController.response.transport === "bluetooth"

    function readSettings() {
        if (connected && !settingsController.busy)
            settingsController.request({op: "status"});
    }
    function setSetting(feature, enabled) {
        if (connected && !settingsController.busy)
            settingsController.request({op: "set", feature: feature, value: enabled});
    }

    BatteryMonitor {
        id: powerSource
        preferBluetooth: root.target.transport === "bluetooth"
        // The driver registers its battery only on a confirmed link change.
        onPresenceChanged: linkMonitor.refresh()
    }

    LinkMonitor {
        id: linkMonitor
        Component.onCompleted: refresh()
    }

    // Read only while the status is on screen; the closed panel icon follows the
    // events above. There is no background monitor process.
    Timer {
        interval: root.expanded ? 5000 : 30000
        repeat: true
        running: root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar
        onTriggered: linkMonitor.refresh()
    }

    Plasma5Support.DataSource {
        id: pairingLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.pairingBusy = false;
            linkMonitor.refresh();
            const details = String(data.stdout || "").trim() + "\n" + String(data.stderr || "").trim();
            if (data["exit code"] === 0)
                root.pairingResult = root.label(
                    "Paired. Turn the headset off and on to start the link.",
                    "Emparejado. Apaga y enciende los auriculares para iniciar la conexión.");
            else
                root.pairingError = root.label(
                    "Pairing failed. Check the adapter and HID permissions, and that barracuda-pair is installed on your PATH.",
                    "No se pudo emparejar. Comprueba el adaptador, los permisos HID y que barracuda-pair esté instalado en tu PATH.")
                    + "\n" + details.trim();
        }
    }

    // The panel and tray draw the symbolic glyph in compactRepresentation; this
    // icon only names the widget. Plasma gives the configuration window its own
    // generic icon regardless of this value.
    Plasmoid.icon: "audio-headset"
    Plasmoid.status: ({
        active: PlasmaCore.Types.ActiveStatus,
        passive: PlasmaCore.Types.PassiveStatus,
        attention: PlasmaCore.Types.NeedsAttentionStatus
    })[Output.trayStatus(connection, battery, pairingBusy || powerBusy)]
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.target.transport === "bluetooth"
                ? root.label("Pair USB dongle…", "Emparejar dongle USB…")
                : root.label("Pair Barracuda…", "Emparejar Barracuda…")
            icon.name: "network-wireless"
            enabled: !root.pairingBusy && !root.powerBusy
            onTriggered: root.requestConfirmation("pairing")
        },
        PlasmaCore.Action {
            text: root.target.transport === "bluetooth"
                ? root.label("Turn off through USB dongle…", "Apagar mediante dongle USB…")
                : root.label("Turn off headset…", "Apagar auricular…")
            icon.name: "system-shutdown"
            enabled: !root.pairingBusy && !root.powerBusy
            onTriggered: root.requestConfirmation("power-off")
        },
        PlasmaCore.Action {
            id: dndAction
            text: root.label("Do Not Disturb", "No molestar")
            icon.name: "notifications-disabled"
            checkable: true
            checked: root.dndState === true
            enabled: root.connected && !settingsController.busy && !root.pairingBusy && !root.powerBusy
            onTriggered: {
                const value = dndAction.checked;
                dndAction.checked = Qt.binding(() => root.dndState === true);
                // Without a reading, open the popup, which reads it.
                if (root.dndState === null)
                    root.expanded = true;
                else
                    root.setSetting("dnd", value);
            }
        },
        PlasmaCore.Action {
            id: gamingAction
            text: root.label("Bluetooth gaming mode", "Modo gaming Bluetooth")
            icon.name: "input-gamepad"
            checkable: true
            checked: root.gamingState === true
            // Without a reading the transport is unknown; the popup reads it.
            enabled: root.connected && (root.gamingState === null || root.gamingSettable)
                && !settingsController.busy && !root.pairingBusy && !root.powerBusy
            onTriggered: {
                const value = gamingAction.checked;
                gamingAction.checked = Qt.binding(() => root.gamingState === true);
                if (root.gamingState === null)
                    root.expanded = true;
                else
                    root.setSetting("gaming", value);
            }
        }
    ]

    toolTipMainText: "Razer Barracuda X"
    toolTipSubText: statusText
        + (battery ? "\n" + label("Battery: ", "Batería: ")
            + Output.batteryText(battery, Qt.locale().name) : "")
    // Only the desktop forces the full view. Panels choose the compact icon by
    // size, and the system tray opens its popup only for applets without a
    // preferred representation.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : null
    compactRepresentation: PC3.ToolButton {
        // Panel and tray icons have no button frame on hover; retain the theme's keyboard focus.
        background.visible: visualFocus
        focusPolicy: Qt.TabFocus
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: Kirigami.Units.iconSizes.smallMedium
        // Keep the full click target while sizing artwork independently.
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : 0
        Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : 0
        Layout.preferredWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : implicitWidth
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : implicitHeight
        contentItem: Item {
            HeadsetArtwork {
                anchors.centerIn: parent
                // The tray sizes its icons; a loose panel icon stays at the
                // usual panel icon size.
                width: root.inTray ? Math.min(parent.width, parent.height)
                    : Math.min(parent.width, parent.height, Kirigami.Units.iconSizes.smallMedium)
                height: width
                symbolic: true
                connected: root.connected
                slashed: root.slashed
                emblem: root.emblem
                emblemSize: Math.min(Kirigami.Units.iconSizes.small, width / 2)
            }
        }
        Accessible.name: "Razer Barracuda X"
        Accessible.description: root.statusText
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: HeadsetPanel {
        status: root.linkStatus
        target: root.target
        activeView: root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar
        showHeader: !root.inTray
        request: root.pendingRequest
        onRequestHandled: root.pendingRequest = ""
        pairingBusy: root.pairingBusy
        pairingError: root.pairingError
        pairingResult: root.pairingResult
        powerBusy: root.powerBusy
        powerError: root.powerError
        powerResult: root.powerResult
        battery: root.battery
        dndState: root.dndState
        gamingState: root.gamingState
        gamingSettable: root.gamingSettable
        configureText: Plasmoid.internalAction("configure") ? Plasmoid.internalAction("configure").text : ""
        settingsBusy: settingsController.busy
        onSettingsRequested: root.openSettings()
        onHeadsetSettingsRequested: root.openHeadsetSettings()
        onPairingRequested: root.openPairing()
        onPowerOffRequested: root.turnOffHeadset()
        onSettingChangeRequested: (feature, enabled) => root.setSetting(feature, enabled)
    }
}
