import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The Power tab: what the battery reports and when the headset turns itself
// off. The Battery rows come from KDE's battery and the driver's link
// report, so they need no headset request; idle shutdown comes from the
// view's one settings read and is sent at once when chosen.
PC3.ScrollView {
    id: page
    objectName: "powerPage"
    // The HeadsetView: its status, settings reading, geometry and feedback slot.
    required property var view
    property Component feedback: null
    readonly property string localeName: view.localeName
    readonly property alias standbyControl: standbyRow.control
    function label(english, spanish) { return Output.text(english, spanish, localeName); }

    readonly property var standbyMinutes: [0, 5, 15, 30, 45, 60]
    readonly property var state: view.settingsState
    // Monochrome glyphs only: Breeze's charging battery icons carry a green
    // part that a mask does not remove. The bolt is the drawing of power
    // coming in, whatever the icon's own name.
    readonly property var rowIcons: ({charge: "battery-good-symbolic", cable: "quickopen-symbolic",
                                      voltage: "speedometer-symbolic"})

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
                objectName: "batteryHeader"
                Layout.fillWidth: true
                text: page.label("Battery", "Batería")
            }
            Repeater {
                model: Output.powerRows(page.view.linkStatus, page.view.battery, page.localeName)
                ValueRow {
                    required property var modelData
                    objectName: "battery-" + modelData.key
                    Layout.fillWidth: true
                    iconName: page.rowIcons[modelData.key]
                    indicatorX: page.view.iconColumn
                    labelX: page.view.titleColumn
                    trailingInset: page.view.trailingInset
                    text: modelData.label
                    value: modelData.value
                }
            }

            PlasmaExtras.ListSectionHeader {
                objectName: "shutdownHeader"
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: page.view.sectionsShown
                text: page.label("Shutdown", "Apagado")
            }
            // Never first, as Power Management's screen timeouts.
            ChoiceRow {
                id: standbyRow
                objectName: "standby"
                Layout.fillWidth: true
                visible: page.view.sectionsShown
                iconName: "chronometer-symbolic"
                indicatorX: page.view.iconColumn
                labelX: page.view.titleColumn
                trailingInset: page.view.trailingInset
                busySize: page.view.rowBusySize
                text: page.label("Turn off when idle", "Apagar por inactividad")
                values: page.standbyMinutes
                names: [page.label("Never", "Nunca"), "5 min", "15 min", "30 min", "45 min", "60 min"]
                value: page.state !== null && typeof page.state.standby === "number" ? page.state.standby : null
                busy: page.view.pendingFeature === "standby"
                interactive: page.view.settingsEnabled
                // Shown only for a value the headset has not confirmed.
                note: page.view.rowNote(null)
                onChoiceRequested: value => page.view.settingChangeRequested("standby", value)
                onStepRequested: (step, event) => page.view.stepFocus(control, step, event)
            }
        }
    }
}
