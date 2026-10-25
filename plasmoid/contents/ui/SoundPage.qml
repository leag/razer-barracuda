import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The Sound tab: the sound profile and, with Custom, its ten bands, from the
// view's one settings read. Every change is sent at once, as the Modes
// switches are; there is no Apply and nothing to cancel.
//
// The profile row shows the confirmed profile only. The bands follow the
// pointer while it drags, since a slider must; each slider's level is sent
// once the pointer lets go and the levels have rested for a moment, as one
// request for the whole curve. Edits made while a request runs wait for it
// and go next, latest levels only. A change the headset did not apply puts
// the sliders back on the confirmed curve.
PC3.ScrollView {
    id: page
    objectName: "soundPage"
    // The HeadsetView: its settings reading, geometry and feedback slot.
    required property var view
    property Component feedback: null
    readonly property string localeName: view.localeName
    readonly property alias profileControl: profileRow.control
    function label(english, spanish) { return Output.text(english, spanish, localeName); }

    readonly property var presetIds: [0, 7, 8, 9, 255]
    readonly property var presetNames: [label("Default", "Predeterminado"), label("Game", "Juegos"),
                                        label("Music", "Música"), label("Movie", "Cine"),
                                        label("Custom", "Personalizado")]
    readonly property var state: view.settingsState
    readonly property var preset: state !== null && typeof state.preset === "number" ? state.preset : null
    readonly property var confirmedBands: state !== null && state.bands && state.bands.length === 10
        ? Array.from(state.bands) : null
    readonly property bool showBands: preset === 255
    readonly property bool bandsEnabled: confirmedBands !== null && view.connected
        && !view.pairingBusy && !view.powerBusy
    readonly property bool bandsBusy: view.pendingFeature === "bands"

    // The curve on the sliders, and whether it differs from the confirmed
    // one and is still to be sent.
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool bandsEdited: false
    // Sliders the pointer holds.
    property int dragging: 0
    function sameCurve(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function showConfirmed() {
        bandsEdited = false;
        bands = confirmedBands !== null ? confirmedBands.slice() : [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }
    onConfirmedBandsChanged: {
        if (!bandsEdited)
            showConfirmed();
        else if (sameCurve(bands, confirmedBands))
            bandsEdited = false;
    }
    function setBands(next) {
        bands = next;
        bandsEdited = !sameCurve(next, confirmedBands);
        bandsRest.restart();
    }
    function sendBands() {
        // Edits for a profile that is no longer Custom are dropped.
        if (bandsEdited && !showBands)
            showConfirmed();
        if (!bandsEdited || bandsRest.running || dragging > 0 || !view.settingsEnabled || confirmedBands === null)
            return;
        bandsEdited = false;
        view.settingChangeRequested("bands", bands.slice());
    }
    Timer {
        id: bandsRest
        interval: 400
        onTriggered: page.sendBands()
    }
    Connections {
        target: page.view
        // Waiting edits go once the running request has been handled.
        function onSettingsEnabledChanged() {
            if (page.view.settingsEnabled)
                Qt.callLater(page.sendBands);
        }
    }
    Connections {
        target: page.view.settings
        function onErrorChanged() {
            if (page.view.settings.error.length > 0 && page.view.settings.requestFeature === "bands")
                page.showConfirmed();
        }
        function onTargetKeyChanged() { page.showConfirmed(); }
    }

    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
    contentWidth: availableWidth

    Item {
        implicitWidth: page.availableWidth
        implicitHeight: column.implicitHeight + Kirigami.Units.largeSpacing * 2
        ColumnLayout {
            id: column
            x: Kirigami.Units.largeSpacing
            y: Kirigami.Units.largeSpacing
            width: parent.width - Kirigami.Units.largeSpacing * 2
            spacing: 0

            Loader {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                active: page.view.noticeShown && page.visible
                visible: active
                sourceComponent: page.feedback
            }

            PlasmaExtras.ListSectionHeader {
                objectName: "equalizerHeader"
                Layout.fillWidth: true
                visible: page.view.sectionsShown
                text: page.label("Equalizer", "Ecualizador")
                // This tab's only help.
                PlasmaExtras.ContextualHelpButton {
                    objectName: "equalizerHelp"
                    Layout.maximumHeight: -1
                    toolTipText: page.label(
                        "Profiles and the custom bands are stored on the headset, and each change is sent at once. With Custom, each band is relative and 0 is neutral. The Game profile is not Bluetooth gaming mode.",
                        "Los perfiles y las bandas personalizadas se guardan en el auricular, y cada cambio se envía al momento. Con Personalizado, cada banda es relativa y 0 es neutro. El perfil Juegos no es el modo gaming Bluetooth.")
                }
            }
            ChoiceRow {
                id: profileRow
                objectName: "profile"
                Layout.fillWidth: true
                visible: page.view.sectionsShown
                iconName: "view-media-equalizer-symbolic"
                indicatorX: page.view.iconColumn
                labelX: page.view.titleColumn
                trailingInset: page.view.trailingInset
                busySize: page.view.rowBusySize
                text: page.label("Sound profile", "Perfil de sonido")
                values: page.presetIds
                names: page.presetNames
                value: page.preset
                busy: page.view.pendingFeature === "preset"
                interactive: page.view.settingsEnabled
                // Shown only for a profile the headset has not confirmed.
                note: page.view.rowNote(null)
                onChoiceRequested: value => page.view.settingChangeRequested("preset", value)
                onStepRequested: (step, event) => page.view.stepFocus(control, step, event)
            }

            // Custom only: one vertical slider per band across the row, the
            // level above, the frequency below and the unit once.
            RowLayout {
                id: bandsRow
                objectName: "customBands"
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.leftMargin: page.view.iconColumn
                Layout.rightMargin: page.view.trailingInset
                visible: page.view.sectionsShown && page.showBands
                enabled: page.bandsEnabled
                spacing: 0
                Repeater {
                    model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                    ColumnLayout {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: (page.bands[index] > 0 ? "+" : "") + page.bands[index]
                            font: Kirigami.Theme.smallFont
                            opacity: page.bands[index] === 0 ? 0.6 : 1
                        }
                        ScrollSafeSlider {
                            objectName: "bandSlider"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 7
                            orientation: Qt.Vertical
                            scrollItem: page.contentItem
                            from: -5; to: 5; stepSize: 1
                            snapMode: QQC2.Slider.SnapAlways
                            value: page.bands[index]
                            Accessible.name: modelData + " Hz"
                            onPressedChanged: {
                                page.dragging += pressed ? 1 : -1;
                                if (!pressed)
                                    bandsRest.restart();
                            }
                            onMoved: {
                                const next = page.bands.slice();
                                next[index] = Math.round(value);
                                page.setBands(next);
                            }
                        }
                        PC3.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.view.iconColumn
                Layout.rightMargin: page.view.trailingInset
                visible: bandsRow.visible
                PC3.Label {
                    objectName: "bandsUnit"
                    Layout.fillWidth: true
                    text: page.label("Hz · relative levels", "Hz · niveles relativos")
                    textFormat: Text.PlainText
                    font: Kirigami.Theme.smallFont
                    opacity: 0.75
                    elide: Text.ElideRight
                }
                PC3.BusyIndicator {
                    objectName: "bandsBusy"
                    Layout.preferredWidth: page.view.rowBusySize
                    Layout.preferredHeight: page.view.rowBusySize
                    visible: page.bandsBusy
                    running: visible
                }
                PC3.ToolButton {
                    objectName: "resetBands"
                    icon.name: "edit-reset-symbolic"
                    text: page.label("Reset Bands", "Restablecer bandas")
                    enabled: page.bandsEnabled && page.bands.some(value => value !== 0)
                    onClicked: page.setBands([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
                }
            }
        }
    }
}
