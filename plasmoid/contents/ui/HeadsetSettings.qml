import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

ColumnLayout {
    id: page
    objectName: "headsetSettings"
    required property var controller
    required property var audioController
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
    property bool showOptions: false
    readonly property var state: controller.response ? controller.response.state : null
    readonly property bool legacyEq: audioController.response !== null &&
        (audioController.response.legacy_effects_loaded ||
         audioController.response.state.equalizers.output.enabled ||
         audioController.response.state.equalizers.microphone.enabled)
    readonly property bool optionsAvailable: ["gaming", "dnd", "standby", "devices"].some(feature => available(feature))
    readonly property bool busy: controller.busy || audioController.busy
    function label(en, es) { return Output.text(en, es, localeName); }
    function available(feature) { return state !== null && state[feature] !== null && state[feature] !== undefined; }
    function apply(feature, value) { controller.request({op: "set", feature: feature, value: value}); }
    readonly property string settingsError: {
        const errors = controller.response ? controller.response.errors || {} : {};
        const labels = {preset: label("Equalizer", "Ecualizador"), bands: label("Custom EQ", "EQ personalizado"),
                        gaming: "Gaming", dnd: label("Do Not Disturb", "No molestar"),
                        standby: label("Idle shutdown", "Apagado por inactividad"), devices: "Quick Connect"};
        const keys = Object.keys(errors);
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
            if (Array.isArray(result.state.bands))
                page.bands = result.state.bands.slice();
            page.bandsDirty = false;
        }
    }
    PC3.ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: 0
        implicitWidth: Kirigami.Units.gridUnit * 22
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
        contentWidth: availableWidth
        ColumnLayout {
            id: settingsContent
            width: scroll.availableWidth
            spacing: Kirigami.Units.largeSpacing
            PC3.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                wrapMode: Text.Wrap
                visible: page.legacyEq
                text: page.label("Remove the previous software effects before using the headset EQ. This briefly interrupts playback and calls.",
                                 "Quita los efectos de software anteriores antes de usar el EQ del auricular. Esto interrumpe brevemente la reproducción y las llamadas.")
            }
            PC3.Button {
                objectName: "removeSoftwareEq"
                Layout.fillWidth: true
                visible: page.legacyEq
                enabled: !page.busy
                text: page.label("Remove software effects and restart audio", "Quitar efectos de software y reiniciar audio")
                onClicked: page.audioController.request({op: "remove_effects", confirmed: true})
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                enabled: !page.busy && !page.legacyEq && page.audioController.response !== null
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: page.label("Headset equalizer", "Ecualizador del auricular")
                }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.label("Choose a sound profile stored on your headset.",
                                     "Elige un perfil de sonido guardado en el auricular.")
                    opacity: 0.75
                }
                PC3.Label {
                    id: profileLabel
                    text: page.label("Profile", "Perfil")
                }
                PC3.ComboBox {
                    id: profileSelector
                    objectName: "nativeProfileSelector"
                    Layout.fillWidth: true
                    wheelEnabled: false
                    Accessible.name: profileLabel.text
                    model: page.presetIds.map(id => page.presetLabel(id))
                    currentIndex: page.presetIds.indexOf(page.confirmedPreset)
                    onModelChanged: currentIndex = Qt.binding(() => page.presetIds.indexOf(page.confirmedPreset))
                    displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
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
                PC3.Label {
                    objectName: "nativeProfileStatus"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: page.applyingPreset || (!page.available("preset") && page.settingsError === "" && page.controller.error === "")
                    text: page.applyingPreset ? page.label("Applying profile…", "Aplicando perfil…")
                        : page.confirmedPreset >= 0
                            ? page.label("Last confirmed profile. Refresh to read the current setting.",
                                         "Último perfil confirmado. Actualiza para leer el ajuste actual.")
                            : page.label("Applied profile unknown. Refresh to read the headset.",
                                         "Perfil aplicado desconocido. Actualiza para leer el auricular.")
                    opacity: 0.75
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    objectName: "nativeCustomBands"
                    visible: page.showBands
                    enabled: page.available("bands")
                    PlasmaExtras.Heading {
                        level: 4
                        text: page.label("Custom bands", "Bandas personalizadas")
                    }
                    Repeater {
                        model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                        RowLayout {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            PC3.Label { text: modelData + " Hz"; Layout.preferredWidth: Kirigami.Units.gridUnit * 3 }
                            ScrollSafeSlider {
                                Layout.fillWidth: true
                                scrollItem: scroll.contentItem
                                from: -5; to: 5; stepSize: 1
                                value: page.bands[index]
                                Accessible.name: modelData + " Hz"
                                onMoved: {
                                    const next = page.bands.slice();
                                    next[index] = Math.round(value);
                                    page.bands = next;
                                    page.bandsDirty = JSON.stringify(next) !== JSON.stringify(page.state.bands);
                                }
                            }
                            PC3.Label { text: String(page.bands[index]); Layout.preferredWidth: Kirigami.Units.gridUnit }
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: page.label("Relative levels · 0 is neutral · Apply changes to hear your adjustments", "Niveles relativos · 0 es neutro · Aplica los cambios para escuchar tus ajustes")
                    }
                    RowLayout {
                        PC3.Button {
                            objectName: "resetNativeBands"
                            text: page.label("Reset bands", "Restablecer bandas")
                            onClicked: {
                                page.bands = [0,0,0,0,0,0,0,0,0,0];
                                page.bandsDirty = JSON.stringify(page.bands) !== JSON.stringify(page.state.bands);
                            }
                        }
                        PC3.Button {
                            objectName: "applyNativeBands"
                            text: page.label("Apply changes", "Aplicar cambios")
                            enabled: page.bandsDirty && page.available("bands")
                            onClicked: page.apply("bands", page.bands)
                        }
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true; visible: page.optionsAvailable }
                PC3.ToolButton {
                    objectName: "toggleHeadsetOptions"
                    visible: page.optionsAvailable
                    text: page.label("More settings", "Más ajustes")
                    icon.name: page.showOptions ? "arrow-down" : "arrow-right"
                    onClicked: page.showOptions = !page.showOptions
                }
                ColumnLayout {
                    objectName: "headsetOptions"
                    Layout.fillWidth: true
                    visible: page.showOptions && page.optionsAvailable
                    spacing: Kirigami.Units.largeSpacing
                    PC3.CheckBox {
                        objectName: "nativeGaming"
                        text: page.controller.response && page.controller.response.transport === "bluetooth"
                            ? page.label("Gaming mode", "Modo Gaming")
                            : page.label("Gaming mode (experimental)", "Modo Gaming (experimental)")
                        enabled: page.available("gaming")
                        checked: page.available("gaming") && page.state.gaming
                        onClicked: page.apply("gaming", checked)
                    }
                    PC3.Label {
                        objectName: "nativeGamingHint"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: page.controller.response && page.controller.response.transport === "bluetooth"
                            ? page.label("Gaming and the Game EQ preset are independent settings.", "Gaming y el perfil EQ Juegos son ajustes independientes.")
                            : page.label("The app exposes Gaming through Bluetooth. Activation through the dongle is unverified. Game EQ is a separate sound preset.",
                                         "La app ofrece Gaming por Bluetooth. Su activación desde el dongle no está confirmada. El EQ Juegos es otro ajuste de sonido.")
                    }
                    PC3.CheckBox {
                        objectName: "nativeDnd"
                        text: page.label("Do Not Disturb", "No molestar")
                        enabled: page.available("dnd")
                        checked: page.available("dnd") && page.state.dnd
                        onClicked: page.apply("dnd", checked)
                    }
                    PC3.Label { text: page.label("Turn off when idle", "Apagar por inactividad") }
                    PC3.ComboBox {
                        objectName: "nativeStandby"
                        Layout.fillWidth: true
                        wheelEnabled: false
                        enabled: page.available("standby")
                        model: [page.label("Never", "Nunca"), "5 min", "15 min", "30 min", "45 min", "60 min"]
                        currentIndex: page.available("standby") ? [0,5,15,30,45,60].indexOf(page.state.standby) : -1
                        onActivated: index => page.apply("standby", [0,5,15,30,45,60][index])
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    PlasmaExtras.Heading { level: 3; text: "Quick Connect" }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: page.label("Switch between Bluetooth devices already known by the headset. Switching may interrupt audio.",
                                         "Cambia entre dispositivos Bluetooth que el auricular ya conoce. El cambio puede interrumpir el audio.")
                    }
                    Repeater {
                        model: page.available("devices") ? page.state.devices : []
                        PC3.Button {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name || modelData.address
                            font.bold: modelData.active
                            enabled: !modelData.active && page.available("gaming") && !page.state.gaming
                            onClicked: page.apply("devices", modelData.address)
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        visible: page.available("devices") && page.state.devices.length === 0
                        text: page.label("No known Bluetooth devices", "No hay dispositivos Bluetooth conocidos")
                    }
                }

            }
        }
    }
    Kirigami.InlineMessage {
        objectName: "nativeSettingsError"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Warning
        visible: text.length > 0
        text: {
            const error = page.controller.error || page.settingsError || page.audioController.error;
            return error ? error + "\n" + page.label("Refresh to try reading the settings again.",
                "Actualiza para volver a leer los ajustes.") : "";
        }
    }
    PC3.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: controller.message !== ""
        text: controller.message
    }
    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        PC3.Button {
            objectName: "refreshNativeSettings"
            icon.name: "view-refresh"
            text: controller.busy ? page.label("Reading headset…", "Leyendo auricular…") : page.label("Refresh", "Actualizar")
            enabled: !page.busy && !page.bandsDirty
            onClicked: controller.request({op: "status"})
        }
    }
}
