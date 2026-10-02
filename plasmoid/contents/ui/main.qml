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
        if (connected) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onExpandedChanged: {
        if (root.expanded)
            linkMonitor.refresh();
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

    Plasmoid.icon: Output.artwork("audio-headset")
    toolTipMainText: "Razer Barracuda X"
    toolTipSubText: statusText
        + (battery ? "\n" + label("Battery: ", "Batería: ")
            + Output.batteryText(battery, Qt.locale().name) : "")
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : compactRepresentation
    compactRepresentation: PC3.ToolButton {
        // Panel icons have no button frame on hover; retain the theme's keyboard focus.
        background.visible: visualFocus
        focusPolicy: Qt.TabFocus
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
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
                width: Math.min(parent.width, parent.height, Kirigami.Units.iconSizes.medium)
                height: width
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
        pairingBusy: root.pairingBusy
        pairingError: root.pairingError
        pairingResult: root.pairingResult
        powerBusy: root.powerBusy
        powerError: root.powerError
        powerResult: root.powerResult
        battery: root.battery
        onSettingsRequested: root.openSettings()
        onPairingRequested: root.openPairing()
        onPowerOffRequested: root.turnOffHeadset()
    }
}
