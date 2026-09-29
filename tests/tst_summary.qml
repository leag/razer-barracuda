import QtQuick
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
    OutputSummary {
        id: summary
        anchors.fill: parent
        sink: null
        localeName: "en_US"
    }
    SignalSpy {
        id: pairingSpy
        target: summary
        signalName: "pairingRequested"
    }
    TestCase {
        name: "OutputSummary"
        when: windowShown
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
        function test_default_device_changes() {
            compare(summary.deviceName, "No audio output")
            verify(!summary.hasOutput)
            summary.sink = {name: "speakers", description: "Speakers", volume: 32768, muted: false}
            compare(summary.deviceName, "Speakers")
            compare(summary.statusText, "Volume: 50%")
            summary.sink = {name: "hdmi", description: "Monitor", iconName: "video-display", volume: 65536, muted: true}
            compare(summary.deviceName, "Monitor")
            compare(summary.deviceIcon, "video-display")
            compare(summary.statusText, "Muted · Volume: 100%")
            summary.localeName = "es_CL"
            compare(summary.statusText, "Silenciado · Volumen: 100%")
            summary.sink = {name: "auto_null", volume: 65536}
            compare(summary.deviceName, "Sin salida de audio")
            verify(!summary.hasOutput)
            summary.sink = null
        }
        function test_pairing_is_explicit_and_independent_of_output() {
            pairingSpy.clear()
            const button = findChild(summary, "pairingButton")
            verify(button !== null)
            compare(pairingSpy.count, 0)
            mouseClick(button)
            compare(pairingSpy.count, 0)
            verify(summary.confirmingPairing)
            mouseClick(findChild(summary, "cancelPairingButton"))
            verify(!summary.confirmingPairing)
            compare(pairingSpy.count, 0)
            mouseClick(button)
            mouseClick(findChild(summary, "confirmPairingButton"))
            compare(pairingSpy.count, 1)
            summary.pairingBusy = true
            verify(!button.enabled)
            mouseClick(button)
            compare(pairingSpy.count, 1)
            summary.pairingBusy = false
        }
        function test_closing_clears_pending_confirmation() {
            summary.confirmingPairing = true
            summary.activeView = false
            verify(!summary.confirmingPairing)
            summary.activeView = true
            verify(!summary.confirmingPairing)
        }
        function test_reconnection_clears_pending_confirmation() {
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
