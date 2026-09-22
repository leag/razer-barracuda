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
 'The previous audio output is unavailable': 'La salida anterior no está disponible'}


def set_language(language):
    global LANGUAGE
    if language not in ("en", "es"):
        raise ValueError(f"Unsupported language: {language}")
    LANGUAGE = language


def tr(message, **values):
    return (SPANISH.get(message, message) if LANGUAGE == "es" else message).format(**values)
