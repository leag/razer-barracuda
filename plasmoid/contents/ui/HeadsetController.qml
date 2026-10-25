import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/output.js" as Output

Plasma5Support.DataSource {
    id: controller
    engine: "executable"
    connectedSources: []
    property var target: ({transport: "usb"})
    property bool activeView: false
    readonly property string targetKey: target.transport === "bluetooth" ? target.address : "usb"
    property string requestedKey: targetKey
    onTargetKeyChanged: {
        response = null;
        error = "";
        errorCode = "";
        if (activeView && !busy)
            Qt.callLater(() => request({op: "status"}));
    }
    property bool busy: false
    property var response: null
    property string error: ""
    // The helper's code for the last failure, so a view can word what failed.
    property string errorCode: ""
    // The feature of the last set request ("dnd", "gaming", "devices", …), or
    // empty for a status read, so its feedback can appear beside its control.
    property string requestFeature: ""
    property string localeName: Qt.locale().name
    signal loaded(var result)
    function label(en, es) { return Output.text(en, es, localeName); }
    // Plain sentences: what happened and what the user can do. Helper names,
    // PATH and HID details go to the journal, never to a view.
    function errorLabel(code) {
        const labels = {
            "helper-missing": label("Install or update the barracuda-pair package.", "Instala o actualiza el paquete barracuda-pair."),
            "driver-required": label("Install or update the Barracuda driver.", "Instala o actualiza el driver del Barracuda."),
            "missing-adapter": label("Plug in the USB dongle.", "Conecta el dongle USB."),
            "unknown-link": label("The headset link is not confirmed.", "La conexión del auricular no está confirmada."),
            // The driver's udev rule gives the audio group headset access.
            "permission-denied": label("Install or update the Barracuda driver and add your user to the audio group.", "Instala o actualiza el driver del Barracuda y añade tu usuario al grupo audio."),
            "bluetooth-runtime-unavailable": label("Install or update the barracuda-pair package to use Bluetooth.", "Instala o actualiza el paquete barracuda-pair para usar Bluetooth."),
            "bluetooth-unsupported": label("This headset can't be controlled over Bluetooth.", "Este auricular no se puede controlar por Bluetooth."),
            "bluetooth-unavailable": label("The headset didn't answer over Bluetooth.", "El auricular no respondió por Bluetooth."),
            "invalid-response": label("The headset sent an unexpected answer.", "El auricular envió una respuesta inesperada."),
            "busy": label("Another headset command is running. Try again in a moment.", "Hay otra orden en curso. Vuelve a intentarlo en un momento."),
            "timeout": label("The headset didn't answer.", "El auricular no respondió."),
            "route-failed": label("Unplug the USB dongle and plug it in again.", "Desconecta el dongle USB y vuelve a conectarlo."),
            "rejected": label("The headset rejected the change.", "El auricular rechazó el cambio."),
            "unconfirmed": label("The headset didn't confirm the change.", "El auricular no confirmó el cambio."),
            "gaming-active": label("Turn off Bluetooth gaming mode first.", "Desactiva primero el modo gaming Bluetooth."),
            "unknown-device": label("The headset no longer knows this device.", "El auricular ya no conoce este dispositivo."),
            "gaming-not-applied": label("The headset didn't change Bluetooth gaming mode.", "El auricular no cambió el modo gaming Bluetooth.")
        };
        return labels[code] || label("This setting isn't available on this headset.", "Este ajuste no está disponible en este auricular.");
    }
    // Failures after which the headset certainly kept its previous state: the
    // last reading stays, so controls keep showing confirmed values. Any other
    // failure of a change (a timeout, an unconfirmed change) may have changed
    // the headset, so nothing stays known.
    readonly property var unchangedCodes: ["rejected", "busy", "gaming-active", "unknown-device", "gaming-not-applied",
                                           "missing-adapter", "unknown-link", "permission-denied", "driver-required"]
    function request(value) {
        if (busy)
            return;
        busy = true;
        error = "";
        errorCode = "";
        requestFeature = value.op === "set" ? String(value.feature) : "";
        requestedKey = targetKey;
        connectSource(Output.headsetCommand(value, target));
    }
    onNewData: (sourceName, data) => {
        disconnectSource(sourceName);
        busy = false;
        if (requestedKey !== targetKey) {
            if (activeView)
                request({op: "status"});
            return;
        }
        let result;
        try { result = JSON.parse(String(data.stdout)); }
        catch (e) {
            console.warn("barracuda-headset gave no readable reply:", String(data.stdout || "").trim(),
                         String(data.stderr || "").trim());
            response = null;
            errorCode = "helper-missing";
            error = errorLabel(errorCode);
            return;
        }
        if (!result.ok) {
            errorCode = String(result.error || "");
            if (requestFeature === "" || !unchangedCodes.includes(errorCode))
                response = null;
            error = errorLabel(errorCode);
            return;
        }
        // A change shows in the reading it returns, not in a message.
        response = result;
        loaded(result);
    }
}
