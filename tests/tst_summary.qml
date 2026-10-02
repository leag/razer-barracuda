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
    QtObject {
        id: fakeAudio
        property bool busy: false
        property var response: null
        property string error: ""
        property string message: ""
        property var requests: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]) }
    }
    QtObject {
        id: fakeHeadset
        property bool busy: false
        property var response: null
        property string error: ""
        property string message: ""
        property var requests: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]); }
        function errorLabel(code) { return code; }
    }
    HeadsetPanel {
        id: panel
        width: 400
        height: 540
        visible: false
        audioController: fakeAudio
        headsetController: fakeHeadset
    }
    PlasmaCore.Dialog {
        id: sizeDialog
        visible: false
        mainItem: HeadsetPanel {
            id: sizedPanel
            audioController: fakeAudio
            headsetController: fakeHeadset
        }
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
        id: settingsSpy
        target: summary
        signalName: "settingsRequested"
    }
    TestCase {
        name: "ConnectionSummary"
        when: windowShown
        function test_help_navigation_and_translation() {
            summary.visible = false
            panel.visible = true
            panel.activeView = true
            const audioRequests = fakeAudio.requests.length
            const headsetRequests = fakeHeadset.requests.length
            for (const locale of ["en_US", "es_CL"]) {
                panel.localeName = locale
                compare(findChild(panel, "configureEffectsButton").text,
                    locale === "en_US" ? "Headset settings…" : "Ajustes del auricular…")
                const action = findChild(panel, "helpMenuItem")
                compare(action.text, locale === "en_US" ? "Help" : "Ayuda")
                action.triggered()
                verify(panel.helpOpen)
                verify(findChild(panel, "headsetHelp").visible)
                compare(findChild(panel, "headsetHelp").localeName, locale)
                const body = findChild(findChild(panel, "headsetHelp"), "helpBody")
                compare(body.textFormat, Text.RichText)
                verify(body.text.includes("<b>"))
                verify(body.text.includes("<p>"))
                verify(!findChild(panel, "connectionOverview").activeView)
                compare(fakeAudio.requests.length, audioRequests)
                compare(fakeHeadset.requests.length, headsetRequests)
                wait(20)
                mouseClick(findChild(panel, "backToOverview"))
                verify(!panel.helpOpen)
            }
            panel.effectsOpen = true
            wait(20)
            mouseClick(findChild(panel, "effectsHelpButton"))
            verify(panel.helpOpen)
            verify(findChild(panel, "headsetHelp").visible)
            panel.activeView = false
            verify(!panel.helpOpen)
            verify(!panel.effectsOpen)
            panel.activeView = true
            panel.localeName = "en_US"
            panel.visible = false
            summary.visible = true
        }
        function test_action_layout_adapts_to_width() {
            const actions = findChild(summary, "overviewActions")
            const settings = findChild(summary, "soundSettingsButton")
            const effects = findChild(summary, "configureEffectsButton")
            const originalWidth = summary.parent.width
            for (const locale of ["en_US", "es_CL"]) {
                summary.localeName = locale
                summary.parent.width = 300
                tryCompare(actions, "columns", 1)
                tryVerify(() => effects.y > settings.y)
                verify(settings.width <= actions.width)
                verify(effects.width <= actions.width)
                summary.parent.width = 500
                tryCompare(actions, "columns", 2)
                tryVerify(() => effects.x > settings.x)
            }
            summary.parent.width = originalWidth
            summary.localeName = "en_US"
        }
        function test_effects_height_tracks_available_controls() {
            sizedPanel.activeView = true
            sizedPanel.effectsOpen = true
            fakeHeadset.response = {state: {preset: null, bands: null}, errors: {preset: "unknown-link"}}
            sizeDialog.visible = true
            wait(50)
            const unavailableHeight = sizeDialog.height
            const settings = findChild(sizedPanel, "headsetSettings")
            verify(unavailableHeight < 24 * Kirigami.Units.gridUnit)
            fakeHeadset.response = {state: {preset: 255, bands: [0,0,0,0,0,0,0,0,0,0], gaming: false}}
            fakeHeadset.loaded(fakeHeadset.response)
            tryVerify(() => sizeDialog.height > unavailableHeight)
            fakeHeadset.response = {state: {preset: null, bands: null}, errors: {preset: "unknown-link"}}
            tryCompare(sizeDialog, "height", unavailableHeight)
            verify(settings.contentHeight > 0)
            fakeHeadset.response = null
            sizedPanel.effectsOpen = false
            sizeDialog.visible = false
        }
        function test_popup_height_tracks_battery_visibility() {
            sizedPanel.activeView = true
            sizedPanel.effectsOpen = false
            sizedPanel.helpOpen = false
            sizedPanel.status = null
            sizedPanel.battery = null
            sizeDialog.visible = true
            wait(50)
            const overview = findChild(sizedPanel, "connectionOverview")
            const compactHeight = sizeDialog.height
            const compactContent = overview.implicitHeight
            verify(!overview.showBattery)
            sizedPanel.battery = {percent: 65, state: "Discharging"}
            tryVerify(() => sizeDialog.height > compactHeight)
            verify(overview.implicitHeight > compactContent)
            sizedPanel.battery = null
            tryCompare(sizeDialog, "height", compactHeight)
            tryCompare(overview, "implicitHeight", compactContent)
            verify(overview.height >= overview.implicitHeight - 1)
            sizeDialog.visible = false
        }
        function test_popup_shrinks_after_effects() {
            sizeDialog.visible = true
            wait(50)
            const compactHeight = sizeDialog.height
            sizedPanel.effectsOpen = true
            tryVerify(() => sizeDialog.height > compactHeight)
            sizedPanel.effectsOpen = false
            tryCompare(sizeDialog, "height", compactHeight)
            sizedPanel.effectsOpen = true
            tryVerify(() => sizeDialog.height > compactHeight)
            sizedPanel.activeView = false
            tryCompare(sizeDialog, "height", compactHeight)
            sizeDialog.visible = false
        }
        function test_popup_fits_pairing_and_power_messages() {
            sizedPanel.activeView = true
            sizedPanel.effectsOpen = false
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
        function test_native_effects_navigation() {
            summary.visible = false
            panel.visible = true
            verify(findChild(panel, "audioTabs") === null)
            compare(fakeAudio.requests.length, 0)
            wait(20)
            mouseClick(findChild(panel, "configureEffectsButton"))
            verify(panel.effectsOpen)
            verify(findChild(panel, "headsetSettings").visible)
            verify(findChild(panel, "audioSettings") === null)
            compare(fakeAudio.requests.length, 1)
            compare(fakeAudio.requests[0].op, "status")
            const eq = {enabled: false, gains: [0,0,0,0,0,0,0,0,0,0], custom: {}, favorites: []}
            const result = {state: {equalizers: {output: eq, microphone: eq},
                sidetone: {enabled: false, level: 15}, tuning: {quantum: 0, fixed_rate: false, never_suspend: false, headroom: 0}},
                presets: {output: {Flat: eq.gains}, microphone: {Flat: eq.gains}},
                frequencies: {output: [31,63,125,250,500,1000,2000,4000,8000,16000],
                    microphone: [100,200,300,500,800,1500,3000,5000,8000,12000]}, has_microphone: true}
            fakeAudio.response = result
            fakeAudio.loaded(result)
            wait(20)
            mouseClick(findChild(panel, "backToOverview"))
            verify(!panel.effectsOpen)
            wait(20)
            mouseClick(findChild(panel, "configureEffectsButton"))
            verify(findChild(panel, "headsetSettings").visible)
            compare(fakeAudio.requests.length, 1)
            panel.activeView = false
            verify(!panel.effectsOpen)
            panel.activeView = true
            verify(!findChild(panel, "headsetSettings").visible)
            panel.visible = false
            summary.visible = true
        }
        function test_settings_and_unknown_battery() {
            summary.localeName = "en_US"
            summary.battery = null
            summary.status = linked("connected")
            const hint = findChild(summary, "batteryUnavailableHint")
            verify(hint.visible)
            verify(hint.text.includes("No battery reading"))
            const settings = findChild(summary, "soundSettingsButton")
            compare(settings.text, "Sound settings…")
            settingsSpy.clear()
            mouseClick(settings)
            compare(settingsSpy.count, 1)
            summary.localeName = "es_CL"
            compare(settings.text, "Ajustes de sonido…")
            verify(hint.text.includes("lectura de batería"))
            summary.battery = {percent: 65, state: "Discharging"}
            verify(!hint.visible)
            summary.battery = null
            summary.localeName = "en_US"
            summary.status = null
            verify(!hint.visible)
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
            compare(percent.text, "Desconocido")
            summary.localeName = "en_US"
            compare(percent.text, "Unknown")
        }
        function test_bluetooth_presentation() {
            summary.status = {ok: true, usb: {adapter: "missing"},
                              bluetooth: {state: "connected", address: "01:02:03:04:05:06"}}
            summary.target = {transport: "bluetooth", address: "01:02:03:04:05:06"}
            summary.battery = {percent: 60, state: "NoCharge"}
            compare(summary.statusText, "Connected · Bluetooth")
            compare(findChild(summary, "batteryPercentage").text, "60%")
            verify(!findChild(summary, "batteryStatus").visible)
            verify(!findChild(summary, "batteryUnavailableHint").visible)
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
            compare(state.text, "Connected · USB dongle")
            verify(!hint.visible)
            verify(!emblem.visible)
            verify(!slash.visible)
            tryVerify(() => values().length === 4)
            compare(values(), ["Detected", "Connected", "Connected", "4.12 V"])
            summary.localeName = "es_CL"
            compare(state.text, "Conectado · Dongle USB")
            tryVerify(() => values()[3] === "4,12 V")
            summary.localeName = "en_US"
            summary.status = null
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
