import QtQuick
import org.kde.kirigami as Kirigami
import "../code/output.js" as Output

// Product artwork with its state treatment. The popup draws the headset as
// the project's logo (images/logo.svg, docs/logo.svg in a square viewBox)
// and the dongle as the project's drawing of it (images/dongle.svg,
// docs/dongle-2022.svg in a square viewBox): full opacity with a confirmed or
// possible link, half opacity when the object is known to be absent. No colour is added: state is carried by
// opacity, emblem and the words next to it. Panel and tray icons use the
// theme's symbolic glyph instead.
//
// Two kinds of marks, each with one placement:
//   "corner"  a state emblem (full colour: question, warning) over the
//             bottom-right corner, as KDE draws every icon emblem;
//   "beside"  transport marks (the dongle's drawing, the symbolic Bluetooth
//             glyph) in a column right of the drawing, bottom-aligned with
//             it, never over it: marks drawn on detailed artwork turn into
//             clutter.
Item {
    id: artwork
    property bool symbolic: false
    // A Breeze device icon name; the project's drawings are loaded for
    // headsets and the USB dongle, the symbolic glyph otherwise.
    property string iconName: "audio-headset"
    property bool dimmed: false
    property var emblems: []
    property real emblemSize: Kirigami.Units.iconSizes.small
    property string emblemPlacement: "corner"
    // The square the artwork is drawn in.
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Where the logo's drawing lies inside its square viewBox, in 256ths
    // (columns 29..226, rows 5..250), scaled to iconSize.
    readonly property real drawingLeft: Math.round(iconSize * 29 / 256)
    readonly property real drawingRight: Math.round(iconSize * 227 / 256)
    readonly property real drawingBottom: Math.round(iconSize * 251 / 256)
    readonly property string detailed: Output.artwork(iconName)
    readonly property bool beside: emblemPlacement === "beside" && emblems.length > 0
    // A drawing of the package among the marks is wider than a glyph: its
    // square is twice the glyph's, of which the dongle fills 264 x 146 of 320.
    readonly property real drawnMarkWidth: Math.round(emblemSize * 2 * 264 / 320) + 2
    readonly property real markWidth: Array.from(emblems).some(mark => mark.startsWith("../")) ? drawnMarkWidth : emblemSize

    implicitWidth: beside ? drawingRight + Math.round(Kirigami.Units.smallSpacing / 4) + markWidth : iconSize
    implicitHeight: iconSize

    Kirigami.Icon {
        objectName: "artworkIcon"
        width: artwork.iconSize
        height: artwork.iconSize
        source: artwork.symbolic ? artwork.iconName + "-symbolic"
              : artwork.detailed.startsWith("../") ? Qt.resolvedUrl(artwork.detailed).toString()
              : artwork.detailed
        // The theme's own icon if the file is missing.
        fallback: artwork.iconName
        opacity: artwork.dimmed ? 0.5 : 1
        Accessible.ignored: true
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.longDuration }
        }
    }
    // State emblem over the corner.
    Kirigami.Icon {
        objectName: "artworkEmblem"
        visible: artwork.emblemPlacement === "corner" && artwork.emblems.length > 0
        x: artwork.iconSize - width
        y: artwork.iconSize - height
        width: artwork.emblemSize
        height: artwork.emblemSize
        source: visible ? artwork.emblems[0] : ""
        Accessible.ignored: true
    }
    // Transport marks beside the drawing, the first one at the bottom.
    Column {
        objectName: "artworkTransport"
        visible: artwork.beside
        x: artwork.drawingRight + Math.round(Kirigami.Units.smallSpacing / 4)
        y: artwork.drawingBottom - height
        spacing: Kirigami.Units.smallSpacing / 2
        Repeater {
            model: artwork.beside ? Array.from(artwork.emblems).reverse() : []
            Item {
                required property string modelData
                readonly property bool drawn: modelData.startsWith("../")
                readonly property string source: modelData
                objectName: "artworkGlyph"
                // Centred on the widest mark.
                x: (artwork.markWidth - width) / 2
                width: drawn ? artwork.drawnMarkWidth : artwork.emblemSize
                height: artwork.emblemSize
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: parent.drawn ? artwork.emblemSize * 2 : artwork.emblemSize
                    height: width
                    source: parent.drawn ? Qt.resolvedUrl(parent.modelData).toString() : parent.modelData
                    Accessible.ignored: true
                }
            }
        }
    }
}
