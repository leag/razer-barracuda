import QtQuick
import QtQuick.Window
import org.kde.kcmutils as KCM
import org.kde.plasma.private.volume
import "../code/output.js" as Output

// One section of the native headset settings ("equalizer", "powerSaving" or
// "quickConnect"). The
// page reads the link and the default output on its own, so it chooses the same
// transport as the popup without a shared state; it has no configuration keys
// and applies each change on request.
KCM.AbstractKCM {
    id: page
    framedView: false
    property string section: "equalizer"
    readonly property var target: Output.headsetTarget(Server.defaultSink, link.status)
    // Plasma may create configuration pages before showing them. Nothing is read
    // until the page is in a window: only then does it query the link and the
    // headset, once per showing.
    readonly property bool shown: visible && Window.window !== null
    function load() {
        if (!shown)
            return;
        link.refresh();
        // Only the equalizer depends on the legacy software effects state.
        if (section === "equalizer")
            audio.request({op: "status"});
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
    AudioController { id: audio; objectName: "audioController" }
    HeadsetController {
        id: headset
        objectName: "headsetController"
        target: page.target
        activeView: page.shown
    }
    // Plasma's configuration window enables its Apply button from
    // unsavedChanges and calls saveConfig() for Apply and OK.
    readonly property bool unsavedChanges: settings.unsavedBands
    function saveConfig() { settings.applyBands(); }
    HeadsetSettings {
        id: settings
        anchors.fill: parent
        section: page.section
        controller: headset
        audioController: audio
    }
}
