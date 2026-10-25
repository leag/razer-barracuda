import QtQuick
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/code/output.js" as Output

// HeadsetController, the popup's one channel to barracuda-headset, with
// injected replies. The popup's Sound and Power tabs are in tst_summary.qml.
Item {
    id: host
    width: 600
    height: 700
    // An unknown engine name runs nothing; an empty one would keep the
    // component's executable engine.
    HeadsetController { id: nativeBackend; engine: "barracuda-test-none" }
    TestCase {
        name: "HeadsetController"
        when: windowShown
        function test_native_error_clears_confirmed_state() {
            // A failed read leaves nothing known.
            nativeBackend.requestFeature = "";
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: "rejected"})});
            compare(nativeBackend.response, null);
            compare(nativeBackend.errorCode, "rejected");
            // A change that may have reached the headset leaves nothing known.
            nativeBackend.requestFeature = "dnd";
            for (const code of ["timeout", "unconfirmed", "invalid-response", "bluetooth-unavailable", "route-failed"]) {
                nativeBackend.response = {state: {dnd: true}};
                nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: code})});
                compare(nativeBackend.response, null, code);
                compare(nativeBackend.errorCode, code);
                compare(nativeBackend.error, nativeBackend.errorLabel(code));
            }
            // A change the headset certainly did not apply keeps the reading,
            // so the controls stay at confirmed values.
            for (const code of ["rejected", "busy", "gaming-active", "unknown-device", "gaming-not-applied",
                                "missing-adapter", "unknown-link", "permission-denied", "driver-required"]) {
                const reading = {state: {dnd: true}};
                nativeBackend.response = reading;
                nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: code})});
                compare(nativeBackend.response, reading, code);
                compare(nativeBackend.errorCode, code);
            }
            // An unreadable reply means the helper is missing or too old; its
            // output goes to the journal, not to the view.
            nativeBackend.newData("fake", {stdout: "barracuda-headset: command not found", stderr: ""});
            compare(nativeBackend.response, null);
            compare(nativeBackend.errorCode, "helper-missing");
            compare(nativeBackend.error, "Install or update the barracuda-pair package.");
            nativeBackend.requestFeature = "";
            nativeBackend.error = "";
            nativeBackend.errorCode = "";
        }
        function test_error_labels_in_plain_language() {
            const expected = {
                "helper-missing": ["Install or update the barracuda-pair package.",
                                   "Instala o actualiza el paquete barracuda-pair."],
                "driver-required": ["Install or update the Barracuda driver.",
                                    "Instala o actualiza el driver del Barracuda."],
                "missing-adapter": ["Plug in the USB dongle.", "Conecta el dongle USB."],
                "unknown-link": ["The headset link is not confirmed.", "La conexión del auricular no está confirmada."],
                "permission-denied": ["Install or update the Barracuda driver and add your user to the audio group.",
                                      "Instala o actualiza el driver del Barracuda y añade tu usuario al grupo audio."],
                "bluetooth-runtime-unavailable": ["Install or update the barracuda-pair package to use Bluetooth.",
                                                  "Instala o actualiza el paquete barracuda-pair para usar Bluetooth."],
                "bluetooth-unsupported": ["This headset can't be controlled over Bluetooth.",
                                          "Este auricular no se puede controlar por Bluetooth."],
                "bluetooth-unavailable": ["The headset didn't answer over Bluetooth.", "El auricular no respondió por Bluetooth."],
                "invalid-response": ["The headset sent an unexpected answer.", "El auricular envió una respuesta inesperada."],
                "busy": ["Another headset command is running. Try again in a moment.",
                         "Hay otra orden en curso. Vuelve a intentarlo en un momento."],
                "timeout": ["The headset didn't answer.", "El auricular no respondió."],
                "route-failed": ["Unplug the USB dongle and plug it in again.", "Desconecta el dongle USB y vuelve a conectarlo."],
                "rejected": ["The headset rejected the change.", "El auricular rechazó el cambio."],
                "unconfirmed": ["The headset didn't confirm the change.", "El auricular no confirmó el cambio."],
                "gaming-active": ["Turn off Bluetooth gaming mode first.", "Desactiva primero el modo gaming Bluetooth."],
                "unknown-device": ["The headset no longer knows this device.", "El auricular ya no conoce este dispositivo."],
                "gaming-not-applied": ["The headset didn't change Bluetooth gaming mode.",
                                       "El auricular no cambió el modo gaming Bluetooth."],
                "device-error": ["This setting isn't available on this headset.",
                                 "Este ajuste no está disponible en este auricular."]
            };
            for (const code of Object.keys(expected)) {
                nativeBackend.localeName = "en_US";
                compare(nativeBackend.errorLabel(code), expected[code][0]);
                nativeBackend.localeName = "es_CL";
                compare(nativeBackend.errorLabel(code), expected[code][1]);
            }
            // No label names a helper command, PATH or HID.
            for (const locale of ["en_US", "es_CL"]) {
                nativeBackend.localeName = locale;
                for (const code of Object.keys(expected))
                    verify(!/barracuda-headset|PATH|HID/.test(nativeBackend.errorLabel(code)), code);
            }
            nativeBackend.localeName = "en_US";
        }
        function test_controller_remembers_the_requested_feature() {
            // Feedback appears beside the control whose request produced it.
            nativeBackend.request({op: "set", feature: "devices", value: "01:02:03:04:05:06"});
            verify(nativeBackend.busy);
            compare(nativeBackend.requestFeature, "devices");
            compare(nativeBackend.connectedSources.length, 1);
            verify(nativeBackend.connectedSources[0].includes('"feature":"devices"'));
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: false, error: "gaming-active"})});
            verify(!nativeBackend.busy);
            compare(nativeBackend.requestFeature, "devices");
            compare(nativeBackend.error, nativeBackend.errorLabel("gaming-active"));
            nativeBackend.request({op: "status"});
            compare(nativeBackend.requestFeature, "");
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: true, transport: "usb", state: {dnd: true}, errors: {}})});
            verify(!nativeBackend.busy);
            compare(nativeBackend.error, "");
            compare(nativeBackend.response.state.dnd, true);
            nativeBackend.response = null;
        }
        function test_transport_change_drops_old_reply() {
            nativeBackend.target = {transport: "usb"};
            nativeBackend.requestedKey = "usb";
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.target = {transport: "bluetooth", address: "01:02:03:04:05:06"};
            compare(nativeBackend.response, null);
            nativeBackend.newData("old request", {stdout: JSON.stringify({ok: true, state: {preset: 9}})});
            compare(nativeBackend.response, null);
            nativeBackend.requestedKey = nativeBackend.targetKey;
            nativeBackend.newData("current request", {stdout: JSON.stringify({ok: true, state: {preset: 0}, transport: "bluetooth"})});
            compare(nativeBackend.response.state.preset, 0);
            nativeBackend.target = {transport: "usb"};
            nativeBackend.requestedKey = nativeBackend.targetKey;
        }
        function test_command_quotes_arguments() {
            const command = Output.headsetCommand({op: "status"}, {transport: "bluetooth", address: "' $(touch nope)"});
            verify(command.startsWith("barracuda-headset --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
