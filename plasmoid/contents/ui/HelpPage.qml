import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

PC3.ScrollView {
    id: help
    implicitWidth: 0
    objectName: "headsetHelp"
    property string localeName: Qt.locale().name
    function label(en, es) { return Output.text(en, es, localeName); }
    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
    PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
    contentWidth: availableWidth
    ColumnLayout {
        width: help.availableWidth
        spacing: Kirigami.Units.largeSpacing
        Repeater {
            model: [
                [help.label("Connection status", "Estado de la conexión"),
                 help.label("<p>The status comes from the Barracuda driver for the <b>USB dongle</b> and from BlueZ for <b>Bluetooth</b>. It is read while this popup is open and when the headset battery appears or disappears; nothing is sent to the headset.</p><ul><li><b>Connected</b>: the dongle or Bluetooth confirmed the link.</li><li><b>Disconnected</b>: the dongle reported that the headset is off or out of range.</li><li><b>Link not confirmed</b>: no confirmed state yet. This is not a disconnection.</li></ul><p>Cable and voltage are the last values reported by the driver.</p>",
                            "<p>El estado proviene del driver del Barracuda para el <b>dongle USB</b> y de BlueZ para <b>Bluetooth</b>. Se lee mientras esta ventana está abierta y cuando la batería del auricular aparece o desaparece; no se envía nada al auricular.</p><ul><li><b>Conectado</b>: el dongle o Bluetooth confirmó la conexión.</li><li><b>Desconectado</b>: el dongle informó que el auricular está apagado o fuera de alcance.</li><li><b>Conexión no confirmada</b>: aún no hay un estado confirmado. Esto no es una desconexión.</li></ul><p>El cable y el voltaje son los últimos valores informados por el driver.</p>")],
                [help.label("Battery", "Batería"),
                 help.label("<p>The reading comes from KDE, or from the driver when KDE does not list it, and may be the <b>last reported value</b>.</p><p><b>Unknown</b> means no reading is available yet.</p>",
                            "<p>La lectura proviene de KDE, o del driver si KDE no la muestra, y puede ser el <b>último valor informado</b>.</p><p><b>Desconocido</b> significa que aún no hay una lectura disponible.</p>")],
                [help.label("Sound settings", "Ajustes de sonido"),
                 help.label("<p><b>Sound settings…</b> opens KDE's audio controls. <b>WirePlumber</b> manages automatic output switching; this widget does not change audio routing.</p>",
                            "<p><b>Ajustes de sonido…</b> abre los controles de audio de KDE. <b>WirePlumber</b> gestiona el cambio automático de salida; este widget no cambia el enrutamiento de audio.</p>")],
                [help.label("Headset equalizer", "Ecualizador del auricular"),
                 help.label("<p>Choose a preset in <b>Profile</b> to change the headset's own EQ. The selection updates after the headset confirms it.</p><p>For custom EQ:</p><ol><li>Select <b>Custom</b>.</li><li>Adjust the bands; <b>0</b> is neutral.</li><li>Select <b>Apply changes</b>.</li></ol><p><b>Gaming mode</b> and the <b>Game</b> EQ preset are independent.</p>",
                            "<p>Elige un perfil en <b>Perfil</b> para cambiar el EQ del auricular. La selección se actualiza cuando el auricular la confirma.</p><p>Para personalizar el EQ:</p><ol><li>Selecciona <b>Personalizado</b>.</li><li>Ajusta las bandas; <b>0</b> es neutro.</li><li>Selecciona <b>Aplicar cambios</b>.</li></ol><p>El <b>modo Gaming</b> y el perfil EQ <b>Juegos</b> son independientes.</p>")],
                [help.label("Do Not Disturb", "No molestar"),
                 help.label("<p><b>Do Not Disturb</b> prevents incoming Bluetooth calls from automatically switching the headset away from <b>USB-dongle audio</b>.</p><p>This headset setting does not affect desktop notifications.</p>",
                            "<p><b>No molestar</b> evita que las llamadas Bluetooth entrantes cambien automáticamente el auricular del <b>audio del dongle USB</b>.</p><p>Este ajuste del auricular no afecta a las notificaciones del escritorio.</p>")],
                [help.label("Idle shutdown", "Apagado por inactividad"),
                 help.label("<p><b>Turn off when idle</b> sets how long the headset waits before turning off when idle.</p><p>Select <b>Never</b> to disable automatic idle shutdown.</p>",
                            "<p><b>Apagar por inactividad</b> define cuánto espera el auricular antes de apagarse por inactividad.</p><p>Selecciona <b>Nunca</b> para desactivar el apagado automático por inactividad.</p>")],
                ["Quick Connect",
                 help.label("<p>Switch to a Bluetooth device <b>already known</b> by the headset:</p><ol><li>Disable <b>Gaming mode</b>.</li><li>Select the device in <b>Quick Connect</b>.</li><li>Select <b>Refresh</b> to check the active device.</li></ol><p>Switching may interrupt audio. A request does not confirm a completed switch.</p>",
                            "<p>Cambia a un dispositivo Bluetooth que el auricular <b>ya conoce</b>:</p><ol><li>Desactiva el <b>modo Gaming</b>.</li><li>Selecciona el dispositivo en <b>Quick Connect</b>.</li><li>Selecciona <b>Actualizar</b> para comprobar el dispositivo activo.</li></ol><p>El cambio puede interrumpir el audio. Una solicitud no confirma que el cambio haya terminado.</p>")],
                [help.label("Pairing and power-off", "Emparejamiento y apagado"),
                 help.label("<p>Both actions are under <b>More actions</b> and require confirmation.</p><ul><li><b>Pair Barracuda…</b>: connect the USB dongle and put the headset in pairing mode. After pairing, turn the headset off and on again.</li><li><b>Turn off headset…</b>: after power-off, use the headset's <b>physical button</b> to turn it on.</li></ul>",
                            "<p>Ambas acciones están en <b>Más acciones</b> y requieren confirmación.</p><ul><li><b>Emparejar Barracuda…</b>: conecta el dongle USB y pon el auricular en modo de emparejamiento. Al terminar, apágalo y enciéndelo de nuevo.</li><li><b>Apagar auricular…</b>: tras apagarlo, usa su <b>botón físico</b> para encenderlo.</li></ul>")],
                [help.label("Unavailable controls", "Controles no disponibles"),
                 help.label("<p>Unknown or failed readings disable the affected controls.</p><p>In <b>Headset settings</b>, select <b>Refresh</b> to try reading again. A timeout leaves the headset state <b>unknown</b>.</p>",
                            "<p>Las lecturas desconocidas o fallidas desactivan los controles afectados.</p><p>En <b>Ajustes del auricular</b>, selecciona <b>Actualizar</b> para volver a leer. Un tiempo de espera agotado deja el estado del auricular <b>desconocido</b>.</p>")]
            ]
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: modelData[0]
                    wrapMode: Text.Wrap
                }
                PC3.Label {
                    Layout.fillWidth: true
                    objectName: "helpBody"
                    text: modelData[1]
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
