import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import QtTest
import "../plasmoid/contents/ui"

Item {
    id: host
    width: 400
    height: 650
    // The applet's actions as main.qml declares them; triggering one only
    // counts here.
    property list<QtObject> fakeActions: [
        PlasmaCore.Action {
            id: audioAction
            text: "&Configure Audio Devices…"
            icon.name: "audio-card-symbolic"
        }
    ]
    // An unknown engine name loads nothing. An empty one would keep the
    // engine that the component itself sets, and run it.
    BatteryMonitor {
        id: monitor
        // Inject engine events without using the system's power service.
        engine: "barracuda-test-none"
    }
    LinkMonitor {
        id: link
        // Inject command output without running the helper.
        engine: "barracuda-test-none"
    }
    // Stands in for HeadsetController; nothing is sent to a headset.
    QtObject {
        id: fakeSettings
        property bool busy: false
        property var response: null
        property string error: ""
        property string message: ""
        property string requestFeature: ""
        function errorLabel(code) { return "label:" + code }
    }
    ConnectionSummary {
        id: summary
        anchors.fill: parent
        localeName: "en_US"
        settings: fakeSettings
    }
    HeadsetPanel {
        id: panel
        width: 400
        height: 540
        visible: false
        menuActions: host.fakeActions
    }
    PlasmaCore.Dialog {
        id: sizeDialog
        visible: false
        mainItem: HeadsetPanel {
            id: sizedPanel
        }
    }
    SignalSpy {
        id: headsetSettingsSpy
        target: panel
        signalName: "headsetSettingsRequested"
    }
    SignalSpy {
        id: powerSpy
        target: summary
        signalName: "powerOffRequested"
    }
    SignalSpy {
        id: pairingSpy
        target: summary
        signalName: "pairingRequested"
    }
    SignalSpy {
        id: settingSpy
        target: summary
        signalName: "settingChangeRequested"
    }
    SignalSpy {
        id: refreshSpy
        target: summary
        signalName: "settingsRefreshRequested"
    }
    SignalSpy {
        id: switchSpy
        target: summary
        signalName: "sourceSwitchRequested"
    }
    SignalSpy {
        id: panelSpy
        target: panel
    }
    SignalSpy {
        id: actionSpy
        target: audioAction
        signalName: "triggered"
    }
    TestCase {
        name: "ConnectionSummary"
        when: windowShown
        function test_heading_title_menu_and_gear() {
            summary.visible = false
            panel.visible = true
            panel.activeView = true
            const title = findChild(panel, "popupTitle")
            const more = findChild(panel, "moreActionsButton")
            const gear = findChild(panel, "configureButton")
            // Outside Plasma the heading uses the metadata name.
            panel.title = ""
            for (const locale of ["en_US", "es_CL"]) {
                panel.localeName = locale
                const english = locale === "en_US"
                compare(title.text, english ? "Barracuda Headset" : "Auricular Barracuda")
                compare(more.text, english ? "More actions" : "Más acciones")
                compare(gear.text, english ? "Configure Barracuda Headset…" : "Configurar Auricular Barracuda…")
            }
            panel.localeName = "en_US"
            panel.title = "Auricular Barracuda"
            compare(title.text, "Auricular Barracuda")
            // Plasma's own configure text names the gear, without its
            // keyboard accelerator marker.
            panel.configureText = "&Configure Barracuda Headset…"
            compare(gear.text, "Configure Barracuda Headset…")
            compare(gear.Accessible.name, "Configure Barracuda Headset…")
            compare(gear.display, PC3.AbstractButton.IconOnly)
            compare(gear.icon.name, "configure")
            headsetSettingsSpy.clear()
            mouseClick(gear)
            compare(headsetSettingsSpy.count, 1)
            // Title, then More actions, then the gear at the top right.
            verify(more.x > title.x)
            verify(gear.x > more.x)
            // More actions is a menu button built from the applet's actions.
            verify(more.visible)
            verify(more.checkable)
            compare(more.display, PC3.AbstractButton.IconOnly)
            compare(more.Accessible.role, Accessible.ButtonMenu)
            const menu = findChild(panel, "moreActionsMenu")
            compare(menu.count, 1)
            compare(menu.itemAt(0).text, "Configure Audio Devices…")
            compare(menu.itemAt(0).icon.name, "audio-card-symbolic")
            actionSpy.clear()
            mouseClick(more)
            tryCompare(menu, "opened", true)
            verify(more.checked)
            mouseClick(menu.itemAt(0))
            tryCompare(menu, "visible", false)
            compare(actionSpy.count, 1)
            verify(!more.checked)
            // A second press on the button closes the menu.
            mouseClick(more)
            tryCompare(menu, "opened", true)
            mouseClick(more)
            tryCompare(menu, "visible", false)
            verify(!more.checked)
            compare(actionSpy.count, 1)
            // Closing the popup closes the menu.
            mouseClick(more)
            tryCompare(menu, "opened", true)
            panel.activeView = false
            tryCompare(menu, "visible", false)
            panel.activeView = true
            // Without actions there is no More actions button.
            panel.menuActions = []
            verify(!more.visible)
            compare(menu.count, 0)
            panel.menuActions = host.fakeActions
            compare(menu.count, 1)
            // Headset settings and help are not pages of the popup, and the
            // commands have no second copy in a menu or footer.
            for (const name of ["headsetSettings", "headsetHelp", "backToOverview", "overviewActions",
                                "soundSettingsButton", "headsetSettingsButton", "pairingSection",
                                "pairNowButton", "pairingButton", "dndMenuItem", "gamingMenuItem"])
                compare(findChild(panel, name), null)
            panel.configureText = ""
            panel.title = ""
            panel.visible = false
            summary.visible = true
        }
        function test_contextual_help_translation() {
            summary.status = {ok: true, usb: {adapter: "present", driver: true, link: "connected", battery: null},
                              bluetooth: null}
            summary.battery = {percent: 65, state: "Discharging"}
            // One help button in the popup, for the connection and battery.
            const buttons = findChildren(summary, "connectionHelp")
            compare(buttons.length, 1)
            compare(findChild(summary, "batteryHelp"), null)
            for (const locale of ["en_US", "es_CL"]) {
                summary.localeName = locale
                const help = buttons[0].toolTipText
                compare(help, locale === "en_US"
                        ? "Shows how the headset is connected and its last battery reading. “Link not confirmed” means the connection is not known yet, not that the headset is off."
                        : "Muestra cómo está conectado el auricular y su última lectura de batería. «Conexión no confirmada» significa que aún no se sabe si está conectado, no que esté apagado.")
            }
            summary.localeName = "en_US"
            summary.status = null
            summary.battery = null
        }
        function test_tray_heading() {
            summary.visible = false
            panel.visible = true
            panel.activeView = true
            const heading = findChild(panel, "summaryHeader")
            const overview = findChild(panel, "connectionOverview")
            verify(heading.visible)
            // The heading stays outside the scrolling body and counts in the
            // popup's size, even while the popup is hidden.
            verify(heading.mapToItem(panel, 0, 0).y < overview.mapToItem(panel, 0, 0).y)
            const withHeading = panel.Layout.preferredHeight
            panel.visible = false
            compare(panel.Layout.preferredHeight, withHeading)
            panel.visible = true
            // The system tray draws its own heading.
            panel.showHeader = false
            verify(!heading.visible)
            verify(panel.Layout.preferredHeight < withHeading)
            panel.showHeader = true
            panel.visible = false
            summary.visible = true
        }
        function test_hidden_settings_page_sends_nothing() {
            // Plasma may create the page without showing it; no command runs.
            for (const file of ["ConfigEqualizer.qml", "ConfigPowerSaving.qml"]) {
                const component = Qt.createComponent("../plasmoid/contents/ui/" + file)
                compare(component.status, Component.Ready, component.errorString())
                const page = component.createObject(null)
                verify(page !== null)
                verify(!page.shown)
                // Plasma's Apply calls saveConfig(); with nothing unsaved it sends nothing.
                verify(!page.unsavedChanges)
                page.saveConfig()
                wait(20)
                const controller = findChild(page, "headsetController")
                verify(!controller.busy)
                compare(controller.connectedSources.length, 0)
                verify(findChild(page, "audioController") === null)
                page.destroy()
            }
        }
        function test_settings_categories_and_icons() {
            const model = Qt.createComponent("../plasmoid/contents/config/config.qml").createObject(null)
            verify(model !== null)
            // How the headset sounds and when it turns itself off; Quick
            // Connect is in the popup.
            compare(model.count, 2)
            compare(model.get(0).source, "ConfigEqualizer.qml")
            compare(model.get(0).icon, "view-media-equalizer")
            compare(model.get(1).source, "ConfigPowerSaving.qml")
            compare(model.get(1).icon, "preferences-system-power-management")
            const english = Qt.locale().name.startsWith("es") === false
            compare(model.get(0).name, english ? "Equalizer" : "Ecualizador")
            compare(model.get(1).name, english ? "Power Saving" : "Ahorro de energía")
            model.destroy()
            compare(Qt.createComponent("../plasmoid/contents/ui/ConfigQuickConnect.qml").status, Component.Error)
        }
        function test_config_pages_compile() {
            for (const page of ["../plasmoid/contents/ui/ConfigPowerSaving.qml",
                                "../plasmoid/contents/ui/ConfigEqualizer.qml",
                                "../plasmoid/contents/config/config.qml"]) {
                const component = Qt.createComponent(page)
                compare(component.status, Component.Ready, component.errorString())
            }
        }
        function test_quick_connect_in_the_popup() {
            summary.localeName = "en_US"
            const section = findChild(summary, "quickConnect")
            const description = findChild(summary, "quickConnectDescription")
            const unread = findChild(summary, "quickConnectUnread")
            const empty = findChild(summary, "quickConnectEmpty")
            const blocked = findChild(summary, "quickConnectBlocked")
            const list = findChild(summary, "quickConnectDevices")
            const rows = () => findChildren(list, "quickConnectDevice")
            const top = name => findChild(summary, name).mapToItem(summary, 0, 0).y
            // Always laid out; without a reading it says when devices appear.
            summary.status = linked("disconnected")
            verify(section.visible)
            compare(findChild(summary, "quickConnectHeading").text, "Quick Connect")
            compare(description.text, "Move the headset's Bluetooth connection to a device it already knows. "
                    + "Switching may interrupt audio.")
            verify(unread.visible)
            compare(unread.text, "Known devices appear once the headset is connected and read.")
            verify(!list.visible)
            verify(!empty.visible)
            verify(!blocked.visible)
            summary.status = linked("connected")
            fakeSettings.busy = true
            compare(unread.text, "Reading…")
            fakeSettings.busy = false
            // Below the connection modes, above the details.
            tryVerify(() => top("quickConnect") > top("connectionModes"))
            verify(top("quickConnect") < top("detailsToggle"))
            // Device rows come from the same status read.
            const phone = {address: "0a0b0c0d0e0f", name: "Phone", active: true}
            const laptop = {address: "010203040506", name: "", active: false}
            read({gaming: false, devices: [phone, laptop]})
            verify(list.visible)
            verify(!unread.visible)
            verify(!blocked.visible)
            tryCompare(rows(), "length", 2)
            const name = findChild(rows()[0], "quickConnectName")
            compare(name.text, "Phone")
            verify(name.font.bold)
            compare(findChild(rows()[0], "quickConnectDetail").text, "Active source")
            verify(findChild(rows()[0], "quickConnectActive").visible)
            verify(!findChild(rows()[0], "quickConnectButton").visible)
            // A nameless device shows its formatted address once.
            compare(findChild(rows()[1], "quickConnectName").text, "01:02:03:04:05:06")
            verify(!findChild(rows()[1], "quickConnectDetail").visible)
            verify(!findChild(rows()[1], "quickConnectActive").visible)
            const button = findChild(rows()[1], "quickConnectButton")
            verify(button.visible)
            verify(button.enabled)
            compare(button.text, "Switch")
            compare(button.Accessible.name, "Switch to 01:02:03:04:05:06")
            switchSpy.clear()
            mouseClick(button)
            compare(switchSpy.count, 1)
            compare(switchSpy.signalArguments[0][0], "010203040506")
            // The active marker moves only with a new reading.
            verify(findChild(rows()[0], "quickConnectActive").visible)
            verify(!findChild(rows()[1], "quickConnectActive").visible)
            // Disabled while any request or command runs.
            fakeSettings.busy = true
            verify(!button.enabled)
            fakeSettings.busy = false
            summary.powerBusy = true
            verify(!button.enabled)
            summary.powerBusy = false
            verify(button.enabled)
            // Gaming mode on or unknown blocks switching, with one line
            // pointing at its switch above.
            read({gaming: true, devices: [phone, laptop]})
            verify(blocked.visible)
            compare(blocked.text, "Turn off Bluetooth Gaming Mode above to switch devices.")
            verify(!findChild(rows()[1], "quickConnectButton").enabled)
            read({gaming: null, devices: [phone, laptop]})
            verify(blocked.visible)
            verify(!findChild(rows()[1], "quickConnectButton").enabled)
            read({gaming: false, devices: [{address: "a1b2c3d4e5f6", name: "Pixel", active: false}]})
            tryCompare(rows(), "length", 1)
            compare(findChild(rows()[0], "quickConnectDetail").text, "A1:B2:C3:D4:E5:F6")
            // An empty list explains itself.
            read({gaming: false, devices: []})
            verify(empty.visible)
            verify(!list.visible)
            verify(!blocked.visible)
            compare(empty.text, "No known Bluetooth devices. Pair the headset with a phone or computer first.")
            summary.localeName = "es_CL"
            compare(findChild(summary, "quickConnectHeading").text, "Quick Connect")
            compare(description.text, "Mueve la conexión Bluetooth del auricular a un dispositivo que ya conoce. "
                    + "El cambio puede interrumpir el audio.")
            compare(empty.text, "No hay dispositivos Bluetooth conocidos. Primero empareja el auricular con un "
                    + "teléfono o computador.")
            read({gaming: true, devices: [phone, laptop]})
            compare(blocked.text, "Desactiva el modo gaming Bluetooth (arriba) para cambiar de dispositivo.")
            tryCompare(rows(), "length", 2)
            compare(findChild(rows()[0], "quickConnectDetail").text, "Fuente activa")
            compare(findChild(rows()[1], "quickConnectButton").text, "Cambiar")
            compare(findChild(rows()[1], "quickConnectButton").Accessible.name, "Cambiar a 01:02:03:04:05:06")
            fakeSettings.response = null
            compare(unread.text, "Los dispositivos conocidos aparecen cuando el auricular está conectado y se ha leído.")
            fakeSettings.busy = true
            compare(unread.text, "Leyendo…")
            fakeSettings.busy = false
            summary.localeName = "en_US"
            // Without a confirmed link an earlier list is not shown.
            read({gaming: false, devices: [phone]})
            verify(list.visible)
            summary.status = linked("unknown")
            verify(!list.visible)
            verify(unread.visible)
            fakeSettings.response = null
            summary.status = null
        }
        function test_quick_connect_feedback() {
            summary.localeName = "en_US"
            summary.status = linked("connected")
            const message = findChild(summary, "quickConnectMessage")
            const error = findChild(summary, "quickConnectError")
            const modesError = findChild(summary, "connectionModesError")
            const top = name => findChild(summary, name).mapToItem(summary, 0, 0).y
            verify(!message.visible)
            verify(!error.visible)
            // A switch request is not a confirmed switch: its notice under
            // Quick Connect offers Refresh.
            fakeSettings.requestFeature = "devices"
            fakeSettings.response = {ok: true, sent: "devices", transport: "usb", errors: {},
                                     state: {gaming: false, devices: [{address: "010203040506", name: "Phone", active: false}]}}
            fakeSettings.message = "Connection switch requested. Refresh to check the active device."
            verify(message.visible)
            compare(message.type, Kirigami.MessageType.Information)
            compare(message.text, "Connection switch requested. Refresh to check the active device.")
            compare(message.actions.length, 1)
            compare(message.actions[0].objectName, "refreshSettings")
            tryVerify(() => top("quickConnectMessage") > top("quickConnect"))
            verify(top("quickConnectMessage") < top("detailsToggle"))
            refreshSpy.clear()
            message.actions[0].trigger()
            compare(refreshSpy.count, 1)
            verify(!modesError.visible)
            // A failed switch: a warning with Refresh under Quick Connect.
            fakeSettings.response = null
            fakeSettings.message = ""
            fakeSettings.error = "Turn off Bluetooth Gaming Mode before switching Bluetooth devices."
            verify(!message.visible)
            verify(error.visible)
            compare(error.type, Kirigami.MessageType.Warning)
            compare(error.text, "Turn off Bluetooth Gaming Mode before switching Bluetooth devices.")
            compare(error.actions.length, 1)
            compare(error.actions[0].objectName, "refreshSettings")
            verify(!modesError.visible)
            // A failed read is reported once, under the modes.
            fakeSettings.requestFeature = ""
            verify(!error.visible)
            verify(modesError.visible)
            fakeSettings.error = ""
            // A read error of only the device list shows here.
            fakeSettings.response = {ok: true, transport: "usb", state: {dnd: true, gaming: false, devices: null},
                                     errors: {devices: "timeout"}}
            verify(error.visible)
            compare(error.text, "label:timeout")
            verify(!modesError.visible)
            // The same error for every feature appears once, under the modes.
            fakeSettings.response = {ok: true, transport: "usb", state: {dnd: null, gaming: null, devices: null},
                                     errors: {dnd: "unknown-link", gaming: "unknown-link", devices: "unknown-link"}}
            verify(modesError.visible)
            verify(!error.visible)
            fakeSettings.response = null
            summary.status = null
        }
        function test_panel_relays_requests() {
            const overview = findChild(panel, "connectionOverview")
            for (const [name, args] of [["pairingRequested", []], ["powerOffRequested", []],
                                        ["settingChangeRequested", ["dnd", true]],
                                        ["sourceSwitchRequested", ["010203040506"]],
                                        ["settingsRefreshRequested", []]]) {
                panelSpy.signalName = name
                panelSpy.clear()
                overview[name](...args)
                compare(panelSpy.count, 1)
                compare(Array.from(panelSpy.signalArguments[0]), args)
            }
            // The panel hands its settings controller to the summary.
            panel.settings = fakeSettings
            compare(overview.settings, fakeSettings)
            panel.settings = null
        }
        function test_transport_icon_beside_state() {
            const icon = findChild(summary, "transportIcon")
            summary.status = linked("connected")
            verify(icon.visible)
            compare(icon.source, "drive-removable-media-usb-pendrive-symbolic")
            summary.status = linked("connected", {state: "connected", address: "01:02:03:04:05:06"})
            compare(icon.source, "drive-removable-media-usb-pendrive-symbolic")
            summary.status = {ok: true, usb: {adapter: "missing"},
                              bluetooth: {state: "connected", address: "01:02:03:04:05:06"}}
            compare(icon.source, "network-bluetooth-symbolic")
            summary.status = linked("disconnected")
            verify(!icon.visible)
            summary.status = null
        }
        function test_fixed_height_leaves_free_space_below() {
            // The system tray gives every applet the same popup size.
            panel.visible = true
            summary.visible = false
            const overview = findChild(panel, "connectionOverview")
            panel.height = panel.Layout.preferredHeight + 200
            wait(50)
            verify(overview.height >= overview.implicitHeight + 150)
            // The content stays at the top; the free space is at the bottom.
            const spacer = findChild(panel, "footerSpacer")
            verify(spacer.height >= 150)
            const commands = findChild(panel, "deviceCommands")
            verify(commands.mapToItem(overview, 0, commands.height).y < spacer.mapToItem(overview, 0, 0).y + 1)
            panel.height = 540
            panel.visible = false
            summary.visible = true
        }
        function test_details_are_folded() {
            summary.status = linked("connected", null, {percent: 65, status: "Discharging", cable: false, voltage_mv: 3950})
            const toggle = findChild(summary, "detailsToggle")
            const details = findChild(summary, "connectionDetails")
            verify(toggle.visible)
            verify(!details.visible)
            mouseClick(toggle)
            verify(details.visible)
            mouseClick(toggle)
            verify(!details.visible)
            mouseClick(toggle)
            // Closing the popup folds them again.
            summary.activeView = false
            verify(!summary.showDetails)
            summary.activeView = true
            summary.status = null
        }
        function test_popup_height_tracks_battery_visibility() {
            sizedPanel.activeView = true
            sizedPanel.status = null
            sizedPanel.battery = null
            sizeDialog.visible = true
            wait(50)
            const overview = findChild(sizedPanel, "connectionOverview")
            const compactHeight = sizeDialog.height
            const compactContent = overview.implicitHeight
            verify(!overview.showBattery)
            sizedPanel.battery = {percent: 65, state: "Discharging"}
            // The battery sits beside the artwork; the popup still fits it.
            verify(findChild(sizedPanel, "headsetBatteryRow").visible)
            tryVerify(() => sizeDialog.height >= compactHeight)
            tryVerify(() => overview.height >= overview.implicitHeight - 1)
            sizedPanel.battery = null
            tryCompare(sizeDialog, "height", compactHeight)
            tryCompare(overview, "implicitHeight", compactContent)
            verify(overview.height >= overview.implicitHeight - 1)
            sizeDialog.visible = false
        }
        function test_popup_fits_pairing_and_power_messages() {
            sizedPanel.activeView = true
            sizeDialog.visible = true
            wait(50)
            const compactHeight = sizeDialog.height
            const overview = findChild(sizedPanel, "connectionOverview")
            for (const action of ["pairButton", "powerOffButton"]) {
                findChild(sizedPanel, action).clicked()
                tryVerify(() => sizeDialog.height > compactHeight)
                tryVerify(() => overview.height >= overview.implicitHeight - 1)
                const cancel = action === "pairButton" ? "cancelPairingButton" : "cancelPowerOffButton"
                mouseClick(findChild(sizedPanel, cancel))
                tryCompare(sizeDialog, "height", compactHeight)
            }
            for (const field of ["pairingBusy", "powerBusy"]) {
                sizedPanel[field] = true
                tryVerify(() => sizeDialog.height > compactHeight)
                tryVerify(() => overview.height >= overview.implicitHeight - 1)
                sizedPanel[field] = false
                tryCompare(sizeDialog, "height", compactHeight)
            }
            for (const field of ["pairingError", "powerError", "pairingResult", "powerResult"]) {
                sizedPanel[field] = "Headset action message. ".repeat(12)
                tryVerify(() => sizeDialog.height > compactHeight)
                tryVerify(() => overview.height >= overview.implicitHeight - 1)
                sizedPanel[field] = ""
                tryCompare(sizeDialog, "height", compactHeight)
            }
            sizeDialog.visible = false
        }
        function test_dnd_switch_row() {
            summary.localeName = "en_US"
            const row = findChild(summary, "dnd")
            const toggle = findChild(summary, "dndSwitch")
            const value = findChild(summary, "dndValue")
            const description = findChild(summary, "dndDescription")
            const icon = findChild(summary, "dndIcon")
            // Always laid out; without a confirmed link the value is unknown,
            // never an Off switch, even with an earlier reading.
            read({dnd: true})
            for (const state of [null, linked("disconnected"), linked("unknown"), {ok: false},
                                 {ok: true, usb: {adapter: "missing"}, bluetooth: null}]) {
                summary.status = state
                verify(row.visible)
                verify(!toggle.visible)
                verify(value.visible)
                compare(value.text, "Unknown")
            }
            fakeSettings.response = null
            summary.status = linked("connected")
            fakeSettings.busy = true
            compare(value.text, "Reading…")
            fakeSettings.busy = false
            compare(value.text, "Unknown")
            compare(icon.source, "notifications-disabled-symbolic")
            compare(icon.opacity, 0.5)
            compare(icon.width, findChild(summary, "headsetBatteryIcon").width)
            read({dnd: true})
            verify(toggle.visible)
            verify(!value.visible)
            verify(toggle.checked)
            verify(toggle.enabled)
            compare(icon.opacity, 1)
            compare(findChild(summary, "dndLabel").text, "Do Not Disturb")
            compare(toggle.Accessible.name, "Do Not Disturb")
            compare(description.text, "Calls from a phone connected by Bluetooth do not interrupt the dongle audio. "
                    + "Desktop notifications are not affected.")
            // A click asks for the new value; the switch keeps showing the
            // reported one until a reading confirms it.
            settingSpy.clear()
            mouseClick(toggle)
            compare(settingSpy.count, 1)
            compare(settingSpy.signalArguments[0][0], "dnd")
            compare(settingSpy.signalArguments[0][1], false)
            verify(toggle.checked)
            read({dnd: false})
            verify(!toggle.checked)
            // Disabled while any request or command runs; the value stays.
            fakeSettings.busy = true
            verify(toggle.visible)
            verify(!toggle.enabled)
            fakeSettings.busy = false
            summary.pairingBusy = true
            verify(!toggle.enabled)
            summary.pairingBusy = false
            summary.powerBusy = true
            verify(!toggle.enabled)
            summary.powerBusy = false
            verify(toggle.enabled)
            settingSpy.clear()
            summary.localeName = "es_CL"
            compare(findChild(summary, "dndLabel").text, "No molestar")
            compare(description.text, "Las llamadas de un teléfono conectado por Bluetooth no interrumpen el audio "
                    + "del dongle. No afecta a las notificaciones del escritorio.")
            read({dnd: null})
            compare(value.text, "Desconocido")
            fakeSettings.busy = true
            compare(value.text, "Leyendo…")
            fakeSettings.busy = false
            summary.localeName = "en_US"
            fakeSettings.response = null
            summary.status = null
        }
        function test_gaming_switch_row() {
            summary.localeName = "en_US"
            summary.status = linked("connected")
            const toggle = findChild(summary, "gamingSwitch")
            const value = findChild(summary, "gamingValue")
            const description = findChild(summary, "gamingDescription")
            compare(findChild(summary, "gamingIcon").source, "input-gamepad-symbolic")
            compare(findChild(summary, "gamingLabel").text, "Bluetooth Gaming Mode")
            compare(value.text, "Unknown")
            verify(!toggle.visible)
            compare(description.text, "Lowers Bluetooth audio delay. Not the Game sound profile.")
            // Read through the USB dongle: shown but not settable, and the
            // line under it says why.
            read({gaming: false})
            verify(toggle.visible)
            verify(!toggle.checked)
            verify(!toggle.enabled)
            compare(description.text, "Can be changed only over Bluetooth; settings are being read through the USB dongle.")
            // Also while Bluetooth is connected but the settings follow the dongle.
            summary.status = linked("connected", {state: "connected", address: "01:02:03:04:05:06"})
            verify(!toggle.enabled)
            compare(description.text, "Can be changed only over Bluetooth; settings are being read through the USB dongle.")
            // Over Bluetooth the switch sets the new value.
            read({gaming: false}, "bluetooth")
            verify(toggle.enabled)
            compare(description.text, "Lowers Bluetooth audio delay. Not the Game sound profile.")
            settingSpy.clear()
            mouseClick(toggle)
            compare(settingSpy.count, 1)
            compare(settingSpy.signalArguments[0][0], "gaming")
            compare(settingSpy.signalArguments[0][1], true)
            verify(!toggle.checked)
            summary.localeName = "es_CL"
            compare(findChild(summary, "gamingLabel").text, "Modo gaming Bluetooth")
            compare(description.text, "Reduce el retraso del audio Bluetooth. No es el perfil de sonido Juegos.")
            read({gaming: true})
            verify(toggle.checked)
            compare(description.text, "Solo se puede cambiar por Bluetooth; los ajustes se están leyendo mediante el dongle USB.")
            summary.localeName = "en_US"
            fakeSettings.response = null
            summary.status = null
        }
        function test_connection_modes_layout_and_feedback() {
            summary.localeName = "en_US"
            summary.status = linked("connected")
            const modes = findChild(summary, "connectionModes")
            const notice = findChild(summary, "connectionModesError")
            const top = name => findChild(summary, name).mapToItem(summary, 0, 0).y
            // How it is, what to do now, how it connects, then the details.
            tryVerify(() => top("connectionModes") < top("detailsToggle"))
            verify(top("connectionState") < top("deviceCommands"))
            verify(top("deviceCommands") < top("connectionModes"))
            verify(top("dnd") < top("gaming"))
            verify(!notice.visible)
            // A failed request for a mode or a failed read: a warning with
            // Refresh, right under the modes.
            fakeSettings.requestFeature = "dnd"
            fakeSettings.error = "The headset did not answer."
            verify(notice.visible)
            compare(notice.type, Kirigami.MessageType.Warning)
            compare(notice.text, "The headset did not answer.")
            tryVerify(() => top("connectionModesError") >= top("connectionModes") + modes.height)
            verify(top("connectionModesError") < top("detailsToggle"))
            compare(notice.actions.length, 1)
            const refresh = notice.actions[0]
            compare(refresh.objectName, "refreshSettings")
            compare(refresh.text, "Refresh")
            compare(refresh.icon.name, "view-refresh")
            refreshSpy.clear()
            refresh.trigger()
            compare(refreshSpy.count, 1)
            fakeSettings.busy = true
            verify(!refresh.enabled)
            fakeSettings.busy = false
            fakeSettings.requestFeature = ""
            verify(notice.visible)
            // A Quick Connect request reports under Quick Connect instead.
            fakeSettings.requestFeature = "devices"
            verify(!notice.visible)
            fakeSettings.error = ""
            fakeSettings.requestFeature = ""
            // The modes' read errors share one notice; each is named when they differ.
            fakeSettings.response = {ok: true, transport: "usb", state: {dnd: null, gaming: null},
                                     errors: {dnd: "timeout", gaming: "timeout"}}
            compare(notice.text, "label:timeout")
            fakeSettings.response = {ok: true, transport: "usb", state: {dnd: null, gaming: null},
                                     errors: {dnd: "timeout", gaming: "rejected"}}
            compare(notice.text, "Do Not Disturb: label:timeout Bluetooth Gaming Mode: label:rejected")
            summary.localeName = "es_CL"
            compare(notice.text, "No molestar: label:timeout Modo gaming Bluetooth: label:rejected")
            compare(refresh.text, "Actualizar")
            summary.localeName = "en_US"
            fakeSettings.response = {ok: true, transport: "usb", state: {dnd: true, gaming: false, devices: null},
                                     errors: {devices: "timeout"}}
            verify(!notice.visible)
            // No success notice: the switch shows the confirmed value.
            fakeSettings.response = {ok: true, sent: "dnd", transport: "usb", state: {dnd: true}, errors: {}}
            fakeSettings.message = "Change confirmed by the headset."
            verify(!notice.visible)
            fakeSettings.message = ""
            fakeSettings.response = null
            // Refresh needs a confirmed link.
            summary.status = linked("disconnected")
            verify(!refresh.enabled)
            summary.status = null
        }
        function test_poweroff_is_explicit_and_serialized_in_ui() {
            const action = findChild(summary, "powerOffButton")
            summary.localeName = "en_US"
            compare(action.text, "Turn Off Headset…")
            powerSpy.clear()
            mouseClick(action)
            verify(summary.confirmingPowerOff)
            compare(powerSpy.count, 0)
            wait(20)
            mouseClick(findChild(summary, "cancelPowerOffButton"))
            compare(powerSpy.count, 0)
            verify(!summary.confirmingPowerOff)
            mouseClick(action)
            // The confirming button is the primary one.
            tryVerify(() => findChild(summary, "confirmPowerOffButton").focus)
            wait(20)
            mouseClick(findChild(summary, "confirmPowerOffButton"))
            compare(powerSpy.count, 1)
            verify(!summary.confirmingPowerOff)
            summary.powerBusy = true
            verify(!action.enabled)
            verify(!findChild(summary, "pairButton").enabled)
            summary.powerBusy = false
            summary.pairingBusy = true
            verify(!action.enabled)
            summary.pairingBusy = false
            summary.localeName = "es_CL"
            compare(action.text, "Apagar auricular…")
            action.clicked()
            summary.activeView = false
            verify(!summary.confirmingPowerOff)
            summary.activeView = true
            summary.localeName = "en_US"
        }
        function test_settings_and_unknown_battery() {
            summary.localeName = "en_US"
            summary.battery = null
            summary.status = linked("connected")
            // Without a reading the battery line says so beside the artwork.
            const percent = findChild(summary, "batteryPercentage")
            verify(findChild(summary, "headsetBatteryRow").visible)
            compare(percent.text, "Battery unknown")
            summary.localeName = "es_CL"
            compare(percent.text, "Batería desconocida")
            summary.battery = {percent: 65, state: "Discharging"}
            compare(percent.text, "65%")
            summary.battery = null
            summary.localeName = "en_US"
            summary.status = null
            verify(!findChild(summary, "headsetBatteryRow").visible)
            // A missing reading is not shown as a battery for a disconnected headset.
            summary.status = linked("disconnected")
            verify(!findChild(summary, "headsetBatteryRow").visible)
            summary.battery = {percent: 65, state: "Discharging"}
            verify(findChild(summary, "headsetBatteryRow").visible)
            summary.battery = null
            summary.status = null
        }
        function test_native_battery_presentation() {
            const icon = findChild(summary, "headsetBatteryIcon")
            const percent = findChild(summary, "batteryPercentage")
            compare(findChild(summary, "batteryChargeBar"), null)
            const state = findChild(summary, "batteryStatus")
            summary.localeName = "en_US"
            for (const level of [0, 5, 65, 99, 100]) {
                summary.battery = {percent: level, state: "Discharging"}
                compare(icon.batteryType, "")
                compare(icon.percent, level)
                compare(percent.text, level + "%")
                verify(!icon.pluggedIn)
                verify(!state.visible)
            }
            summary.battery = {percent: 99, state: "Charging"}
            verify(icon.pluggedIn)
            compare(state.text, "Charging")
            verify(state.visible)
            compare(percent.text, "99%")
            summary.localeName = "es_CL"
            compare(state.text, "Cargando")
            summary.battery = {percent: 99, state: "Unknown"}
            verify(!icon.pluggedIn)
            compare(state.text, "Estado de carga desconocido")
            summary.battery = null
            verify(!icon.hasBattery)
            compare(percent.text, "Batería desconocida")
            summary.localeName = "en_US"
            compare(percent.text, "Battery unknown")
        }
        function test_bluetooth_presentation() {
            summary.status = {ok: true, usb: {adapter: "missing"},
                              bluetooth: {state: "connected", address: "01:02:03:04:05:06"}}
            summary.battery = {percent: 60, state: "NoCharge"}
            // The popup says whether; its transport icon says how.
            compare(summary.statusText, "Connected")
            compare(findChild(summary, "transportIcon").Accessible.name, "Bluetooth")
            compare(findChild(summary, "batteryPercentage").text, "60%")
            verify(!findChild(summary, "batteryStatus").visible)
            // Without the dongle, pairing and power-off wait for it.
            verify(!findChild(summary, "pairButton").enabled)
            verify(!findChild(summary, "powerOffButton").enabled)
            summary.status = null
            summary.battery = null
        }
        function test_battery_reconnect_and_late_data() {
            const frame = {Product: "Razer Barracuda X (2022)", Type: "Headset",
                           "Is Power Supply": false, "Plugged in": true,
                           Percent: 65, State: "Discharging"}
            monitor.newData("Battery1", frame)
            compare(monitor.battery.percent, 65)
            monitor.sourceRemoved("Battery1")
            compare(monitor.battery, null)
            monitor.sourceAdded("Battery1")
            monitor.newData("Battery1", {})
            compare(monitor.battery, null)
            monitor.newData("Battery1", Object.assign({}, frame, {Percent: 64}))
            compare(monitor.battery.percent, 64)
            monitor.sourceRemoved("Battery1")
            monitor.sourceAdded("Battery2")
            monitor.newData("Battery2", Object.assign({}, frame, {Percent: 63, State: "Charging"}))
            compare(monitor.battery.percent, 63)
            compare(monitor.battery.state, "Charging")
            monitor.newData("Battery2", Object.assign({}, frame, {Percent: 0, State: "Unknown"}))
            compare(monitor.battery, null)
            monitor.newData("Battery2", frame)
            compare(monitor.battery.percent, 65)
            monitor.sourceRemoved("Battery2")
            compare(monitor.battery, null)
        }
        function test_main_component_compiles() {
            const component = Qt.createComponent("../plasmoid/contents/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
        }
        function test_connection_presentation() {
            const state = findChild(summary, "connectionState")
            const hint = findChild(summary, "connectionHint")
            const details = findChild(summary, "connectionDetails")
            const emblem = findChild(summary, "connectionEmblem")
            const slash = findChild(summary, "disconnectedSlash")
            summary.localeName = "en_US"
            // The diagnostic rows are folded by default; open them to check.
            summary.showDetails = true
            summary.status = null
            compare(state.text, "Checking…")
            verify(!hint.visible)
            verify(!details.visible)
            verify(!emblem.visible)
            verify(!slash.visible)
            summary.status = {ok: false}
            compare(state.text, "Status unavailable")
            verify(hint.visible)
            verify(hint.text.includes("barracuda-headset"))
            summary.status = {ok: true, usb: {adapter: "missing"}, bluetooth: null}
            compare(state.text, "USB dongle not detected")
            verify(details.visible)
            verify(slash.visible)
            verify(!emblem.visible)
            summary.status = linked("unknown")
            compare(state.text, "Link not confirmed")
            verify(hint.text.includes("does not mean"))
            compare(emblem.source, "emblem-question")
            verify(!slash.visible)
            summary.status = linked("disconnected", {state: "disconnected", address: "01:02:03:04:05:06"})
            compare(state.text, "Disconnected")
            verify(slash.visible)
            verify(!emblem.visible)
            const values = () => findChildren(details, "detailValue").filter(item => item.visible).map(item => item.text)
            tryCompare(values(), "length", 3)
            compare(values(), ["Detected", "Disconnected", "Not connected"])
            summary.status = linked("connected", null,
                                    {percent: 65, status: "Charging", cable: true, voltage_mv: 4123})
            compare(state.text, "Connected")
            verify(!hint.visible)
            verify(!emblem.visible)
            verify(!slash.visible)
            tryVerify(() => values().length === 4)
            compare(values(), ["Detected", "Connected", "Connected", "4.12 V"])
            compare(findChildren(details, "detailIcon").filter(item => item.visible).map(item => item.source),
                    ["drive-removable-media-usb-pendrive-symbolic", "network-wireless-symbolic",
                     "battery-full-charging-symbolic", "battery-full-symbolic"])
            summary.localeName = "es_CL"
            compare(state.text, "Conectado")
            tryVerify(() => values()[3] === "4,12 V")
            summary.localeName = "en_US"
            summary.status = null
            summary.showDetails = false
        }
        function findChildren(item, name) {
            let found = item.objectName === name ? [item] : []
            for (const child of item.children)
                found = found.concat(findChildren(child, name))
            return found
        }
        function test_link_monitor_serializes_queries() {
            link.status = null
            link.refresh()
            verify(link.running)
            compare(link.connectedSources.length, 1)
            link.refresh()
            verify(link.pending)
            compare(link.connectedSources.length, 1)
            link.newData(link.connectedSources[0],
                         {stdout: '{"ok": true, "usb": {"adapter": "missing"}, "bluetooth": null}'})
            compare(link.status.usb.adapter, "missing")
            // The pending refresh starts once the previous query finished.
            verify(link.running)
            verify(!link.pending)
            link.newData(link.connectedSources[0], {stdout: ""})
            verify(!link.running)
            compare(link.status.ok, false)
            compare(link.connectedSources.length, 0)
            link.status = null
        }
        function test_pairing_is_explicit_and_independent_of_output() {
            pairingSpy.clear()
            // Re-pairing stays available with a confirmed link.
            summary.status = linked("connected")
            const button = findChild(summary, "pairButton")
            verify(button.visible)
            verify(button.enabled)
            mouseClick(button)
            compare(pairingSpy.count, 0)
            verify(summary.confirmingPairing)
            wait(20)
            mouseClick(findChild(summary, "cancelPairingButton"))
            verify(!summary.confirmingPairing)
            compare(pairingSpy.count, 0)
            mouseClick(button)
            // The confirming button is the primary one.
            tryVerify(() => findChild(summary, "confirmPairingButton").focus)
            wait(20)
            mouseClick(findChild(summary, "confirmPairingButton"))
            compare(pairingSpy.count, 1)
            verify(!summary.confirmingPairing)
            summary.pairingBusy = true
            verify(!button.enabled)
            verify(!findChild(summary, "powerOffButton").enabled)
            mouseClick(button)
            verify(!summary.confirmingPairing)
            compare(pairingSpy.count, 1)
            summary.pairingBusy = false
            summary.status = null
        }
        function test_device_commands_stay_visible() {
            summary.localeName = "en_US"
            const commands = findChild(summary, "deviceCommands")
            const pair = findChild(summary, "pairButton")
            const power = findChild(summary, "powerOffButton")
            // Visible and enabled in every state but a confirmed missing
            // dongle, including while the first read is pending.
            for (const state of [null, linked("connected"), linked("disconnected"), linked("unknown"), {ok: false},
                                 {ok: true, usb: {adapter: "multiple"}, bluetooth: null}]) {
                summary.status = state
                verify(commands.visible)
                verify(pair.visible)
                verify(power.visible)
                verify(pair.enabled)
                verify(power.enabled)
                compare(summary.commandsHint, "")
            }
            compare(pair.text, "Pair USB Dongle…")
            compare(power.text, "Turn Off Headset…")
            compare(pair.icon.name, "network-wireless")
            compare(power.icon.name, "system-shutdown")
            // Each confirmation sits right under the command row.
            pairingSpy.clear()
            summary.status = linked("disconnected")
            pair.clicked()
            verify(summary.confirmingPairing)
            compare(pairingSpy.count, 0)
            const below = item => {
                const top = item.mapToItem(summary, 0, 0).y
                return top >= commands.y + commands.height && top < findChild(summary, "detailsToggle").y
            }
            tryVerify(() => below(findChild(summary, "confirmPairingButton")))
            verify(below(findChild(summary, "pairingStatus")))
            findChild(summary, "cancelPairingButton").clicked()
            verify(!summary.confirmingPairing)
            power.clicked()
            verify(summary.confirmingPowerOff)
            tryVerify(() => below(findChild(summary, "confirmPowerOffButton")))
            verify(below(findChild(summary, "powerStatus")))
            // A confirmed missing dongle disables pairing and power-off,
            // never hides them, and drops a pending confirmation.
            summary.status = {ok: true, usb: {adapter: "missing"}, bluetooth: null}
            verify(pair.visible)
            verify(power.visible)
            verify(!pair.enabled)
            verify(!power.enabled)
            verify(!summary.confirmingPowerOff)
            compare(summary.commandsHint, "Connect the USB dongle first.")
            summary.confirm("pairing")
            verify(!summary.confirmingPairing)
            summary.confirm("power-off")
            verify(!summary.confirmingPowerOff)
            summary.localeName = "es_CL"
            compare(pair.text, "Emparejar dongle USB…")
            compare(power.text, "Apagar auricular…")
            compare(summary.commandsHint, "Conecta primero el dongle USB.")
            summary.localeName = "en_US"
            summary.status = null
        }
        function test_confirmation_progress_and_result_texts() {
            const pairing = findChild(summary, "pairingStatus")
            const power = findChild(summary, "powerStatus")
            const pairingError = findChild(summary, "pairingError")
            summary.status = linked("disconnected")
            for (const locale of ["en_US", "es_CL"]) {
                const english = locale === "en_US"
                summary.localeName = locale
                summary.confirm("pairing")
                compare(pairing.type, Kirigami.MessageType.Warning)
                compare(pairing.text, english
                        ? "Connect the USB dongle and put the headset in pairing mode. This replaces the dongle's current pairing."
                        : "Conecta el dongle USB y pon el auricular en modo de emparejamiento. Esto reemplaza el emparejamiento actual del dongle.")
                compare(findChild(summary, "confirmPairingButton").text, english ? "Pair" : "Emparejar")
                compare(findChild(summary, "cancelPairingButton").text, english ? "Cancel" : "Cancelar")
                // One confirmation at a time.
                summary.confirm("power-off")
                verify(!summary.confirmingPairing)
                verify(!pairing.visible)
                compare(power.type, Kirigami.MessageType.Warning)
                compare(power.text, english
                        ? "Turn off the headset through the USB dongle? Use its button to turn it on again."
                        : "¿Apagar el auricular mediante el dongle USB? Usa su botón para encenderlo de nuevo.")
                compare(findChild(summary, "confirmPowerOffButton").text, english ? "Turn Off" : "Apagar")
                compare(findChild(summary, "cancelPowerOffButton").text, english ? "Cancel" : "Cancelar")
                summary.confirmingPowerOff = false
                summary.pairingBusy = true
                compare(pairing.type, Kirigami.MessageType.Information)
                compare(pairing.text, english
                        ? "Pairing… Keep the headset in pairing mode. Searching can take up to a minute; the result will appear here."
                        : "Emparejando… Mantén el auricular en modo de emparejamiento. La búsqueda puede tardar un minuto; el resultado aparecerá aquí.")
                summary.pairingBusy = false
                summary.powerBusy = true
                compare(power.text, english ? "Sending power-off request…" : "Enviando solicitud de apagado…")
                summary.powerBusy = false
            }
            summary.localeName = "en_US"
            summary.pairingResult = "Paired."
            verify(pairing.visible)
            compare(pairing.text, "Paired.")
            summary.pairingResult = ""
            // A previous error gives way to a new confirmation.
            summary.pairingError = "Pairing failed."
            verify(pairingError.visible)
            summary.confirm("pairing")
            verify(!pairingError.visible)
            summary.confirmingPairing = false
            verify(pairingError.visible)
            summary.pairingError = ""
            summary.powerError = "Could not send the power-off request."
            compare(power.type, Kirigami.MessageType.Error)
            compare(power.text, "Could not send the power-off request.")
            summary.powerError = ""
            summary.powerResult = "Power-off request sent."
            compare(power.type, Kirigami.MessageType.Information)
            summary.powerResult = ""
            verify(!power.visible)
            summary.status = null
        }
        function test_closing_clears_pending_confirmation() {
            summary.confirmingPairing = true
            summary.activeView = false
            verify(!summary.confirmingPairing)
            summary.activeView = true
            verify(!summary.confirmingPairing)
        }
        // A status reply from the settings controller.
        function read(state, transport) {
            fakeSettings.response = {ok: true, transport: transport || "usb", state: state, errors: {}}
        }
        function linked(value, bluetooth, battery) {
            return {ok: true, usb: {adapter: "present", driver: true, link: value, battery: battery || null},
                    bluetooth: bluetooth === undefined ? null : bluetooth}
        }
        function test_reconnection_clears_pending_confirmation() {
            summary.status = linked("disconnected")
            summary.confirmingPairing = true
            summary.status = linked("connected")
            verify(!summary.confirmingPairing)
            summary.confirmingPairing = true
            summary.status = linked("connected")
            verify(summary.confirmingPairing)
            summary.confirmingPairing = false
            summary.status = null
            summary.battery = null
            summary.confirmingPairing = true
            summary.battery = {percent: 65, state: "Discharging"}
            verify(!summary.confirmingPairing)
            // Ordinary telemetry updates must not dismiss a new confirmation.
            summary.confirmingPairing = true
            summary.battery = {percent: 64, state: "Discharging"}
            verify(summary.confirmingPairing)
            summary.confirmingPairing = false
            summary.battery = null
        }
    }
}
