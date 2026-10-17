import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// Facts as the Bluetooth applet lists a device's details (DeviceItem.qml):
// two columns in the small font, keys right-aligned at 0.6 opacity ending in
// a colon, values left-aligned and elided.
GridLayout {
    id: grid
    // [[key, value], …]
    property var rows: []
    columns: 2
    rowSpacing: Kirigami.Units.smallSpacing / 4
    columnSpacing: Kirigami.Units.smallSpacing

    Repeater {
        model: grid.rows.reduce((cells, row) => cells.concat(row), [])
        PC3.Label {
            required property int index
            required property string modelData
            readonly property bool isValue: index % 2 === 1
            objectName: isValue ? "detailValue" : "detailKey"
            // Both columns share the width, as in DeviceItem.qml, so the
            // colons line up at the middle.
            Layout.fillWidth: true
            horizontalAlignment: isValue ? Text.AlignLeft : Text.AlignRight
            elide: isValue ? Text.ElideRight : Text.ElideNone
            font: Kirigami.Theme.smallFont
            opacity: isValue ? 1 : 0.6
            text: isValue ? modelData : modelData + ":"
            textFormat: Text.PlainText
        }
    }
}
