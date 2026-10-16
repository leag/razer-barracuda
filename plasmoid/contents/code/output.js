.pragma library

function headsetCommand(request, target) {
    const command = Object.assign({}, request);
    if (target && target.transport === "bluetooth") {
        command.transport = "bluetooth";
        command.address = target.address || "";
    }
    // Quote JSON as one POSIX shell argument.
    return "barracuda-headset --request '" + JSON.stringify(command).replace(/'/g, "'\\''") + "'";
}

// Set requests from the configuration window, run in order: each starts only
// after the previous one succeeded, and the last reply is printed. Plasma
// destroys a configuration page, and ends its process, as soon as OK closes
// the window or another category replaces it. The chain therefore runs in a
// background subshell that writes to a private file and finishes on its own;
// the waiting shell reports the reply when it is still there to read it.
function headsetChainCommand(requests, target) {
    const chain = requests.map(request => headsetCommand(request, target)).join(" && ");
    return "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\") || exit 1; (" + chain + ") > \"$f\" 2>/dev/null & "
        + "wait $!; s=$?; tail -n 1 \"$f\"; rm -f \"$f\"; exit $s";
}

// Finite, read-only query of the driver's published link and BlueZ; no HID access.
function linkCommand() {
    return "barracuda-headset --request '{\"op\":\"link\"}'";
}

function parseLink(stdout) {
    let result;
    try {
        result = JSON.parse(stdout);
    } catch (e) {
        return {ok: false};
    }
    // Older helpers reject the link operation; treat any other shape as unavailable.
    if (!result || result.ok !== true || typeof result.usb !== "object" || result.usb === null)
        return {ok: false};
    return result;
}

// Only the driver's link report and BlueZ's connection are link evidence. The
// default output, device icons and battery presence are not.
function connection(status) {
    if (!status)
        return {state: "checking", transport: ""};
    if (!status.ok)
        return {state: "unavailable", transport: ""};
    const usb = status.usb;
    const bt = status.bluetooth || null;
    const usbLinked = usb.adapter === "present" && usb.link === "connected";
    const btLinked = bt !== null && bt.state === "connected";
    if (usbLinked || btLinked)
        return {state: "connected", transport: usbLinked && btLinked ? "both" : usbLinked ? "usb" : "bluetooth"};
    if (usb.adapter === "present")
        return {state: usb.link === "disconnected" ? "disconnected" : "unknown", transport: "usb"};
    if (usb.adapter === "multiple")
        return {state: "unknown", transport: "usb"};
    if (bt !== null && bt.state === "disconnected")
        return {state: "disconnected", transport: "bluetooth"};
    return {state: "no-adapter", transport: ""};
}

function transportText(transport, locale) {
    switch (transport) {
    case "usb":
        return text("USB dongle", "Dongle USB", locale);
    case "bluetooth":
        return "Bluetooth";
    case "both":
        return text("USB dongle and Bluetooth", "Dongle USB y Bluetooth", locale);
    default:
        return "";
    }
}

// The popup omits the transport, which its icon shows; tooltips keep it.
function connectionText(value, locale, withTransport = true) {
    switch (value.state) {
    case "connected":
        return text("Connected", "Conectado", locale)
            + (withTransport ? " · " + transportText(value.transport, locale) : "");
    case "disconnected":
        return text("Disconnected", "Desconectado", locale);
    case "unknown":
        return text("Link not confirmed", "Conexión no confirmada", locale);
    case "no-adapter":
        return text("USB dongle not detected", "Dongle USB no detectado", locale);
    case "unavailable":
        return text("Status unavailable", "Estado no disponible", locale);
    default:
        return text("Checking…", "Comprobando…", locale);
    }
}

function connectionHint(status, value, locale) {
    switch (value.state) {
    case "disconnected":
        if (adapterMissing(status))
            return text("Turn the headset on. To pair it with the USB dongle, connect the dongle first.",
                        "Enciende el auricular. Para emparejarlo con el dongle USB, conecta primero el dongle.", locale);
        return text("Turn the headset on. If it does not connect, use Pair USB Dongle.",
                    "Enciende el auricular. Si no se conecta, usa Emparejar dongle USB.", locale);
    case "unknown":
        if (status.usb.adapter === "multiple")
            return text("More than one Barracuda USB dongle is connected. Connect only one.",
                        "Hay más de un dongle USB Barracuda conectado. Conecta solo uno.", locale);
        if (status.usb.driver === false)
            return text("Install or update the Barracuda driver to read the link state.",
                        "Instala o actualiza el driver del Barracuda para leer el estado de la conexión.", locale);
        return text("The dongle has not confirmed the link yet. This does not mean the headset is disconnected.",
                    "El dongle aún no confirma la conexión. Esto no significa que el auricular esté desconectado.", locale);
    case "no-adapter":
        return text("Connect the USB dongle, or connect the headset over Bluetooth.",
                    "Conecta el dongle USB o conecta el auricular por Bluetooth.", locale);
    case "unavailable":
        return text("Connection status requires an updated barracuda-headset on PATH.",
                    "El estado de la conexión requiere barracuda-headset actualizado en PATH.", locale);
    default:
        return "";
    }
}

function voltageText(millivolts, locale) {
    const volts = (millivolts / 1000).toFixed(2);
    return (/^es([_-]|$)/i.test(locale) ? volts.replace(".", ",") : volts) + " V";
}

// Label/value/icon rows for the details list; empty until a status has been read.
function connectionDetails(status, locale) {
    if (!status || !status.ok)
        return [];
    const usb = status.usb;
    const rows = [[text("USB dongle", "Dongle USB", locale),
        usb.adapter === "present" ? text("Detected", "Detectado", locale)
            : usb.adapter === "multiple" ? text("More than one", "Más de uno", locale)
            : text("Not detected", "No detectado", locale),
        "drive-removable-media-usb-pendrive-symbolic"]];
    if (usb.adapter === "present")
        rows.push([text("2.4 GHz link", "Enlace 2,4 GHz", locale),
            !usb.driver ? text("Driver required", "Requiere driver", locale)
                : usb.link === "connected" ? text("Connected", "Conectado", locale)
                : usb.link === "disconnected" ? text("Disconnected", "Desconectado", locale)
                : text("Not confirmed", "No confirmado", locale),
            "network-wireless-symbolic"]);
    const bt = status.bluetooth;
    if (bt)
        rows.push(["Bluetooth", bt.state === "connected" ? text("Connected", "Conectado", locale)
            : bt.state === "disconnected" ? text("Not connected", "No conectado", locale)
            : text("Unknown", "Desconocido", locale),
            "network-bluetooth-symbolic"]);
    const battery = usb.adapter === "present" && usb.link === "connected" ? usb.battery : null;
    if (battery) {
        rows.push([text("Charging cable", "Cable de carga", locale),
            battery.cable === true ? text("Connected", "Conectado", locale)
                : battery.cable === false ? text("Not connected", "No conectado", locale)
                : text("Unknown", "Desconocido", locale),
            // The charging glyph only while the cable is known to be connected.
            battery.cable === true ? "battery-full-charging-symbolic" : "battery-full-symbolic"]);
        if (typeof battery.voltage_mv === "number" && battery.voltage_mv > 0)
            rows.push([text("Battery voltage", "Voltaje de batería", locale),
                       voltageText(battery.voltage_mv, locale), "battery-full-symbolic"]);
    }
    return rows;
}

// The driver's last published reading, used when KDE does not list the battery.
function driverBattery(status) {
    const usb = status && status.ok ? status.usb : null;
    const value = usb && usb.adapter === "present" && usb.link === "connected" ? usb.battery : null;
    if (!value || typeof value.percent !== "number")
        return null;
    const states = {Charging: "Charging", Full: "FullyCharged", Discharging: "Discharging"};
    return {percent: value.percent, state: states[value.status] || "Unknown"};
}

// Native controls follow the confirmed transport; with both or neither confirmed,
// they follow the default output as before.
function headsetTarget(sink, status) {
    const linked = connection(status);
    if (linked.state === "connected" && linked.transport === "usb")
        return {transport: "usb"};
    if (linked.state === "connected" && linked.transport === "bluetooth")
        return {transport: "bluetooth", address: status.bluetooth.address || ""};
    return bluetooth(sink) ? {transport: "bluetooth", address: bluetoothAddress(sink)} : {transport: "usb"};
}

// Icon of the confirmed transport; the USB dongle wins when both are linked.
function transportIcon(value) {
    if (value.state !== "connected")
        return "";
    return value.transport === "bluetooth" ? "network-bluetooth-symbolic"
        : "drive-removable-media-usb-pendrive-symbolic";
}

// Disconnected and missing-adapter states strike the artwork through.
function slashed(value) {
    return value.state === "disconnected" || value.state === "no-adapter";
}

// Corner emblem for an unconfirmed or unreadable state, and for a low battery.
function emblem(value, battery) {
    if (value.state === "unknown" || value.state === "unavailable")
        return "emblem-question";
    if (value.state === "connected" && battery && battery.percent <= 10
            && !["Charging", "FullyCharged"].includes(battery.state))
        return "emblem-warning";
    return "";
}

// System tray visibility. A confirmed or unconfirmed link and a running action
// keep the icon shown; a disconnected headset, a missing adapter and an
// unavailable helper move it to the tray's hidden items. A low battery asks for
// attention.
// The tray icon never hides itself: without a connection the popup holds the
// controls needed to pair. The tray's own visibility setting still wins.
function trayStatus(value, battery) {
    return emblem(value, battery) === "emblem-warning" ? "attention" : "active";
}

// Pairing and power-off need the dongle. Only a confirmed missing adapter
// disables them; unknown, unavailable and checking states never do.
function adapterMissing(status) {
    return status !== null && status !== undefined && status.ok === true
        && status.usb.adapter === "missing";
}

// Result of a finished barracuda-pair run, from the executable engine's data.
function pairingOutcome(data, locale) {
    if (data["exit code"] === 0)
        return {ok: true, text: text("Paired. Turn the headset off and on to start the link.",
                                     "Emparejado. Apaga y enciende el auricular para iniciar la conexión.", locale)};
    const details = (String(data.stdout || "").trim() + "\n" + String(data.stderr || "").trim()).trim();
    return {ok: false, text: text(
        "Pairing failed. Check the USB dongle and HID permissions, and that barracuda-pair is installed on your PATH.",
        "No se pudo emparejar. Comprueba el dongle USB, los permisos HID y que barracuda-pair esté instalado en tu PATH.",
        locale) + "\n" + details};
}

// Result of a finished barracuda-power run.
function powerOutcome(data, locale) {
    if (data["exit code"] === 0)
        return {ok: true, text: text("Power-off request sent. Use the headset button to turn it on again.",
                                     "Solicitud de apagado enviada. Usa el botón del auricular para encenderlo de nuevo.", locale)};
    return {ok: false, text: text("Could not send the power-off request.", "No se pudo enviar la solicitud de apagado.", locale)
        + "\n" + String(data.stderr || data.stdout || "").trim()};
}

// The More actions entries, chosen as the system tray chooses them: visible,
// normal-priority actions other than Plasma's own configure action.
function moreActions(actions, configure, normalPriority) {
    return Array.from(actions || []).filter(action => action && action.visible && !action.isSeparator
        && action.priority === normalPriority && action !== configure);
}

// Plasma action texts carry a keyboard accelerator marker; buttons, tooltips
// and accessible names show them without it.
function actionText(value) {
    return String(value || "").replace(/&(?!&)/g, "");
}

function pairingCommand(locale) {
    // Called only after explicit confirmation in the native UI.
    return "barracuda-pair --yes --timeout 60 --language "
        + (/^es([_-]|$)/i.test(locale) ? "es" : "en");
}

// Changes when a Barracuda battery appears or disappears, not on every reading.
function batteryPresence(data, sources) {
    return sources.filter(source => data[source] && data[source]["Plugged in"] === true
            && ["Razer Barracuda X (2022)", "Razer Barracuda X (BT)"].includes(data[source].Product))
        .map(source => source + ":" + data[source].Product).sort().join("|");
}

function batterySources(sources) {
    // Subscribing to Battery makes the engine discover individual batteries.
    return ["Battery"].concat(sources.filter(source => /^Battery\d+$/.test(source)));
}

function bluetooth(sink) {
    const props = sink ? (sink.properties || {}) : {};
    return props["device.api"] === "bluez5" || props["api.bluez5.address"] !== undefined
        || /^bluez_output[.]/.test(sink ? String(sink.name || "") : "");
}

function bluetoothAddress(sink) {
    const props = sink ? (sink.properties || {}) : {};
    const address = props["api.bluez5.address"] || props["device.string"];
    if (typeof address === "string" && /^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$/i.test(address))
        return address.toUpperCase();
    const match = /^bluez_output[.]((?:[0-9a-f]{2}_){5}[0-9a-f]{2})[.]/i.exec(sink ? sink.name : "");
    return match ? match[1].replace(/_/g, ":").toUpperCase() : "";
}

function battery(data, sources, preferBluetooth) {
    const preferred = preferBluetooth ? "Razer Barracuda X (BT)" : "Razer Barracuda X (2022)";
    const ordered = sources.filter(source => data[source] && data[source].Product === preferred)
        .concat(sources.filter(source => !data[source] || data[source].Product !== preferred));
    for (const source of ordered) {
        const item = data[source];
        if (!item || item["Is Power Supply"] !== false || item.Type !== "Headset"
                || !["Razer Barracuda X (2022)", "Razer Barracuda X (BT)"].includes(item.Product)
                || item["Plugged in"] !== true)
            continue;
        const percent = item.Percent;
        if (typeof percent !== "number" || !isFinite(percent) || percent < 0 || percent > 100)
            continue;
        // KDE can expose zero when the underlying percentage is unavailable.
        if (percent === 0 && item.State === "Unknown")
            continue;
        return {percent: Math.round(percent), state: item.State};
    }
    return null;
}

function batteryText(value, locale) {
    if (!value)
        return text("Battery unavailable", "Batería no disponible", locale);
    return value.percent + "% · " + batteryState(value, locale);
}

function batteryState(value, locale) {
    if (!value)
        return text("Battery unavailable", "Batería no disponible", locale);
    switch (value.state) {
    case "Charging":
        return text("Charging", "Cargando", locale);
    case "FullyCharged":
        return text("Fully charged", "Carga completa", locale);
    case "Discharging":
        return text("On battery", "Con batería", locale);
    default:
        return text("Charge state unknown", "Estado de carga desconocido", locale);
    }
}

function text(english, spanish, locale) {
    return /^es([_-]|$)/i.test(locale) ? spanish : english;
}

// Select KDE Breeze's detailed variants, not its small monochrome variants.
// Files remain owned by breeze-icons; no theme artwork is copied into this package.
// Bluetooth addresses arrive as 12 hex digits; show them as AA:BB:CC:DD:EE:FF.
function macAddress(address) {
    const hex = String(address || "").replace(/[^0-9a-fA-F]/g, "");
    if (hex.length !== 12)
        return String(address || "");
    return hex.toUpperCase().match(/../g).join(":");
}

function artwork(iconName) {
    if (/^audio-(headphones|headset)(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-headset.svg";
    if (/^audio-speakers(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-speakers.svg";
    return iconName;
}

function powerOffCommand(locale) {
    return "barracuda-power --off --yes --language " + (String(locale).toLowerCase().startsWith("es") ? "es" : "en");
}
