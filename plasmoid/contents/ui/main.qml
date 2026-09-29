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
    // Follow the server default, not individual applications' output overrides.
    readonly property var sink: Server.defaultSink
    readonly property bool hasOutput: Output.available(sink)
    readonly property string deviceName: hasOutput ? (sink.description || sink.name)
        : label("No audio output", "Sin salida de audio")
    readonly property string deviceIcon: Output.icon(sink)
    readonly property string deviceArtwork: Output.artwork(deviceIcon)
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    readonly property var battery: powerSource.battery
    readonly property bool batteryAvailable: battery !== null
    onBatteryAvailableChanged: {
        if (batteryAvailable) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onExpandedChanged: {
        if (!expanded) {
            pairingError = "";
            pairingResult = "";
        }
    }
    function label(english, spanish) {
        return Output.text(english, spanish, Qt.locale().name)
    }
    function openSettings() {
        KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
    }
    function openPairing() {
        if (pairingBusy)
            return;
        pairingError = "";
        pairingResult = "";
        pairingBusy = true;
        pairingLauncher.connectSource(Output.pairingCommand(Qt.locale().name));
    }

    BatteryMonitor {
        id: powerSource
    }

    Plasma5Support.DataSource {
        id: pairingLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.pairingBusy = false;
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

    Plasmoid.icon: deviceArtwork
    toolTipMainText: deviceName
    toolTipSubText: Output.status(sink, Qt.locale().name)
        + (battery ? "\n" + label("Barracuda battery: ", "Batería del Barracuda: ")
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
            Image {
                id: panelArtwork
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height, Kirigami.Units.iconSizes.medium)
                height: width
                source: root.deviceArtwork.startsWith("file:") ? root.deviceArtwork : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: panelArtwork
                source: root.deviceIcon
                visible: panelArtwork.status !== Image.Ready
            }
            Kirigami.Icon {
                anchors.right: panelArtwork.right
                anchors.bottom: panelArtwork.bottom
                width: Math.min(Kirigami.Units.iconSizes.small, panelArtwork.width / 2)
                height: width
                source: "audio-volume-muted"
                visible: root.hasOutput && root.sink.muted
            }
        }
        Accessible.name: root.deviceName
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: OutputPanel {
        sink: root.sink
        activeView: root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar
        pairingBusy: root.pairingBusy
        pairingError: root.pairingError
        pairingResult: root.pairingResult
        battery: root.battery
        onSettingsRequested: root.openSettings()
        onPairingRequested: root.openPairing()
    }
}
