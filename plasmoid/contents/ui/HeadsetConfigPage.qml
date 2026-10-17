import QtQuick
import QtQuick.Window
import org.kde.kcmutils as KCM
import org.kde.plasma.private.volume
import "../code/output.js" as Output

// The Headset page of the configuration window. It reads the link and the
// default output on its own, so it chooses the same transport as the popup
// without a shared state; it has no configuration keys. Its changes wait for
// the window's Apply or OK.
KCM.AbstractKCM {
    id: page
    framedView: false
    readonly property var target: Output.headsetTarget(Server.defaultSink, link.status)
    // Plasma may create configuration pages before showing them. Nothing is read
    // until the page is in a window: only then does it query the link and the
    // headset, once per showing.
    readonly property bool shown: visible && Window.window !== null
    function load() {
        if (!shown)
            return;
        link.refresh();
        headset.request({op: "status"});
    }
    onShownChanged: load()
    Component.onCompleted: load()

    LinkMonitor { id: link }
    // Follow transport changes only while the page is shown.
    Timer {
        interval: 5000
        repeat: true
        running: page.shown
        onTriggered: link.refresh()
    }
    HeadsetController {
        id: headset
        objectName: "headsetController"
        target: page.target
        activeView: page.shown
    }
    // Plasma's configuration window enables its Apply button from
    // unsavedChanges, calls saveConfig() for Apply and OK, and discards the
    // page on Cancel.
    readonly property bool unsavedChanges: settings.unsavedChanges
    function saveConfig() { settings.save(); }
    HeadsetSettings {
        id: settings
        anchors.fill: parent
        controller: headset
    }
}
