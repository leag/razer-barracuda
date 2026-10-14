import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2

QQC2.Slider {
    required property var scrollItem
    wheelEnabled: false

    // Some styles handle wheels in their own MouseArea, independently of
    // wheelEnabled. Consume the event first and scroll the surrounding view.
    MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            event.accepted = true;
            const view = parent.scrollItem;
            if (!view)
                return;
            const delta = event.pixelDelta.y || event.angleDelta.y / 120 * Kirigami.Units.gridUnit * 3;
            const minimum = view.originY;
            const maximum = minimum + Math.max(0, view.contentHeight - view.height);
            view.contentY = Math.max(minimum, Math.min(maximum, view.contentY - delta));
        }
    }
}
