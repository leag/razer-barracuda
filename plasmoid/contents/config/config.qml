import QtQuick
import org.kde.plasma.configuration
import "../code/output.js" as Output

// The widget's configuration window holds how the headset sounds and when it
// turns itself off; everything about its connection is in the popup. It opens
// from the gear of the popup or tray heading and from the context menu.
// Explanations use at most one KDE contextual help button per view, not a
// separate page.
ConfigModel {
    ConfigCategory {
        name: Output.text("Equalizer", "Ecualizador", Qt.locale().name)
        icon: "view-media-equalizer"
        source: "ConfigEqualizer.qml"
    }
    ConfigCategory {
        name: Output.text("Power Saving", "Ahorro de energía", Qt.locale().name)
        icon: "preferences-system-power-management"
        source: "ConfigPowerSaving.qml"
    }
}
