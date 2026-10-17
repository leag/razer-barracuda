import QtQuick
import org.kde.kirigami as Kirigami
import "../code/output.js" as Output

// Product artwork with its state treatment. The popup uses Breeze's detailed
// artwork: full opacity with a confirmed or possible link, half opacity when
// the object is known to be absent. No colour is added: state is carried by
// opacity, emblem and the words next to it. Panel and tray icons use the
// theme's symbolic glyph instead.
//
// Two kinds of marks, each with one placement:
//   "corner"  a state emblem (full colour: question, warning) over the
//             bottom-right corner, as KDE draws every icon emblem;
//   "beside"  transport glyphs (symbolic USB, Bluetooth) in a column right of
//             the drawing, bottom-aligned with it, never over it: line glyphs
//             drawn on detailed artwork turn into clutter.
Item {
    id: artwork
    property bool symbolic: false
    // A Breeze device icon name; detailed artwork is loaded for headsets and
    // the USB dongle, the symbolic glyph otherwise.
    property string iconName: "audio-headset"
    property bool dimmed: false
    property var emblems: []
    property real emblemSize: Kirigami.Units.iconSizes.small
    property string emblemPlacement: "corner"
    // The square the artwork is drawn in.
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Where Breeze's 64 px audio-headset drawing lies inside its square
    // (columns 7..58, rows 6..57), scaled to iconSize.
    readonly property real drawingLeft: Math.round(iconSize * 7 / 64)
    readonly property real drawingRight: Math.round(iconSize * 59 / 64)
    readonly property real drawingBottom: Math.round(iconSize * 58 / 64)
    readonly property bool beside: emblemPlacement === "beside" && emblems.length > 0

    implicitWidth: beside ? drawingRight + Math.round(Kirigami.Units.smallSpacing / 4) + emblemSize : iconSize
    implicitHeight: iconSize

    Kirigami.Icon {
        objectName: "artworkIcon"
        width: artwork.iconSize
        height: artwork.iconSize
        source: artwork.symbolic ? artwork.iconName + "-symbolic" : Output.artwork(artwork.iconName)
        // The theme's own icon if the detailed file is missing.
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
    // Transport glyphs beside the drawing, the first one at the bottom.
    Column {
        objectName: "artworkTransport"
        visible: artwork.beside
        x: artwork.drawingRight + Math.round(Kirigami.Units.smallSpacing / 4)
        y: artwork.drawingBottom - height
        spacing: Kirigami.Units.smallSpacing / 2
        Repeater {
            model: artwork.beside ? Array.from(artwork.emblems).reverse() : []
            Kirigami.Icon {
                required property string modelData
                objectName: "artworkGlyph"
                width: artwork.emblemSize
                height: artwork.emblemSize
                source: modelData
                Accessible.ignored: true
            }
        }
    }
}
