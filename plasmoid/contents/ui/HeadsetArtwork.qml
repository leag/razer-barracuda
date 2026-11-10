import QtQuick
import org.kde.kirigami as Kirigami
import "../code/output.js" as Output

// Product artwork with its state treatment. The popup draws the headset as
// the project's logo (images/logo.svg, docs/logo.svg in a square viewBox)
// and the dongle as the project's drawing of it (images/dongle.svg,
// docs/dongle-2022.svg in a square viewBox): full opacity with a confirmed or
// possible link, half opacity when the object is known to be absent. No
// colour is added: state is carried by opacity, the emblem and the words next
// to it. Panel and tray icons use the theme's symbolic glyph instead.
//
// The emblem (full colour: question, warning) sits over the bottom-right
// corner, as KDE draws every icon emblem.
Item {
    id: artwork
    property bool symbolic: false
    // A Breeze device icon name; the project's drawings are loaded for
    // headsets and the USB dongle, the symbolic glyph otherwise.
    property string iconName: "audio-headset"
    property bool dimmed: false
    property var emblems: []
    property real emblemSize: Kirigami.Units.iconSizes.small
    // The square the artwork is drawn in.
    property real iconSize: Kirigami.Units.iconSizes.huge
    readonly property string detailed: Output.artwork(iconName)

    implicitWidth: iconSize
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
    Kirigami.Icon {
        objectName: "artworkEmblem"
        visible: artwork.emblems.length > 0
        x: artwork.iconSize - width
        y: artwork.iconSize - height
        width: artwork.emblemSize
        height: artwork.emblemSize
        source: visible ? artwork.emblems[0] : ""
        Accessible.ignored: true
    }
}
