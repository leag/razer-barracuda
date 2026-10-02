import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/output.js" as Output

// Runs the finite, read-only link query on request. It reads what the driver and
// BlueZ already publish; it never opens HID or sends anything to the headset.
Plasma5Support.DataSource {
    id: monitor
    engine: "executable"
    connectedSources: []
    property var status: null
    property bool running: false
    property bool pending: false

    function refresh() {
        if (running) {
            pending = true;
            return;
        }
        running = true;
        connectSource(Output.linkCommand());
    }
    onNewData: (sourceName, data) => {
        disconnectSource(sourceName);
        running = false;
        status = Output.parseLink(String(data.stdout || ""));
        if (pending) {
            pending = false;
            refresh();
        }
    }
}
