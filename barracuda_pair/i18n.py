"""Explicit English/Spanish CLI translations; English is the default."""

LANGUAGE = "en"
SPANISH = {'Adapter not detected': 'Adaptador no detectado',
 'HID permission denied': 'Sin permisos HID',
 'The adapter did not answer the handshake': 'El adaptador no respondió al saludo inicial',
 'Unexpected handshake reply: {reply}': 'Respuesta inesperada al saludo inicial: {reply}',
 'No response to command {frame}': 'Sin respuesta al comando {frame}',
 'The adapter rejected command {frame}': 'El adaptador rechazó el comando {frame}',
 'Short write to the adapter': 'Escritura incompleta en el adaptador',
 'The adapter is not in local mode ({mode}); aborting': 'El adaptador no está en modo local '
                                                        '({mode}); se cancela',
 'Adapter model data: {model}': 'Datos de modelo del adaptador: {model}',
 'Found {name} {address} (class 0x{device_class:06X}, {rssi} dBm)': 'Encontrado {name} {address} '
                                                                    '(clase 0x{device_class:06X}, '
                                                                    '{rssi} dBm)',
 'No Bluetooth devices were found': 'No se encontraron dispositivos Bluetooth',
 'Put the headset in pairing mode now': 'Pon los audífonos en modo de emparejamiento ahora',
 'No Barracuda headset in pairing mode was found': 'No se encontraron audífonos Barracuda en modo '
                                                   'de emparejamiento',
 'Pairing with {name} {address}…': 'Emparejando con {name} {address}…',
 'Paired. Turn the headset off and on to start the link': 'Emparejados. Apaga y enciende los '
                                                          'audífonos para iniciar el enlace',
 'Connection status: 0x{status:02X}': 'Estado de conexión: 0x{status:02X}',
 'The headset did not connect': 'Los audífonos no se enlazaron',
 'Pair the dongle with a headset? This replaces its current pairing. [y/N] ': '¿Emparejar el '
                                                                              'adaptador con unos '
                                                                              'audífonos? '
                                                                              'Reemplaza el '
                                                                              'emparejamiento '
                                                                              'actual. [s/N] ',
 'Pairing failed: {error}': 'Falló el emparejamiento: {error}',
 'Pairing cancelled': 'Emparejamiento cancelado'}

SPANISH.update({
 'More than one Barracuda adapter is connected': 'Hay más de un adaptador Barracuda conectado',
 'Update the Barracuda driver to enable headset power-off': 'Actualiza el driver Barracuda para habilitar el apagado de los auriculares',
 'Power-off permission denied; install the power-control udev rule': 'Sin permiso para apagar; instala la regla udev de control de energía',
 'Another headset operation is in progress; try again shortly': 'Hay otra operación en curso; vuelve a intentarlo en unos segundos',
 'The headset link is not confirmed; no power-off command was sent': 'El enlace no está confirmado; no se envió el comando de apagado',
 'The adapter did not answer; headset state is unknown': 'El adaptador no respondió; el estado de los auriculares es desconocido',
 'Power control failed; inspect the headset and reconnect the dongle if needed': 'Falló el control de energía; comprueba los auriculares y reconecta el adaptador si es necesario',
 'Turn off the Barracuda headset? Use its button to turn it on again. [y/N] ': '¿Apagar los auriculares Barracuda? Usa su botón para encenderlos de nuevo. [s/N] ',
 'Power-off cancelled': 'Apagado cancelado',
 'Power control interrupted; check the headset state before trying again': 'Control de energía interrumpido; comprueba el estado antes de volver a intentarlo',
 'Power-off request sent. Use the headset button to turn it on again.': 'Solicitud de apagado enviada. Usa el botón de los auriculares para encenderlos de nuevo.',
})

def set_language(language):
    global LANGUAGE
    if language not in ("en", "es"):
        raise ValueError(f"Unsupported language: {language}")
    LANGUAGE = language


def tr(message, **values):
    return (SPANISH.get(message, message) if LANGUAGE == "es" else message).format(**values)
