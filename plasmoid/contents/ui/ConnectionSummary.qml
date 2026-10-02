import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.workspace.components as WorkspaceComponents
import "../code/output.js" as Output

ColumnLayout {
    id: summary

    property var status: null
    property var target: ({transport: "usb"})
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
    readonly property var connection: Output.connection(status)
    readonly property bool connected: connection.state === "connected"
    readonly property bool showBattery: batteryAvailable || connected
    readonly property string statusText: Output.connectionText(connection, localeName)
    readonly property string hintText: Output.connectionHint(status, connection, localeName)
    readonly property var details: Output.connectionDetails(status, localeName)
    readonly property bool viaBluetooth: target.transport === "bluetooth"
    onBatteryAvailableChanged: {
        if (batteryAvailable)
            confirmingPairing = false;
    }
    onConnectedChanged: {
        if (connected)
            confirmingPairing = false;
    }
    signal helpRequested()
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
            text: "Razer Barracuda X"
            textFormat: Text.PlainText
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
                    text: summary.viaBluetooth
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
                    text: summary.viaBluetooth
                        ? summary.label("Turn off through USB dongle…", "Apagar mediante dongle USB…")
                        : summary.label("Turn off headset…", "Apagar auricular…")
                    icon.name: "system-shutdown"
                    enabled: !summary.pairingBusy && !summary.powerBusy
                    onTriggered: {
                        summary.confirmingPairing = false;
                        summary.confirmingPowerOff = true;
                    }
                }
                PC3.MenuSeparator {}
                PC3.MenuItem {
                    objectName: "helpMenuItem"
                    text: summary.label("Help", "Ayuda")
                    icon.name: "help-contents"
                    onTriggered: summary.helpRequested()
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
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            Image {
                id: artwork
                anchors.fill: parent
                source: Output.artwork("audio-headset")
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
                opacity: summary.connected ? 1 : 0.5
            }
            Kirigami.Icon {
                anchors.fill: parent
                source: "audio-headset"
                visible: artwork.status !== Image.Ready
                opacity: artwork.opacity
            }
            Kirigami.Icon {
                objectName: "connectionEmblem"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                source: Output.emblem(summary.connection, summary.battery)
                visible: source !== ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                objectName: "connectionState"
                Layout.fillWidth: true
                text: summary.statusText
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.bold: true
                color: summary.connected ? Kirigami.Theme.positiveTextColor
                    : summary.connection.state === "unavailable" ? Kirigami.Theme.negativeTextColor
                    : Kirigami.Theme.textColor
            }
            PC3.Label {
                objectName: "connectionHint"
                Layout.fillWidth: true
                visible: text.length > 0
                text: summary.hintText
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.75
            }
        }
    }

    ColumnLayout {
        objectName: "connectionDetails"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: summary.details.length > 0
        Repeater {
            model: summary.details
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: modelData[0]
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    opacity: 0.75
                }
                PC3.Label {
                    objectName: "detailValue"
                    text: modelData[1]
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    Kirigami.Separator {
        visible: summary.showBattery
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.gridUnit
        objectName: "headsetBatteryRow"
        visible: summary.showBattery

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
        visible: summary.showBattery && !summary.batteryAvailable
        text: summary.label("No battery reading is available yet.",
                            "Aún no hay una lectura de batería disponible.")
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

    GridLayout {
        objectName: "overviewActions"
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        columns: width < Kirigami.Units.gridUnit * 20 ? 1 : 2
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.smallSpacing
        PC3.ToolButton {
            Layout.fillWidth: true
            objectName: "soundSettingsButton"
            icon.name: "configure"
            text: summary.label("Sound settings…", "Ajustes de sonido…")
            onClicked: summary.settingsRequested()
        }
        PC3.Button {
            Layout.fillWidth: true
            objectName: "configureEffectsButton"
            text: summary.label("Headset settings…", "Ajustes del auricular…")
            onClicked: summary.effectsRequested()
        }
    }
}
