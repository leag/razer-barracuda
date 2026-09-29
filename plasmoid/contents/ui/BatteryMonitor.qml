import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/output.js" as Output

Plasma5Support.DataSource {
    id: monitor

    engine: "powermanagement"
    connectedSources: ["Battery"]
    property var records: ({})
    readonly property var battery: Output.battery(records, Object.keys(records))

    // Sources may disappear and return under the same name. Subscribe on each
    // addition and publish a fresh snapshot on every update, including updates
    // that arrive after discovery with initially incomplete device properties.
    onSourceAdded: source => {
        if (/^Battery\d+$/.test(source))
            connectSource(source);
    }
    onSourceRemoved: source => {
        disconnectSource(source);
        const next = Object.assign({}, records);
        delete next[source];
        records = next;
    }
    onNewData: (sourceName, data) => {
        if (!/^Battery\d+$/.test(sourceName))
            return;
        const next = Object.assign({}, records);
        next[sourceName] = Object.assign({}, data);
        records = next;
    }
    Component.onCompleted: {
        for (const source of Output.batterySources(sources))
            connectSource(source);
    }
}
