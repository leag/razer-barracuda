import QtQuick
import QtTest
import "../plasmoid/contents/code/output.js" as Output

TestCase {
    name: "OutputIcon"
    function test_volume_and_status() {
        compare(Output.volumePercent(null), null);
        compare(Output.volumePercent({name: "auto_null", volume: 65536}), null);
        compare(Output.volumePercent({name: "HDMI"}), null);
        compare(Output.volumePercent({volume: NaN}), null);
        compare(Output.volumePercent({volume: -1}), null);
        compare(Output.volumePercent({volume: 0}), 0);
        compare(Output.volumePercent({volume: 32768}), 50);
        compare(Output.volumePercent({volume: 98304}), 150);
        compare(Output.status(null, "en_US"), "No audio output");
        compare(Output.status(null, "es_CL"), "Sin salida de audio");
        compare(Output.status({volume: 32768, muted: true}, "es_CL"), "Silenciado · Volumen: 50%");
        compare(Output.status({volume: 0, muted: false}, "en_US"), "Volume: 0%");
        compare(Output.status({}, "en_US"), "Volume unavailable");
        compare(Output.status({}, "es_CL"), "Volumen no disponible");
    }
    function test_pairing_command_after_ui_confirmation() {
        compare(Output.powerOffCommand("es_CL"), "barracuda-power --off --yes --language es");
        compare(Output.powerOffCommand("en_US; echo unsafe"), "barracuda-power --off --yes --language en");
        compare(Output.pairingCommand("es_CL"),
                "barracuda-pair --yes --timeout 60 --language es");
        compare(Output.pairingCommand("en_US"),
                "barracuda-pair --yes --timeout 60 --language en");
        compare(Output.pairingCommand("de_DE; echo unsafe"), Output.pairingCommand("en_US"));
    }
    function test_battery_identity_and_unknown_states() {
        const data = {Battery0: {Product: "Logitech mouse", Type: "Mouse", "Is Power Supply": false,
                                 "Plugged in": true, Percent: 90, State: "Discharging"},
                      Battery1: {Product: "Razer Barracuda X (2022)", Type: "Headset", "Is Power Supply": false,
                                 "Plugged in": true, Percent: 65, State: "Discharging"}};
        compare(Output.battery(data, ["Battery0"]), null);
        compare(Output.battery(data, ["Battery0", "Battery1"]).percent, 65);
        compare(Output.battery(data, []), null);
        data.Battery1["Plugged in"] = false;
        compare(Output.battery(data, ["Battery1"]), null);
        data.Battery1["Plugged in"] = true;
        data.Battery1.Percent = 101;
        compare(Output.battery(data, ["Battery1"]), null);
        data.Battery1.Percent = 0;
        data.Battery1.State = "Unknown";
        compare(Output.battery(data, ["Battery1"]), null);
        data.Battery1.State = "Discharging";
        compare(Output.battery(data, ["Battery1"]).percent, 0);
        compare(Output.batteryText(null, "es_CL"), "Batería no disponible");
        compare(Output.batteryText(null, "en_US"), "Battery unavailable");
        compare(Output.batteryText({percent: 65, state: "Charging"}, "es_CL"), "65% · Cargando");
        compare(Output.batteryText({percent: 99, state: "Unknown"}, "en_US"), "99% · Charge state unknown");
        compare(Output.batteryText({percent: 100, state: "FullyCharged"}, "en_US"), "100% · Fully charged");
    }
    function test_bluetooth_command_target() {
        const sink = {name: "bluez_output.01_02_03_04_05_06.1", properties: {"device.api": "bluez5"}};
        compare(Output.bluetoothAddress(sink), "01:02:03:04:05:06");
        const command = Output.headsetCommand({op: "set", feature: "gaming", value: true}, sink);
        verify(command.includes('"transport":"bluetooth"'));
        verify(command.includes('"address":"01:02:03:04:05:06"'));
        verify(!Output.headsetCommand({op: "status"}, null).includes('"transport"'));
    }
    function test_bluetooth_battery_and_transport_changes() {
        const data = {
            Battery0: {Product: "Razer Barracuda X (2022)", Type: "Headset", "Is Power Supply": false,
                       "Plugged in": true, Percent: 65, State: "Discharging"},
            Battery1: {Product: "Razer Barracuda X (BT)", Type: "Headset", "Is Power Supply": false,
                       "Plugged in": true, Percent: 60, State: "NoCharge"}
        };
        const sources = ["Battery0", "Battery1"];
        const bt = {name: "bluez_output.example.1", properties: {"device.api": "bluez5"}};
        compare(Output.battery(data, sources, bt).percent, 60);
        bt.description = "Razer Barracuda X (BT)";
        compare(Output.icon(bt), "audio-headset");
        compare(Output.deviceName(bt, "es_CL"), "Razer Barracuda X");
        verify(Output.bluetooth(bt));
        verify(!Output.bluetooth({name: "alsa_output.example"}));
        compare(Output.battery(data, sources, {name: "alsa_output.example"}).percent, 65);
        compare(Output.battery(data, ["Battery1"]).percent, 60);
        compare(Output.batteryText(Output.battery(data, ["Battery1"]), "es_CL"),
                "60% · Estado de carga desconocido");
        data.Battery1["Plugged in"] = false;
        compare(Output.battery(data, ["Battery1"], bt), null);
        data.Battery1["Plugged in"] = true;
        data.Battery1.Percent = 101;
        compare(Output.battery(data, ["Battery1"], bt), null);
        data.Battery1.Product = "Other Bluetooth headset";
        data.Battery1.Percent = 60;
        compare(Output.battery(data, ["Battery1"], bt), null);
    }
    function test_battery_discovery_subscription() {
        compare(Output.batterySources([]), ["Battery"]);
        compare(Output.batterySources(["Battery", "AC Adapter", "Power Profiles"]), ["Battery"]);
        compare(Output.batterySources(["Battery", "Battery0", "Battery1", "AC Adapter"]),
                ["Battery", "Battery0", "Battery1"]);
        compare(Output.batterySources(["Battery", "Battery0"]), ["Battery", "Battery0"]);
    }
    function test_missing() {
        compare(Output.icon(null), "audio-card");
        compare(Output.icon({name: "auto_null"}), "audio-card");
    }
    function test_barracuda() {
        compare(Output.icon({properties: {"alsa.components": "USB1532:0552"}}),
                "audio-headset");
        compare(Output.icon({properties: {"device.vendor.id": "0x1532",
                                         "device.product.id": "0x0552"}}),
                "audio-headset");
        compare(Output.icon({properties: {"alsa.components": "USB1532:05520"}}),
                "audio-speakers");
    }
    function test_device_changes() {
        compare(Output.icon({formFactor: "headset"}), "audio-headset");
        compare(Output.icon({iconName: "video-display"}), "video-display");
        compare(Output.icon({ports: [{name: "analog-output-headphones"}],
                             activePortIndex: 0}), "audio-headset");
        compare(Output.icon({ports: [{name: "analog-output-headphones"}],
                             activePortIndex: 99}), "audio-speakers");
        compare(Output.icon({name: "speaker", muted: true}), "audio-speakers");
    }
    function test_languages() {
        compare(Output.text("Muted", "Silenciado", "es_CL"), "Silenciado");
        compare(Output.text("Muted", "Silenciado", "en_US"), "Muted");
        compare(Output.text("Muted", "Silenciado", "de_DE"), "Muted");
    }
    function test_kde_detailed_artwork() {
        compare(Output.artwork("audio-headset"),
                "file:///usr/share/icons/breeze/devices/64/audio-headset.svg");
        compare(Output.artwork("audio-headset-usb"), Output.artwork("audio-headset"));
        compare(Output.artwork("audio-speakers"),
                "file:///usr/share/icons/breeze/devices/64/audio-speakers.svg");
        compare(Output.artwork("video-display"), "video-display");
        compare(Output.artwork("audio-card"), "audio-card");
    }
}
