import QtQuick
import org.kde.plasma.configuration
import "../code/output.js" as Output

// One page for what the headset stores: how it sounds and when it turns
// itself off. Everything about its connection is in the popup. It opens from
// the gear of the popup or tray heading and from the context menu. The
// category icon is the full-colour headset the popup shows, in the same icon
// language as Plasma's own categories. Explanations use at most one KDE
// contextual help button per view, not a separate page.
ConfigModel {
    ConfigCategory {
        name: Output.text("Headset", "Auricular", Qt.locale().name)
        icon: "audio-headset"
        source: "ConfigHeadset.qml"
    }
}
