import QtQuick
import QtTest
import "../plasmoid/contents/code/output.js" as Output

// Pure logic only: this suite also runs where Qt is installed without Plasma.
TestCase {
    name: "HeadsetLogic"
    // QAction::Priority values, which Plasma's actions use.
    readonly property int normalPriority: 128
    readonly property int highPriority: 256
    // The action properties that output.js reads.
    component FakeAction: QtObject {
        property bool isSeparator: false
        property string text: ""
        property int priority: 128
        property bool visible: true
    }
    property list<QtObject> actions: [
        FakeAction { id: leadingSeparator; isSeparator: true },
        FakeAction { id: high; text: "Pair Headset…"; priority: 256 },
        FakeAction { id: powerOff; text: "Turn Off Headset…" },
        FakeAction { id: hidden; text: "Hidden"; visible: false },
        FakeAction { id: separator; isSeparator: true },
        FakeAction { id: doubled; isSeparator: true },
        FakeAction { id: audio; text: "Configure Audio Devices…" },
        FakeAction { id: configure; text: "&Configure Barracuda Headset…" },
        FakeAction { id: trailingSeparator; isSeparator: true }
    ]
    function test_more_actions_match_the_tray() {
        // Visible normal-priority actions without Plasma's configure action;
        // a separator stays only between two entries, once.
        compare(Output.moreActions(actions, configure, normalPriority), [powerOff, doubled, audio]);
        compare(Output.moreActions([audio, separator], configure, normalPriority), [audio]);
        compare(Output.moreActions([separator, audio], configure, normalPriority), [audio]);
        compare(Output.moreActions([], configure, normalPriority), []);
        compare(Output.moreActions(null, null, normalPriority), []);
        // The heading's icon buttons are the high-priority actions.
        compare(Output.primaryActions(actions, highPriority), [high]);
        compare(Output.primaryActions(null, highPriority), []);
    }
    function linked(link, bluetooth, battery) {
        return {ok: true, usb: {adapter: "present", driver: true, link: link, battery: battery || null},
                bluetooth: bluetooth === undefined ? null : bluetooth};
    }
    function test_mac_address_format() {
        compare(Output.macAddress("0a0b0c0d0e0f"), "0A:0B:0C:0D:0E:0F");
        compare(Output.macAddress("01:02:03:04:05:06"), "01:02:03:04:05:06");
        // Anything that is not six bytes is shown unchanged.
        compare(Output.macAddress("abc"), "abc");
        compare(Output.macAddress(undefined), "");
    }
    function test_configuration_changes_run_as_one_chain() {
        const requests = [{op: "set", feature: "preset", value: 255},
                          {op: "set", feature: "bands", value: [1, 0, 0, 0, 0, 0, 0, 0, 0, -1]}];
        compare(Output.headsetChainCommand(requests, {transport: "usb"}),
                // The file is unlinked before the chain starts and read
                // through a descriptor opened earlier.
                "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\") || exit 1; exec 3>\"$f\" 4<\"$f\"; rm -f \"$f\"; ("
                + "barracuda-headset --request '{\"op\":\"set\",\"feature\":\"preset\",\"value\":255}' && "
                + "barracuda-headset --request '{\"op\":\"set\",\"feature\":\"bands\",\"value\":[1,0,0,0,0,0,0,0,0,-1]}'"
                + ") >&3 3>&- 4<&- 2>/dev/null & exec 3>&-; wait $!; s=$?; tail -n 1 <&4; exit $s");
        // Over Bluetooth every step names the headset's address.
        const bluetooth = Output.headsetChainCommand([{op: "set", feature: "standby", value: 0}],
                                                     {transport: "bluetooth", address: "01:02:03:04:05:06"});
        verify(bluetooth.includes('"transport":"bluetooth","address":"01:02:03:04:05:06"'));
        verify(!bluetooth.includes("&&"));
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
    function test_connection_text() {
        compare(Output.connectionText(Output.connection(linked("connected")), "en_US"), "Connected · USB dongle");
        compare(Output.connectionText(Output.connection(linked("connected")), "es_CL"), "Conectado · Dongle USB");
        compare(Output.connectionText(Output.connection(linked("connected")), "en_US", false), "Connected");
        compare(Output.connectionText(Output.connection(linked("disconnected")), "en_US", false), "Disconnected");
        compare(Output.connectionText({state: "connected", transport: "both"}, "es_CL"),
                "Conectado · Dongle USB y Bluetooth");
        compare(Output.connectionText({state: "connected", transport: "bluetooth"}, "en_US"), "Connected · Bluetooth");
        compare(Output.connectionText({state: "disconnected"}, "es_CL"), "Desconectado");
        compare(Output.connectionText({state: "unknown"}, "en_US"), "Link not confirmed");
        compare(Output.connectionText({state: "unknown"}, "es_CL"), "Conexión no confirmada");
        compare(Output.connectionText({state: "no-adapter"}, "es_CL"), "Dongle USB no detectado");
        compare(Output.connectionText({state: "no-adapter"}, "en_US"), "USB dongle not detected");
        compare(Output.connectionText({state: "unavailable"}, "en_US"), "Status unavailable");
        compare(Output.connectionText({state: "unavailable"}, "es_CL"), "Estado no disponible");
        compare(Output.connectionText({state: "checking"}, "es_CL"), "Comprobando…");
        compare(Output.connectionText({state: "checking"}, "en_US"), "Checking…");
    }
    function test_connection_detail_rows() {
        compare(Output.detailRows({ok: true, usb: {adapter: "missing"}, bluetooth: null}, null, "en_US"),
                [["USB dongle", "Not detected"]]);
        compare(Output.detailRows({ok: true, usb: {adapter: "multiple"}, bluetooth: null}, null, "es_CL"),
                [["Dongle USB", "Más de uno"]]);
        compare(Output.detailRows(linked("disconnected", {state: "disconnected", address: "x"}), null, "es_CL"),
                [["Dongle USB", "Detectado"], ["Enlace 2,4 GHz", "Desconectado"], ["Bluetooth", "No conectado"]]);
        compare(Output.detailRows({ok: true, usb: {adapter: "present", driver: false, link: "unknown"},
                                   bluetooth: {state: "unknown"}}, null, "en_US"),
                [["USB dongle", "Detected"], ["2.4 GHz link", "Driver required"], ["Bluetooth", "Unknown"]]);
        compare(Output.detailRows(linked("unknown"), null, "es_CL")[1], ["Enlace 2,4 GHz", "No confirmado"]);
        const battery = {percent: 65, status: "Charging", cable: true, voltage_mv: 4123};
        compare(Output.detailRows(linked("connected", null, battery), null, "es_CL").slice(2),
                [["Cable de carga", "Conectado"], ["Voltaje de batería", "4,12 V"]]);
        battery.cable = null;
        battery.voltage_mv = null;
        compare(Output.detailRows(linked("connected", null, battery), null, "en_US").slice(2),
                [["Charging cable", "Unknown"]]);
        battery.cable = false;
        compare(Output.detailRows(linked("connected", null, battery), null, "en_US").slice(2),
                [["Charging cable", "Not connected"]]);
        // Retained values are not shown as current while the link is not confirmed.
        compare(Output.detailRows(linked("unknown", null, battery), null, "en_US").length, 2);
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
        // Disconnected and missing-adapter states are dimmed, without an emblem.
        compare(Output.emblem({state: "disconnected"}, null), "");
        compare(Output.emblem({state: "no-adapter"}, null), "");
        compare(Output.emblem({state: "unknown"}, null), "emblem-question");
        compare(Output.emblem({state: "unavailable"}, null), "emblem-question");
        compare(Output.emblem({state: "connected"}, {percent: 10, state: "Discharging"}), "emblem-warning");
        compare(Output.emblem({state: "connected"}, {percent: 10, state: "Charging"}), "");
        compare(Output.emblem({state: "connected"}, {percent: 11, state: "Discharging"}), "");
        // A stale low reading without a link is not a warning.
        compare(Output.emblem({state: "disconnected"}, {percent: 5, state: "Discharging"}), "");
    }
    function test_tray_status() {
        // The icon stays visible in every state, so pairing stays reachable.
        for (const state of ["connected", "unknown", "disconnected", "no-adapter", "unavailable", "checking"])
            compare(Output.trayStatus({state: state}, null), "active");
        compare(Output.trayStatus({state: "connected"}, {percent: 10, state: "Discharging"}), "attention");
        compare(Output.trayStatus({state: "connected"}, {percent: 10, state: "Unknown"}), "attention");
        compare(Output.trayStatus({state: "connected"}, {percent: 10, state: "Charging"}), "active");
        compare(Output.trayStatus({state: "connected"}, {percent: 5, state: "FullyCharged"}), "active");
        compare(Output.trayStatus({state: "connected"}, {percent: 11, state: "Discharging"}), "active");
        // A stale low reading without a confirmed link does not ask for attention.
        compare(Output.trayStatus({state: "disconnected"}, {percent: 5, state: "Discharging"}), "active");
        compare(Output.trayStatus({state: "unknown"}, {percent: 5, state: "Discharging"}), "active");
    }
    function test_commands_disabled_only_for_confirmed_missing_adapter() {
        verify(Output.adapterMissing({ok: true, usb: {adapter: "missing"}, bluetooth: null}));
        verify(Output.adapterMissing({ok: true, usb: {adapter: "missing"}, bluetooth: {state: "connected"}}));
        for (const status of [null, undefined, {ok: false}, {ok: true, usb: {adapter: "multiple"}},
                              linked("unknown"), linked("disconnected"), linked("connected")])
            verify(!Output.adapterMissing(status));
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
    function test_pairing_and_power_outcomes() {
        compare(Output.pairingOutcome({"exit code": 0, stdout: "ok"}, "en_US"),
                {ok: true, details: "", text: "Paired. Turn the headset off and on to start the link."});
        compare(Output.pairingOutcome({"exit code": 0}, "es_CL"),
                {ok: true, details: "", text: "Emparejado. Apaga y enciende el auricular para iniciar la conexión."});
        // A plain sentence for the popup; the cause for the journal.
        compare(Output.pairingOutcome({"exit code": 1, stdout: "searching\n", stderr: "timeout\n"}, "en_US"),
                {ok: false, details: "barracuda-pair exited with 1: searching timeout",
                 text: "Couldn't pair. Check the USB dongle and that the headset is in pairing mode."});
        compare(Output.pairingOutcome({"exit code": 2, stderr: "x"}, "es_CL"),
                {ok: false, details: "barracuda-pair exited with 2: x",
                 text: "No se pudo emparejar. Revisa el dongle USB y que el auricular esté en modo de emparejamiento."});
        // Success says nothing: the next reading shows the headset off.
        compare(Output.powerOutcome({"exit code": 0}, "en_US"), {ok: true, details: "", text: ""});
        compare(Output.powerOutcome({"exit code": 1, stderr: "not linked\n"}, "en_US"),
                {ok: false, details: "barracuda-power exited with 1: not linked",
                 text: "Couldn't turn off the headset. Check the USB dongle."});
        compare(Output.powerOutcome({"exit code": 1, stdout: "busy"}, "es_CL"),
                {ok: false, details: "barracuda-power exited with 1: busy",
                 text: "No se pudo apagar el auricular. Revisa el dongle USB."});
        compare(Output.commandDetails("barracuda-power", {"exit code": 127}), "barracuda-power exited with 127");
        // No helper name, PATH or HID detail reaches the popup.
        for (const locale of ["en_US", "es_CL"])
            for (const outcome of [Output.pairingOutcome({"exit code": 1, stderr: "PATH"}, locale),
                                   Output.powerOutcome({"exit code": 1, stderr: "PATH"}, locale)])
                verify(!/barracuda-|PATH|HID/.test(outcome.text));
    }
    function test_action_text_drops_accelerators() {
        compare(Output.actionText("&Configure Barracuda Headset…"), "Configure Barracuda Headset…");
        compare(Output.actionText("Configurar &Auricular Barracuda…"), "Configurar Auricular Barracuda…");
        compare(Output.actionText("Sound && Video"), "Sound & Video");
        compare(Output.actionText(undefined), "");
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
        compare(Output.battery(data, ["Battery1"]).state, "NoCharge");
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
        // The missing USB dongle is drawn as the dongle.
        compare(Output.artwork("drive-removable-media-usb"),
                "file:///usr/share/icons/breeze/devices/64/drive-removable-media-usb.svg");
        compare(Output.artwork("video-display"), "video-display");
        compare(Output.artwork("audio-card"), "audio-card");
    }

    readonly property string nbsp: " "
    function test_percentages_as_each_language_writes_them() {
        compare(Output.percentText(80, "en_US"), "80%");
        compare(Output.percentText(80, "es_CL"), "80" + nbsp + "%");
        compare(Output.percentText(5, "es_ES"), "5" + nbsp + "%");
        compare(Output.percentText(100, "de_DE"), "100%");
    }
    function test_low_battery_and_charge_notes() {
        verify(!Output.lowBattery(null));
        verify(!Output.lowBattery(undefined));
        verify(Output.lowBattery({percent: 10, state: "Discharging"}));
        verify(Output.lowBattery({percent: 0, state: "Unknown"}));
        verify(!Output.lowBattery({percent: 11, state: "Discharging"}));
        verify(!Output.lowBattery({percent: 3, state: "Charging"}));
        verify(!Output.lowBattery({percent: 3, state: "FullyCharged"}));
        const notes = [[null, "Battery unavailable", "Batería no disponible"],
                       [{percent: 60, state: "Charging"}, "Charging", "Cargando"],
                       [{percent: 100, state: "FullyCharged"}, "Fully charged", "Carga completa"],
                       [{percent: 8, state: "Discharging"}, "Low battery", "Batería baja"],
                       // The percentage and the bar already say it.
                       [{percent: 80, state: "Discharging"}, "", ""],
                       [{percent: 80, state: "Unknown"}, "", ""]];
        for (const [battery, english, spanish] of notes) {
            compare(Output.chargeNote(battery, "en_US"), english);
            compare(Output.chargeNote(battery, "es_CL"), spanish);
        }
    }
    function test_headset_card_lines() {
        const usb = {state: "connected", transport: "usb"};
        const discharging = {percent: 80, state: "Discharging"};
        compare(Output.hero(usb, discharging, false, "en_US"),
                {headline: "Connected", percent: "80%", line: "USB dongle",
                 accessible: "Connected, 80% battery, USB dongle"});
        compare(Output.hero(usb, discharging, false, "es_CL"),
                {headline: "Conectado", percent: "80" + nbsp + "%", line: "Dongle USB",
                 accessible: "Conectado, 80" + nbsp + "% de batería, dongle USB"});
        compare(Output.hero({state: "connected", transport: "bluetooth"}, {percent: 65, state: "Charging"}, false, "en_US"),
                {headline: "Connected", percent: "65%", line: "Bluetooth · Charging",
                 accessible: "Connected, 65% battery, Bluetooth, charging"});
        compare(Output.hero({state: "connected", transport: "both"}, {percent: 8, state: "Discharging"}, false, "es_CL"),
                {headline: "Conectado", percent: "8" + nbsp + "%", line: "Dongle USB y Bluetooth · Batería baja",
                 accessible: "Conectado, 8" + nbsp + "% de batería, dongle USB y Bluetooth, batería baja"});
        compare(Output.hero({state: "connected", transport: "both"}, {percent: 100, state: "FullyCharged"}, false, "en_US").line,
                "USB dongle and Bluetooth · Fully charged");
        // Without a reading the line says so and there is no percentage.
        compare(Output.hero(usb, null, false, "en_US"),
                {headline: "Connected", percent: "", line: "USB dongle · Battery unavailable",
                 accessible: "Connected, USB dongle, battery unavailable"});
        compare(Output.hero(usb, null, false, "es_CL").line, "Dongle USB · Batería no disponible");
        // A command running on the headset replaces the state.
        compare(Output.hero(usb, discharging, true, "en_US").headline, "Turning off…");
        compare(Output.hero(usb, discharging, true, "es_CL").headline, "Apagando…");
        compare(Output.hero(usb, discharging, true, "es_CL").accessible, "Apagando…, 80" + nbsp + "% de batería, dongle USB");
    }
    function test_transport_glyphs_beside_the_artwork() {
        compare(Output.transportEmblems({state: "connected", transport: "usb"}), ["drive-removable-media-usb-symbolic"]);
        compare(Output.transportEmblems({state: "connected", transport: "bluetooth"}), ["network-bluetooth-symbolic"]);
        // Bottom first: the dongle, then Bluetooth above it.
        compare(Output.transportEmblems({state: "connected", transport: "both"}),
                ["drive-removable-media-usb-symbolic", "network-bluetooth-symbolic"]);
        for (const state of ["disconnected", "unknown", "no-adapter", "unavailable", "checking"])
            compare(Output.transportEmblems({state: state, transport: "usb"}), []);
    }
    // Each state without a confirmed link has its own words and artwork.
    function test_placeholders_keep_states_distinct() {
        const expect = (status, battery, pairing, english, spanish, look) => {
            for (const [locale, words] of [["en_US", english], ["es_CL", spanish]]) {
                const value = Output.placeholder(status, Output.connection(status), battery, pairing, false, locale);
                compare(value.title, words[0]);
                compare(value.explanation, words[1]);
                compare(value.state, look[0]);
                compare(value.artwork, look[1]);
                compare(value.dimmed, look[2]);
                compare(value.emblem, look[3]);
                compare(value.busy, look[4]);
            }
        };
        expect(null, null, false, ["Checking…", ""], ["Comprobando…", ""],
               ["checking", "audio-headset", true, "", true]);
        expect(linked("disconnected"), null, false, ["Disconnected", "Turn on the headset."],
               ["Desconectado", "Enciende el auricular."], ["disconnected", "audio-headset", true, "", false]);
        // Without the dongle, pairing waits for it; the words say so.
        expect({ok: true, usb: {adapter: "missing"}, bluetooth: {state: "disconnected"}}, null, false,
               ["Disconnected", "Turn on the headset or plug in the USB dongle."],
               ["Desconectado", "Enciende el auricular o conecta el dongle USB."],
               ["disconnected", "audio-headset", true, "", false]);
        expect(linked("unknown"), null, false,
               ["Link not confirmed", "The headset may still be on."],
               ["Conexión no confirmada", "El auricular puede seguir encendido."],
               ["unknown", "audio-headset", false, "emblem-question", false]);
        expect(linked("unknown"), {percent: 80, state: "Discharging"}, false,
               ["Link not confirmed", "The headset may still be on. Last battery reading: 80%."],
               ["Conexión no confirmada", "El auricular puede seguir encendido. Última lectura de batería: 80" + nbsp + "%."],
               ["unknown", "audio-headset", false, "emblem-question", false]);
        expect({ok: true, usb: {adapter: "multiple"}, bluetooth: null}, null, false,
               ["Link not confirmed", "More than one Barracuda USB dongle is plugged in. Leave only one."],
               ["Conexión no confirmada", "Hay más de un dongle USB Barracuda conectado. Deja solo uno."],
               ["unknown", "audio-headset", false, "emblem-question", false]);
        expect({ok: true, usb: {adapter: "present", driver: false, link: "unknown"}, bluetooth: null}, null, false,
               ["Link not confirmed", "Install or update the Barracuda driver."],
               ["Conexión no confirmada", "Instala o actualiza el driver del Barracuda."],
               ["unknown", "audio-headset", false, "emblem-question", false]);
        expect({ok: true, usb: {adapter: "missing"}, bluetooth: null}, null, false,
               ["USB dongle not detected", "Plug in the dongle, or use the headset over Bluetooth."],
               ["Dongle USB no detectado", "Conecta el dongle o usa el auricular por Bluetooth."],
               ["no-adapter", "drive-removable-media-usb", true, "", false]);
        expect({ok: false}, null, false,
               ["Status unavailable", "Install or update the barracuda-pair package."],
               ["Estado no disponible", "Instala o actualiza el paquete barracuda-pair."],
               ["unavailable", "audio-headset", false, "emblem-warning", false]);
        // Pairing replaces any link, also a confirmed one.
        for (const status of [linked("disconnected"), linked("connected")])
            expect(status, null, true,
                   ["Pairing…", "Keep the headset in pairing mode. This can take up to a minute."],
                   ["Emparejando…", "Mantén el auricular en modo de emparejamiento. Puede tardar hasta un minuto."],
                   ["pairing", "audio-headset", false, "", true]);
        compare(Output.placeholder(linked("connected"), Output.connection(linked("connected")), null, false, false,
                                   "en_US").state, "connected");
        // A power-off running without a confirmed link waits in the
        // placeholder, in every such state; with one, the card says it.
        for (const status of [null, {ok: false}, linked("unknown"), linked("disconnected"),
                              {ok: true, usb: {adapter: "multiple"}, bluetooth: null}]) {
            for (const [locale, title] of [["en_US", "Turning off…"], ["es_CL", "Apagando…"]]) {
                const value = Output.placeholder(status, Output.connection(status), {percent: 80, state: "Discharging"},
                                                 false, true, locale);
                compare(value, {state: "turning-off", artwork: "audio-headset", dimmed: false, emblem: "", busy: true,
                                title: title, explanation: ""});
            }
        }
        compare(Output.placeholder(linked("connected"), Output.connection(linked("connected")), null, false, true,
                                   "en_US").state, "connected");
        // Pairing and power-off never run together; pairing would win.
        compare(Output.placeholder(linked("unknown"), Output.connection(linked("unknown")), null, true, true,
                                   "en_US").state, "pairing");
    }
    function test_detail_rows() {
        compare(Output.detailRows(null, null, "en_US"), []);
        compare(Output.detailRows({ok: false}, null, "en_US"), []);
        const battery = {percent: 65, status: "Charging", cable: true, voltage_mv: 4123};
        compare(Output.detailRows(linked("connected", null, battery), {percent: 65, state: "Charging"}, "en_US"),
                [["USB dongle", "Detected"], ["2.4 GHz link", "Connected"],
                 ["Charging cable", "Connected"], ["Battery voltage", "4.12 V"]]);
        // A discharging battery, which the card's line leaves out, is named here.
        compare(Output.detailRows(linked("connected", {state: "disconnected"}), {percent: 65, state: "Discharging"}, "es_CL"),
                [["Dongle USB", "Detectado"], ["Enlace 2,4 GHz", "Conectado"], ["Bluetooth", "No conectado"],
                 ["Carga", "Con batería"]]);
        compare(Output.detailRows(linked("connected"), {percent: 65, state: "Discharging"}, "en_US").slice(-1),
                [["Charge", "On battery"]]);
        compare(Output.detailRows({ok: true, usb: {adapter: "missing"}, bluetooth: {state: "connected"}},
                                  {percent: 65, state: "FullyCharged"}, "en_US"),
                [["USB dongle", "Not detected"], ["Bluetooth", "Connected"]]);
    }
    function test_tooltip_is_one_line() {
        const usb = Output.connection(linked("connected"));
        compare(Output.toolTip(usb, {percent: 80, state: "Discharging"}, "en_US"), "Connected · USB dongle · 80% Battery");
        compare(Output.toolTip(usb, {percent: 80, state: "Discharging"}, "es_CL"),
                "Conectado · Dongle USB · 80" + nbsp + "% de batería");
        compare(Output.toolTip(usb, {percent: 80, state: "Charging"}, "es_CL"),
                "Conectado · Dongle USB · 80" + nbsp + "% de batería · Cargando");
        compare(Output.toolTip({state: "connected", transport: "both"}, {percent: 8, state: "Discharging"}, "en_US"),
                "Connected · USB dongle and Bluetooth · 8% Battery · Low battery");
        compare(Output.toolTip(usb, null, "en_US"), "Connected · USB dongle");
        compare(Output.toolTip({state: "disconnected"}, null, "es_CL"), "Desconectado");
        compare(Output.toolTip({state: "unknown"}, {percent: 40, state: "Charging"}, "en_US"),
                "Link not confirmed · 40% Battery");
        compare(Output.toolTip({state: "no-adapter"}, null, "en_US"), "USB dongle not detected");
        compare(Output.toolTip({state: "unavailable"}, null, "es_CL"), "Estado no disponible");
        compare(Output.toolTip({state: "checking"}, null, "en_US"), "Checking…");
        verify(!Output.toolTip(usb, {percent: 80, state: "Charging"}, "en_US").includes("\n"));
    }
    function test_settings_feedback_words() {
        compare(Output.settingName("dnd", "en_US"), "the Do not disturb setting");
        compare(Output.settingName("dnd", "es_CL"), "el ajuste No molestar");
        compare(Output.settingName("gaming", "en_US"), "Bluetooth gaming mode");
        compare(Output.settingName("gaming", "es_CL"), "el modo gaming Bluetooth");
        compare(Output.settingName("devices", "en_US"), "the list of Bluetooth devices");
        compare(Output.settingName("devices", "es_CL"), "la lista de dispositivos Bluetooth");
        compare(Output.settingName("preset", "en_US"), "");
        // A failed read names a reason only when the user can act on it.
        for (const code of ["driver-required", "permission-denied", "helper-missing", "bluetooth-runtime-unavailable",
                            "route-failed", "missing-adapter", "busy", "bluetooth-unsupported"]) {
            verify(Output.actionableError(code), code);
            compare(Output.settingsFailure("", code, "Do this.", "en_US"), "Couldn't read the headset. Do this.");
        }
        for (const code of ["timeout", "invalid-response", "bluetooth-unavailable", "unconfirmed", "rejected", ""]) {
            verify(!Output.actionableError(code), code);
            compare(Output.settingsFailure("", code, "The headset didn't answer.", "en_US"), "Couldn't read the headset.");
        }
        compare(Output.settingsFailure("", "timeout", "x", "es_CL"), "No se pudo leer el auricular.");
        compare(Output.settingsFailure("", "missing-adapter", "Conecta el dongle USB.", "es_CL"),
                "No se pudo leer el auricular. Conecta el dongle USB.");
        // A failed change always says why.
        const changes = {dnd: ["Couldn't change the Do not disturb setting.", "No se pudo cambiar el ajuste No molestar."],
                         gaming: ["Couldn't change Bluetooth gaming mode.", "No se pudo cambiar el modo gaming Bluetooth."],
                         devices: ["Couldn't switch devices.", "No se pudo cambiar de dispositivo."],
                         other: ["Couldn't change the setting.", "No se pudo cambiar el ajuste."]};
        for (const feature of Object.keys(changes)) {
            compare(Output.settingsFailure(feature, "timeout", "Reason.", "en_US"), changes[feature][0] + " Reason.");
            compare(Output.settingsFailure(feature, "timeout", "Motivo.", "es_CL"), changes[feature][1] + " Motivo.");
        }
        compare(Output.readFailure(["gaming"], "en_US"), "Couldn't read Bluetooth gaming mode.");
        compare(Output.readFailure(["gaming"], "es_CL"), "No se pudo leer el modo gaming Bluetooth.");
        compare(Output.readFailure(["dnd"], "en_US"), "Couldn't read the Do not disturb setting.");
        compare(Output.readFailure(["devices"], "es_CL"), "No se pudo leer la lista de dispositivos Bluetooth.");
        compare(Output.readFailure(["dnd", "gaming"], "en_US"), "Couldn't read some settings.");
        compare(Output.readFailure(["dnd", "devices"], "es_CL"), "No se pudieron leer algunos ajustes.");
    }
    function test_bluetooth_devices_note() {
        const devices = [{address: "010203040506", name: "Phone", active: true}];
        compare(Output.devicesNote(null, true, null, "en_US"), "Reading…");
        compare(Output.devicesNote(null, true, null, "es_CL"), "Leyendo…");
        compare(Output.devicesNote(null, false, null, "en_US"), "");
        compare(Output.devicesNote([], false, false, "en_US"), "No known devices.");
        compare(Output.devicesNote([], false, true, "es_CL"), "Sin dispositivos conocidos.");
        compare(Output.devicesNote(devices, false, true, "en_US"), "Turn off Bluetooth gaming mode to switch devices.");
        compare(Output.devicesNote(devices, false, true, "es_CL"),
                "Desactiva el modo gaming Bluetooth para cambiar de dispositivo.");
        compare(Output.devicesNote(devices, false, null, "en_US"),
                "Switching devices needs Bluetooth gaming mode to be read first.");
        compare(Output.devicesNote(devices, false, null, "es_CL"),
                "Para cambiar de dispositivo, primero hay que leer el modo gaming Bluetooth.");
        compare(Output.devicesNote(devices, false, false, "en_US"), "");
    }
}
