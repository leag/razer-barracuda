import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The whole-view message for a view with no confirmed link. It is
// PlasmaExtras.PlaceholderMessage, metric for metric (spacing gridUnit, icon
// huge × 1.5, Primary heading, explanation Label, informational opacity
// 0.75), with one difference: its icon is HeadsetArtwork, so each state can
// carry its artwork treatment and state emblem (medium, over the corner),
// which PlaceholderMessage's plain icon cannot. A busy state adds a
// BusyIndicator child, as PlaceholderMessage documents.
ColumnLayout {
    id: message
    property string artwork: "audio-headset"
    property bool dimmed: false
    property string emblem: ""
    property string text: ""
    property string explanation: ""
    property bool busy: false

    spacing: Kirigami.Units.gridUnit

    HeadsetArtwork {
        objectName: "placeholderArtwork"
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: iconSize
        Layout.preferredHeight: iconSize
        // PlaceholderMessage's icon size.
        iconSize: Math.round(Kirigami.Units.iconSizes.huge * 1.5)
        emblemPlacement: "corner"
        iconName: message.artwork
        dimmed: message.dimmed
        emblems: message.emblem ? [message.emblem] : []
        emblemSize: Kirigami.Units.iconSizes.medium
    }
    Kirigami.Heading {
        objectName: "placeholderTitle"
        Layout.fillWidth: true
        text: message.text
        type: Kirigami.Heading.Primary
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        opacity: 0.75
    }
    PC3.Label {
        objectName: "placeholderExplanation"
        Layout.fillWidth: true
        visible: text.length > 0
        text: message.explanation
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        opacity: 0.75
    }
    PC3.BusyIndicator {
        objectName: "placeholderBusy"
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        visible: message.busy
        running: visible
    }
}
