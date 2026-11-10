import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One link under the headset card: the device's artwork in a large square,
// then its name and, when there is one, the line under it, as a list row's
// title and subtitle. A link known to be down dims the artwork, as
// HeadsetArtwork does. The row only reports; it takes no focus and has no
// action.
Item {
    id: row
    // A theme icon name, or a path relative to contents/ui for the
    // project's own drawings (Output.artwork).
    property string artwork
    property string title
    // The line under the title; empty for a working link.
    property string subtitle
    // What a screen reader says for the row.
    property string spoken: subtitle.length > 0 ? title + ", " + subtitle : title
    property bool dimmed: false
    // x of the artwork square and of the text column.
    property real iconX: 0
    property real textX: iconX + Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing

    implicitHeight: Math.max(icon.height, texts.implicitHeight) + Kirigami.Units.smallSpacing
    Accessible.role: Accessible.StaticText
    Accessible.name: spoken

    Kirigami.Icon {
        id: icon
        objectName: "connectionArtwork"
        x: row.iconX
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.large
        height: width
        source: row.artwork.startsWith("../") ? Qt.resolvedUrl(row.artwork).toString() : row.artwork
        opacity: row.dimmed ? 0.5 : 1
        Accessible.ignored: true
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.longDuration }
        }
    }
    Column {
        id: texts
        x: row.textX
        width: row.width - x - Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        PC3.Label {
            objectName: "connectionTitle"
            width: parent.width
            text: row.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            Accessible.ignored: true
        }
        PC3.Label {
            objectName: "connectionState"
            visible: text.length > 0
            width: parent.width
            text: row.subtitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            Accessible.ignored: true
        }
    }
}
