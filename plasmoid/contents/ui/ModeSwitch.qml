import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// One headset boolean, laid out like the device rows under it: a monochrome
// symbolic icon centred in the device-icon column, the name on the device
// titles' column with an optional second line, and the switch in the
// trailing slot where device rows show Connect or their busy indicator.
//
// The whole row is the switch, so a click anywhere toggles it. A value the
// headset has not confirmed draws no indicator: the trailing slot says
// "Reading…" or "Unknown" instead, so an unknown value never looks Off. A
// reason a known switch cannot change ("Only over Bluetooth") is the second
// line, as a device row's subtitle. While its own request runs, a busy
// indicator replaces the switch. Nothing is optimistic: the switch returns
// to the confirmed value at once and moves only when a reading says so.
Item {
    id: row
    property string text: ""
    property string iconName: ""
    // true, false, or anything else for unknown.
    property var value: null
    property bool interactive: true
    property bool busy: false
    property string note: ""
    // Columns, in the row's coordinates, from the list. indicatorX is the
    // left edge of the device icons' box; labelX the device titles' column.
    property real indicatorX: 0
    property real labelX: Kirigami.Units.gridUnit * 2
    // Inset of the trailing slot, matching the device rows' button text.
    property real trailingInset: Kirigami.Units.smallSpacing
    // The device rows' busy indicator size (their button's height).
    property real busySize: Kirigami.Units.iconSizes.smallMedium
    readonly property bool known: typeof value === "boolean"
    readonly property bool hasSubtitle: known && note.length > 0
    readonly property alias control: control
    signal toggleRequested(bool value)

    // A one-line or two-line device row: the 32 px icon box plus its margins.
    implicitHeight: Math.max(Kirigami.Units.iconSizes.medium, labels.implicitHeight) + Kirigami.Units.smallSpacing * 2
    activeFocusOnTab: false

    PlasmaExtras.Highlight {
        anchors.fill: parent
        hovered: true
        pressed: control.pressed
        visible: control.visible && control.enabled && (control.hovered || control.visualFocus)
    }

    // The switch fills the row so the whole row is its click target; only its
    // indicator is drawn, in the trailing slot.
    PC3.Switch {
        id: control
        objectName: "modeSwitch"
        anchors.fill: parent
        visible: row.known && !row.busy
        text: ""
        topPadding: 0
        bottomPadding: 0
        rightPadding: row.trailingInset
        leftPadding: Math.max(0, width - rightPadding - indicator.width)
        checked: row.value === true
        enabled: row.interactive && !row.busy
        Accessible.name: row.text
        Accessible.description: row.note
        onToggled: {
            const wanted = checked;
            checked = Qt.binding(() => row.value === true);
            row.toggleRequested(wanted);
        }
    }

    Kirigami.Icon {
        id: icon
        objectName: "modeIcon"
        // Centred in the 32 px device-icon box, at the size of a symbolic icon.
        x: row.indicatorX + (Kirigami.Units.iconSizes.medium - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        source: row.iconName
        isMask: true
        color: Kirigami.Theme.textColor
        opacity: control.visible && !control.enabled ? 0.5 : 1
    }

    Column {
        id: labels
        x: row.labelX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, trailing.x - x - Kirigami.Units.smallSpacing)
        PC3.Label {
            id: title
            objectName: "modeLabel"
            width: parent.width
            text: row.text
            textFormat: Text.PlainText
            elide: Text.ElideRight
            opacity: control.visible && !control.enabled ? 0.5 : 1
            Accessible.ignored: control.visible
        }
        PC3.Label {
            objectName: "modeSubtitle"
            width: parent.width
            visible: row.hasSubtitle
            text: row.hasSubtitle ? row.note : ""
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    // The trailing slot: the switch indicator, a busy indicator, or the word
    // standing in for an unknown value.
    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        anchors.verticalCenter: parent.verticalCenter
        width: row.busy ? busyIndicator.width
            : !row.known ? noteLabel.implicitWidth
            : control.indicator.width
        height: parent.height
    }
    PC3.Label {
        id: noteLabel
        objectName: "modeNote"
        visible: !row.busy && !row.known && text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        anchors.verticalCenter: parent.verticalCenter
        text: row.known ? "" : row.note
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.75
        Accessible.name: row.text
        Accessible.description: row.note
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
