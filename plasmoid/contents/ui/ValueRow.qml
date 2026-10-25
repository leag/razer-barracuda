import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One reading that cannot be changed, laid out like a ModeSwitch row: a
// monochrome symbolic icon in the device-icon column, the name on the device
// titles' column and the value ending on the trailing edge.
Item {
    id: row
    property string text: ""
    property string value: ""
    property string iconName: ""
    property real indicatorX: 0
    property real labelX: Kirigami.Units.gridUnit * 2
    property real trailingInset: Kirigami.Units.smallSpacing

    implicitHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    Accessible.description: value

    Kirigami.Icon {
        objectName: "valueIcon"
        x: row.indicatorX + (Kirigami.Units.iconSizes.medium - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        source: row.iconName
        isMask: true
        color: Kirigami.Theme.textColor
    }
    PC3.Label {
        objectName: "valueLabel"
        x: row.labelX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, valueText.x - x - Kirigami.Units.smallSpacing)
        text: row.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        Accessible.ignored: true
    }
    PC3.Label {
        id: valueText
        objectName: "valueText"
        anchors.right: parent.right
        anchors.rightMargin: row.trailingInset
        anchors.verticalCenter: parent.verticalCenter
        text: row.value
        textFormat: Text.PlainText
        opacity: 0.75
        Accessible.ignored: true
    }
}
