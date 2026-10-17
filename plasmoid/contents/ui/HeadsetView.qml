import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

// The full view, in the structure of every Plasma system applet: a
// Representation whose header is the applet's heading and whose body is a
// ScrollView with one ListView.
//
// With a confirmed link the list's header holds, in dependency order, the
// headset (HeroCard), the single feedback slot, the Modes section and the
// Bluetooth Devices section heading; the list rows are the devices the
// headset knows. Without a confirmed link, and while pairing, one
// placeholder replaces the body, with the feedback slot under it; it also
// waits for a power-off started without a confirmed link. The Disconnected
// placeholder offers the heading's pairing action as its next step.
//
// Visual vocabulary, one form per kind of thing:
//   headset command with consequences  PlasmaCore.Action with "…" in the
//                                     heading ('+' Pair, More actions › Turn Off)
//   confirmation                       Kirigami.PromptDialog (HeadsetPrompt)
//   headset boolean                    a list row that is a Switch (ModeSwitch)
//   one item's action in a list        ExpandableListItem default action
//   more information                   'expand'/'collapse' at a row's trailing edge
//   command in progress                BusyIndicator in that trailing slot, or in
//                                     the placeholder for the whole view
//   value being read / unknown         "Reading…" / "Unknown" in that trailing slot
//   outcome or problem                 the one Kirigami.InlineMessage slot
//   explanation                        one PlasmaExtras.ContextualHelpButton
//
// Columns, shared by every row (see the geometry block below): the section
// text and switch indicators start at the list's edge; device icons and the
// headset drawing start one icon inset further; switch labels, device titles
// and section notes share the title column.
PlasmaExtras.Representation {
    id: view

    property var linkStatus: null
    property var battery: null
    // HeadsetController: the one settings read per showing, and the requests.
    property var settings: null
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    // Inside the system tray, which draws the heading itself.
    property bool inTray: false
    property string localeName: Qt.locale().name
    // Plasmoid.contextualActions and Plasmoid.internalAction("configure").
    property var actions: []
    property QtObject configureAction: null
    // The view is on screen; closing it closes what was open in it.
    property bool activeView: true

    signal settingChangeRequested(string feature, var value)
    signal settingsRefreshRequested()
    signal pairingConfirmed()
    signal powerOffConfirmed()

    function label(english, spanish) { return Output.text(english, spanish, view.localeName); }
    // Called by the Pair and Turn Off actions once the popup is visible; one
    // question at a time.
    function confirmPairing() {
        if (openPrompt === null)
            pairPrompt.open();
    }
    function confirmPowerOff() {
        if (openPrompt === null)
            powerPrompt.open();
    }
    // The confirmation on screen, or null.
    readonly property var openPrompt: pairPrompt.dialog !== null ? pairPrompt.dialog : powerPrompt.dialog

    // --- geometry, from the components themselves --------------------------
    // ExpandableListItem: smallSpacing row margins, a medium icon, then the
    // RowLayout's spacing before the title.
    RowLayout { id: rowSpacingProbe; visible: false }
    PC3.ToolButton { id: buttonProbe; visible: false; text: "M"; icon.name: "network-connect-symbolic" }
    readonly property real iconColumn: Kirigami.Units.smallSpacing
    readonly property real titleColumn: Kirigami.Units.smallSpacing + Kirigami.Units.iconSizes.medium + rowSpacingProbe.spacing
    // Breeze device icons leave 1/16 of their size empty at the left.
    readonly property real deviceIconInset: Math.round(Kirigami.Units.iconSizes.medium / 16)
    // The default-action button's text ends this far from the row's edge.
    readonly property real trailingInset: Kirigami.Units.smallSpacing + buttonProbe.rightPadding
    readonly property real rowBusySize: buttonProbe.implicitHeight

    // --- link -----------------------------------------------------------
    readonly property var connection: Output.connection(linkStatus)
    readonly property bool connected: connection.state === "connected"
    readonly property bool adapterMissing: Output.adapterMissing(linkStatus)
    // Pairing and power-off wait only for a confirmed missing dongle or a
    // running command; unknown, unavailable and checking states never do.
    readonly property bool commandsEnabled: !pairingBusy && !powerBusy && !adapterMissing
    readonly property bool showPlaceholder: pairingBusy || !connected
    readonly property var placeholder: Output.placeholder(linkStatus, connection, battery, pairingBusy, powerBusy,
                                                          localeName)
    // The heading's '+': the one pairing action, which the Disconnected
    // placeholder also offers as its next step, as the Bluetooth applet
    // offers Pair Device… under No devices paired.
    readonly property QtObject pairAction: Output.primaryActions(actions, PlasmaCore.Action.HighPriority)[0] || null
    // Only Disconnected has a next step the widget can take; the other
    // states name what the user does.
    readonly property bool placeholderOffersPairing: showPlaceholder && placeholder.state === "disconnected"
        && pairAction !== null

    // --- settings, from the last reading taken with a confirmed link -------
    readonly property bool settingsBusy: settings !== null && settings.busy === true
    readonly property string pendingFeature: settingsBusy ? settings.requestFeature : ""
    readonly property var settingsState: connected && settings !== null && settings.response
        && settings.response.state ? settings.response.state : null
    readonly property string settingsError: connected && settings !== null ? settings.error : ""
    // Nothing could be read: the sections have nothing to show, so they go
    // and the feedback slot says why.
    readonly property bool readFailed: settingsState === null && !settingsBusy && settingsError.length > 0
    // The one read of this showing is running, or about to.
    readonly property bool reading: (settingsBusy && pendingFeature === "") || (settingsState === null && !readFailed)
    function settingValue(feature) {
        return settingsState !== null && typeof settingsState[feature] === "boolean" ? settingsState[feature] : null;
    }
    readonly property var dndState: settingValue("dnd")
    readonly property var gamingState: settingValue("gaming")
    // Gaming mode changes only over Bluetooth; the reading says which way the
    // settings went.
    readonly property bool gamingSettable: settingsState !== null && settings.response.transport === "bluetooth"
    readonly property bool settingsEnabled: connected && !settingsBusy && !pairingBusy && !powerBusy
    readonly property var devices: settingsState !== null && settingsState.devices
        && settingsState.devices.length !== undefined ? settingsState.devices : null
    readonly property var readErrors: settingsState !== null && settings.response.errors ? settings.response.errors : ({})
    readonly property bool sectionsShown: connected && !readFailed
    // A list that failed to read is left out; the feedback slot says so.
    readonly property bool devicesShown: sectionsShown && (devices !== null || reading)
    // Switching needs Bluetooth gaming mode known to be off.
    readonly property bool switchBlocked: devices !== null && devices.length > 0 && gamingState !== false
    property string pendingAddress: ""
    function rowNote(value) {
        return value !== null ? "" : reading ? label("Reading…", "Leyendo…") : label("Unknown", "Desconocido");
    }

    // --- the one feedback slot: the most relevant notice wins --------------
    readonly property var notice: {
        if (pairingError.length > 0)
            return {type: Kirigami.MessageType.Error, text: pairingError, retry: "pair"};
        if (pairingResult.length > 0)
            return {type: Kirigami.MessageType.Positive, text: pairingResult, retry: ""};
        if (powerError.length > 0)
            return {type: Kirigami.MessageType.Error, text: powerError, retry: "power"};
        if (settingsError.length > 0) {
            // A change the headset did not apply leaves its control in place
            // to try again; anything that left the state unknown offers a read.
            return {type: Kirigami.MessageType.Warning,
                    text: Output.settingsFailure(settings.requestFeature, settings.errorCode, settingsError, localeName),
                    retry: settingsState === null ? "read" : ""};
        }
        const failed = ["dnd", "gaming", "devices"].filter(feature => readErrors[feature]);
        if (connected && failed.length > 0)
            return {type: Kirigami.MessageType.Warning, text: Output.readFailure(failed, localeName), retry: "read"};
        return {type: Kirigami.MessageType.Information, text: "", retry: ""};
    }
    // The text of a notice the user closed; a new attempt shows it again.
    property string dismissedNotice: ""
    readonly property bool noticeShown: notice.text.length > 0 && notice.text !== dismissedNotice
    onSettingsBusyChanged: {
        if (settingsBusy)
            dismissedNotice = "";
        else
            pendingAddress = "";
    }
    onPairingBusyChanged: {
        if (pairingBusy)
            dismissedNotice = "";
    }
    onPowerBusyChanged: {
        if (powerBusy)
            dismissedNotice = "";
    }
    onActiveViewChanged: {
        if (!activeView) {
            dismissedNotice = "";
            header.closeMenu();
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: Kirigami.Units.gridUnit * 24
    Layout.minimumWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    collapseMarginsHint: true
    focus: true

    // --- keyboard: Down from the heading enters the body; Up from its first
    // control returns to the heading, as in the Bluetooth applet.
    // The body's focusable items, published by the list header and the
    // placeholder themselves.
    property Item heroItem: null
    property Item dndControl: null
    property Item gamingControl: null
    property Item placeholderButton: null
    // The card takes focus only when it can expand.
    readonly property var bodyControls: (showPlaceholder ? [placeholderButton] : [heroItem, dndControl, gamingControl])
        .filter(item => item !== null && item.visible && item.enabled && item.expandable !== false)
    function focusBody(index, reason) {
        const controls = bodyControls;
        if (index >= 0 && index < controls.length) {
            list.currentIndex = -1;
            controls[index].forceActiveFocus(reason);
            return true;
        }
        if (index >= controls.length && list.count > 0) {
            list.currentIndex = 0;
            list.currentItem.forceActiveFocus(reason);
            return true;
        }
        if (index < 0 && !inTray && header.visible) {
            header.focusFirst(reason);
            return true;
        }
        return false;
    }
    function stepFocus(item, step, event) {
        const index = bodyControls.indexOf(item);
        event.accepted = index >= 0 && focusBody(index + step, step > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }
    // Only from outside the body (the list is a focus scope): Down past the
    // last control does not wrap to the first.
    Keys.onDownPressed: event => {
        event.accepted = !list.activeFocus && focusBody(0, Qt.TabFocusReason);
    }

    // Inside the system tray the tray draws this row itself; the tray merges
    // only a visible heading, so a hidden one leaves its heading alone.
    header: HeadsetHeading {
        visible: !view.inTray
        title: view.title
        actions: view.actions
        configureAction: view.configureAction
        moreActionsText: view.label("More actions", "Más acciones")
    }

    HeadsetPrompt {
        id: pairPrompt
        popup: view
        // Rejected on its own if the dongle goes away or the popup closes.
        available: view.commandsEnabled && view.activeView
        title: view.label("Pair Headset?", "¿Emparejar el auricular?")
        subtitle: view.label(
            "Put the headset in pairing mode. This replaces the dongle's current pairing and can take up to a minute.",
            "Pon el auricular en modo de emparejamiento. Esto reemplaza el emparejamiento actual del dongle y puede tardar hasta un minuto.")
        verb: view.label("Pair", "Emparejar")
        verbIcon: "list-add-symbolic"
        cancelText: view.label("Cancel", "Cancelar")
        onAccepted: view.pairingConfirmed()
    }
    HeadsetPrompt {
        id: powerPrompt
        popup: view
        available: view.commandsEnabled && view.activeView
        title: view.label("Turn Off Headset?", "¿Apagar el auricular?")
        subtitle: view.label("Turn it back on with its power button.",
                             "Vuelve a encenderlo con su botón de encendido.")
        verb: view.label("Turn Off", "Apagar")
        verbIcon: "system-shutdown-symbolic"
        cancelText: view.label("Cancel", "Cancelar")
        onAccepted: view.powerOffConfirmed()
    }

    // The placeholder's button for the pairing action: same text, icon,
    // enabled state and handler, so it opens the same confirmation.
    QQC2.Action {
        id: placeholderPairAction
        text: view.pairAction ? Output.actionText(view.pairAction.text) : ""
        icon.name: view.pairAction ? view.pairAction.icon.name : ""
        enabled: view.pairAction !== null && view.pairAction.enabled
        onTriggered: view.pairAction.trigger()
    }

    Component {
        id: feedbackComponent
        Kirigami.InlineMessage {
            objectName: "feedback"
            visible: view.noticeShown
            type: view.notice.type
            text: view.notice.text
            showCloseButton: true
            // The close button hides the message itself while its Loader
            // stays visible; hiding the whole view is not a dismissal.
            onVisibleChanged: {
                if (!visible && parent && parent.visible && view.noticeShown)
                    view.dismissedNotice = view.notice.text;
            }
            // A failed pairing under the Disconnected placeholder needs no
            // Try Again: the placeholder's Pair Headset… just above it opens
            // the same confirmation.
            actions: view.notice.retry.length > 0
                && !(view.notice.retry === "pair" && view.placeholderOffersPairing) ? [retryAction] : []
            Kirigami.Action {
                id: retryAction
                objectName: "retry"
                text: view.label("Try Again", "Reintentar")
                icon.name: "view-refresh-symbolic"
                enabled: view.notice.retry === "read" ? view.connected && !view.settingsBusy : view.commandsEnabled
                onTriggered: {
                    if (view.notice.retry === "pair")
                        view.confirmPairing();
                    else if (view.notice.retry === "power")
                        view.confirmPowerOff();
                    else
                        view.settingsRefreshRequested();
                }
            }
        }
    }

    PC3.ScrollView {
        id: scroll
        objectName: "bodyScroll"
        anchors.fill: parent
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        contentWidth: availableWidth - contentItem.leftMargin - contentItem.rightMargin

        contentItem: ListView {
            id: list
            objectName: "deviceList"
            readonly property real rowWidth: width - leftMargin - rightMargin
            clip: true
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            spacing: Kirigami.Units.smallSpacing
            topMargin: Kirigami.Units.largeSpacing
            leftMargin: Kirigami.Units.largeSpacing
            rightMargin: Kirigami.Units.largeSpacing
            bottomMargin: Kirigami.Units.largeSpacing
            highlight: PlasmaExtras.Highlight {}
            highlightMoveDuration: Kirigami.Units.shortDuration
            highlightResizeDuration: Kirigami.Units.shortDuration
            interactive: !view.showPlaceholder
            model: !view.devicesShown || view.devices === null ? [] : view.devices
            // A new reading replaces the model; no row is current until hovered.
            onModelChanged: currentIndex = -1
            Keys.onUpPressed: event => {
                if (currentIndex === 0) {
                    currentIndex = -1;
                    event.accepted = view.focusBody(view.bodyControls.length - 1, Qt.BacktabFocusReason);
                } else {
                    event.accepted = false;
                }
            }
            // A notice or a reading that changes the header's height must not
            // scroll the view: a list shown from its top stays at its top.
            property bool atTop: true
            onMovementEnded: atTop = contentY <= originY - topMargin + 0.5
            onContentHeightChanged: {
                if (atTop && !moving)
                    contentY = originY - topMargin;
            }
            onOriginYChanged: {
                if (atTop && !moving)
                    contentY = originY - topMargin;
            }

            header: ColumnLayout {
                width: list.rowWidth
                visible: !view.showPlaceholder
                height: visible ? implicitHeight + list.spacing : 0
                spacing: 0
                Component.onCompleted: {
                    view.heroItem = hero;
                    view.dndControl = dndRow.control;
                    view.gamingControl = gamingRow.control;
                }

                HeroCard {
                    id: hero
                    objectName: "hero"
                    Layout.fillWidth: true
                    connection: view.connection
                    battery: view.battery
                    turningOff: view.powerBusy
                    details: Output.detailRows(view.linkStatus, view.battery, view.localeName)
                    localeName: view.localeName
                    // The drawing, not its square, starts on the device icons' column.
                    artworkX: view.iconColumn + view.deviceIconInset - Math.round(Kirigami.Units.iconSizes.huge * 7 / 64)
                    Keys.onDownPressed: event => view.stepFocus(hero, 1, event)
                    Keys.onUpPressed: event => view.stepFocus(hero, -1, event)
                    Connections {
                        target: view
                        function onActiveViewChanged() {
                            if (!view.activeView)
                                hero.expanded = false;
                        }
                    }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    active: view.noticeShown && !view.showPlaceholder
                    visible: active
                    sourceComponent: feedbackComponent
                }

                PlasmaExtras.ListSectionHeader {
                    id: modesHeader
                    objectName: "modesHeader"
                    Layout.fillWidth: true
                    visible: view.sectionsShown
                    text: view.label("Modes", "Modos")
                    // The popup's only help.
                    PlasmaExtras.ContextualHelpButton {
                        objectName: "modesHelp"
                        // Its default caps it at the header row's text height.
                        Layout.maximumHeight: -1
                        toolTipText: view.label(
                            "Do not disturb keeps calls from a phone connected over Bluetooth from interrupting the dongle's audio; desktop notifications are not affected. Bluetooth gaming mode lowers Bluetooth audio delay; it is not the Game sound profile and changes only over Bluetooth. Bluetooth Devices (Razer Quick Connect) moves the headset's Bluetooth link to a device it already knows, while gaming mode is off.",
                            "No molestar evita que las llamadas de un teléfono conectado por Bluetooth interrumpan el audio del dongle; no afecta a las notificaciones del escritorio. El modo gaming Bluetooth reduce el retraso del audio Bluetooth; no es el perfil de sonido Juegos y solo se cambia por Bluetooth. Dispositivos Bluetooth (Quick Connect de Razer) mueve la conexión Bluetooth del auricular a un dispositivo que ya conoce, con el modo gaming desactivado.")
                    }
                }
                ModeSwitch {
                    id: dndRow
                    objectName: "dnd"
                    Layout.fillWidth: true
                    visible: view.sectionsShown
                    indicatorX: modesHeader.leftPadding
                    labelX: view.titleColumn
                    trailingInset: view.trailingInset
                    busySize: view.rowBusySize
                    text: view.label("Do not disturb", "No molestar")
                    value: view.dndState
                    busy: view.pendingFeature === "dnd"
                    interactive: view.settingsEnabled
                    note: view.rowNote(value)
                    onToggleRequested: value => view.settingChangeRequested("dnd", value)
                    Keys.onDownPressed: event => view.stepFocus(control, 1, event)
                    Keys.onUpPressed: event => view.stepFocus(control, -1, event)
                }
                ModeSwitch {
                    id: gamingRow
                    objectName: "gaming"
                    Layout.fillWidth: true
                    // The list's own row spacing.
                    Layout.topMargin: list.spacing
                    visible: view.sectionsShown
                    indicatorX: modesHeader.leftPadding
                    labelX: view.titleColumn
                    trailingInset: view.trailingInset
                    busySize: view.rowBusySize
                    text: view.label("Bluetooth gaming mode", "Modo gaming Bluetooth")
                    value: view.gamingState
                    busy: view.pendingFeature === "gaming"
                    interactive: view.settingsEnabled && view.gamingSettable
                    note: value !== null && !view.gamingSettable ? view.label("Only over Bluetooth", "Solo por Bluetooth")
                        : view.rowNote(value)
                    onToggleRequested: value => view.settingChangeRequested("gaming", value)
                    Keys.onDownPressed: event => view.stepFocus(control, 1, event)
                    Keys.onUpPressed: event => view.stepFocus(control, -1, event)
                }

                PlasmaExtras.ListSectionHeader {
                    id: devicesHeader
                    objectName: "devicesHeader"
                    Layout.fillWidth: true
                    visible: view.devicesShown
                    text: view.label("Bluetooth Devices", "Dispositivos Bluetooth")
                }
                PlasmaExtras.DescriptiveLabel {
                    objectName: "devicesNote"
                    Layout.fillWidth: true
                    // On the device titles' column, as a note about them.
                    Layout.leftMargin: view.titleColumn
                    Layout.rightMargin: view.trailingInset
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    visible: view.devicesShown && text.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: Output.devicesNote(view.devices, view.reading, view.gamingState, view.localeName)
                }
            }

            delegate: PlasmaExtras.ExpandableListItem {
                id: device
                required property int index
                required property var modelData
                readonly property bool active: modelData.active === true
                readonly property bool switching: view.pendingFeature === "devices"
                    && view.pendingAddress === modelData.address
                objectName: "deviceRow"
                width: list.rowWidth
                // The helper reports no device class; this is the icon BluezQt
                // gives a Bluetooth device of unknown type.
                icon: "preferences-system-bluetooth"
                title: modelData.name || Output.macAddress(modelData.address)
                subtitle: active ? view.label("Connected", "Conectado")
                    : switching ? view.label("Connecting…", "Conectando…") : ""
                isDefault: active
                isBusy: switching
                defaultActionButtonVisible: !active
                defaultActionButtonAction: QQC2.Action {
                    text: view.label("Connect", "Conectar")
                    icon.name: "network-connect-symbolic"
                    enabled: view.settingsEnabled && !view.switchBlocked
                    onTriggered: {
                        view.pendingAddress = device.modelData.address;
                        view.settingChangeRequested("devices", device.modelData.address);
                    }
                }
            }

            Loader {
                id: placeholderLoader
                objectName: "placeholderLoader"
                anchors.centerIn: parent
                width: parent.width - 4 * Kirigami.Units.gridUnit
                active: view.showPlaceholder
                sourceComponent: ColumnLayout {
                    spacing: Kirigami.Units.gridUnit
                    StatePlaceholder {
                        objectName: "placeholder"
                        Layout.fillWidth: true
                        artwork: view.placeholder.artwork
                        dimmed: view.placeholder.dimmed
                        emblem: view.placeholder.emblem
                        text: view.placeholder.title
                        explanation: view.placeholder.explanation
                        busy: view.placeholder.busy
                        helpfulAction: view.placeholderOffersPairing ? placeholderPairAction : null
                        Component.onCompleted: view.placeholderButton = actionButton
                        Keys.onUpPressed: event => view.stepFocus(actionButton, -1, event)
                    }
                    Loader {
                        Layout.fillWidth: true
                        active: view.noticeShown
                        visible: active
                        sourceComponent: feedbackComponent
                    }
                }
            }
        }
    }
}
