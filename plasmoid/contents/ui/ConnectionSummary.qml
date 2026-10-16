import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.workspace.components as WorkspaceComponents
import "../code/output.js" as Output

// The popup body, top to bottom: how the headset is (state, hint, battery),
// what can be done to it now (Pair, Turn Off, each confirmed right below), how
// its connection behaves (Do Not Disturb, Bluetooth gaming mode), which
// Bluetooth device it serves (Quick Connect) and, folded, the diagnostic
// details. Feedback appears under the control that caused it.
ColumnLayout {
    id: summary

    property var status: null
    property string localeName: Qt.locale().name
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property bool confirmingPowerOff: false
    property bool confirmingPairing: false
    // The headset settings controller (HeadsetController): its last status
    // read, whether a request runs and its feedback.
    property var settings: null
    readonly property bool settingsBusy: settings !== null && settings.busy === true
    // Only a reading taken with a confirmed link is shown; anything else is
    // unknown, never Off.
    readonly property var settingsState: connected && settings !== null && settings.response
        && settings.response.state ? settings.response.state : null
    readonly property var dndState: settingValue("dnd")
    readonly property var gamingState: settingValue("gaming")
    // Bluetooth gaming mode is read through either transport but set only over
    // Bluetooth.
    readonly property bool gamingSettable: settingsState !== null && settings.response.transport === "bluetooth"
    function settingValue(feature) {
        return settingsState !== null && typeof settingsState[feature] === "boolean" ? settingsState[feature] : null;
    }
    // Settings change only with a confirmed link and while nothing else runs.
    readonly property bool settingsEnabled: connected && !settingsBusy && !pairingBusy && !powerBusy
    // Feedback for the connection modes: a failed request for them or a failed
    // read, and the modes' own read errors.
    readonly property string modesError: settings === null ? ""
        : settings.error.length > 0 && settings.requestFeature !== "devices" ? settings.error
        : featureError(["dnd", "gaming"])
    // Feedback for Quick Connect: a failed switch request, or a read error of
    // the device list that the modes' notice does not already give.
    readonly property string quickConnectError: settings === null ? ""
        : settings.requestFeature === "devices" ? settings.error
        : settings.error.length > 0 || featureError(["devices"]) === modesError ? ""
        : featureError(["devices"])
    // A switch request does not confirm the new active device; only a new
    // read can, so its notice offers Refresh.
    readonly property string switchMessage: settings !== null && settings.response
        && settings.response.sent === "devices" ? settings.message : ""
    function featureName(feature) {
        return ({dnd: label("Do Not Disturb", "No molestar"),
                 gaming: label("Bluetooth Gaming Mode", "Modo gaming Bluetooth"),
                 devices: "Quick Connect"})[feature] || feature;
    }
    // One notice for the read errors of these features; each is named when
    // they differ. Kept on one paragraph: Kirigami's InlineMessage with an
    // action loops on short lines split by a hard line break.
    function featureError(features) {
        const errors = settingsState !== null && settings.response.errors ? settings.response.errors : {};
        const failed = features.filter(feature => errors[feature]);
        if (!failed.length)
            return "";
        if (failed.every(feature => errors[feature] === errors[failed[0]]))
            return settings.errorLabel(errors[failed[0]]);
        return failed.map(feature => featureName(feature) + ": " + settings.errorLabel(errors[feature])).join(" ");
    }
    property bool activeView: true
    // Diagnostic rows (dongle, link, cable, voltage) stay folded by default.
    property bool showDetails: false
    onActiveViewChanged: {
        if (!activeView) {
            confirmingPairing = false;
            confirmingPowerOff = false;
            showDetails = false;
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
    // Pairing and power-off need the dongle; only a confirmed missing dongle
    // disables them.
    readonly property bool adapterMissing: Output.adapterMissing(status)
    readonly property bool commandsEnabled: !pairingBusy && !powerBusy && !adapterMissing
    // Why both commands are disabled without the dongle.
    readonly property string commandsHint: adapterMissing
        ? label("Connect the USB dongle first.", "Conecta primero el dongle USB.") : ""
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
    signal pairingRequested()
    signal powerOffRequested()
    signal settingChangeRequested(string feature, bool enabled)
    signal settingsRefreshRequested()
    signal sourceSwitchRequested(string address)

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
                // The popup's only help button: connection and battery. The
                // connection modes explain themselves on their own rows.
                Kirigami.ContextualHelpButton {
                    objectName: "connectionHelp"
                    toolTipText: summary.label(
                        "Shows how the headset is connected and its last battery reading. “Link not confirmed” means the connection is not known yet, not that the headset is off.",
                        "Muestra cómo está conectado el auricular y su última lectura de batería. «Conexión no confirmada» significa que aún no se sabe si está conectado, no que esté apagado.")
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

    // What can be done to the headset now. Both commands stay visible; they
    // are disabled only while one runs or when the driver reports no dongle.
    Flow {
        objectName: "deviceCommands"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        PC3.Button {
            objectName: "pairButton"
            text: summary.label("Pair USB Dongle…", "Emparejar dongle USB…")
            icon.name: "network-wireless"
            enabled: summary.commandsEnabled
            onClicked: summary.confirm("pairing")
            PC3.ToolTip.text: summary.commandsHint
            PC3.ToolTip.visible: hovered && summary.commandsHint.length > 0
        }
        PC3.Button {
            objectName: "powerOffButton"
            text: summary.label("Turn Off Headset…", "Apagar auricular…")
            icon.name: "system-shutdown"
            enabled: summary.commandsEnabled
            onClicked: summary.confirm("power-off")
            PC3.ToolTip.text: summary.commandsHint
            PC3.ToolTip.visible: hovered && summary.commandsHint.length > 0
        }
    }

    // Pairing: confirmation, progress and result, right under its button.
    Kirigami.InlineMessage {
        objectName: "pairingStatus"
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
    RowLayout {
        objectName: "pairingConfirmation"
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPairing
        PC3.Button {
            objectName: "confirmPairingButton"
            text: summary.label("Pair", "Emparejar")
            icon.name: "network-wireless"
            enabled: !summary.pairingBusy && !summary.powerBusy && !summary.adapterMissing
            // The confirming button is the primary one: it takes keyboard
            // focus, which Plasma draws highlighted.
            onVisibleChanged: {
                if (visible)
                    forceActiveFocus(Qt.TabFocusReason);
            }
            onClicked: {
                summary.confirmingPairing = false;
                summary.pairingRequested();
            }
        }
        PC3.Button {
            objectName: "cancelPairingButton"
            text: summary.label("Cancel", "Cancelar")
            icon.name: "dialog-cancel"
            onClicked: summary.confirmingPairing = false
        }
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
        objectName: "pairingError"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        visible: summary.pairingError.length > 0 && !summary.confirmingPairing
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

    // Power-off: confirmation, progress and result.
    Kirigami.InlineMessage {
        objectName: "powerStatus"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPowerOff || summary.powerBusy
            || summary.powerError.length > 0 || summary.powerResult.length > 0
        type: summary.confirmingPowerOff ? Kirigami.MessageType.Warning
            : summary.powerError.length > 0 ? Kirigami.MessageType.Error : Kirigami.MessageType.Information
        text: summary.powerBusy ? summary.label("Sending power-off request…", "Enviando solicitud de apagado…")
            : summary.confirmingPowerOff ? summary.label(
                "Turn off the headset through the USB dongle? Use its button to turn it on again.",
                "¿Apagar el auricular mediante el dongle USB? Usa su botón para encenderlo de nuevo.")
            : summary.powerError.length > 0 ? summary.powerError : summary.powerResult
    }
    RowLayout {
        objectName: "powerOffConfirmation"
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPowerOff
        PC3.Button {
            objectName: "confirmPowerOffButton"
            text: summary.label("Turn Off", "Apagar")
            icon.name: "system-shutdown"
            enabled: !summary.pairingBusy && !summary.powerBusy && !summary.adapterMissing
            onVisibleChanged: {
                if (visible)
                    forceActiveFocus(Qt.TabFocusReason);
            }
            onClicked: {
                summary.confirmingPowerOff = false;
                summary.powerOffRequested();
            }
        }
        PC3.Button {
            objectName: "cancelPowerOffButton"
            text: summary.label("Cancel", "Cancelar")
            icon.name: "dialog-cancel"
            onClicked: summary.confirmingPowerOff = false
        }
    }

    // Offered only inside the messages that ask for it; reopening the popup
    // also reads the headset again.
    Kirigami.Action {
        id: refreshAction
        objectName: "refreshSettings"
        icon.name: "view-refresh"
        text: summary.label("Refresh", "Actualizar")
        enabled: summary.connected && !summary.settingsBusy
        onTriggered: summary.settingsRefreshRequested()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
    }

    // How the headset's connection behaves. Always laid out, so the popup
    // keeps its shape; each switch changes the headset directly.
    ColumnLayout {
        objectName: "connectionModes"
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        SettingRow {
            objectName: "dnd"
            iconName: "notifications-disabled-symbolic"
            text: summary.label("Do Not Disturb", "No molestar")
            description: summary.label(
                "Calls from a phone connected by Bluetooth do not interrupt the dongle audio. Desktop notifications are not affected.",
                "Las llamadas de un teléfono conectado por Bluetooth no interrumpen el audio del dongle. No afecta a las notificaciones del escritorio.")
            value: summary.dndState
            busy: summary.settingsBusy
            interactive: summary.settingsEnabled
            localeName: summary.localeName
            onToggleRequested: value => summary.settingChangeRequested("dnd", value)
        }
        SettingRow {
            objectName: "gaming"
            iconName: "input-gamepad-symbolic"
            text: summary.label("Bluetooth Gaming Mode", "Modo gaming Bluetooth")
            description: summary.label("Lowers Bluetooth audio delay. Not the Game sound profile.",
                                       "Reduce el retraso del audio Bluetooth. No es el perfil de sonido Juegos.")
            // With both links confirmed the settings may follow the dongle
            // even though Bluetooth is connected; say which one they use.
            disabledReason: summary.settingsState !== null && !summary.gamingSettable
                ? summary.label("Can be changed only over Bluetooth; settings are being read through the USB dongle.",
                                "Solo se puede cambiar por Bluetooth; los ajustes se están leyendo mediante el dongle USB.")
                : ""
            value: summary.gamingState
            busy: summary.settingsBusy
            interactive: summary.settingsEnabled && summary.gamingSettable
            localeName: summary.localeName
            onToggleRequested: value => summary.settingChangeRequested("gaming", value)
        }
    }
    // No success notice: each switch shows the value the headset confirmed.
    Kirigami.InlineMessage {
        objectName: "connectionModesError"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        type: Kirigami.MessageType.Warning
        visible: text.length > 0
        text: summary.modesError
        actions: [refreshAction]
    }

    // Which Bluetooth device the headset serves, from the same status read.
    // The active marker moves only when a new reading says so.
    ColumnLayout {
        id: quickConnect
        objectName: "quickConnect"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        readonly property var devices: summary.settingsState !== null && summary.settingsState.devices
            && summary.settingsState.devices.length !== undefined ? summary.settingsState.devices : null
        // Switching needs Bluetooth gaming mode known to be off.
        readonly property bool blocked: devices !== null && devices.length > 0 && summary.gamingState !== false
        Kirigami.Heading {
            objectName: "quickConnectHeading"
            Layout.fillWidth: true
            level: 4
            // Razer's name for the feature, in every language.
            text: "Quick Connect"
            textFormat: Text.PlainText
        }
        PC3.Label {
            objectName: "quickConnectDescription"
            Layout.fillWidth: true
            text: summary.label("Move the headset's Bluetooth connection to a device it already knows. Switching may interrupt audio.",
                                "Mueve la conexión Bluetooth del auricular a un dispositivo que ya conoce. El cambio puede interrumpir el audio.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }
        PC3.Label {
            objectName: "quickConnectBlocked"
            Layout.fillWidth: true
            visible: quickConnect.blocked
            text: summary.label("Turn off Bluetooth Gaming Mode above to switch devices.",
                                "Desactiva el modo gaming Bluetooth (arriba) para cambiar de dispositivo.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        ColumnLayout {
            objectName: "quickConnectDevices"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: quickConnect.devices !== null && quickConnect.devices.length > 0
            Repeater {
                model: quickConnect.devices !== null ? quickConnect.devices : []
                RowLayout {
                    id: deviceRow
                    required property var modelData
                    readonly property string text: modelData.name || Output.macAddress(modelData.address)
                    objectName: "quickConnectDevice"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: "network-bluetooth"
                        opacity: deviceRow.modelData.active ? 1 : 0.6
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PC3.Label {
                            objectName: "quickConnectName"
                            Layout.fillWidth: true
                            text: deviceRow.text
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.bold: deviceRow.modelData.active === true
                        }
                        PC3.Label {
                            objectName: "quickConnectDetail"
                            Layout.fillWidth: true
                            // A nameless device already shows its address as its title.
                            visible: text !== ""
                            text: deviceRow.modelData.active ? summary.label("Active source", "Fuente activa")
                                : deviceRow.modelData.name ? Output.macAddress(deviceRow.modelData.address) : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    Kirigami.Icon {
                        objectName: "quickConnectActive"
                        visible: deviceRow.modelData.active === true
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: "checkmark"
                        color: Kirigami.Theme.positiveTextColor
                        isMask: true
                    }
                    PC3.Button {
                        objectName: "quickConnectButton"
                        visible: deviceRow.modelData.active !== true
                        icon.name: "network-connect"
                        text: summary.label("Switch", "Cambiar")
                        Accessible.name: summary.label("Switch to ", "Cambiar a ") + deviceRow.text
                        enabled: summary.settingsEnabled && !quickConnect.blocked
                        onClicked: summary.sourceSwitchRequested(deviceRow.modelData.address)
                    }
                }
            }
        }
        PC3.Label {
            objectName: "quickConnectEmpty"
            Layout.fillWidth: true
            visible: quickConnect.devices !== null && quickConnect.devices.length === 0
            text: summary.label("No known Bluetooth devices. Pair the headset with a phone or computer first.",
                                "No hay dispositivos Bluetooth conocidos. Primero empareja el auricular con un teléfono o computador.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            opacity: 0.75
        }
        PC3.Label {
            objectName: "quickConnectUnread"
            Layout.fillWidth: true
            visible: quickConnect.devices === null
            text: summary.connected && summary.settingsBusy ? summary.label("Reading…", "Leyendo…")
                : summary.label("Known devices appear once the headset is connected and read.",
                                "Los dispositivos conocidos aparecen cuando el auricular está conectado y se ha leído.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            opacity: 0.75
        }
    }
    Kirigami.InlineMessage {
        objectName: "quickConnectMessage"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        type: Kirigami.MessageType.Information
        visible: text.length > 0
        text: summary.switchMessage
        actions: [refreshAction]
    }
    Kirigami.InlineMessage {
        objectName: "quickConnectError"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        type: Kirigami.MessageType.Warning
        visible: text.length > 0
        text: summary.quickConnectError
        actions: [refreshAction]
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

    // The system tray gives the popup a fixed size; the free space stays
    // below the content.
    Item {
        objectName: "footerSpacer"
        Layout.fillHeight: true
    }
}
