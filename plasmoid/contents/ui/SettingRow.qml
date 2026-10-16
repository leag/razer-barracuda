import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../code/output.js" as Output

// A headset connection mode: its icon and name, a switch showing the value the
// headset reported, and one line that explains it. Without a boolean reading
// the switch gives way to "Reading…" or "Unknown", so an unknown value never
// looks Off. Child object names extend the row's.
ColumnLayout {
    id: row
    property string iconName: ""
    property string text: ""
    property string description: ""
    // Shown instead of the description while the switch cannot be used for a
    // reason the user should know.
    property string disabledReason: ""
    property var value: null
    property bool busy: false
    // Whether the switch accepts a change now.
    property bool interactive: false
    property string localeName: Qt.locale().name
    readonly property bool known: typeof value === "boolean"
    // Asks for the new value. The switch keeps showing the reported value
    // until a new reading confirms the change.
    signal toggleRequested(bool value)
    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.largeSpacing
    Layout.rightMargin: Kirigami.Units.largeSpacing
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        Kirigami.Icon {
            id: icon
            objectName: row.objectName + "Icon"
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            source: row.iconName
            opacity: row.known ? 1 : 0.5
        }
        PC3.Label {
            objectName: row.objectName + "Label"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: row.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        PC3.Switch {
            objectName: row.objectName + "Switch"
            visible: row.known
            checked: row.value === true
            enabled: row.interactive
            Accessible.name: row.text
            Accessible.description: descriptionLabel.text
            onToggled: {
                const requested = checked;
                checked = Qt.binding(() => row.value === true);
                row.toggleRequested(requested);
            }
        }
        PC3.Label {
            objectName: row.objectName + "Value"
            visible: !row.known
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: row.busy ? Output.text("Reading…", "Leyendo…", row.localeName)
                : Output.text("Unknown", "Desconocido", row.localeName)
            opacity: 0.75
        }
    }
    PC3.Label {
        id: descriptionLabel
        objectName: row.objectName + "Description"
        Layout.fillWidth: true
        // Under the name, past the icon column.
        Layout.leftMargin: icon.Layout.preferredWidth + Kirigami.Units.largeSpacing
        visible: text.length > 0
        text: row.disabledReason.length > 0 ? row.disabledReason : row.description
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.75
    }
}
