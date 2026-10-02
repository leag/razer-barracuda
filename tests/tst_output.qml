import QtQuick
import QtTest
import "../plasmoid/contents/code/output.js" as Output

TestCase {
    name: "HeadsetLogic"
    function linked(link, bluetooth, battery) {
        return {ok: true, usb: {adapter: "present", driver: true, link: link, battery: battery || null},
                bluetooth: bluetooth === undefined ? null : bluetooth};
    }
    function test_link_parsing_and_command() {
        compare(Output.linkCommand(), "barracuda-headset --request '{\"op\":\"link\"}'");
        compare(Output.parseLink("").ok, false);
        compare(Output.parseLink("not json").ok, false);
        // Helpers without the link operation reject it.
        compare(Output.parseLink('{"ok": false, "error": "invalid-request"}').ok, false);
        compare(Output.parseLink('{"ok": true, "state": {}}').ok, false);
        compare(Output.parseLink('{"ok": true, "usb": {"adapter": "missing"}, "bluetooth": null}').usb.adapter,
                "missing");
    }
    function test_connection_states_stay_distinct() {
        compare(Output.connection(null).state, "checking");
        compare(Output.connection({ok: false}).state, "unavailable");
        compare(Output.connection(linked("connected")), {state: "connected", transport: "usb"});
        compare(Output.connection(linked("disconnected")), {state: "disconnected", transport: "usb"});
        compare(Output.connection(linked("unknown")), {state: "unknown", transport: "usb"});
        compare(Output.connection({ok: true, usb: {adapter: "present", driver: false, link: "unknown"},
                                   bluetooth: null}).state, "unknown");
        compare(Output.connection({ok: true, usb: {adapter: "multiple"}, bluetooth: null}).state, "unknown");
        compare(Output.connection({ok: true, usb: {adapter: "missing"}, bluetooth: null}).state, "no-adapter");
        compare(Output.connection({ok: true, usb: {adapter: "missing"}, bluetooth: {state: "unknown"}}).state,
                "no-adapter");
        compare(Output.connection({ok: true, usb: {adapter: "missing"},
                                   bluetooth: {state: "disconnected", address: "01:02:03:04:05:06"}}),
                {state: "disconnected", transport: "bluetooth"});
        const bt = {state: "connected", address: "01:02:03:04:05:06"};
        compare(Output.connection({ok: true, usb: {adapter: "missing"}, bluetooth: bt}),
                {state: "connected", transport: "bluetooth"});
        compare(Output.connection(linked("connected", bt)), {state: "connected", transport: "both"});
        // An unconfirmed dongle link does not hide a confirmed Bluetooth one.
        compare(Output.connection(linked("unknown", bt)).state, "connected");
    }
    function test_connection_text_and_hints() {
        compare(Output.connectionText(Output.connection(linked("connected")), "en_US"), "Connected · USB dongle");
        compare(Output.connectionText(Output.connection(linked("connected")), "es_CL"), "Conectado · Dongle USB");
        compare(Output.connectionText({state: "connected", transport: "both"}, "es_CL"),
                "Conectado · Dongle USB y Bluetooth");
        compare(Output.connectionText({state: "disconnected"}, "es_CL"), "Desconectado");
        compare(Output.connectionText({state: "unknown"}, "en_US"), "Link not confirmed");
        compare(Output.connectionText({state: "no-adapter"}, "es_CL"), "Adaptador no detectado");
        compare(Output.connectionText({state: "unavailable"}, "en_US"), "Status unavailable");
        compare(Output.connectionText({state: "checking"}, "es_CL"), "Comprobando…");
        compare(Output.connectionHint(linked("connected"), {state: "connected"}, "en_US"), "");
        verify(Output.connectionHint(linked("unknown"), {state: "unknown"}, "en_US").includes("does not mean"));
        verify(Output.connectionHint(linked("unknown"), {state: "unknown"}, "es_CL").includes("no significa"));
        verify(Output.connectionHint({ok: true, usb: {adapter: "present", driver: false, link: "unknown"}},
                                     {state: "unknown"}, "en_US").includes("driver"));
        verify(Output.connectionHint({ok: true, usb: {adapter: "multiple"}}, {state: "unknown"}, "es_CL")
               .includes("más de un adaptador"));
        verify(Output.connectionHint({ok: false}, {state: "unavailable"}, "en_US").includes("barracuda-headset"));
        verify(Output.connectionHint(linked("disconnected"), {state: "disconnected"}, "es_CL").includes("Enciende"));
    }
    function test_connection_details() {
        compare(Output.connectionDetails(null, "en_US"), []);
        compare(Output.connectionDetails({ok: false}, "en_US"), []);
        compare(Output.connectionDetails({ok: true, usb: {adapter: "missing"}, bluetooth: null}, "en_US"),
                [["USB dongle", "Not detected"]]);
        compare(Output.connectionDetails(linked("disconnected", {state: "disconnected", address: "x"}), "es_CL"),
                [["Dongle USB", "Detectado"], ["Enlace 2,4 GHz", "Desconectado"], ["Bluetooth", "No conectado"]]);
        compare(Output.connectionDetails({ok: true, usb: {adapter: "present", driver: false, link: "unknown"},
                                          bluetooth: {state: "unknown"}}, "en_US"),
                [["USB dongle", "Detected"], ["2.4 GHz link", "Driver required"], ["Bluetooth", "Unknown"]]);
        const battery = {percent: 65, status: "Charging", cable: true, voltage_mv: 4123};
        compare(Output.connectionDetails(linked("connected", null, battery), "en_US"),
                [["USB dongle", "Detected"], ["2.4 GHz link", "Connected"],
                 ["Charging cable", "Connected"], ["Battery voltage", "4.12 V"]]);
        compare(Output.connectionDetails(linked("connected", null, battery), "es_CL")[3],
                ["Voltaje de batería", "4,12 V"]);
        battery.cable = null;
        battery.voltage_mv = null;
        compare(Output.connectionDetails(linked("connected", null, battery), "en_US").slice(2),
                [["Charging cable", "Unknown"]]);
        // Retained values are not shown as current while the link is not confirmed.
        compare(Output.connectionDetails(linked("unknown", null, battery), "en_US").length, 2);
    }
    function test_driver_battery_fallback() {
        compare(Output.driverBattery(null), null);
        compare(Output.driverBattery(linked("connected")), null);
        compare(Output.driverBattery(linked("connected", null, {percent: null, status: "Charging"})), null);
        compare(Output.driverBattery(linked("connected", null, {percent: 70, status: "Full"})),
                {percent: 70, state: "FullyCharged"});
        compare(Output.driverBattery(linked("connected", null, {percent: 70, status: "Discharging"})).state,
                "Discharging");
        compare(Output.driverBattery(linked("connected", null, {percent: 70, status: "Unknown"})).state, "Unknown");
        compare(Output.driverBattery(linked("disconnected", null, {percent: 70, status: "Full"})), null);
    }
    function test_panel_emblem() {
        compare(Output.emblem({state: "connected"}, null), "");
        compare(Output.emblem({state: "checking"}, null), "");
        compare(Output.emblem({state: "disconnected"}, null), "emblem-unavailable");
        compare(Output.emblem({state: "no-adapter"}, null), "emblem-unavailable");
        compare(Output.emblem({state: "unknown"}, null), "emblem-question");
        compare(Output.emblem({state: "unavailable"}, null), "emblem-question");
        compare(Output.emblem({state: "connected"}, {percent: 10, state: "Discharging"}), "emblem-warning");
        compare(Output.emblem({state: "connected"}, {percent: 10, state: "Charging"}), "");
        compare(Output.emblem({state: "connected"}, {percent: 11, state: "Discharging"}), "");
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
        const target = Output.headsetTarget(sink, null);
        compare(target, {transport: "bluetooth", address: "01:02:03:04:05:06"});
        const command = Output.headsetCommand({op: "set", feature: "gaming", value: true}, target);
        verify(command.includes('"transport":"bluetooth"'));
        verify(command.includes('"address":"01:02:03:04:05:06"'));
        verify(!Output.headsetCommand({op: "status"}, null).includes('"transport"'));
        verify(!Output.headsetCommand({op: "status"}, {transport: "usb"}).includes('"transport"'));
    }
    function test_controls_follow_confirmed_transport() {
        const btSink = {name: "bluez_output.01_02_03_04_05_06.1", properties: {"device.api": "bluez5"}};
        const usbSink = {name: "alsa_output.usb-Razer", properties: {}};
        const bt = {state: "connected", address: "0A:0B:0C:0D:0E:0F"};
        compare(Output.headsetTarget(usbSink, null), {transport: "usb"});
        compare(Output.headsetTarget(btSink, linked("connected")), {transport: "usb"});
        compare(Output.headsetTarget(usbSink, {ok: true, usb: {adapter: "missing"}, bluetooth: bt}),
                {transport: "bluetooth", address: "0A:0B:0C:0D:0E:0F"});
        // With both links confirmed, the default output decides, as before.
        compare(Output.headsetTarget(btSink, linked("connected", bt)).transport, "bluetooth");
        compare(Output.headsetTarget(usbSink, linked("connected", bt)), {transport: "usb"});
        compare(Output.headsetTarget(usbSink, linked("disconnected")), {transport: "usb"});
    }
    function test_bluetooth_battery_and_transport_changes() {
        const data = {
            Battery0: {Product: "Razer Barracuda X (2022)", Type: "Headset", "Is Power Supply": false,
                       "Plugged in": true, Percent: 65, State: "Discharging"},
            Battery1: {Product: "Razer Barracuda X (BT)", Type: "Headset", "Is Power Supply": false,
                       "Plugged in": true, Percent: 60, State: "NoCharge"}
        };
        const sources = ["Battery0", "Battery1"];
        compare(Output.battery(data, sources, true).percent, 60);
        const bt = {name: "bluez_output.example.1", properties: {"device.api": "bluez5"}};
        verify(Output.bluetooth(bt));
        verify(!Output.bluetooth({name: "alsa_output.example"}));
        compare(Output.battery(data, sources, false).percent, 65);
        compare(Output.battery(data, ["Battery1"]).percent, 60);
        compare(Output.batteryText(Output.battery(data, ["Battery1"]), "es_CL"),
                "60% · Estado de carga desconocido");
        data.Battery1["Plugged in"] = false;
        compare(Output.battery(data, ["Battery1"], true), null);
        data.Battery1["Plugged in"] = true;
        data.Battery1.Percent = 101;
        compare(Output.battery(data, ["Battery1"], true), null);
        data.Battery1.Product = "Other Bluetooth headset";
        data.Battery1.Percent = 60;
        compare(Output.battery(data, ["Battery1"], true), null);
    }
    function test_battery_presence_tracks_link_changes_only() {
        const data = {Battery0: {Product: "Razer Barracuda X (2022)", "Plugged in": true, Percent: 65},
                      Battery1: {Product: "Logitech mouse", "Plugged in": true}};
        const first = Output.batteryPresence(data, ["Battery0", "Battery1"]);
        compare(first, "Battery0:Razer Barracuda X (2022)");
        data.Battery0.Percent = 64;
        compare(Output.batteryPresence(data, ["Battery0", "Battery1"]), first);
        data.Battery0["Plugged in"] = false;
        compare(Output.batteryPresence(data, ["Battery0", "Battery1"]), "");
        compare(Output.batteryPresence({}, []), "");
    }
    function test_battery_discovery_subscription() {
        compare(Output.batterySources([]), ["Battery"]);
        compare(Output.batterySources(["Battery", "AC Adapter", "Power Profiles"]), ["Battery"]);
        compare(Output.batterySources(["Battery", "Battery0", "Battery1", "AC Adapter"]),
                ["Battery", "Battery0", "Battery1"]);
        compare(Output.batterySources(["Battery", "Battery0"]), ["Battery", "Battery0"]);
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
