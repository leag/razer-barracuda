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
    // Settings read when the popup opens: null until the headset answers.
    property var dndState: null
    property var gamingState: null
    property bool settingsBusy: false
    // Bluetooth gaming mode can be changed only over Bluetooth.
    property bool gamingSettable: false
    property bool activeView: true
    // Diagnostic rows (dongle, link, cable, voltage) stay folded by default.
    property bool showDetails: false
    // The system tray draws its own heading with the applet's actions.
    property bool showHeader: true
    onActiveViewChanged: {
        if (!activeView) {
            confirmingPairing = false;
            confirmingPowerOff = false;
            showDetails = false;
            moreActions.close();
        }
    }
    property var battery: null
    readonly property bool batteryAvailable: battery !== null
    readonly property var connection: Output.connection(status)
    readonly property bool connected: connection.state === "connected"
    readonly property bool showBattery: batteryAvailable || connected
    // The transport icon beside it says how; the text says whether.
    readonly property string statusText: Output.connectionText(connection, localeName, false)
    readonly property string hintText: Output.connectionHint(status, connection, localeName)
    readonly property var details: Output.connectionDetails(status, localeName)
    readonly property bool viaBluetooth: target.transport === "bluetooth"
    // Pairing and power-off need the dongle; only a confirmed missing adapter
    // disables them.
    readonly property bool adapterMissing: Output.adapterMissing(status)
    readonly property bool commandsEnabled: !pairingBusy && !powerBusy && !adapterMissing
    // Any read state without a connection; not while the first read is pending.
    readonly property bool offerPairing: status !== null && !connected
    // Static: pairing and power-off always go through the USB dongle.
    readonly property string pairLabel: label("Pair USB Dongle…", "Emparejar dongle USB…")
    onAdapterMissingChanged: {
        if (adapterMissing) {
            confirmingPairing = false;
            confirmingPowerOff = false;
        }
    }
    onBatteryAvailableChanged: {
        if (batteryAvailable)
            confirmingPairing = false;
    }
    onConnectedChanged: {
        if (connected)
            confirmingPairing = false;
    }
    signal headsetSettingsRequested()
    // Text of Plasma's own "Configure …" action, so the button and the context
    // menu name the same window identically. Empty outside Plasma.
    property string configureText: ""
    signal settingsRequested()
    signal pairingRequested()
    signal powerOffRequested()
    signal settingChangeRequested(string feature, bool enabled)

    function label(english, spanish) {
        return Output.text(english, spanish, localeName)
    }
    // Shows the inline confirmation for "pairing" or "power-off"; nothing runs
    // until it is accepted.
    function confirm(action) {
        if (!commandsEnabled)
            return;
        confirmingPairing = action === "pairing";
        confirmingPowerOff = action === "power-off";

    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: implicitHeight
    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        objectName: "summaryHeader"
        visible: summary.showHeader
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 3
            text: summary.label("Barracuda Headset", "Auricular Barracuda")
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
                    text: summary.pairLabel
                    icon.name: "network-wireless"
                    enabled: summary.commandsEnabled
                    onTriggered: summary.confirm("pairing")
                }
                PC3.MenuItem {
                    objectName: "powerOffButton"
                    text: summary.label("Turn Off Headset…", "Apagar auricular…")
                    icon.name: "system-shutdown"
                    enabled: summary.commandsEnabled
                    onTriggered: summary.confirm("power-off")
                }
                PC3.MenuItem {
                    objectName: "dndMenuItem"
                    text: summary.label("Do Not Disturb", "No molestar")
                    icon.name: "notifications-disabled"
                    checkable: true
                    // Shows only the value the headset reported.
                    checked: summary.dndState === true
                    enabled: summary.connected && summary.dndState !== null && !summary.settingsBusy
                        && !summary.pairingBusy && !summary.powerBusy
                    onTriggered: {
                        const value = checked;
                        checked = Qt.binding(() => summary.dndState === true);
                        summary.settingChangeRequested("dnd", value);
                    }
                }
                PC3.MenuItem {
                    objectName: "gamingMenuItem"
                    text: summary.label("Bluetooth Gaming Mode", "Modo gaming Bluetooth")
                    icon.name: "input-gamepad"
                    checkable: true
                    checked: summary.gamingState === true
                    enabled: summary.connected && summary.gamingSettable && summary.gamingState !== null
                        && !summary.settingsBusy && !summary.pairingBusy && !summary.powerBusy
                    onTriggered: {
                        const value = checked;
                        checked = Qt.binding(() => summary.gamingState === true);
                        summary.settingChangeRequested("gaming", value);
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

        HeadsetArtwork {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            connected: summary.connected
            slashed: Output.slashed(summary.connection)
            emblem: Output.emblem(summary.connection, summary.battery)
            emblemSize: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    objectName: "transportIcon"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: Output.transportIcon(summary.connection)
                    visible: source !== ""
                    color: Kirigami.Theme.positiveTextColor
                    isMask: true
                    Accessible.role: Accessible.Graphic
                    Accessible.name: Output.transportText(summary.connection.transport, summary.localeName)
                }
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
                Kirigami.ContextualHelpButton {
                    objectName: "connectionHelp"
                    toolTipText: summary.label(
                        "Shows how the headset is connected and its last battery reading. “Link not confirmed” means the connection is not known yet, not that the headset is off.\n\nDo Not Disturb keeps calls from a phone connected by Bluetooth from interrupting the dongle audio. It does not silence desktop notifications.\n\nBluetooth gaming mode lowers audio delay. It can only be changed while the headset is connected by Bluetooth.",
                        "Muestra cómo está conectado el auricular y su última lectura de batería. «Conexión no confirmada» significa que aún no se sabe si está conectado, no que esté apagado.\n\nNo molestar evita que las llamadas de un teléfono conectado por Bluetooth interrumpan el audio del dongle. No silencia las notificaciones del escritorio.\n\nEl modo gaming Bluetooth reduce el retraso del audio. Solo se puede cambiar cuando el auricular está conectado por Bluetooth.")
                }
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
            RowLayout {
                objectName: "headsetBatteryRow"
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: summary.showBattery
                WorkspaceComponents.BatteryIcon {
                    objectName: "headsetBatteryIcon"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    batteryType: ""
                    hasBattery: summary.batteryAvailable
                    percent: summary.battery ? summary.battery.percent : 0
                    pluggedIn: summary.battery !== null && summary.battery.state === "Charging"
                    Accessible.name: summary.label("Barracuda battery", "Batería del Barracuda")
                    Accessible.description: Output.batteryText(summary.battery, summary.localeName)
                }
                PC3.Label {
                    objectName: "batteryPercentage"
                    text: summary.battery ? summary.battery.percent + "%"
                        : summary.label("Battery unknown", "Batería desconocida")
                    textFormat: Text.PlainText
                }
                PC3.Label {
                    visible: batteryStatus.visible
                    text: "·"
                    opacity: 0.75
                }
                PC3.Label {
                    id: batteryStatus
                    objectName: "batteryStatus"
                    visible: summary.battery !== null
                        && ["Charging", "FullyCharged"].includes(summary.battery.state)
                    text: Output.batteryState(summary.battery, summary.localeName)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    opacity: 0.75
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // Without a connection the popup offers what pairing needs, beside the
    // state that calls for it. Confirmation, progress and results follow.
    RowLayout {
        objectName: "pairingSection"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.offerPairing
        PC3.Button {
            objectName: "pairNowButton"
            text: summary.pairLabel
            icon.name: "network-wireless"
            enabled: summary.commandsEnabled
            onClicked: summary.confirm("pairing")
            PC3.ToolTip.text: summary.label("Connect the USB dongle first.", "Conecta primero el dongle USB.")
            PC3.ToolTip.visible: hovered && summary.adapterMissing
        }
        Item { Layout.fillWidth: true }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        type: summary.confirmingPairing ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
        visible: summary.pairingBusy || summary.confirmingPairing || summary.pairingResult.length > 0
        text: summary.pairingBusy
            ? summary.label("Pairing… Keep the headset in pairing mode. Searching can take up to a minute; the result will appear here.",
                            "Emparejando… Mantén el auricular en modo de emparejamiento. La búsqueda puede tardar un minuto; el resultado aparecerá aquí.")
            : summary.confirmingPairing
                ? summary.label("Connect the USB dongle and put the headset in pairing mode. This replaces the dongle's current pairing.",
                                "Conecta el dongle USB y pon el auricular en modo de emparejamiento. Esto reemplaza el emparejamiento actual del dongle.")
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
            enabled: !summary.pairingBusy && !summary.adapterMissing
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
                "Turn off the headset through the USB dongle? Use its button to turn it on again.",
                "¿Apagar el auricular mediante el dongle USB? Usa su botón para encenderlo de nuevo.")
            : summary.powerError.length > 0 ? summary.powerError : summary.powerResult
    }
    RowLayout {
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPowerOff
        PC3.Button {
            objectName: "confirmPowerOffButton"
            text: summary.label("Turn Off", "Apagar")
            enabled: !summary.pairingBusy && !summary.powerBusy && !summary.adapterMissing
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

    Kirigami.Separator {
        visible: summary.connected
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
    }

    // Headset settings read when the popup opens; each is changed from its
    // action in the menu.
    SettingRow {
        objectName: "dnd"
        visible: summary.connected
        iconName: "notifications-disabled-symbolic"
        text: summary.label("Do Not Disturb", "No molestar")
        value: summary.dndState
        busy: summary.settingsBusy
        localeName: summary.localeName
    }
    SettingRow {
        objectName: "gaming"
        visible: summary.connected
        iconName: "input-gamepad-symbolic"
        text: summary.label("Bluetooth Gaming Mode", "Modo gaming Bluetooth")
        value: summary.gamingState
        busy: summary.settingsBusy
        localeName: summary.localeName
    }

    PC3.ToolButton {
        objectName: "detailsToggle"
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: summary.details.length > 0
        icon.name: summary.showDetails ? "arrow-down" : "arrow-right"
        text: summary.label("Details", "Detalles")
        Accessible.checkable: true
        Accessible.checked: summary.showDetails
        onClicked: summary.showDetails = !summary.showDetails
    }
    ColumnLayout {
        objectName: "connectionDetails"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        visible: summary.showDetails && summary.details.length > 0
        Repeater {
            model: summary.details
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    objectName: "detailIcon"
                    // Same size and column as the setting rows above.
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    source: modelData[2]
                }
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

    // In the system tray the popup has a fixed size; keep the actions at the
    // bottom and leave the free space above them.
    Item {
        objectName: "footerSpacer"
        Layout.fillHeight: true
    }

    Kirigami.Separator { Layout.fillWidth: true }

    GridLayout {
        objectName: "overviewActions"
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        // Stacked: both labels are long and must not be cut.
        columns: 1
        rowSpacing: 0
        PC3.ToolButton {
            objectName: "soundSettingsButton"
            icon.name: "audio-card-symbolic"
            // KDE's own name for this action in its volume applet.
            text: summary.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")
            onClicked: summary.settingsRequested()
        }
        PC3.ToolButton {
            id: headsetSettingsButton
            objectName: "headsetSettingsButton"
            // In the system tray the heading already has this configure button.
            visible: summary.showHeader
            icon.name: "configure"
            // Drop the keyboard accelerator marker of the menu action.
            text: summary.configureText.length > 0 ? summary.configureText.replace(/&(?!&)/g, "")
                : summary.label("Configure Barracuda Headset…", "Configurar Auricular Barracuda…")
            onClicked: summary.headsetSettingsRequested()
        }
    }
}
