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
    property string localeName: Qt.locale().name
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool bandsDirty: false
    property bool showBands: false
    property bool showOptions: false
    readonly property var state: controller.response ? controller.response.state : null
    readonly property bool legacyEq: audioController.response !== null &&
        (audioController.response.legacy_effects_loaded ||
         audioController.response.state.equalizers.output.enabled ||
         audioController.response.state.equalizers.microphone.enabled)
    readonly property bool busy: controller.busy || audioController.busy
    function label(en, es) { return Output.text(en, es, localeName); }
    function available(feature) { return state !== null && state[feature] !== null && state[feature] !== undefined; }
    function apply(feature, value) { controller.request({op: "set", feature: feature, value: value}); }
    function presetLabel(id) {
        return ({0: label("Default", "Predeterminado"), 7: label("Game", "Juegos"),
                 8: label("Music", "Música"), 9: label("Movie", "Cine"),
                 255: label("Custom", "Personalizado")})[id] || label("Unknown", "Desconocido");
    }
    Connections {
        target: page.controller
        function onLoaded(result) {
            if (page.bandsDirty && result.sent !== "bands")
                return;
            if (result.state.bands !== null)
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
                PlasmaExtras.Heading { level: 3; text: page.label("Headset equalizer", "Ecualizador del auricular") }
                PC3.Label {
                    objectName: "nativeAppliedProfile"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.bold: page.available("preset")
                    text: page.available("preset")
                        ? page.label("Applied: ", "Aplicado: ") + page.presetLabel(page.state.preset)
                        : page.label("Applied profile unknown", "Perfil aplicado desconocido")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: [0, 7, 8, 9, 255]
                        PC3.Button {
                            required property int modelData
                            objectName: "nativePreset" + modelData
                            text: page.presetLabel(modelData)
                            font.bold: page.available("preset") && page.state.preset === modelData
                            enabled: page.available("preset") && page.state.preset !== modelData
                            onClicked: page.apply("preset", modelData)
                        }
                    }
                }
                PC3.ToolButton {
                    text: page.label("Custom bands", "Bandas personalizadas")
                    icon.name: page.showBands ? "arrow-down" : "arrow-right"
                    enabled: page.available("bands")
                    onClicked: page.showBands = !page.showBands
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.showBands
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
                        text: page.label("Relative levels · 0 is neutral · Select Custom to hear these bands", "Niveles relativos · 0 es neutro · Selecciona Personalizado para escuchar estas bandas")
                    }
                    RowLayout {
                        PC3.Button {
                            text: page.label("Reset bands", "Restablecer bandas")
                            onClicked: { page.bands = [0,0,0,0,0,0,0,0,0,0]; page.bandsDirty = true; }
                        }
                        PC3.Button {
                            objectName: "applyNativeBands"
                            text: page.label("Apply bands", "Aplicar bandas")
                            enabled: page.bandsDirty && page.available("bands")
                            onClicked: page.apply("bands", page.bands)
                        }
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true }
                PC3.ToolButton {
                    objectName: "toggleHeadsetOptions"
                    text: page.label("More headset settings", "Más ajustes del auricular")
                    icon.name: page.showOptions ? "arrow-down" : "arrow-right"
                    onClicked: page.showOptions = !page.showOptions
                }
                ColumnLayout {
                    objectName: "headsetOptions"
                    Layout.fillWidth: true
                    visible: page.showOptions
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
                Repeater {
                    model: page.controller.response ? Object.keys(page.controller.response.errors || {}) : []
                    PC3.Label {
                        required property string modelData
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: ({preset: page.label("Equalizer", "Ecualizador"), bands: page.label("Custom EQ", "EQ personalizado"),
                                gaming: "Gaming", dnd: page.label("Do Not Disturb", "No molestar"),
                                standby: page.label("Idle shutdown", "Apagado por inactividad"), devices: "Quick Connect"})[modelData]
                            + ": " + page.controller.errorLabel(page.controller.response.errors[modelData])
                    }
                }
            }
        }
    }
    PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: controller.error !== ""; text: controller.error }
    PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: controller.message !== ""; text: controller.message }
    PC3.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: audioController.error !== ""; text: audioController.error }
    PC3.Button {
        objectName: "refreshNativeSettings"
        icon.name: "view-refresh"
        text: controller.busy ? page.label("Reading headset…", "Leyendo auricular…") : page.label("Refresh", "Actualizar")
        enabled: !page.busy && !page.bandsDirty
        onClicked: controller.request({op: "status"})
    }
}
