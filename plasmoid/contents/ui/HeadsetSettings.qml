import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import "../code/output.js" as Output

// What the headset stores, on one page: how it sounds and when it turns
// itself off. One reading when the page opens, one message slot, one Apply
// chain: the window's Apply or OK sends every change in order and Cancel
// discards them.
//
// The page has three faces, as KCMs do: a loading placeholder while the
// first reading runs, a placeholder with Try Again when nothing was read,
// and one FormLayout. A setting the reading could not return is shown as a
// disabled control saying "Unknown", never as a default value that looks
// real, and the message slot offers the read again.
ColumnLayout {
    id: page
    objectName: "headsetSettings"
    required property var controller
    property string localeName: Qt.locale().name
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool bandsDirty: false
    readonly property var presetIds: [0, 7, 8, 9, 255]
    readonly property var standbyMinutes: [0, 5, 15, 30, 45, 60]
    // Choices waiting for Apply or OK; -1 when there is none.
    property int pendingPreset: -1
    property int pendingStandby: -1
    // The changes sent by Apply or OK are running.
    property bool saving: false
    // The last Apply or OK failed; its message says so before the reason.
    property bool saveFailed: false
    readonly property string targetKey: controller.targetKey === undefined ? "" : controller.targetKey
    onTargetKeyChanged: {
        pendingPreset = -1;
        pendingStandby = -1;
        bandsDirty = false;
    }
    readonly property var state: controller.response ? controller.response.state : null
    readonly property bool busy: controller.busy
    function label(en, es) { return Output.text(en, es, localeName); }
    function available(feature) { return state !== null && state[feature] !== null && state[feature] !== undefined; }
    // Something was read; otherwise a placeholder stands in for the page.
    readonly property bool loaded: available("preset") || available("standby")
    // The stored profile, or -1 when the reading did not return one this
    // page knows: the selector then says Unknown rather than an old value.
    readonly property int confirmedPreset: available("preset") && presetIds.includes(state.preset) ? state.preset : -1
    readonly property int selectedPreset: pendingPreset >= 0 ? pendingPreset : confirmedPreset
    readonly property bool showBands: available("preset") && selectedPreset === 255

    readonly property bool presetChanged: available("preset") && pendingPreset >= 0 && pendingPreset !== confirmedPreset
    readonly property bool unsavedBands: showBands && bandsDirty && available("bands")
    readonly property bool standbyChanged: available("standby") && pendingStandby >= 0 && pendingStandby !== state.standby
    // Plasma's configuration window enables its Apply button from this.
    readonly property bool unsavedChanges: !saving && (presetChanged || unsavedBands || standbyChanged)
    // Sending order: the profile before the bands of the Custom profile.
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

    // The newest problem, in plain words: what could not be read or sent,
    // and what the user can do about it.
    readonly property string problem: {
        if (controller.error.length > 0)
            return saveFailed
                ? label("Couldn't apply the changes.", "No se pudieron aplicar los cambios.") + " " + controller.error
                : controller.error;
        const errors = controller.response ? controller.response.errors || {} : {};
        const names = {preset: label("the sound profile", "el perfil de sonido"),
                       bands: label("the custom bands", "las bandas personalizadas"),
                       standby: label("idle shutdown", "el apagado por inactividad")};
        const failed = Object.keys(names).filter(key => errors[key]);
        if (failed.length === 0)
            return "";
        const listed = failed.map(key => names[key]);
        const what = listed.length === 1 ? listed[0]
            : listed.slice(0, -1).join(", ") + label(" or ", " ni ") + listed[listed.length - 1];
        return label("Couldn't read %1.", "No se pudo leer %1.").replace("%1", what)
            + " " + controller.errorLabel(errors[failed[0]]);
    }
    function presetLabel(id) {
        return ({0: label("Default", "Predeterminado"), 7: label("Game", "Juegos"),
                 8: label("Music", "Música"), 9: label("Movie", "Cine"),
                 255: label("Custom", "Personalizado")})[id] || label("Unknown", "Desconocido");
    }
    Connections {
        target: page.controller
        function onBusyChanged() {
            if (page.controller.busy) {
                page.saveFailed = false;
                return;
            }
            // After the reply has been handled: a failed chain keeps its
            // choices, so Apply can send them again.
            Qt.callLater(() => page.saving = false);
        }
        function onErrorChanged() {
            if (page.controller.error.length > 0 && page.saving)
                page.saveFailed = true;
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

    Kirigami.Action {
        id: readAgainAction
        objectName: "readAgain"
        icon.name: "view-refresh-symbolic"
        text: page.label("Try Again", "Reintentar")
        enabled: !page.busy && !page.unsavedChanges
        onTriggered: page.controller.request({op: "status"})
    }

    // The one message slot: a problem, with Try Again unless changes wait
    // for Apply, or the sending. Before anything is read, the placeholders
    // below say it instead.
    Kirigami.InlineMessage {
        objectName: "settingsMessage"
        Layout.fillWidth: true
        position: Kirigami.InlineMessage.Position.Header
        visible: page.loaded && text.length > 0
        type: page.saving ? Kirigami.MessageType.Information : Kirigami.MessageType.Warning
        text: page.saving ? page.label("Sending changes to the headset…", "Enviando cambios al auricular…")
            : page.problem
        actions: page.saving || page.unsavedChanges ? [] : [readAgainAction]
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !page.loaded
        Kirigami.LoadingPlaceholder {
            objectName: "settingsReading"
            anchors.centerIn: parent
            visible: page.busy
            text: page.label("Reading the headset…", "Leyendo el auricular…")
        }
        Kirigami.PlaceholderMessage {
            objectName: "settingsUnavailable"
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: !page.busy
            icon.name: "audio-headset"
            text: page.label("Settings not read", "Ajustes sin leer")
            explanation: page.problem.length > 0 ? page.problem
                : page.label("Turn on the headset to read its settings.",
                             "Enciende el auricular para leer sus ajustes.")
            helpfulAction: readAgainAction
        }
    }

    QQC2.ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        visible: page.loaded
        implicitHeight: 0
        implicitWidth: Kirigami.Units.gridUnit * 22
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        contentWidth: availableWidth

        Kirigami.FormLayout {
            id: form
            width: scroll.availableWidth
            enabled: !page.busy

            // A row: FormLayout sizing a bare ComboBox loops on its width.
            RowLayout {
                Kirigami.FormData.label: page.label("Sound profile:", "Perfil de sonido:")
                QQC2.ComboBox {
                    id: profileSelector
                    objectName: "profileSelector"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                    wheelEnabled: false
                    enabled: page.confirmedPreset >= 0
                    model: page.presetIds.map(id => page.presetLabel(id))
                    currentIndex: page.presetIds.indexOf(page.selectedPreset)
                    onModelChanged: currentIndex = Qt.binding(() => page.presetIds.indexOf(page.selectedPreset))
                    displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                    Accessible.name: page.label("Sound profile", "Perfil de sonido")
                    onActivated: index => {
                        const value = page.presetIds[index];
                        // Kept for Apply; choosing the stored profile again drops it.
                        page.pendingPreset = value === page.confirmedPreset ? -1 : value;
                        currentIndex = Qt.binding(() => page.presetIds.indexOf(page.selectedPreset));
                    }
                }
                // The page's only help.
                Kirigami.ContextualHelpButton {
                    objectName: "profileHelp"
                    toolTipText: page.label(
                        "Profiles and the custom bands are stored on the headset. With Custom, each band is relative and 0 is neutral. Apply sends the changes; Cancel discards them. The Game profile is not Bluetooth gaming mode.",
                        "Los perfiles y las bandas personalizadas se guardan en el auricular. Con Personalizado, cada banda es relativa y 0 es neutro. Aplicar envía los cambios; Cancelar los descarta. El perfil Juegos no es el modo gaming Bluetooth.")
                }
            }

            // Custom only: one vertical slider per band from the field
            // column, the gain above, the frequency below and the unit once.
            RowLayout {
                objectName: "customBands"
                visible: page.showBands
                enabled: page.available("bands")
                Kirigami.FormData.label: page.label("Bands:", "Bandas:")
                Kirigami.FormData.labelAlignment: Qt.AlignTop
                spacing: 0
                Repeater {
                    model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                    ColumnLayout {
                        required property int index
                        required property string modelData
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
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
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
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
            QQC2.Button {
                objectName: "resetBands"
                visible: page.showBands
                icon.name: "edit-reset"
                text: page.label("Reset Bands", "Restablecer bandas")
                enabled: page.available("bands") && page.bands.some(value => value !== 0)
                onClicked: {
                    page.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                    page.bandsDirty = JSON.stringify(page.bands) !== JSON.stringify(page.state.bands);
                }
            }

            Item {
                Kirigami.FormData.isSection: true
            }

            // One choice, Never first, as Power Management's screen timeouts.
            RowLayout {
                Kirigami.FormData.label: page.label("Turn off when idle:", "Apagar por inactividad:")
                QQC2.ComboBox {
                    id: standbySelector
                    objectName: "standbySelector"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                    wheelEnabled: false
                    enabled: page.available("standby")
                    model: [page.label("Never", "Nunca"), "5 min", "15 min", "30 min", "45 min", "60 min"]
                    readonly property int selectedMinutes: page.pendingStandby >= 0 ? page.pendingStandby
                        : page.available("standby") ? page.state.standby : -1
                    currentIndex: page.standbyMinutes.indexOf(standbySelector.selectedMinutes)
                    onModelChanged: currentIndex = Qt.binding(() => page.standbyMinutes.indexOf(standbySelector.selectedMinutes))
                    displayText: currentIndex < 0 ? page.label("Unknown", "Desconocido") : currentText
                    Accessible.name: page.label("Turn off when idle", "Apagar por inactividad")
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
