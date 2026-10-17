import QtQuick
import org.kde.kirigami as Kirigami

// A headset command's confirmation, built as the Bluetooth applet's
// ForgetDeviceDialog: a Kirigami.PromptDialog over the popup with a question
// as its title, the consequence as its subtitle, the named verb and Cancel as
// its only buttons, and focus on Cancel when it opens. Each dialog is created
// on open and destroyed on close, so nothing of it can take a key once it is
// gone, and it rejects itself as soon as its command stops being possible
// (the USB dongle unplugged, another command started, the popup closed).
QtObject {
    id: prompt
    // The view the dialog is drawn over.
    required property Item popup
    property string title: ""
    property string subtitle: ""
    property string verb: ""
    property string verbIcon: ""
    property string cancelText: "Cancel"
    // False closes an open dialog as rejected and keeps a new one closed.
    property bool available: true
    signal accepted()

    property Kirigami.PromptDialog dialog: null

    function open() {
        if (!available || dialog)
            return;
        dialog = component.createObject(prompt.popup);
        dialog.open();
    }
    onAvailableChanged: {
        if (!available && dialog)
            dialog.reject();
    }

    readonly property Component component: Component {
        Kirigami.PromptDialog {
            id: dialog
            title: prompt.title
            subtitle: prompt.subtitle
            showCloseButton: false
            // Inside the popup, with a grid unit of it showing on each side.
            preferredWidth: prompt.popup.width - Kirigami.Units.gridUnit * 2
            maximumWidth: preferredWidth
            standardButtons: Kirigami.Dialog.NoButton
            customFooterActions: [
                Kirigami.Action {
                    text: prompt.verb
                    icon.name: prompt.verbIcon
                    onTriggered: dialog.accept()
                },
                Kirigami.Action {
                    id: cancelAction
                    text: prompt.cancelText
                    icon.name: "dialog-cancel-symbolic"
                    shortcut: StandardKey.Cancel
                    onTriggered: dialog.reject()
                }
            ]
            // The safe default, as in ForgetDeviceDialog, with visible focus
            // so the user sees which button Enter presses.
            onOpened: customFooterButton(cancelAction)?.forceActiveFocus(Qt.TabFocusReason)
            onAccepted: prompt.accepted()
            onClosed: {
                prompt.dialog = null;
                destroy();
            }
        }
    }
}
