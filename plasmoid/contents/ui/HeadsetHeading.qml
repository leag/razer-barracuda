import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The popup's heading in a panel or on the desktop. The system tray draws
// this same row from the applet's actions, so inside the tray the view hides
// it. Same order, same forms, same selection rules: the title, one icon
// button per high-priority action (the '+' that pairs), More actions with
// the normal-priority actions, and the configure button.
PlasmaExtras.PlasmoidHeading {
    id: heading
    property string title: ""
    // Plasmoid.contextualActions, and Plasmoid.internalAction("configure").
    property var actions: []
    property QtObject configureAction: null
    property string moreActionsText: "More actions"

    readonly property var primaryActions: Output.primaryActions(actions, PlasmaCore.Action.HighPriority)
    readonly property var menuActions: Output.moreActions(actions, configureAction, PlasmaCore.Action.NormalPriority)

    // Keyboard focus for the first button, when Up leaves the body.
    function focusFirst(reason) {
        const button = Array.from(buttons.children).find(item => item.visible && item.enabled
                                                         && (item.focusPolicy & Qt.TabFocus));
        if (button)
            button.forceActiveFocus(reason);
    }
    function closeMenu() {
        if (moreActionsButton.menu)
            moreActionsButton.menu.close();
    }

    contentItem: RowLayout {
        id: buttons
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
        PC3.ToolButton {
            id: configureButton
            objectName: "configureButton"
            visible: heading.configureAction !== null
            icon.name: "configure"
            display: PC3.AbstractButton.IconOnly
            text: heading.configureAction ? Output.actionText(heading.configureAction.text) : ""
            onClicked: heading.configureAction.trigger()
            PC3.ToolTip { text: configureButton.text }
        }
    }
}
