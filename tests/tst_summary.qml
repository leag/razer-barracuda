import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import QtTest
import "../plasmoid/contents/ui"

Item {
    width: 400
    height: 650
    BatteryMonitor {
        id: monitor
        // Inject engine events without using the system's power service.
        engine: ""
    }
    LinkMonitor {
        id: link
        // Inject command output without running the helper.
        engine: ""
    }
    ConnectionSummary {
        id: summary
        anchors.fill: parent
        localeName: "en_US"
    }
    HeadsetPanel {
        id: panel
        width: 400
        height: 540
        visible: false
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
        id: requestSpy
        target: panel
        signalName: "requestHandled"
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
        id: settingsSpy
        target: summary
        signalName: "settingsRequested"
    }
    TestCase {
        name: "ConnectionSummary"
        when: windowShown
        function test_headset_settings_and_help_leave_the_popup() {
            summary.visible = false
            panel.visible = true
            panel.activeView = true
            for (const locale of ["en_US", "es_CL"]) {
                panel.localeName = locale
                const button = findChild(panel, "headsetSettingsButton")
                compare(button.text, locale === "en_US" ? "Configure Barracuda Headset…" : "Configurar Auricular Barracuda…")
                headsetSettingsSpy.clear()
                wait(20)
                mouseClick(button)
                compare(headsetSettingsSpy.count, 1)
            }
            // Plasma's own configure action names the button inside Plasma,
            // without its keyboard accelerator marker.
            panel.configureText = "&Configure Barracuda Headset…"
            compare(findChild(panel, "headsetSettingsButton").text, "Configure Barracuda Headset…")
            panel.configureText = ""
            // Headset settings and help are not pages of the popup.
            compare(findChild(panel, "headsetSettings"), null)
            compare(findChild(panel, "headsetHelp"), null)
            compare(findChild(panel, "helpMenuItem"), null)
            compare(findChild(panel, "backToOverview"), null)
            const menu = findChild(panel, "moreActionsMenu")
            compare(menu.itemAt(menu.count - 2).objectName, "dndMenuItem")
            compare(menu.itemAt(menu.count - 1).objectName, "gamingMenuItem")
            panel.localeName = "en_US"
            panel.visible = false
            summary.visible = true
        }
        function test_contextual_help_translation() {
            summary.status = {ok: true, usb: {adapter: "present", driver: true, link: "connected", battery: null},
                              bluetooth: null}
            summary.battery = {percent: 65, state: "Discharging"}
            // One help button in the popup; it also covers the battery.
            const buttons = findChildren(summary, "connectionHelp")
            compare(buttons.length, 1)
            compare(findChild(summary, "batteryHelp"), null)
            for (const locale of ["en_US", "es_CL"]) {
                summary.localeName = locale
                const help = buttons[0].toolTipText
                verify(help.includes(locale === "en_US" ? "not that the headset is off" : "no que esté apagado"))
                verify(help.includes(locale === "en_US" ? "battery reading" : "lectura de batería"))
                verify(help.includes(locale === "en_US" ? "Do Not Disturb" : "No molestar"))
            }
            summary.localeName = "en_US"
            summary.status = null
            summary.battery = null
        }
        function test_tray_heading_and_action_requests() {
            summary.visible = false
            panel.visible = true
            panel.activeView = true
            const overview = findChild(panel, "connectionOverview")
            verify(findChild(panel, "summaryHeader").visible)
            panel.showHeader = false
            verify(!findChild(panel, "summaryHeader").visible)
            pairingSpy.clear()
            powerSpy.clear()
            for (const request of ["pairing", "power-off"]) {
                requestSpy.clear()
                panel.request = request
                tryCompare(requestSpy, "count", 1)
                compare(overview.confirmingPairing, request === "pairing")
                compare(overview.confirmingPowerOff, request === "power-off")
                // The request is consumed; nothing runs before confirmation.
                panel.request = ""
                compare(pairingSpy.count, 0)
                compare(powerSpy.count, 0)
            }
            // A running action ignores new confirmation requests.
            overview.confirmingPowerOff = false
            panel.pairingBusy = true
            panel.request = "power-off"
            verify(!overview.confirmingPowerOff)
            panel.request = ""
            panel.pairingBusy = false
            panel.showHeader = true
            panel.visible = false
            summary.visible = true
        }
        function test_hidden_settings_page_sends_nothing() {
            // Plasma may create the page without showing it; no command runs.
            for (const file of ["ConfigEqualizer.qml", "ConfigPowerSaving.qml", "ConfigQuickConnect.qml"]) {
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
            // The equalizer, power saving and Quick Connect are separate categories.
            compare(model.count, 3)
            compare(model.get(0).source, "ConfigEqualizer.qml")
            compare(model.get(0).icon, "view-media-equalizer")
            compare(model.get(1).source, "ConfigPowerSaving.qml")
            compare(model.get(1).name, "Power saving")
            compare(model.get(1).icon, "preferences-system-power-management")
            compare(model.get(2).source, "ConfigQuickConnect.qml")
            compare(model.get(2).icon, "preferences-system-bluetooth")
            model.destroy()
        }
        function test_config_pages_compile() {
            for (const page of ["../plasmoid/contents/ui/ConfigPowerSaving.qml",
                                "../plasmoid/contents/ui/ConfigEqualizer.qml",
                                "../plasmoid/contents/ui/ConfigQuickConnect.qml",
                                "../plasmoid/contents/config/config.qml"]) {
                const component = Qt.createComponent(page)
                compare(component.status, Component.Ready, component.errorString())
            }
        }
        function test_footer_actions_are_stacked() {
            const actions = findChild(summary, "overviewActions")
            const settings = findChild(summary, "soundSettingsButton")
            const configure = findChild(summary, "headsetSettingsButton")
            const originalWidth = summary.parent.width
            // Both labels are long: always one column, never side by side.
            for (const width of [300, 500]) {
                summary.parent.width = width
                compare(actions.columns, 1)
                tryVerify(() => configure.y > settings.y)
                verify(settings.width <= actions.width)
                verify(configure.width <= actions.width)
            }
            // In the system tray its heading already has the configure button.
            summary.showHeader = false
            verify(!configure.visible)
            verify(settings.visible)
            summary.showHeader = true
            summary.parent.width = originalWidth
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
        function test_fixed_height_keeps_actions_at_bottom() {
            // The system tray gives every applet the same popup size.
            panel.visible = true
            summary.visible = false
            const overview = findChild(panel, "connectionOverview")
            panel.height = overview.implicitHeight + 200
            wait(50)
            const actions = findChild(panel, "overviewActions")
            const bottom = actions.mapToItem(overview, 0, actions.height).y
            verify(overview.height >= overview.implicitHeight + 150)
            verify(bottom > overview.height - 4 * Kirigami.Units.gridUnit)
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
            for (const action of ["pairingButton", "powerOffButton"]) {
                findChild(sizedPanel, action).triggered()
                tryVerify(() => sizeDialog.height > compactHeight)
                tryVerify(() => overview.height >= overview.implicitHeight - 1)
                const cancel = action === "pairingButton" ? "cancelPairingButton" : "cancelPowerOffButton"
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
        function test_dnd_status_row() {
            summary.localeName = "en_US"
            const row = findChild(summary, "dnd")
            const value = findChild(summary, "dndValue")
            // Only with a confirmed link.
            summary.status = linked("disconnected")
            verify(!row.visible)
            summary.status = linked("connected")
            verify(row.visible)
            summary.settingsBusy = true
            compare(value.text, "Reading…")
            summary.settingsBusy = false
            compare(value.text, "Unknown")
            const icon = findChild(summary, "dndIcon")
            compare(icon.source, "notifications-disabled-symbolic")
            compare(icon.opacity, 0.5)
            summary.dndState = true
            compare(value.text, "On")
            compare(icon.source, "notifications-disabled-symbolic")
            compare(icon.opacity, 1)
            compare(icon.width, findChild(summary, "headsetBatteryIcon").width)
            summary.dndState = false
            compare(value.text, "Off")
            compare(icon.source, "notifications-disabled-symbolic")
            summary.localeName = "es_CL"
            compare(value.text, "Desactivado")
            summary.dndState = true
            compare(value.text, "Activado")
            // The menu entry is a checkbox that requests the opposite value.
            const item = findChild(summary, "dndMenuItem")
            verify(item.checkable)
            verify(item.checked)
            verify(item.enabled)
            settingSpy.clear()
            item.toggle()
            item.triggered()
            compare(settingSpy.count, 1)
            compare(settingSpy.signalArguments[0][0], "dnd")
            compare(settingSpy.signalArguments[0][1], false)
            // It keeps showing the reported value until the headset confirms.
            verify(item.checked)
            summary.settingsBusy = true
            verify(!item.enabled)
            summary.settingsBusy = false
            summary.dndState = null
            verify(!item.enabled)
            summary.dndState = true
            summary.localeName = "en_US"
            summary.dndState = null
            summary.status = null
        }
        function test_gaming_status_row_and_action() {
            summary.localeName = "en_US"
            summary.status = linked("connected")
            const row = findChild(summary, "gaming")
            const value = findChild(summary, "gamingValue")
            const icon = findChild(summary, "gamingIcon")
            const item = findChild(summary, "gamingMenuItem")
            verify(row.visible)
            compare(icon.source, "input-gamepad-symbolic")
            compare(value.text, "Unknown")
            summary.gamingState = false
            compare(value.text, "Off")
            // Read through the USB dongle: shown, but cannot be changed.
            summary.gamingSettable = false
            verify(!item.enabled)
            // Over Bluetooth the menu entry sets the opposite value.
            summary.gamingSettable = true
            verify(item.enabled)
            settingSpy.clear()
            item.toggle()
            item.triggered()
            compare(settingSpy.count, 1)
            compare(settingSpy.signalArguments[0][0], "gaming")
            compare(settingSpy.signalArguments[0][1], true)
            verify(!item.checked)
            summary.localeName = "es_CL"
            compare(item.text, "Modo gaming Bluetooth")
            compare(value.text, "Desactivado")
            summary.localeName = "en_US"
            summary.gamingSettable = false
            summary.gamingState = null
            summary.status = null
            verify(!row.visible)
        }
        function test_poweroff_is_explicit_and_serialized_in_ui() {
            const action = findChild(summary, "powerOffButton")
            summary.localeName = "en_US"
            compare(action.text, "Turn off headset…")
            powerSpy.clear()
            action.triggered()
            verify(summary.confirmingPowerOff)
            compare(powerSpy.count, 0)
            mouseClick(findChild(summary, "cancelPowerOffButton"))
            compare(powerSpy.count, 0)
            verify(!summary.confirmingPowerOff)
            action.triggered()
            wait(20)
            mouseClick(findChild(summary, "confirmPowerOffButton"))
            compare(powerSpy.count, 1)
            verify(!summary.confirmingPowerOff)
            summary.powerBusy = true
            verify(!action.enabled)
            verify(!findChild(summary, "pairingButton").enabled)
            summary.powerBusy = false
            summary.pairingBusy = true
            verify(!action.enabled)
            summary.pairingBusy = false
            summary.localeName = "es_CL"
            compare(action.text, "Apagar auricular…")
            action.triggered()
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
            const settings = findChild(summary, "soundSettingsButton")
            compare(settings.text, "Configure Audio Devices…")
            settingsSpy.clear()
            mouseClick(settings)
            compare(settingsSpy.count, 1)
            summary.localeName = "es_CL"
            compare(settings.text, "Configurar dispositivos de sonido…")
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
            summary.target = {transport: "bluetooth", address: "01:02:03:04:05:06"}
            summary.battery = {percent: 60, state: "NoCharge"}
            // The popup says whether; its transport icon says how.
            compare(summary.statusText, "Connected")
            compare(findChild(summary, "transportIcon").Accessible.name, "Bluetooth")
            compare(findChild(summary, "batteryPercentage").text, "60%")
            verify(!findChild(summary, "batteryStatus").visible)
            verify(findChild(summary, "moreActionsButton").visible)
            verify(findChild(summary, "pairingButton").text.includes("USB"))
            verify(findChild(summary, "powerOffButton").text.includes("USB"))
            summary.target = {transport: "usb"}
            verify(!findChild(summary, "pairingButton").text.includes("USB"))
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
            compare(state.text, "Adapter not detected")
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
            const button = findChild(summary, "pairingButton")
            verify(button !== null)
            compare(pairingSpy.count, 0)
            mouseClick(findChild(summary, "moreActionsButton"))
            tryCompare(findChild(summary, "moreActionsMenu"), "opened", true)
            mouseClick(button)
            compare(pairingSpy.count, 0)
            verify(summary.confirmingPairing)
            tryCompare(findChild(summary, "moreActionsMenu"), "visible", false)
            wait(20)
            mouseClick(findChild(summary, "cancelPairingButton"))
            verify(!summary.confirmingPairing)
            compare(pairingSpy.count, 0)
            mouseClick(findChild(summary, "moreActionsButton"))
            tryCompare(findChild(summary, "moreActionsMenu"), "opened", true)
            mouseClick(button)
            tryCompare(findChild(summary, "moreActionsMenu"), "visible", false)
            wait(20)
            mouseClick(findChild(summary, "confirmPairingButton"))
            compare(pairingSpy.count, 1)
            summary.pairingBusy = true
            verify(!button.enabled)
            mouseClick(findChild(summary, "moreActionsButton"))
            tryCompare(findChild(summary, "moreActionsMenu"), "opened", true)
            mouseClick(button)
            compare(pairingSpy.count, 1)
            findChild(summary, "moreActionsMenu").close()
            tryCompare(findChild(summary, "moreActionsMenu"), "visible", false)
            summary.pairingBusy = false
        }
        function test_closing_clears_pending_confirmation() {
            summary.confirmingPairing = true
            summary.activeView = false
            verify(!summary.confirmingPairing)
            summary.activeView = true
            verify(!summary.confirmingPairing)
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
