"""Explicit English/Spanish UI translations; English is the default."""

LANGUAGE = "en"
SPANISH = {'Razer Barracuda X: waiting for a valid connection response': 'Razer Barracuda X: esperando una respuesta válida de conexión',
 'The adapter stopped responding': 'El adaptador dejó de responder',
 'Automatic audio switching enabled': 'Cambio automático de salida activado',
 'Could not switch output: {error}': 'No se pudo cambiar la salida: {error}',
 'Razer Barracuda X: waiting for link status': 'Razer Barracuda X: esperando estado de enlace',
 'Checking…': 'Consultando…',
 'Quit': 'Salir',
 'Adapter not detected': 'Adaptador no detectado',
 'Razer Barracuda X: adapter not detected': 'Razer Barracuda X: adaptador no detectado',
 'Adapter connected; link unconfirmed': 'Adaptador conectado; enlace sin confirmar',
 'Razer Barracuda X: waiting for a report; turn the headset off and on': 'Razer Barracuda X: '
                                                                         'esperando un reporte; '
                                                                         'apaga y enciende los '
                                                                         'audífonos',
 'Connected': 'Enlazados',
 'Razer Barracuda X: headset connected': 'Razer Barracuda X: audífonos enlazados',
 'Disconnected': 'No enlazados',
 'Razer Barracuda X: headset disconnected': 'Razer Barracuda X: audífonos no enlazados',
 'Could not read the adapter': 'Error al leer el adaptador',
 'HID permission denied': 'Sin permisos HID',
 'Install the included udev rule and log in again': 'Añade la regla udev incluida y vuelve a '
                                                    'iniciar sesión',
 'No system tray is available': 'No hay bandeja del sistema disponible en KDE',
 'The Barracuda audio output is not available yet': 'La salida de audio de los Barracuda todavía '
                                                    'no está disponible',
 'The previous audio output is unavailable': 'La salida anterior no está disponible',
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
                                                                              'audífonos? Reemplaza '
                                                                              'el emparejamiento '
                                                                              'actual. [s/N] ',
 'Pairing failed: {error}': 'Falló el emparejamiento: {error}',
 'Pairing cancelled': 'Emparejamiento cancelado',
 'Pair headset…': 'Emparejar audífonos…',
 'Pair headset': 'Emparejar audífonos',
 'Pairing…': 'Emparejando…',
 "This replaces the dongle's current pairing. Put the headset in pairing mode, then press "
 'Yes. Scanning lasts up to 60 seconds.': 'Esto reemplaza el emparejamiento actual del '
                                          'adaptador. Pon los audífonos en modo de '
                                          'emparejamiento y pulsa Sí. La búsqueda dura hasta '
                                          '60 segundos.'}


def set_language(language):
    global LANGUAGE
    if language not in ("en", "es"):
        raise ValueError(f"Unsupported language: {language}")
    LANGUAGE = language


def tr(message, **values):
    return (SPANISH.get(message, message) if LANGUAGE == "es" else message).format(**values)
