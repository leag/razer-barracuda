import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/output.js" as Output

Plasma5Support.DataSource {
    id: controller
    engine: "executable"
    connectedSources: []
    property bool busy: false
    property var response: null
    property string error: ""
    property string message: ""
    property string operation: ""
    property string localeName: Qt.locale().name
    signal loaded(var result)

    function label(en, es) { return Output.text(en, es, localeName); }
    function request(value) {
        if (busy)
            return;
        busy = true;
        operation = value.op;
        error = "";
        message = "";
        connectSource(Output.audioCommand(value));
    }
    onNewData: (sourceName, data) => {
        disconnectSource(sourceName);
        busy = false;
        let result;
        try {
            result = JSON.parse(String(data.stdout));
        } catch (e) {
            error = label("Audio controls require barracuda-audio and PipeWire tools on PATH.",
                          "Los controles requieren barracuda-audio y las herramientas de PipeWire en PATH.");
            return;
        }
        if (!result.ok) {
            const errors = {
                "busy": label("Another audio update is running. Try again shortly.", "Hay otra actualización de audio en curso. Vuelve a intentarlo en unos segundos."),
                "missing-command": label("A required program is missing.", "Falta un programa necesario."),
                "missing-microphone": label("The Barracuda microphone and output must be available. Check the sound card profile in Sound settings.",
                                             "El micrófono y la salida del Barracuda deben estar disponibles. Revisa el perfil de la tarjeta en Ajustes de sonido."),
                "foreign-config": label("An existing configuration file belongs to another setup; it was not overwritten.",
                                         "Un archivo de configuración existente pertenece a otra instalación; no se sobrescribió."),
                "invalid-profile": label("Use a unique profile name, up to 60 characters.", "Usa un nombre de perfil único, de hasta 60 caracteres."),
                "ambiguous-device": label("More than one Barracuda device matches. Connect only the headset you want to configure.",
                                           "Hay más de un Barracuda. Conecta solo el auricular que quieres configurar."),
                "save-first": label("Save the configuration first.", "Guarda primero la configuración.")
            };
            error = (errors[result.error] || label("Could not apply audio settings.", "No se pudieron aplicar los ajustes de audio."))
                + (result.detail ? "\n" + result.detail : "");
            return;
        }
        response = result;
        loaded(result);
        if (result.warning)
            error = label("Configuration saved, but the live update failed. Apply it with an audio restart.",
                          "Configuración guardada, pero falló la actualización en vivo. Aplícala reiniciando el audio.")
                + "\n" + (result.detail || "");
        if (operation === "save_apply" || operation === "remove_eq" || operation === "remove_effects")
            message = result.state.pending_restart
                ? label("Saved. Apply and restart audio to finish activating the changes.", "Guardado. Aplica y reinicia el audio para terminar de activar los cambios.")
                : label("Changes applied and saved.", "Cambios aplicados y guardados.");
        else if (operation === "save")
            message = result.state.pending_restart
                ? label("Saved. Apply and restart audio to activate these changes.", "Guardado. Aplica y reinicia el audio para activar estos cambios.")
                : label("Saved.", "Guardado.");
        else if (operation === "apply")
            message = label("Audio restarted with the saved configuration.", "Audio reiniciado con la configuración guardada.");
    }
}
