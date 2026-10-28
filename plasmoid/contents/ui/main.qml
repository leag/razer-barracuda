import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.volume
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kcmutils as KCMUtils
import "../code/output.js" as Output

PlasmoidItem {
    id: root
    // The default output only selects the native-control transport when the
    // link reports do not; it is never evidence of a physical link.
    readonly property var sink: Server.defaultSink
    readonly property string sinkName: sink ? String(sink.name || "") : ""
    onSinkNameChanged: linkMonitor.refresh()
    readonly property var linkStatus: linkMonitor.status
    readonly property var connection: Output.connection(linkStatus)
    readonly property bool connected: connection.state === "connected"
    readonly property string statusText: Output.connectionText(connection, Qt.locale().name)
    readonly property var target: Output.headsetTarget(sink, linkStatus)
    readonly property string emblem: Output.emblem(connection, battery)
    // Inside the system tray, which draws the heading and the applet actions.
    readonly property bool inTray: (Plasmoid.containmentDisplayHints
        & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading) !== 0
    // The full view is on screen: the expanded popup, or the desktop, which
    // shows it inline.
    readonly property bool viewShown: root.expanded || Plasmoid.formFactor === PlasmaCore.Types.Planar
    // Headset settings are read once each time the view is shown with a
    // confirmed link, and again if the link returns while it is shown.
    readonly property bool settingsWanted: viewShown && connected
    onSettingsWantedChanged: {
        if (settingsWanted)
            readSettings();
    }
    property bool powerBusy: false
    property string powerError: ""
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    // KDE's reading first; the driver's published value covers a missing UPower entry.
    readonly property var battery: powerSource.battery || Output.driverBattery(linkStatus)
    readonly property bool batteryAvailable: battery !== null
    onBatteryAvailableChanged: {
        if (batteryAvailable) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onConnectedChanged: {
        if (connected) {
            pairingError = "";
            pairingResult = "";
        }
    }
    onViewShownChanged: {
        if (viewShown) {
            linkMonitor.refresh();
        }
        else {
            pairingError = "";
            pairingResult = "";
            powerError = "";
            askedCommand = "";
        }
    }
    function label(english, spanish) {
        return Output.text(english, spanish, Qt.locale().name)
    }
    function openSettings() {
        KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
    }
    // Pairing and power-off go through the USB dongle, one command at a time.
    // Only a confirmed missing dongle or a running command disables them.
    readonly property bool commandsEnabled: !pairingBusy && !powerBusy && !Output.adapterMissing(linkStatus)
    // Called only after the user confirmed in the popup.
    function openPairing() {
        if (!commandsEnabled)
            return;
        pairingError = "";
        pairingResult = "";
        pairingBusy = true;
        pairingLauncher.connectSource(Output.pairingCommand());
    }
    function turnOffHeadset() {
        if (!commandsEnabled)
            return;
        powerError = "";
        powerBusy = true;
        powerLauncher.connectSource(Output.powerOffCommand());
    }
    Plasma5Support.DataSource {
        id: powerLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.powerBusy = false;
            linkMonitor.refresh();
            // Success shows in the next status reading, not in a message; the
            // popup gets a plain sentence and the cause goes to the journal.
            const outcome = Output.powerOutcome(data, Qt.locale().name);
            if (!outcome.ok) {
                console.warn(outcome.details);
                root.powerError = outcome.text;
            }
        }
    }

    // Every headset setting the popup's tabs show, from one status read per
    // showing. The popup changes them only on an explicit switch, choice,
    // band edit or Connect; a transport change while it is shown reads them
    // again.
    HeadsetController {
        id: settingsController
        target: root.target
        activeView: root.settingsWanted
    }
    function readSettings() {
        if (connected && !settingsController.busy)
            settingsController.request({op: "status"});
    }
    // "dnd" and "gaming" take a boolean; "devices" takes a known address;
    // "preset", "standby" and "bands" take the values the Sound and Power tabs
    // offer.
    // The controls stay at the confirmed value; the reply's reading moves them.
    function setSetting(feature, value) {
        if (connected && !settingsController.busy && !pairingBusy && !powerBusy)
            settingsController.request({op: "set", feature: feature, value: value});
    }

    BatteryMonitor {
        id: powerSource
        preferBluetooth: root.target.transport === "bluetooth"
        // The driver registers its battery only on a confirmed link change.
        onPresenceChanged: linkMonitor.refresh()
    }

    LinkMonitor {
        id: linkMonitor
        Component.onCompleted: refresh()
    }

    // Read only while the status is on screen; the closed panel icon follows the
    // events above. There is no background monitor process.
    Timer {
        interval: root.expanded ? 5000 : 30000
        repeat: true
        running: root.viewShown
        onTriggered: linkMonitor.refresh()
    }

    Plasma5Support.DataSource {
        id: pairingLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.pairingBusy = false;
            linkMonitor.refresh();
            // The popup gets a plain sentence; the cause goes to the journal.
            const outcome = Output.pairingOutcome(data, Qt.locale().name);
            if (outcome.ok) {
                root.pairingResult = outcome.text;
            } else {
                console.warn(outcome.details);
                root.pairingError = outcome.text;
            }
        }
    }

    // The panel and tray draw the symbolic glyph in compactRepresentation; this
    // icon only names the widget.
    Plasmoid.icon: "audio-headset"
    // Always shown in the tray, so pairing stays reachable; a low battery asks
    // for attention.
    Plasmoid.status: Output.trayStatus(connection, battery) === "attention"
        ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    // The tray icon spins while a command runs on the headset.
    Plasmoid.busy: pairingBusy || powerBusy
        || (settingsController.busy && settingsController.requestFeature !== "")

    // A command from the heading, the tray or the right-click menu is
    // confirmed in the popup, so the popup opens first and the question
    // appears once its view exists.
    property string askedCommand: ""
    function askInPopup(command) {
        askedCommand = command;
        if (!root.viewShown)
            root.expanded = true;
        Qt.callLater(showAskedCommand);
    }
    function showAskedCommand() {
        const view = root.fullRepresentationItem;
        if (askedCommand === "" || !view || !root.viewShown)
            return;
        const command = askedCommand;
        askedCommand = "";
        if (command === "pair")
            view.confirmPairing();
        else
            view.confirmPowerOff();
    }
    onFullRepresentationItemChanged: Qt.callLater(showAskedCommand)

    // The popup's commands, one home each, placed by priority as every system
    // applet does. The tray draws the high-priority action as the '+' in its
    // heading and the normal-priority ones in its More actions menu; the
    // widget's own heading in a panel or on the desktop draws the same row
    // with the same rules, and Plasma copies every action into the
    // right-click menu.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            id: pairAction
            text: root.label("Pair Headset…", "Emparejar auricular…")
            icon.name: "list-add-symbolic"
            priority: PlasmaCore.Action.HighPriority
            // Kept visible and greyed without the dongle. The handler checks
            // again, so a menu drawn before the state changed starts nothing.
            enabled: root.commandsEnabled
            onTriggered: {
                if (root.commandsEnabled)
                    root.askInPopup("pair");
            }
        },
        PlasmaCore.Action {
            id: powerOffAction
            text: root.label("Turn Off Headset…", "Apagar auricular…")
            icon.name: "system-shutdown-symbolic"
            priority: PlasmaCore.Action.NormalPriority
            enabled: root.commandsEnabled
            onTriggered: {
                if (root.commandsEnabled)
                    root.askInPopup("power-off");
            }
        },
        PlasmaCore.Action {
            isSeparator: true
            priority: PlasmaCore.Action.NormalPriority
        },
        PlasmaCore.Action {
            id: audioDevicesAction
            // KDE's own name for this action in its volume applet.
            text: root.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")
            icon.name: "audio-card-symbolic"
            priority: PlasmaCore.Action.NormalPriority
            onTriggered: root.openSettings()
        }
    ]

    // The widget names itself as Plasma does: the tray heading and Plasma's
    // own menu entries use the same metadata name.
    toolTipMainText: Plasmoid.title
    toolTipSubText: Output.toolTip(connection, battery, Qt.locale().name)
    // Only the desktop forces the full view. Panels choose the compact icon by
    // size, and the system tray opens its popup only for applets without a
    // preferred representation.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : null
    compactRepresentation: PC3.ToolButton {
        // Panel and tray icons have no button frame on hover; retain the theme's keyboard focus.
        background.visible: visualFocus
        focusPolicy: Qt.TabFocus
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: Kirigami.Units.iconSizes.smallMedium
        // Keep the full click target while sizing artwork independently.
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : 0
        Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : 0
        Layout.preferredWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : implicitWidth
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : implicitHeight
        contentItem: Item {
            HeadsetArtwork {
                anchors.centerIn: parent
                // The tray sizes its icons; a loose panel icon stays at the
                // usual panel icon size.
                width: root.inTray ? Math.min(parent.width, parent.height)
                    : Math.min(parent.width, parent.height, Kirigami.Units.iconSizes.smallMedium)
                height: width
                iconSize: width
                symbolic: true
                // Dimmed without a confirmed link; the emblem marks an
                // unconfirmed or unreadable state and a low battery.
                dimmed: !root.connected
                emblems: root.emblem ? [root.emblem] : []
                emblemSize: Math.min(Kirigami.Units.iconSizes.small, width / 2)
            }
        }
        Accessible.name: Plasmoid.title
        Accessible.description: root.statusText
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: HeadsetView {
        linkStatus: root.linkStatus
        activeView: root.viewShown
        inTray: root.inTray
        title: Plasmoid.title
        actions: Plasmoid.contextualActions
        pairingBusy: root.pairingBusy
        pairingError: root.pairingError
        pairingResult: root.pairingResult
        powerBusy: root.powerBusy
        powerError: root.powerError
        battery: root.battery
        settings: settingsController
        onPairingConfirmed: root.openPairing()
        onPowerOffConfirmed: root.turnOffHeadset()
        onSettingChangeRequested: (feature, value) => root.setSetting(feature, value)
        onSettingsRefreshRequested: root.readSettings()
    }
}
