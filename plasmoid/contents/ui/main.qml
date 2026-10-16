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
    readonly property bool slashed: Output.slashed(connection)
    readonly property string emblem: Output.emblem(connection, battery)
    // Inside the system tray, which draws the heading and the actions menu.
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
    property string powerResult: ""
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
            powerResult = "";
        }
    }
    function label(english, spanish) {
        return Output.text(english, spanish, Qt.locale().name)
    }
    function openSettings() {
        KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio")
    }
    function openHeadsetSettings() {
        Plasmoid.internalAction("configure").trigger();
    }
    function openPairing() {
        if (pairingBusy || powerBusy || Output.adapterMissing(linkStatus))
            return;
        pairingError = "";
        pairingResult = "";
        pairingBusy = true;
        pairingLauncher.connectSource(Output.pairingCommand(Qt.locale().name));
    }

    function turnOffHeadset() {
        if (pairingBusy || powerBusy || Output.adapterMissing(linkStatus))
            return;
        powerError = "";
        powerResult = "";
        powerBusy = true;
        powerLauncher.connectSource(Output.powerOffCommand(Qt.locale().name));
    }
    Plasma5Support.DataSource {
        id: powerLauncher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.powerBusy = false;
            linkMonitor.refresh();
            const outcome = Output.powerOutcome(data, Qt.locale().name);
            if (outcome.ok)
                root.powerResult = outcome.text;
            else
                root.powerError = outcome.text;
        }
    }

    // Do Not Disturb, Bluetooth gaming mode and the Quick Connect devices,
    // from one status read per showing. The popup changes them only on an
    // explicit switch or Switch button; a transport change while it is shown
    // reads them again.
    HeadsetController {
        id: settingsController
        target: root.target
        activeView: root.settingsWanted
    }
    function readSettings() {
        if (connected && !settingsController.busy)
            settingsController.request({op: "status"});
    }
    // "dnd" and "gaming" take a boolean; "devices" takes a known address.
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
            const outcome = Output.pairingOutcome(data, Qt.locale().name);
            if (outcome.ok)
                root.pairingResult = outcome.text;
            else
                root.pairingError = outcome.text;
        }
    }

    // The panel and tray draw the symbolic glyph in compactRepresentation; this
    // icon only names the widget. Plasma gives the configuration window its own
    // generic icon regardless of this value.
    Plasmoid.icon: "audio-headset"
    Plasmoid.status: ({
        active: PlasmaCore.Types.ActiveStatus,
        passive: PlasmaCore.Types.PassiveStatus,
        attention: PlasmaCore.Types.NeedsAttentionStatus
    })[Output.trayStatus(connection, battery)]
    // The widget's only action leads out to KDE's own audio settings. The
    // system tray draws it in its More actions menu, the widget's own heading
    // builds the same menu from this list, and Plasma copies it into the
    // right-click menu. Every headset command lives in the popup.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            id: audioDevicesAction
            // KDE's own name for this action in its volume applet.
            text: root.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")
            icon.name: "audio-card-symbolic"
            priority: PlasmaCore.Action.NormalPriority
            onTriggered: root.openSettings()
            // A single action is drawn as a bare button unless it asks to stay a
            // menu. The property is new in Plasma 6.8; older versions skip it.
            Component.onCompleted: {
                if ("alwaysShowAsMenu" in audioDevicesAction)
                    audioDevicesAction.alwaysShowAsMenu = true;
            }
        }
    ]
    // The More actions entries, as the system tray selects them.
    readonly property var menuActions: Plasmoid.contextualActions.filter(action => action.visible
        && !action.isSeparator && action.priority === PlasmaCore.Action.NormalPriority
        && action !== Plasmoid.internalAction("configure"))

    // The widget names itself as Plasma does: the tray heading, the configure
    // action and the configuration window use the same metadata name.
    toolTipMainText: Plasmoid.title
    toolTipSubText: statusText
        + (battery ? "\n" + label("Battery: ", "Batería: ")
            + Output.batteryText(battery, Qt.locale().name) : "")
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
                symbolic: true
                connected: root.connected
                slashed: root.slashed
                emblem: root.emblem
                emblemSize: Math.min(Kirigami.Units.iconSizes.small, width / 2)
            }
        }
        Accessible.name: Plasmoid.title
        Accessible.description: root.statusText
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: HeadsetPanel {
        status: root.linkStatus
        activeView: root.viewShown
        // The system tray draws the same heading itself.
        showHeader: !root.inTray
        title: Plasmoid.title
        configureText: Plasmoid.internalAction("configure") ? Plasmoid.internalAction("configure").text : ""
        menuActions: root.menuActions
        pairingBusy: root.pairingBusy
        pairingError: root.pairingError
        pairingResult: root.pairingResult
        powerBusy: root.powerBusy
        powerError: root.powerError
        powerResult: root.powerResult
        battery: root.battery
        settings: settingsController
        onHeadsetSettingsRequested: root.openHeadsetSettings()
        onPairingRequested: root.openPairing()
        onPowerOffRequested: root.turnOffHeadset()
        onSettingChangeRequested: (feature, enabled) => root.setSetting(feature, enabled)
        onSettingsRefreshRequested: root.readSettings()
    }
}
