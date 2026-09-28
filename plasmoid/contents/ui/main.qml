import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.volume
import org.kde.kcmutils as KCMUtils
import "../code/output.js" as Output

PlasmoidItem {
    id: root
    // Follow the server default, not individual applications' output overrides.
    readonly property var sink: Server.defaultSink
    readonly property bool hasOutput: Boolean(sink) && sink.name !== "auto_null"
    readonly property string deviceName: hasOutput ? (sink.description || sink.name)
        : label("No audio output", "Sin salida de audio")
    readonly property string deviceIcon: Output.icon(sink)
    readonly property string deviceArtwork: Output.artwork(deviceIcon)
    function label(english, spanish) {
        return Output.text(english, spanish, Qt.locale().name)
    }
    function openSettings() {
        KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
    }

    Plasmoid.icon: deviceArtwork
    toolTipMainText: deviceName
    toolTipSubText: (hasOutput && sink.muted ? label("Muted · ", "Silenciado · ") : "")
        + label("Open sound settings", "Abrir ajustes de sonido")
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : compactRepresentation
    compactRepresentation: PC3.ToolButton {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        // Use the panel's available size instead of the theme's small button icon.
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : 0
        Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : 0
        Layout.preferredWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : implicitWidth
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : implicitHeight
        contentItem: Item {
            Image {
                anchors.fill: parent
                source: root.deviceArtwork.startsWith("file:") ? root.deviceArtwork : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                source: root.deviceIcon
                visible: !root.deviceArtwork.startsWith("file:")
            }
        }
        Accessible.name: root.deviceName
        onClicked: root.openSettings()
        Kirigami.Icon {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Kirigami.Units.iconSizes.small
            height: width
            source: "audio-volume-muted"
            visible: root.hasOutput && root.sink.muted
        }
    }
    fullRepresentation: PC3.ToolButton {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3
        icon.name: root.deviceIcon
        icon.source: root.deviceArtwork.startsWith("file:") ? root.deviceArtwork : ""
        text: root.deviceName
        onClicked: root.openSettings()
    }
}
