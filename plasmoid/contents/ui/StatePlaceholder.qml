import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The whole-view message for a view with no confirmed link. It is
// PlasmaExtras.PlaceholderMessage, metric for metric (spacing gridUnit, icon
// huge × 1.5, Primary heading, explanation Label, opacity 0.75 unless an
// enabled helpful action makes it actionable, the action as a button a grid
// unit below), with two differences. Its icon is HeadsetArtwork, so each
// state can carry its artwork treatment and state emblem (medium, over the
// corner), which PlaceholderMessage's plain icon cannot. And a disabled
// helpful action stays visible, greyed, as the heading's own command does.
// A busy state adds a BusyIndicator child, as PlaceholderMessage documents.
ColumnLayout {
    id: message
    property string artwork: "audio-headset"
    property bool dimmed: false
    property string emblem: ""
    property string text: ""
    property string explanation: ""
    property bool busy: false
    // The next step, as a button under the words; null for none.
    property T.Action helpfulAction: null
    readonly property bool actionable: helpfulAction !== null && helpfulAction.enabled
    readonly property alias actionButton: actionButton

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
        opacity: message.actionable ? 1 : 0.75
    }
    PC3.Label {
        objectName: "placeholderExplanation"
        Layout.fillWidth: true
        visible: text.length > 0
        text: message.explanation
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        opacity: message.actionable ? 1 : 0.75
    }
    PC3.BusyIndicator {
        objectName: "placeholderBusy"
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        visible: message.busy
        running: visible
    }
    PC3.Button {
        id: actionButton
        objectName: "placeholderAction"
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: implicitWidth
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit
        visible: message.helpfulAction !== null
        action: message.helpfulAction
    }
}
