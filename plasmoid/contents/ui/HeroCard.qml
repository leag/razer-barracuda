import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../code/output.js" as Output

// The headset with a confirmed link: the popup's subject, so it gets the
// largest picture and the largest words in the body.
//
// One 64 px band: the headset logo (its drawing starts on the same column as
// the device icons below), then a text column with the headset's name as a
// level-2 heading, the battery bar labelled with its charge state and
// percentage, as Power and Battery lists a device. The card exists only with
// a confirmed link and does not repeat it: a status beside the name, and a
// busy indicator at the trailing edge, appear only while a command runs on
// the headset. The card shows and does nothing else: the Connections rows
// under it name each link.
Item {
    id: card
    property var connection: ({state: "connected", transport: "usb"})
    property var battery: null
    property string localeName: Qt.locale().name
    // A command is running on the headset (turning it off).
    property bool turningOff: false
    // x of the artwork square in the card, so that the drawing starts on the
    // list's icon column.
    property real artworkX: 0
    readonly property var lines: Output.hero(connection, battery, turningOff, localeName)

    implicitHeight: artwork.iconSize + 2 * Kirigami.Units.smallSpacing
    Accessible.role: Accessible.StaticText
    Accessible.name: lines.accessible

    HeadsetArtwork {
        id: artwork
        objectName: "heroArtwork"
        x: card.artworkX
        anchors.verticalCenter: parent.verticalCenter
        width: iconSize
        height: iconSize
        iconSize: Kirigami.Units.iconSizes.huge
    }

    ColumnLayout {
        anchors {
            left: artwork.right
            leftMargin: Kirigami.Units.gridUnit
            right: busy.left
            rightMargin: Kirigami.Units.smallSpacing
            verticalCenter: parent.verticalCenter
        }
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                objectName: "heroTitle"
                Layout.fillWidth: true
                level: 2
                text: card.lines.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                Accessible.ignored: true
            }
            PC3.Label {
                objectName: "heroStatus"
                visible: text.length > 0
                text: card.lines.status
                textFormat: Text.PlainText
                opacity: 0.75
                Accessible.ignored: true
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                objectName: "heroLine"
                Layout.fillWidth: true
                text: card.lines.line
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.75
                Accessible.ignored: true
            }
            PC3.Label {
                objectName: "heroPercent"
                visible: text.length > 0
                text: card.lines.percent
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                Accessible.ignored: true
            }
        }
        // Never coloured: a low battery is a word and the tray's attention
        // state.
        PC3.ProgressBar {
            objectName: "heroBattery"
            Layout.fillWidth: true
            visible: card.battery !== null
            from: 0
            to: 100
            value: card.battery ? card.battery.percent : 0
            Accessible.ignored: true
        }
    }

    // The trailing slot, centred on the band, where every list row has its
    // busy indicator.
    PC3.BusyIndicator {
        id: busy
        objectName: "heroBusy"
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Kirigami.Units.iconSizes.medium : 0
        height: Kirigami.Units.iconSizes.medium
        visible: card.turningOff
        running: visible
    }
}
