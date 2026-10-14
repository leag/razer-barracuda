import QtQuick
import org.kde.plasma.configuration
import "../code/output.js" as Output

// Headset settings live in the widget's configuration window, opened from the
// popup, the system tray heading or the context menu. Explanations use at most
// one KDE contextual help button per view, not a separate page.
ConfigModel {
    ConfigCategory {
        name: Output.text("Equalizer", "Ecualizador", Qt.locale().name)
        icon: "view-media-equalizer"
        source: "ConfigEqualizer.qml"
    }
    ConfigCategory {
        name: Output.text("Power saving", "Ahorro de energía", Qt.locale().name)
        icon: "preferences-system-power-management"
        source: "ConfigPowerSaving.qml"
    }
    ConfigCategory {
        name: "Quick Connect"
        icon: "preferences-system-bluetooth"
        source: "ConfigQuickConnect.qml"
    }
}
