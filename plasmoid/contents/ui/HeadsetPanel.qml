import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../code/output.js" as Output

// The full view: a heading that stays put, then the headset summary in a
// scrolling body. In a panel popup or on the desktop the widget draws the
// heading the system tray draws for it there: the widget's name, More actions
// (the applet's actions, which lead out to KDE's audio settings) and a
// configure button for the widget's own configuration window (the equalizer
// and power saving).
ColumnLayout {
    id: panel
    property var status: null
    property bool activeView: true
    property bool showHeader: true
    // Plasmoid.title inside Plasma.
    property string title: ""
    // Text of Plasma's own configure action, so the button names the window as
    // the context menu does. Empty outside Plasma.
    property string configureText: ""
    // The applet's More actions entries, as the system tray selects them from
    // Plasmoid.contextualActions.
    property var menuActions: []
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    property string powerResult: ""
    property var battery: null
    // The headset settings controller (HeadsetController) read by the popup.
    property var settings: null
    property string localeName: Qt.locale().name
    signal headsetSettingsRequested()
    signal pairingRequested()
    signal powerOffRequested()
    signal settingChangeRequested(string feature, bool enabled)
    signal settingsRefreshRequested()
    signal sourceSwitchRequested(string address)

    function label(english, spanish) {
        return Output.text(english, spanish, localeName)
    }
    onActiveViewChanged: {
        if (!activeView)
            moreActionsMenu.close();
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    // From showHeader, not the heading's visibility, which is false while the
    // popup itself is hidden and Plasma sizes it.
    Layout.preferredHeight: (showHeader ? heading.implicitHeight + spacing : 0)
        + overview.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumHeight: panel.Layout.preferredHeight
    // A panel popup fits its content; the system tray gives every applet the
    // same size, which the summary fills.
    Layout.maximumHeight: showHeader ? panel.Layout.preferredHeight : Infinity
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        id: heading
        objectName: "summaryHeader"
        visible: panel.showHeader
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Heading {
            objectName: "popupTitle"
            Layout.fillWidth: true
            leftPadding: Kirigami.Units.largeSpacing
            level: 1
            text: panel.title.length > 0 ? panel.title : panel.label("Barracuda Headset", "Auricular Barracuda")
            textFormat: Text.PlainText
            maximumLineCount: 1
            elide: Text.ElideRight
        }
        PC3.ToolButton {
            id: moreActionsButton
            objectName: "moreActionsButton"
            visible: panel.menuActions.length > 0
            icon.name: "application-menu"
            display: PC3.AbstractButton.IconOnly
            text: panel.label("More actions", "Más acciones")
            checkable: true
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered && !moreActionsMenu.visible
            onToggled: {
                if (checked)
                    moreActionsMenu.popup(moreActionsButton, 0, moreActionsButton.height);
                else
                    moreActionsMenu.close();
            }
            PC3.Menu {
                id: moreActionsMenu
                objectName: "moreActionsMenu"
                // A press on the button itself closes the menu through the
                // button, not twice.
                closePolicy: PC3.Popup.CloseOnEscape | PC3.Popup.CloseOnPressOutsideParent
                onOpened: moreActionsButton.checked = true
                onClosed: moreActionsButton.checked = false
                Instantiator {
                    model: panel.menuActions
                    delegate: PC3.MenuItem {
                        required property var modelData
                        text: Output.actionText(modelData.text)
                        icon.name: modelData.icon.name
                        enabled: modelData.enabled
                        onTriggered: modelData.trigger()
                    }
                    onObjectAdded: (index, object) => moreActionsMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => moreActionsMenu.removeItem(object)
                }
            }
        }
        PC3.ToolButton {
            objectName: "configureButton"
            icon.name: "configure"
            display: PC3.AbstractButton.IconOnly
            text: panel.configureText.length > 0 ? Output.actionText(panel.configureText)
                : panel.label("Configure Barracuda Headset…", "Configurar Auricular Barracuda…")
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
            onClicked: panel.headsetSettingsRequested()
        }
    }

    PC3.ScrollView {
        id: overviewScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitWidth: 0
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
        // Keep wrapping stable while the vertical scrollbar changes visibility.
        contentWidth: width
        ConnectionSummary {
            id: overview
            objectName: "connectionOverview"
            width: overviewScroll.width
            // Fill a taller popup (the system tray's fixed size) without
            // making the content scroll.
            height: Math.max(implicitHeight, overviewScroll.availableHeight)
            status: panel.status
            activeView: panel.activeView
            localeName: panel.localeName
            pairingBusy: panel.pairingBusy
            pairingError: panel.pairingError
            pairingResult: panel.pairingResult
            powerBusy: panel.powerBusy
            powerError: panel.powerError
            powerResult: panel.powerResult
            battery: panel.battery
            settings: panel.settings
            onPairingRequested: panel.pairingRequested()
            onPowerOffRequested: panel.powerOffRequested()
            onSettingChangeRequested: (feature, enabled) => panel.settingChangeRequested(feature, enabled)
            onSettingsRefreshRequested: panel.settingsRefreshRequested()
            onSourceSwitchRequested: address => panel.sourceSwitchRequested(address)
        }
    }
}
