import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// One headset boolean, as a row of the same list as the devices under it:
// the height of a one-line ExpandableListItem (a 32 px icon plus its
// margins), the list highlight on hover and focus, and the label on the
// device titles' column. The switch indicator's outer edge sits on the
// section headers' text column, so the indicator hangs left of the titles
// the way a device icon does.
//
// The whole row is the switch, so a click anywhere toggles it. A value the
// headset has not confirmed draws no indicator: the label stays on its
// column and the trailing slot says "Reading…" or "Unknown", so an unknown
// value never looks Off. The same trailing slot, on the label's baseline,
// holds the reason a switch is disabled, or a busy indicator while its own
// request runs: one place for any note about a switch. Nothing is
// optimistic: the switch returns to the confirmed value at once and moves
// only when a reading says so.
Item {
    id: row
    property string text: ""
    // true, false, or anything else for unknown.
    property var value: null
    property bool interactive: true
    property bool busy: false
    property string note: ""
    // Columns, in the row's coordinates, from the list.
    property real indicatorX: 0
    property real labelX: Kirigami.Units.gridUnit * 2
    // Inset of the trailing slot, matching the device rows' button text.
    property real trailingInset: Kirigami.Units.smallSpacing
    // The device rows' busy indicator size (their button's height).
    property real busySize: Kirigami.Units.iconSizes.smallMedium
    readonly property bool known: typeof value === "boolean"
    readonly property alias control: control
    signal toggleRequested(bool value)

    implicitHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
    activeFocusOnTab: false

    PlasmaExtras.Highlight {
        anchors.fill: parent
        hovered: true
        pressed: control.pressed
        visible: control.visible && control.enabled && (control.hovered || control.visualFocus)
    }

    PC3.Switch {
        id: control
        objectName: "modeSwitch"
        anchors.fill: parent
        visible: row.known
        leftPadding: row.indicatorX
        rightPadding: row.trailingInset + (trailingWidth > 0 ? trailingWidth + Kirigami.Units.smallSpacing : 0)
        topPadding: 0
        bottomPadding: 0
        readonly property real trailingWidth: busyIndicator.visible ? busyIndicator.width
            : noteLabel.visible ? noteLabel.implicitWidth : 0
        spacing: Math.max(0, row.labelX - row.indicatorX - indicator.width)
        text: row.text
        checked: row.value === true
        enabled: row.interactive && !row.busy
        Accessible.description: row.note
        onToggled: {
            const wanted = checked;
            checked = Qt.binding(() => row.value === true);
            row.toggleRequested(wanted);
        }
    }
    PC3.Label {
        id: unknownLabel
        objectName: "modeUnknownLabel"
        visible: !row.known
        x: row.labelX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, (noteLabel.visible ? noteLabel.x : row.width - row.trailingInset) - x - Kirigami.Units.smallSpacing)
        text: row.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        Accessible.name: row.text
        Accessible.description: row.note
    }
    PC3.Label {
        id: noteLabel
        objectName: "modeNote"
        visible: !row.busy && text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        // The unknown-value label is laid out even while hidden: centred, in
        // the switch's font, its baseline is the switch label's baseline.
        anchors.baseline: unknownLabel.baseline
        text: row.note
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.75
        Accessible.ignored: true
    }
    PC3.BusyIndicator {
        id: busyIndicator
        objectName: "modeBusy"
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        anchors.verticalCenter: parent.verticalCenter
        width: row.busySize
        height: width
        visible: row.busy
        running: visible
    }
}
