import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The headset with a confirmed link: the popup's subject, so it gets the
// largest picture and the largest words in the body.
//
// One 64 px band: the detailed artwork (its drawing starts on the same
// column as the device icons below), the transport glyphs beside it, then a
// text column with the state and the percentage as level-2 headings, the
// battery bar across the column and the transport line in the small font.
// The expand toggle, or a busy indicator while a command runs on the headset,
// is centred on the band at the trailing edge, where every list row has it.
// The whole card is one row: hover and keyboard focus draw the list highlight
// over it and a click anywhere expands the details, as an ExpandableListItem.
PC3.ItemDelegate {
    id: card
    property var connection: ({state: "connected", transport: "usb"})
    property var battery: null
    // [[key, value], …] for the expanded details.
    property var details: []
    property string localeName: Qt.locale().name
    property bool expanded: false
    // A command is running on the headset (turning it off).
    property bool turningOff: false
    // x of the artwork square in the card, so that the drawing starts on the
    // list's icon column.
    property real artworkX: 0
    readonly property var lines: Output.hero(connection, battery, turningOff, localeName)
    readonly property bool expandable: details.length > 0 && !turningOff

    hoverEnabled: true
    leftPadding: 0
    rightPadding: Kirigami.Units.smallSpacing
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing
    // Highlight sizes itself from ListView.view, which only delegates have,
    // so here it fills a plain item.
    background: Item {
        PlasmaExtras.Highlight {
            anchors.fill: parent
            hovered: true
            pressed: card.pressed
            visible: card.expandable && (card.hovered || card.visualFocus)
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: lines.accessible
    Accessible.description: expandable ? (expanded ? Output.text("Expanded", "Expandido", localeName)
                                                   : Output.text("Collapsed", "Contraído", localeName)) : ""
    onClicked: {
        if (expandable)
            expanded = !expanded;
    }
    onTurningOffChanged: {
        if (turningOff)
            expanded = false;
    }

    contentItem: ColumnLayout {
        spacing: 0

        Item {
            id: band
            objectName: "heroBand"
            Layout.fillWidth: true
            implicitHeight: artwork.iconSize

            HeadsetArtwork {
                id: artwork
                objectName: "heroArtwork"
                x: card.artworkX
                width: implicitWidth
                height: implicitHeight
                iconSize: Kirigami.Units.iconSizes.huge
                emblemPlacement: "beside"
                emblems: Output.transportEmblems(card.connection)
                emblemSize: Kirigami.Units.iconSizes.small
            }

            ColumnLayout {
                id: textColumn
                anchors {
                    left: artwork.right
                    leftMargin: Kirigami.Units.gridUnit
                    right: trailing.left
                    rightMargin: Kirigami.Units.smallSpacing
                    verticalCenter: parent.verticalCenter
                }
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        objectName: "heroHeadline"
                        Layout.fillWidth: true
                        level: 2
                        text: card.lines.headline
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                    Kirigami.Heading {
                        objectName: "heroPercent"
                        visible: text.length > 0
                        level: 2
                        text: card.lines.percent
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
                // Never coloured: a low battery is a word and the tray's
                // attention state.
                PC3.ProgressBar {
                    objectName: "heroBattery"
                    Layout.fillWidth: true
                    visible: card.battery !== null
                    from: 0
                    to: 100
                    value: card.battery ? card.battery.percent : 0
                    Accessible.ignored: true
                }
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
            }

            // One trailing slot, centred on the band: expand, or busy.
            Item {
                id: trailing
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: expandButton.implicitWidth
                implicitHeight: expandButton.implicitHeight
                width: implicitWidth
                height: implicitHeight

                PC3.ToolButton {
                    id: expandButton
                    objectName: "heroExpand"
                    anchors.fill: parent
                    visible: card.expandable
                    display: PC3.AbstractButton.IconOnly
                    icon.name: card.expanded ? "collapse" : "expand"
                    text: card.expanded ? Output.text("Collapse", "Contraer", card.localeName)
                                        : Output.text("Expand", "Expandir", card.localeName)
                    // The card itself takes keyboard focus; this is for the pointer.
                    focusPolicy: Qt.NoFocus
                    onClicked: card.expanded = !card.expanded
                    PC3.ToolTip { text: expandButton.text }
                }
                PC3.BusyIndicator {
                    objectName: "heroBusy"
                    anchors.fill: parent
                    visible: card.turningOff
                    running: visible
                }
            }
        }

        DetailsGrid {
            objectName: "heroDetails"
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: card.expanded && card.expandable
            rows: card.details
        }
    }
}
