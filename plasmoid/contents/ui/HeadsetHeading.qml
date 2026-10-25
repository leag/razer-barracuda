import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The popup's heading. In a panel or on the desktop its first row is the
// title and the commands; the system tray draws that same row from the
// applet's actions, so inside the tray the view hides it. Same order, same
// forms, same selection rules: the title, one icon button per high-priority
// action (the '+' that pairs) and More actions with the normal-priority
// actions. Under it, with a confirmed link, are the view's tabs, as the
// volume applet puts Devices and Applications in its own heading; inside the
// tray they are all the heading shows, and the tray joins it to its own.
PlasmaExtras.PlasmoidHeading {
    id: heading
    property string title: ""
    // Plasmoid.contextualActions.
    property var actions: []
    property string moreActionsText: "More actions"
    // The title row; the tray draws its own.
    property bool titleShown: true
    // Tab names, or none for a view without tabs.
    property var tabs: []
    // The selected tab, kept while the tab buttons come and go.
    property int currentTab: 0
    readonly property alias tabBar: tabBar
    readonly property bool tabsShown: tabs.length > 0

    readonly property var primaryActions: Output.primaryActions(actions, PlasmaCore.Action.HighPriority)
    readonly property var menuActions: Output.moreActions(actions, PlasmaCore.Action.NormalPriority)

    // The tabs touch the heading's separator, as in the volume applet.
    bottomPadding: tabsShown ? -bottomInset : undefined

    // Keyboard focus for the first button, or the current tab, when Up
    // leaves the body.
    function focusFirst(reason) {
        if (tabsShown) {
            tabBar.currentItem.forceActiveFocus(reason);
            return;
        }
        const button = Array.from(buttons.children).find(item => item.visible && item.enabled
                                                         && (item.focusPolicy & Qt.TabFocus));
        if (button)
            button.forceActiveFocus(reason);
    }
    function closeMenu() {
        if (moreActionsButton.menu)
            moreActionsButton.menu.close();
    }

    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            id: buttons
            objectName: "titleRow"
            Layout.fillWidth: true
            visible: heading.titleShown
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                objectName: "popupTitle"
                Layout.fillWidth: true
                leftPadding: Kirigami.Units.largeSpacing
                level: 1
                text: heading.title
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
            }
            Repeater {
                model: heading.primaryActions
                PC3.ToolButton {
                    id: primaryButton
                    required property QtObject modelData
                    objectName: "primaryAction"
                    visible: modelData.visible
                    enabled: modelData.enabled
                    display: PC3.AbstractButton.IconOnly
                    text: Output.actionText(modelData.text)
                    // The tray's own drawing of a high-priority action.
                    contentItem: Kirigami.Icon {
                        anchors.centerIn: parent
                        active: primaryButton.hovered
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        source: primaryButton.modelData.icon.name
                    }
                    onClicked: modelData.trigger()
                    PC3.ToolTip { text: primaryButton.text }
                }
            }
            PC3.ToolButton {
                id: moreActionsButton
                objectName: "moreActionsButton"
                visible: heading.menuActions.length > 0
                icon.name: "application-menu"
                display: PC3.AbstractButton.IconOnly
                text: heading.moreActionsText
                Accessible.role: Accessible.ButtonMenu
                checkable: true
                // The menu, a QMenu as in the tray, is built on first use.
                property PlasmaExtras.Menu menu: null
                checked: menu !== null && menu.status !== PlasmaExtras.Menu.Closed
                onToggled: {
                    if (!checked) {
                        heading.closeMenu();
                        return;
                    }
                    if (menu === null)
                        menu = menuComponent.createObject(moreActionsButton);
                    menu.openRelative();
                }
                PC3.ToolTip { text: moreActionsButton.text }
                Component {
                    id: menuComponent
                    PlasmaExtras.Menu {
                        id: menu
                        visualParent: moreActionsButton
                        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
                        property Instantiator items: Instantiator {
                            model: heading.menuActions
                            delegate: PlasmaExtras.MenuItem {
                                required property QtObject modelData
                                action: modelData
                            }
                            onObjectAdded: (index, object) => menu.addMenuItem(object)
                            onObjectRemoved: (index, object) => menu.removeMenuItem(object)
                        }
                    }
                }
            }
        }
        PC3.TabBar {
            id: tabBar
            objectName: "tabBar"
            Layout.fillWidth: true
            visible: heading.tabsShown
            position: PC3.TabBar.Header
            currentIndex: heading.currentTab
            onCurrentIndexChanged: {
                if (currentIndex >= 0)
                    heading.currentTab = currentIndex;
            }
            // By count, so new names never recreate the buttons, which would
            // move the selection back to the first tab.
            Repeater {
                model: heading.tabs.length
                PC3.TabButton {
                    required property int index
                    objectName: "tab"
                    text: heading.tabs[index] || ""
                }
            }
        }
    }
}
