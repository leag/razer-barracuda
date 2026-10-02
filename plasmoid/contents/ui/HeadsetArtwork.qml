import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "../code/output.js" as Output

// KDE's detailed headset artwork with the connection overlay: dimmed without a
// confirmed link, a red slash when disconnected or without an adapter, and an
// optional corner emblem for the remaining states.
Item {
    id: headset
    property bool connected: false
    property bool slashed: false
    property string emblem: ""
    property real emblemSize: Kirigami.Units.iconSizes.small
    // Breeze's camera-off proportions at 22 px: a 1 px stroke over about 70%
    // of the diagonal, with the glyph cut away on both sides of it.
    readonly property real stroke: Math.max(1, Math.min(width, height) / 22)
    readonly property real strokeLength: Math.hypot(width, height) * 0.7
    // The software scene graph has no shader effects; it keeps the plain glyph.
    readonly property bool cutGap: slashed && GraphicsInfo.api !== GraphicsInfo.Software

    Item {
        id: glyph
        objectName: "headsetGlyph"
        anchors.fill: parent
        // While slashed, the glyph is drawn with the gap cut out of it.
        layer.enabled: headset.cutGap
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: gapMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Image {
            id: picture
            objectName: "headsetPicture"
            anchors.fill: parent
            source: Output.artwork("audio-headset")
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            opacity: headset.connected ? 1 : 0.5
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: "audio-headset"
            visible: picture.status !== Image.Ready
            opacity: picture.opacity
        }
    }
    Item {
        id: gap
        anchors.fill: parent
        visible: headset.cutGap
        Rectangle {
            anchors.centerIn: parent
            width: headset.strokeLength + headset.stroke * 2
            height: headset.stroke * 3
            rotation: 45
            antialiasing: true
            color: "black"
        }
    }
    ShaderEffectSource {
        id: gapMask
        anchors.fill: parent
        sourceItem: gap
        // Only the mask texture is used; the gap itself is never drawn.
        hideSource: true
        visible: false
    }
    Rectangle {
        objectName: "disconnectedSlash"
        anchors.centerIn: parent
        width: headset.strokeLength
        height: headset.stroke
        rotation: 45
        antialiasing: true
        color: Kirigami.Theme.negativeTextColor
        visible: headset.slashed
    }
    Kirigami.Icon {
        objectName: "connectionEmblem"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: headset.emblemSize
        height: width
        source: headset.emblem
        visible: headset.emblem !== ""
    }
}
