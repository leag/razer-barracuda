import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/output.js" as Output

Plasma5Support.DataSource {
    id: controller
    engine: "executable"
    connectedSources: []
    property var sink: null
    property bool activeView: false
    readonly property string targetKey: Output.bluetooth(sink) ? Output.bluetoothAddress(sink) : "usb"
    property string requestedKey: targetKey
    onTargetKeyChanged: {
        response = null;
        error = "";
        message = "";
        if (activeView && !busy)
            Qt.callLater(() => request({op: "status"}));
    }
    property bool busy: false
    property var response: null
    property string error: ""
    property string message: ""
    property string localeName: Qt.locale().name
    signal loaded(var result)
    function label(en, es) { return Output.text(en, es, localeName); }
    function errorLabel(code) {
        const labels = {
            "driver-required": label("Update the Barracuda driver to use native controls.", "Actualiza el driver del Barracuda para usar los controles nativos."),
            "missing-adapter": label("Adapter not detected.", "Adaptador no detectado."),
            "unknown-link": label("The headset link is not confirmed.", "La conexión del auricular no está confirmada."),
            "permission-denied": label("Install the headset-control permissions rule.", "Instala la regla de permisos de control del auricular."),
            "bluetooth-runtime-unavailable": label("Install the helper with the system Python to enable Bluetooth sockets.", "Instala la utilidad con el Python del sistema para habilitar Bluetooth."),
            "bluetooth-unsupported": label("The headset has no supported Bluetooth control service.", "El auricular no ofrece un servicio de control Bluetooth compatible."),
            "bluetooth-unavailable": label("Bluetooth controls could not connect. Refresh to try again.", "No se pudo conectar al control Bluetooth. Actualiza para volver a intentarlo."),
            "invalid-response": label("The headset returned an invalid response. Refresh to read its state.", "El auricular devolvió una respuesta inválida. Actualiza para leer su estado."),
            "busy": label("Another headset operation is running. Try again shortly.", "Hay otra operación en curso. Vuelve a intentarlo en unos segundos."),
            "timeout": label("The headset did not answer. Its state is unknown.", "El auricular no respondió. Su estado es desconocido."),
            "route-failed": label("Could not restore the adapter route. Reconnect the dongle.", "No se pudo restaurar la ruta del adaptador. Reconecta el dongle."),
            "rejected": label("The headset rejected this change.", "El auricular rechazó este cambio."),
            "unconfirmed": label("The change could not be confirmed. Refresh before trying again.", "No se pudo confirmar el cambio. Actualiza antes de volver a intentarlo."),
            "gaming-active": label("Turn Gaming off before switching Bluetooth devices.", "Desactiva Gaming antes de cambiar de dispositivo Bluetooth."),
            "gaming-not-applied": label("The headset accepted the Gaming request but did not change its mode. Activation over USB is unverified; this does not enable the Game EQ preset.", "El auricular aceptó la solicitud Gaming, pero no cambió de modo. Su activación por USB no está confirmada; esto no activa el perfil EQ Juegos.")
        };
        return labels[code] || label("This control is unavailable on the current headset.", "Este control no está disponible en el auricular actual.");
    }
    function request(value) {
        if (busy)
            return;
        busy = true;
        error = "";
        message = "";
        requestedKey = targetKey;
        connectSource(Output.headsetCommand(value, sink));
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
            response = null;
            error = label("Native controls require barracuda-headset on PATH.", "Los controles nativos requieren barracuda-headset en PATH.");
            return;
        }
        if (!result.ok) {
            response = null;
            error = errorLabel(result.error);
            return;
        }
        response = result;
        loaded(result);
        if (result.sent)
            message = result.sent === "devices"
                ? label("Connection switch requested. Refresh to check the active device.", "Cambio de conexión solicitado. Actualiza para comprobar el dispositivo activo.")
                : result.state[result.sent] !== null
                    ? label("Change confirmed by the headset.", "Cambio confirmado por el auricular.") : "";
    }
}
