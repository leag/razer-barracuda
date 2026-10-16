import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "../code/output.js" as Output

ColumnLayout {
    id: page
    objectName: "headsetSettings"
    required property var controller
    readonly property real contentHeight: settingsContent.implicitHeight + implicitHeight
    property string localeName: Qt.locale().name
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool bandsDirty: false
    readonly property var presetIds: [0, 7, 8, 9, 255]
    property int confirmedPreset: -1
    property bool applyingPreset: false
    readonly property string targetKey: controller.targetKey === undefined ? "" : controller.targetKey
    onTargetKeyChanged: { confirmedPreset = -1; bandsDirty = false; }
    readonly property bool showBands: available("preset") && state.preset === 255
    onStateChanged: {
        if (available("preset") && presetIds.includes(state.preset))
            confirmedPreset = state.preset;
    }
    // "equalizer" shows the headset EQ, "powerSaving" idle shutdown and
    // "quickConnect" Bluetooth source switching. Each is its own configuration
    // category.
    property string section: "equalizer"
    readonly property var sectionFeatures: ({equalizer: ["preset", "bands"], powerSaving: ["standby"],
                                             quickConnect: ["devices"]})[section] || []
    readonly property var state: controller.response ? controller.response.state : null
    // Do Not Disturb and Bluetooth gaming mode are in the popup and its action
    // menu. Quick Connect still needs gaming mode off.
    readonly property bool busy: controller.busy
    function label(en, es) { return Output.text(en, es, localeName); }
    function available(feature) { return state !== null && state[feature] !== null && state[feature] !== undefined; }
    function apply(feature, value) { controller.request({op: "set", feature: feature, value: value}); }
    // Custom bands are sent with the configuration window's Apply or OK button.
    readonly property bool unsavedBands: section === "equalizer" && showBands && bandsDirty && available("bands")
    function applyBands() {
        if (unsavedBands)
            apply("bands", bands);
    }
    readonly property string settingsError: {
        const errors = controller.response ? controller.response.errors || {} : {};
        const labels = {preset: label("Equalizer", "Ecualizador"), bands: label("Custom EQ", "EQ personalizado"),
                        gaming: label("Bluetooth gaming mode", "Modo gaming Bluetooth"), dnd: label("Do Not Disturb", "No molestar"),
                        standby: label("Idle shutdown", "Apagado por inactividad"), devices: "Quick Connect"};
        const keys = Object.keys(errors).filter(key => sectionFeatures.includes(key));
        if (!keys.length)
            return "";
        const codes = keys.map(key => errors[key]);
        if (codes.every(code => code === codes[0]))
            return controller.errorLabel(codes[0]);
        return keys.map(key => labels[key] + ": " + controller.errorLabel(errors[key])).join("\n");
    }
    function presetLabel(id) {
        return ({0: label("Default", "Predeterminado"), 7: label("Game", "Juegos"),
                 8: label("Music", "Música"), 9: label("Movie", "Cine"),
                 255: label("Custom", "Personalizado")})[id] || label("Unknown", "Desconocido");
    }
    readonly property string confirmedPresetIcon: presetIcon(confirmedPreset)
    // Breeze has no EQ profile icons; these are the closest standard ones.
    function presetIcon(id) {
        return ({0: "view-media-equalizer", 7: "input-gamepad", 8: "audio-x-generic",
                 9: "video-x-generic", 255: "configure"})[id] || "";
    }
    Connections {
        target: page.controller
        function onBusyChanged() {
            if (!page.controller.busy)
                page.applyingPreset = false;
        }
        function onLoaded(result) {
            page.applyingPreset = false;
            if (page.bandsDirty && result.sent !== "bands")
                return;
            // A var signal argument is no longer a JavaScript array, so
            // Array.isArray() rejects it; copy any list of ten values.
            const bands = result.state ? result.state.bands : null;
            if (bands && bands.length === 10)
                page.bands = Array.from(bands);
            page.bandsDirty = false;
        }
    }
    QQC2.ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: 0
        implicitWidth: Kirigami.Units.gridUnit * 22
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded
        contentWidth: availableWidth
        ColumnLayout {
            id: settingsContent
            width: scroll.availableWidth
            spacing: Kirigami.Units.largeSpacing
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                enabled: !page.busy
                ColumnLayout {
                    objectName: "equalizerSection"
                    Layout.fillWidth: true
                    visible: page.section === "equalizer"
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.FormLayout {
                        Layout.fillWidth: true
                        RowLayout {
                            Kirigami.FormData.label: page.label("Sound profile:", "Perfil de sonido:")
                            QQC2.ComboBox {
                                id: profileSelector
                                objectName: "nativeProfileSelector"
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                                wheelEnabled: false
                                Accessible.name: page.label("Sound profile", "Perfil de sonido")
                                textRole: "text"
                                model: page.presetIds.map(id => ({text: page.presetLabel(id), icon: page.presetIcon(id)}))
                                currentIndex: page.presetIds.indexOf(page.confirmedPreset)
                                onModelChanged: currentIndex = Qt.binding(() => page.presetIds.indexOf(page.confirmedPreset))
                                displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                                delegate: QQC2.ItemDelegate {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view ? ListView.view.width : implicitWidth
                                    text: modelData.text
                                    icon.name: modelData.icon
                                    highlighted: profileSelector.highlightedIndex === index
                                }
                                // The style draws the confirmed profile's icon in the closed selector.
                                Kirigami.StyleHints.iconName: page.confirmedPresetIcon
                                enabled: page.available("preset") && page.presetIds.includes(page.state.preset)
                                onActivated: index => {
                                    const value = page.presetIds[index];
                                    // Show only readback-confirmed selections, including after a failed SET.
                                    currentIndex = Qt.binding(() => page.presetIds.indexOf(page.confirmedPreset));
                                    if (value === page.confirmedPreset)
                                        return;
                                    page.applyingPreset = true;
                                    page.apply("preset", value);
                                }
                            }
                            Kirigami.ContextualHelpButton {
                                objectName: "profileHelp"
                                toolTipText: page.label(
                                    "Profiles are stored on the headset; the selection updates once the headset confirms it. For a custom EQ, choose Custom, adjust the bands (0 is neutral) and select Apply. Bluetooth gaming mode and the Game profile are independent.",
                                    "Los perfiles se guardan en el auricular; la selección se actualiza cuando el auricular la confirma. Para un EQ personalizado, elige Personalizado, ajusta las bandas (0 es neutro) y selecciona Aplicar. El modo gaming Bluetooth y el perfil Juegos son independientes.")
                            }
                        }
                        QQC2.Label {
                            objectName: "nativeProfileStatus"
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                            wrapMode: Text.Wrap
                            visible: page.applyingPreset || (!page.available("preset") && page.settingsError === "" && page.controller.error === "")
                            text: page.applyingPreset ? page.label("Applying profile…", "Aplicando perfil…")
                                : page.confirmedPreset >= 0
                                    ? page.label("Last confirmed profile. Refresh to read the current setting.",
                                                 "Último perfil confirmado. Actualiza para leer el ajuste actual.")
                                    : page.label("Applied profile unknown. Refresh to read the headset.",
                                                 "Perfil aplicado desconocido. Actualiza para leer el auricular.")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                    // A graphic equalizer: one vertical slider per band, the gain
                    // above it and the frequency below.
                    ColumnLayout {
                        Layout.fillWidth: true
                        objectName: "nativeCustomBands"
                        visible: page.showBands
                        enabled: page.available("bands")
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Heading {
                            level: 4
                            text: page.label("Custom bands", "Bandas personalizadas")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Repeater {
                                model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                                ColumnLayout {
                                    required property int index
                                    required property string modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: (page.bands[index] > 0 ? "+" : "") + page.bands[index]
                                        font: Kirigami.Theme.smallFont
                                        opacity: page.bands[index] === 0 ? 0.6 : 1
                                    }
                                    ScrollSafeSlider {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredHeight: Kirigami.Units.gridUnit * 9
                                        orientation: Qt.Vertical
                                        scrollItem: scroll.contentItem
                                        from: -5; to: 5; stepSize: 1
                                        snapMode: QQC2.Slider.SnapAlways
                                        value: page.bands[index]
                                        Accessible.name: modelData + " Hz"
                                        onMoved: {
                                            const next = page.bands.slice();
                                            next[index] = Math.round(value);
                                            page.bands = next;
                                            page.bandsDirty = JSON.stringify(next) !== JSON.stringify(page.state.bands);
                                        }
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.75
                                    }
                                }
                            }
                            // Unit legend, level with the frequency labels.
                            QQC2.Label {
                                objectName: "bandsUnit"
                                Layout.alignment: Qt.AlignBottom
                                text: "Hz"
                                font: Kirigami.Theme.smallFont
                                opacity: 0.75
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: page.label("Levels are relative; 0 is neutral. Apply sends the bands to the headset.",
                                                 "Los niveles son relativos; 0 es neutro. Aplicar envía las bandas al auricular.")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.75
                            }
                            QQC2.Button {
                                objectName: "resetNativeBands"
                                icon.name: "edit-reset"
                                text: page.label("Reset bands", "Restablecer bandas")
                                onClicked: {
                                    page.bands = [0,0,0,0,0,0,0,0,0,0];
                                    page.bandsDirty = JSON.stringify(page.bands) !== JSON.stringify(page.state.bands);
                                }
                            }
                        }
                    }
                }
                Kirigami.FormLayout {
                    objectName: "powerSaving"
                    Layout.fillWidth: true
                    visible: page.section === "powerSaving"
                    QQC2.ComboBox {
                        objectName: "nativeStandby"
                        Kirigami.FormData.label: page.label("Turn off when idle:", "Apagar por inactividad:")
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        wheelEnabled: false
                        enabled: page.available("standby")
                        model: [page.label("Never", "Nunca"), "5 min", "15 min", "30 min", "45 min", "60 min"]
                        currentIndex: page.available("standby") ? [0,5,15,30,45,60].indexOf(page.state.standby) : -1
                        displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                        onActivated: index => page.apply("standby", [0,5,15,30,45,60][index])
                    }
                }
                ColumnLayout {
                    id: quickConnect
                    objectName: "quickConnect"
                    Layout.fillWidth: true
                    visible: page.section === "quickConnect"
                    spacing: Kirigami.Units.largeSpacing
                    readonly property var devices: page.available("devices") ? page.state.devices : []
                    // Switching needs gaming mode known to be off.
                    readonly property bool canSwitch: page.available("gaming") && !page.state.gaming
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: page.label("Move the headset's Bluetooth connection to a device it already knows. Switching may interrupt audio.",
                                         "Mueve la conexión Bluetooth del auricular a un dispositivo que ya conoce. El cambio puede interrumpir el audio.")
                        opacity: 0.75
                    }
                    Kirigami.InlineMessage {
                        objectName: "quickConnectBlocked"
                        Layout.fillWidth: true
                        type: Kirigami.MessageType.Information
                        visible: quickConnect.devices.length > 0 && !quickConnect.canSwitch
                        text: page.available("gaming")
                            ? page.label("Turn off Bluetooth gaming mode in the popup to switch devices.",
                                         "Desactiva el modo gaming Bluetooth en la ventana emergente para cambiar de dispositivo.")
                            : page.label("Gaming mode state unknown. Refresh to read it before switching devices.",
                                         "Estado del modo gaming desconocido. Actualiza para leerlo antes de cambiar de dispositivo.")
                    }
                    ColumnLayout {
                        objectName: "quickConnectDevices"
                        Layout.fillWidth: true
                        spacing: 0
                        visible: quickConnect.devices.length > 0
                        Repeater {
                            model: quickConnect.devices
                            ColumnLayout {
                                id: deviceRow
                                required property var modelData
                                required property int index
                                readonly property string text: modelData.name || Output.macAddress(modelData.address)
                                Layout.fillWidth: true
                                spacing: 0
                                Kirigami.Separator { Layout.fillWidth: true; visible: deviceRow.index > 0 }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.largeSpacing
                                    Kirigami.Icon {
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                        source: "network-bluetooth"
                                        opacity: deviceRow.modelData.active ? 1 : 0.6
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: deviceRow.text
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            font.bold: deviceRow.modelData.active
                                        }
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            // A nameless device already shows its address as its title.
                                            visible: text !== ""
                                            text: deviceRow.modelData.active
                                                ? page.label("Active source", "Fuente activa")
                                                : deviceRow.modelData.name ? Output.macAddress(deviceRow.modelData.address) : ""
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.7
                                        }
                                    }
                                    Kirigami.Icon {
                                        visible: deviceRow.modelData.active
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                        source: "checkmark"
                                        color: Kirigami.Theme.positiveTextColor
                                        isMask: true
                                    }
                                    QQC2.Button {
                                        objectName: "quickConnectButton"
                                        visible: !deviceRow.modelData.active
                                        icon.name: "network-connect"
                                        text: page.label("Switch", "Cambiar")
                                        Accessible.name: page.label("Switch to ", "Cambiar a ") + deviceRow.text
                                        enabled: quickConnect.canSwitch
                                        onClicked: page.apply("devices", deviceRow.modelData.address)
                                    }
                                }
                            }
                        }
                    }
                    Kirigami.PlaceholderMessage {
                        objectName: "quickConnectEmpty"
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        visible: page.available("devices") && page.state.devices.length === 0
                        icon.name: "network-bluetooth"
                        text: page.label("No known Bluetooth devices", "No hay dispositivos Bluetooth conocidos")
                        explanation: page.label("Pair the headset with a phone or computer over Bluetooth first.",
                                                "Primero empareja el auricular con un teléfono o computador por Bluetooth.")
                    }
                }

            }
        }
    }
    // The page reads the headset when it opens. Refreshing is offered only where
    // it is needed: after a failed read or change, and after a device switch.
    Kirigami.Action {
        id: refreshAction
        objectName: "refreshNativeSettings"
        icon.name: "view-refresh"
        text: page.label("Refresh", "Actualizar")
        enabled: !page.busy && !page.bandsDirty
        onTriggered: page.controller.request({op: "status"})
    }
    Kirigami.InlineMessage {
        objectName: "nativeSettingsError"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Warning
        visible: text.length > 0
        text: page.controller.error || page.settingsError
        actions: [refreshAction]
    }
    Kirigami.InlineMessage {
        objectName: "nativeSettingsMessage"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Positive
        visible: text.length > 0
        text: page.controller.message
        // A switch request does not confirm the active device.
        actions: page.controller.response && page.controller.response.sent === "devices" ? [refreshAction] : []
    }
    QQC2.Label {
        objectName: "nativeSettingsReading"
        Layout.fillWidth: true
        visible: page.controller.busy && !page.applyingPreset
        text: page.label("Reading headset…", "Leyendo auricular…")
        opacity: 0.75
    }
}
