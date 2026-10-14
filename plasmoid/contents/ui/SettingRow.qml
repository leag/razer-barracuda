import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../code/output.js" as Output

// A headset setting read when the popup opens: its icon, name and value. It is
// changed from its action in the menu. Child object names extend the row's.
RowLayout {
    id: row
    property string iconName: ""
    property string text: ""
    property var value: null
    property bool busy: false
    property string localeName: Qt.locale().name
    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.largeSpacing
    Layout.rightMargin: Kirigami.Units.largeSpacing
    spacing: Kirigami.Units.largeSpacing
    Kirigami.Icon {
        objectName: row.objectName + "Icon"
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        source: row.iconName
        opacity: row.value === null ? 0.5 : 1
    }
    PC3.Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: row.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        opacity: 0.75
    }
    PC3.Label {
        objectName: row.objectName + "Value"
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.busy ? Output.text("Reading…", "Leyendo…", row.localeName)
            : row.value === true ? Output.text("On", "Activado", row.localeName)
            : row.value === false ? Output.text("Off", "Desactivado", row.localeName)
            : Output.text("Unknown", "Desconocido", row.localeName)
    }
}
