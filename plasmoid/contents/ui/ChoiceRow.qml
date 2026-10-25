import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One headset setting with a few named values, laid out like a ModeSwitch
// row: a monochrome symbolic icon in the device-icon column, the name on the
// device titles' column, and a ComboBox ending on the trailing edge.
//
// The ComboBox shows the confirmed value only. Choosing another one asks for
// it and returns to the confirmed value at once; the reply's reading moves
// it. A value the headset has not confirmed draws "Reading…" or "Unknown"
// in the ComboBox, which cannot be changed then. While its own request runs,
// a busy indicator stands just before the ComboBox. Scrolling over it and
// the arrow keys leave it alone; Space opens it.
Item {
    id: row
    property string text: ""
    property string iconName: ""
    // The values, and their names in the same order.
    property var values: []
    property var names: []
    // One of values, or anything else for unknown.
    property var value: null
    property bool interactive: true
    property bool busy: false
    // Shown for an unknown value.
    property string note: ""
    // Columns, in the row's coordinates, as for ModeSwitch.
    property real indicatorX: 0
    property real labelX: Kirigami.Units.gridUnit * 2
    property real trailingInset: Kirigami.Units.smallSpacing
    property real busySize: Kirigami.Units.iconSizes.smallMedium
    readonly property int confirmedIndex: values.indexOf(value)
    readonly property bool known: confirmedIndex >= 0
    readonly property alias control: control
    signal choiceRequested(var value)
    // Up and Down move the focus, as in the other rows; they never change
    // the value of a closed ComboBox.
    signal stepRequested(int step, var event)

    implicitHeight: Math.max(Kirigami.Units.iconSizes.medium, control.implicitHeight) + Kirigami.Units.smallSpacing * 2
    activeFocusOnTab: false

    Kirigami.Icon {
        objectName: "choiceIcon"
        x: row.indicatorX + (Kirigami.Units.iconSizes.medium - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        source: row.iconName
        isMask: true
        color: Kirigami.Theme.textColor
        opacity: control.enabled ? 1 : 0.5
    }

    PC3.Label {
        objectName: "choiceLabel"
        x: row.labelX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, (row.busy ? busyIndicator.x : control.x) - x - Kirigami.Units.smallSpacing)
        text: row.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        opacity: control.enabled ? 1 : 0.5
        Accessible.ignored: true
    }

    PC3.BusyIndicator {
        id: busyIndicator
        objectName: "choiceBusy"
        anchors.right: control.left
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: row.busySize
        height: width
        visible: row.busy
        running: visible
    }

    PC3.ComboBox {
        id: control
        objectName: "choice"
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.gridUnit * 9
        // Scrolling the popup's page never changes a stored setting.
        wheelEnabled: false
        enabled: row.interactive && row.known && !row.busy
        model: row.names
        currentIndex: row.confirmedIndex
        // A new model resets the index; keep it on the confirmed value.
        onModelChanged: currentIndex = Qt.binding(() => row.confirmedIndex)
        displayText: row.known ? currentText : row.note
        Accessible.name: row.text
        Keys.onUpPressed: event => {
            row.stepRequested(-1, event);
            event.accepted = true;
        }
        Keys.onDownPressed: event => {
            row.stepRequested(1, event);
            event.accepted = true;
        }
        onActivated: index => {
            currentIndex = Qt.binding(() => row.confirmedIndex);
            if (index !== row.confirmedIndex)
                row.choiceRequested(row.values[index]);
        }
    }
}
