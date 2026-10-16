import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "../code/output.js" as Output

// How the headset sounds ("equalizer") and when it turns itself off
// ("powerSaving"); each is its own configuration category. Every change on a
// page waits for the window's Apply or OK, which send it, and Cancel discards
// it. Messages about reading, sending and errors sit at the top.
ColumnLayout {
    id: page
    objectName: "headsetSettings"
    required property var controller
    readonly property real contentHeight: settingsContent.implicitHeight + implicitHeight
    property string localeName: Qt.locale().name
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool bandsDirty: false
    readonly property var presetIds: [0, 7, 8, 9, 255]
    readonly property var standbyMinutes: [0, 5, 15, 30, 45, 60]
    property int confirmedPreset: -1
    // Choices waiting for Apply or OK; -1 when there is none.
    property int pendingPreset: -1
    property int pendingStandby: -1
    // The changes sent by Apply or OK are running.
    property bool saving: false
    readonly property string targetKey: controller.targetKey === undefined ? "" : controller.targetKey
    onTargetKeyChanged: {
        confirmedPreset = -1;
        pendingPreset = -1;
        pendingStandby = -1;
        bandsDirty = false;
    }
    readonly property int selectedPreset: pendingPreset >= 0 ? pendingPreset : confirmedPreset
    readonly property bool showBands: available("preset") && selectedPreset === 255
    onStateChanged: {
        if (available("preset") && presetIds.includes(state.preset))
            confirmedPreset = state.preset;
    }
    property string section: "equalizer"
    readonly property var sectionFeatures: ({equalizer: ["preset", "bands"], powerSaving: ["standby"]})[section] || []
    readonly property var state: controller.response ? controller.response.state : null
    readonly property bool busy: controller.busy
    function label(en, es) { return Output.text(en, es, localeName); }
    function available(feature) { return state !== null && state[feature] !== null && state[feature] !== undefined; }

    readonly property bool presetChanged: section === "equalizer" && available("preset")
        && pendingPreset >= 0 && pendingPreset !== confirmedPreset
    readonly property bool unsavedBands: section === "equalizer" && showBands && bandsDirty && available("bands")
    readonly property bool standbyChanged: section === "powerSaving" && available("standby")
        && pendingStandby >= 0 && pendingStandby !== state.standby
    // Plasma's configuration window enables its Apply button from this.
    readonly property bool unsavedChanges: !saving && (presetChanged || unsavedBands || standbyChanged)
    // The page's changes in sending order: the profile before the bands of
    // the Custom profile.
    function changes() {
        const requests = [];
        if (presetChanged)
            requests.push({op: "set", feature: "preset", value: pendingPreset});
        if (unsavedBands)
            requests.push({op: "set", feature: "bands", value: bands.slice()});
        if (standbyChanged)
            requests.push({op: "set", feature: "standby", value: pendingStandby});
        return requests;
    }
    // Called for Apply and OK. The controller takes one request at a time, so
    // the changes go as one chain that stops at the first failure.
    function save() {
        const requests = changes();
        if (busy || requests.length === 0)
            return;
        saving = true;
        controller.requestChain(requests);
    }

    readonly property string settingsError: {
        const errors = controller.response ? controller.response.errors || {} : {};
        const labels = {preset: label("Equalizer", "Ecualizador"), bands: label("Custom EQ", "EQ personalizado"),
                        standby: label("Idle shutdown", "Apagado por inactividad")};
        const keys = Object.keys(errors).filter(key => sectionFeatures.includes(key));
        if (!keys.length)
            return "";
        const codes = keys.map(key => errors[key]);
        if (codes.every(code => code === codes[0]))
            return controller.errorLabel(codes[0]);
        // One paragraph: Kirigami's InlineMessage with an action loops on
        // short lines split by a hard line break.
        return keys.map(key => labels[key] + ": " + controller.errorLabel(errors[key])).join(" ");
    }
    // The page's setting has no reading, and nothing else explains why.
    readonly property string staleText: busy || controller.error !== "" || settingsError !== "" ? ""
        : section === "equalizer" && !available("preset")
            ? (confirmedPreset >= 0
                ? label("Last confirmed profile. Refresh to read the current setting.",
                        "Último perfil confirmado. Actualiza para leer el ajuste actual.")
                : label("Applied profile unknown. Refresh to read the headset.",
                        "Perfil aplicado desconocido. Actualiza para leer el auricular."))
        : section === "powerSaving" && !available("standby")
            ? label("Idle shutdown unknown. Refresh to read the headset.",
                    "Apagado por inactividad desconocido. Actualiza para leer el auricular.")
        : ""
    function presetLabel(id) {
        return ({0: label("Default", "Predeterminado"), 7: label("Game", "Juegos"),
                 8: label("Music", "Música"), 9: label("Movie", "Cine"),
                 255: label("Custom", "Personalizado")})[id] || label("Unknown", "Desconocido");
    }
    readonly property string confirmedPresetIcon: presetIcon(confirmedPreset)
    readonly property string selectedPresetIcon: presetIcon(selectedPreset)
    // Breeze has no EQ profile icons; these are the closest standard ones.
    function presetIcon(id) {
        return ({0: "view-media-equalizer", 7: "input-gamepad", 8: "audio-x-generic",
                 9: "video-x-generic", 255: "configure"})[id] || "";
    }
    Connections {
        target: page.controller
        function onBusyChanged() {
            // After the reply has been handled: a failed chain keeps its
            // choices, so Apply can send them again.
            if (!page.controller.busy)
                Qt.callLater(() => page.saving = false);
        }
        function onLoaded(result) {
            if (result.sent === "preset" || result.sent === "bands")
                page.pendingPreset = -1;
            if (result.sent === "standby")
                page.pendingStandby = -1;
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

    // The page reads the headset when it opens. Refresh is offered inside the
    // messages that call for it.
    Kirigami.Action {
        id: refreshAction
        objectName: "refreshNativeSettings"
        icon.name: "view-refresh"
        text: page.label("Refresh", "Actualizar")
        enabled: !page.busy && !page.unsavedChanges
        onTriggered: page.controller.request({op: "status"})
    }
    QQC2.Label {
        objectName: "nativeSettingsReading"
        Layout.fillWidth: true
        visible: page.busy && !page.saving
        text: page.label("Reading headset…", "Leyendo auricular…")
        opacity: 0.75
    }
    QQC2.Label {
        objectName: "nativeSettingsSaving"
        Layout.fillWidth: true
        visible: page.saving
        text: page.label("Sending changes to the headset…", "Enviando cambios al auricular…")
        opacity: 0.75
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
        objectName: "nativeSettingsStale"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Information
        visible: text.length > 0
        text: page.staleText
        actions: [refreshAction]
    }
    Kirigami.InlineMessage {
        objectName: "nativeSettingsMessage"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Positive
        visible: text.length > 0
        text: page.controller.message
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
                                currentIndex: page.presetIds.indexOf(page.selectedPreset)
                                onModelChanged: currentIndex = Qt.binding(() => page.presetIds.indexOf(page.selectedPreset))
                                displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                                delegate: QQC2.ItemDelegate {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view ? ListView.view.width : implicitWidth
                                    text: modelData.text
                                    icon.name: modelData.icon
                                    highlighted: profileSelector.highlightedIndex === index
                                }
                                // The style draws the selected profile's icon in the closed selector.
                                Kirigami.StyleHints.iconName: page.selectedPresetIcon
                                enabled: page.available("preset") && page.presetIds.includes(page.state.preset)
                                onActivated: index => {
                                    const value = page.presetIds[index];
                                    // Kept for Apply; choosing the stored profile again drops it.
                                    page.pendingPreset = value === page.confirmedPreset ? -1 : value;
                                    currentIndex = Qt.binding(() => page.presetIds.indexOf(page.selectedPreset));
                                }
                            }
                            Kirigami.ContextualHelpButton {
                                objectName: "profileHelp"
                                toolTipText: page.label(
                                    "Profiles are stored on the headset. Choose a profile, or Custom to adjust the bands (0 is neutral), then select Apply to send it; Cancel discards it. The Game profile is independent of Bluetooth Gaming Mode in the popup.",
                                    "Los perfiles se guardan en el auricular. Elige un perfil, o Personalizado para ajustar las bandas (0 es neutro), y selecciona Aplicar para enviarlo; Cancelar lo descarta. El perfil Juegos es independiente del modo gaming Bluetooth de la ventana emergente.")
                            }
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
                                text: page.label("Reset Bands", "Restablecer bandas")
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
                    // A row, like the sound profile: FormLayout sizing a bare
                    // ComboBox loops on its implicit width.
                    RowLayout {
                        Kirigami.FormData.label: page.label("Turn off when idle:", "Apagar por inactividad:")
                        QQC2.ComboBox {
                            id: standbySelector
                            objectName: "nativeStandby"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                            wheelEnabled: false
                            Accessible.name: page.label("Turn off when idle", "Apagar por inactividad")
                            enabled: page.available("standby")
                            model: [page.label("Never", "Nunca"), "5 min", "15 min", "30 min", "45 min", "60 min"]
                            readonly property int selectedMinutes: page.pendingStandby >= 0 ? page.pendingStandby
                                : page.available("standby") ? page.state.standby : -1
                            currentIndex: page.standbyMinutes.indexOf(standbySelector.selectedMinutes)
                            onModelChanged: currentIndex = Qt.binding(() => page.standbyMinutes.indexOf(standbySelector.selectedMinutes))
                            displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                            onActivated: index => {
                                const value = page.standbyMinutes[index];
                                // Kept for Apply; choosing the stored value again drops it.
                                page.pendingStandby = value === page.state.standby ? -1 : value;
                                currentIndex = Qt.binding(() => page.standbyMinutes.indexOf(standbySelector.selectedMinutes));
                            }
                        }
                    }
                }
            }
        }
    }
}
