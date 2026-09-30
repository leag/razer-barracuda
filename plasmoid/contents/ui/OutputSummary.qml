import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.workspace.components as WorkspaceComponents
import "../code/output.js" as Output

ColumnLayout {
    id: summary

    required property var sink
    property string localeName: Qt.locale().name
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property bool confirmingPowerOff: false
    property bool confirmingPairing: false
    property bool activeView: true
    onActiveViewChanged: {
        if (!activeView) {
            confirmingPairing = false;
            confirmingPowerOff = false;
            moreActions.close();
        }
    }
    property var battery: null
    readonly property bool batteryAvailable: battery !== null
    onBatteryAvailableChanged: {
        if (batteryAvailable)
            confirmingPairing = false;
    }
    readonly property bool hasOutput: Output.available(sink)
    readonly property string deviceName: Output.deviceName(sink, localeName)
    readonly property string deviceIcon: Output.icon(sink)
    readonly property string deviceArtwork: Output.artwork(deviceIcon)
    readonly property string statusText: (Output.bluetooth(sink) ? "Bluetooth · " : "")
        + Output.status(sink, localeName)
    signal effectsRequested()
    signal settingsRequested()
    signal pairingRequested()
    signal powerOffRequested()

    function label(english, spanish) {
        return Output.text(english, spanish, localeName)
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: implicitHeight
    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 3
            text: summary.label("Audio output", "Salida de audio")
        }
        PC3.ToolButton {
            objectName: "moreActionsButton"
            icon.name: "application-menu"
            text: summary.label("More actions", "Más acciones")
            display: PC3.AbstractButton.IconOnly
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
            onClicked: moreActions.popup()
            PC3.Menu {
                id: moreActions
                objectName: "moreActionsMenu"
                PC3.MenuItem {
                    objectName: "pairingButton"
                    text: Output.bluetooth(summary.sink)
                        ? summary.label("Pair USB dongle…", "Emparejar dongle USB…")
                        : summary.label("Pair Barracuda…", "Emparejar Barracuda…")
                    icon.name: "network-wireless"
                    enabled: !summary.pairingBusy && !summary.powerBusy
                    onTriggered: {
                        summary.confirmingPowerOff = false;
                        summary.confirmingPairing = true;
                    }
                }
                PC3.MenuItem {
                    objectName: "powerOffButton"
                    text: Output.bluetooth(summary.sink)
                        ? summary.label("Turn off through USB dongle…", "Apagar mediante dongle USB…")
                        : summary.label("Turn off headset…", "Apagar auricular…")
                    icon.name: "system-shutdown"
                    enabled: !summary.pairingBusy && !summary.powerBusy
                    onTriggered: {
                        summary.confirmingPairing = false;
                        summary.confirmingPowerOff = true;
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Item {
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            Image {
                id: artwork
                anchors.fill: parent
                source: summary.deviceArtwork.startsWith("file:") ? summary.deviceArtwork : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                source: summary.deviceIcon
                visible: artwork.status !== Image.Ready
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            PC3.Label {
                Layout.fillWidth: true
                text: summary.deviceName
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.bold: true
            }
            PC3.Label {
                Layout.fillWidth: true
                visible: summary.hasOutput
                text: summary.statusText
                wrapMode: Text.Wrap
            }
        }
    }

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: !summary.hasOutput
        text: summary.label("Connect an audio device to see its output here.", "Conecta un dispositivo de audio para ver su salida aquí.")
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.gridUnit

        WorkspaceComponents.BatteryIcon {
            objectName: "headsetBatteryIcon"
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            batteryType: ""
            hasBattery: summary.batteryAvailable
            percent: summary.battery ? summary.battery.percent : 0
            pluggedIn: summary.battery !== null && summary.battery.state === "Charging"
            Accessible.name: summary.label("Barracuda battery", "Batería del Barracuda")
            Accessible.description: Output.batteryText(summary.battery, summary.localeName)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: summary.label("Battery", "Batería")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
                PC3.Label {
                    objectName: "batteryPercentage"
                    text: summary.battery ? summary.battery.percent + "%"
                        : summary.label("Unknown", "Desconocido")
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                }
            }
            PC3.Label {
                objectName: "batteryStatus"
                visible: summary.battery !== null
                    && ["Charging", "FullyCharged"].includes(summary.battery.state)
                Layout.fillWidth: true
                text: Output.batteryState(summary.battery, summary.localeName)
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.75
            }
        }
    }

    PC3.Label {
        objectName: "batteryUnavailableHint"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: !summary.batteryAvailable
        text: summary.label("No battery reading is available. This does not determine whether the headset is connected.",
                            "No hay una lectura de batería disponible. Esto no indica si los auriculares están conectados.")
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        type: summary.confirmingPairing ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
        visible: summary.pairingBusy || summary.confirmingPairing || summary.pairingResult.length > 0
        text: summary.pairingBusy
            ? summary.label("Pairing… Keep the headset in pairing mode. Searching can take up to a minute; the result will appear here.",
                            "Emparejando… Mantén los auriculares en modo de emparejamiento. La búsqueda puede tardar un minuto; el resultado aparecerá aquí.")
            : summary.confirmingPairing
                ? summary.label("Connect the Barracuda dongle and put the headset in pairing mode. Continue? This replaces the dongle's current pairing.",
                                "Conecta el adaptador Barracuda y pon los auriculares en modo de emparejamiento. ¿Continuar? Esto reemplaza el emparejamiento actual del adaptador.")
                : summary.pairingResult
    }

    PC3.ProgressBar {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.pairingBusy
        indeterminate: summary.pairingBusy
        Accessible.name: summary.label("Pairing in progress", "Emparejamiento en curso")
    }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        visible: summary.pairingError.length > 0
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        contentWidth: width
        PC3.TextArea {
            text: summary.pairingError
            textFormat: TextEdit.PlainText
            readOnly: true
            color: Kirigami.Theme.negativeTextColor
            wrapMode: TextEdit.Wrap
        }
    }

    RowLayout {
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPairing
        PC3.Button {
            objectName: "confirmPairingButton"
            text: summary.label("Pair", "Emparejar")
            enabled: !summary.pairingBusy
            onClicked: {
                summary.confirmingPairing = false;
                summary.pairingRequested();
            }
        }
        PC3.Button {
            objectName: "cancelPairingButton"
            text: summary.label("Cancel", "Cancelar")
            onClicked: summary.confirmingPairing = false
        }
    }

    Kirigami.InlineMessage {
        objectName: "powerStatus"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPowerOff || summary.powerBusy
            || summary.powerError.length > 0 || summary.powerResult.length > 0
        type: summary.powerError.length > 0 ? Kirigami.MessageType.Error
            : summary.confirmingPowerOff ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
        text: summary.powerBusy ? summary.label("Sending power-off request…", "Enviando solicitud de apagado…")
            : summary.confirmingPowerOff ? summary.label(
                "Turn off the Barracuda headset? Use its physical button to turn it on again.",
                "¿Apagar los auriculares Barracuda? Usa su botón físico para encenderlos de nuevo.")
            : summary.powerError.length > 0 ? summary.powerError : summary.powerResult
    }
    RowLayout {
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPowerOff
        PC3.Button {
            objectName: "confirmPowerOffButton"
            text: summary.label("Turn off", "Apagar")
            enabled: !summary.pairingBusy && !summary.powerBusy
            onClicked: {
                summary.confirmingPowerOff = false;
                summary.powerOffRequested();
            }
        }
        PC3.Button {
            objectName: "cancelPowerOffButton"
            text: summary.label("Cancel", "Cancelar")
            onClicked: summary.confirmingPowerOff = false
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        PC3.ToolButton {
            objectName: "soundSettingsButton"
            icon.name: "configure"
            text: summary.label("Sound settings…", "Ajustes de sonido…")
            onClicked: summary.settingsRequested()
        }
        Item { Layout.fillWidth: true }
        PC3.Button {
            objectName: "configureEffectsButton"
            text: summary.label("Audio effects…", "Efectos de audio…")
            onClicked: summary.effectsRequested()
        }
    }
}
