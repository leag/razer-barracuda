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
// destroys a configuration page, and kills its shell, as soon as OK closes
// the window or another category replaces it. The chain therefore runs in a
// background subshell that finishes on its own and writes to a private file;
// the waiting shell reports the reply when it is still there to read it. The
// file is unlinked before the chain starts and read through a descriptor
// opened beforehand, so nothing is left behind when the shell is killed.
function headsetChainCommand(requests, target) {
    const chain = requests.map(request => headsetCommand(request, target)).join(" && ");
    return "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\") || exit 1; exec 3>\"$f\" 4<\"$f\"; rm -f \"$f\"; ("
        + chain + ") >&3 3>&- 4<&- 2>/dev/null & exec 3>&-; wait $!; s=$?; tail -n 1 <&4; exit $s";
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

// The state, with the transport for a screen reader; the tooltip names the
// transport as a separate fact.
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

function voltageText(millivolts, locale) {
    const volts = (millivolts / 1000).toFixed(2);
    return (/^es([_-]|$)/i.test(locale) ? volts.replace(".", ",") : volts) + " V";
}

// Key/value rows of the headset card's details, empty until a status has been
// read: the dongle, its 2.4 GHz link, Bluetooth, and with a confirmed dongle
// link the charging cable and voltage; then the charge state when the card's
// line leaves it out.
function detailRows(status, battery, locale) {
    if (!status || !status.ok)
        return [];
    const usb = status.usb;
    const rows = [[text("USB dongle", "Dongle USB", locale),
        usb.adapter === "present" ? text("Detected", "Detectado", locale)
            : usb.adapter === "multiple" ? text("More than one", "Más de uno", locale)
            : text("Not detected", "No detectado", locale)]];
    if (usb.adapter === "present")
        rows.push([text("2.4 GHz link", "Enlace 2,4 GHz", locale),
            !usb.driver ? text("Driver required", "Requiere driver", locale)
                : usb.link === "connected" ? text("Connected", "Conectado", locale)
                : usb.link === "disconnected" ? text("Disconnected", "Desconectado", locale)
                : text("Not confirmed", "No confirmado", locale)]);
    const bt = status.bluetooth;
    if (bt)
        rows.push(["Bluetooth", bt.state === "connected" ? text("Connected", "Conectado", locale)
            : bt.state === "disconnected" ? text("Not connected", "No conectado", locale)
            : text("Unknown", "Desconocido", locale)]);
    // Retained values are not shown as current without a confirmed link.
    const reading = usb.adapter === "present" && usb.link === "connected" ? usb.battery : null;
    if (reading) {
        rows.push([text("Charging cable", "Cable de carga", locale),
            reading.cable === true ? text("Connected", "Conectado", locale)
                : reading.cable === false ? text("Not connected", "No conectado", locale)
                : text("Unknown", "Desconocido", locale)]);
        if (typeof reading.voltage_mv === "number" && reading.voltage_mv > 0)
            rows.push([text("Battery voltage", "Voltaje de batería", locale), voltageText(reading.voltage_mv, locale)]);
    }
    if (battery && battery.state === "Discharging")
        rows.push([text("Charge", "Carga", locale), text("On battery", "Con batería", locale)]);
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

// Emblem of the panel and tray glyph: an unconfirmed or unreadable state, or
// a low battery.
function emblem(value, battery) {
    if (value.state === "unknown" || value.state === "unavailable")
        return "emblem-question";
    if (value.state === "connected" && lowBattery(battery))
        return "emblem-warning";
    return "";
}

// The tray icon never hides itself (never Passive): without a link the popup
// is where the user pairs. A low battery asks for attention.
function trayStatus(value, battery) {
    return value.state === "connected" && lowBattery(battery) ? "attention" : "active";
}

// Pairing and power-off need the dongle. Only a confirmed missing adapter
// disables them; unknown, unavailable and checking states never do.
function adapterMissing(status) {
    return status !== null && status !== undefined && status.ok === true
        && status.usb.adapter === "missing";
}

// Result of a finished barracuda-pair run, from the executable engine's data.
// The popup gets a plain sentence naming what the user can check; the
// technical cause (exit code, helper output) is in "details", for the
// journal, never for the popup.
function pairingOutcome(data, locale) {
    if (data["exit code"] === 0)
        return {ok: true, details: "", text: text("Paired. Turn the headset off and on to start the link.",
                                                  "Emparejado. Apaga y enciende el auricular para iniciar la conexión.", locale)};
    return {ok: false, details: commandDetails("barracuda-pair", data), text: text(
        "Couldn't pair. Check the USB dongle and that the headset is in pairing mode.",
        "No se pudo emparejar. Revisa el dongle USB y que el auricular esté en modo de emparejamiento.", locale)};
}

// Result of a finished barracuda-power run. Success says nothing: the next
// status reading shows the headset off.
function powerOutcome(data, locale) {
    if (data["exit code"] === 0)
        return {ok: true, details: "", text: ""};
    return {ok: false, details: commandDetails("barracuda-power", data), text: text(
        "Couldn't turn off the headset. Check the USB dongle.",
        "No se pudo apagar el auricular. Revisa el dongle USB.", locale)};
}

// One journal line for a failed helper run.
function commandDetails(name, data) {
    const output = (String(data.stdout || "").trim() + " " + String(data.stderr || "").trim()).trim();
    return name + " exited with " + data["exit code"] + (output ? ": " + output : "");
}

// The More actions entries, chosen as the system tray chooses them: visible,
// normal-priority actions other than Plasma's own configure action, with a
// separator kept only between two entries.
function moreActions(actions, configure, normalPriority) {
    const candidates = Array.from(actions || []).filter(action => action && action.visible
        && action.priority === normalPriority && action !== configure);
    return candidates.reduce((entries, action, index) => {
        if (!action.isSeparator) {
            const previous = candidates[index - 1];
            if (previous && previous.isSeparator && entries.length > 0)
                entries.push(previous);
            entries.push(action);
        }
        return entries;
    }, []);
}

// The heading's icon buttons: high-priority actions, as the tray draws them.
function primaryActions(actions, highPriority) {
    return Array.from(actions || []).filter(action => action && !action.isSeparator
        && action.priority === highPriority);
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

function text(english, spanish, locale) {
    return /^es([_-]|$)/i.test(locale) ? spanish : english;
}

// Bluetooth addresses arrive as 12 hex digits; show them as AA:BB:CC:DD:EE:FF.
function macAddress(address) {
    const hex = String(address || "").replace(/[^0-9a-fA-F]/g, "");
    if (hex.length !== 12)
        return String(address || "");
    return hex.toUpperCase().match(/../g).join(":");
}

// Select KDE Breeze's detailed variants, not its small monochrome variants.
// Files remain owned by breeze-icons; no theme artwork is copied into this package.
function artwork(iconName) {
    if (/^audio-(headphones|headset)(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-headset.svg";
    if (/^audio-speakers(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-speakers.svg";
    if (iconName === "drive-removable-media-usb")
        return "file:///usr/share/icons/breeze/devices/64/drive-removable-media-usb.svg";
    return iconName;
}

function powerOffCommand(locale) {
    return "barracuda-power --off --yes --language " + (String(locale).toLowerCase().startsWith("es") ? "es" : "en");
}

// A percentage as each language writes it: "80%" in English, "80 %" with a
// no-break space in Spanish, as KDE's Spanish catalogue does.
function percentText(value, locale) {
    return /^es([_-]|$)/i.test(locale) ? value + " %" : value + "%";
}

// Ten percent or less and not on the charger.
function lowBattery(value) {
    return value !== null && value !== undefined && value.percent <= 10
        && !["Charging", "FullyCharged"].includes(value.state);
}

// The charge words after the transport. A discharging battery adds nothing,
// since the percentage and the bar already say it, unless it is low.
function chargeNote(value, locale) {
    if (!value)
        return text("Battery unavailable", "Batería no disponible", locale);
    if (value.state === "Charging")
        return text("Charging", "Cargando", locale);
    if (value.state === "FullyCharged")
        return text("Fully charged", "Carga completa", locale);
    if (lowBattery(value))
        return text("Low battery", "Batería baja", locale);
    return "";
}

// The transport in the middle of a sentence.
function transportPhrase(transport, locale) {
    switch (transport) {
    case "usb":
        return text("USB dongle", "dongle USB", locale);
    case "both":
        return text("USB dongle and Bluetooth", "dongle USB y Bluetooth", locale);
    default:
        return transportText(transport, locale);
    }
}

// The headset card's words for a confirmed link: the state (or the command
// running on the headset), the percentage beside it, the line under the
// battery bar and one sentence for screen readers.
function hero(value, battery, turningOff, locale) {
    const note = chargeNote(battery, locale);
    const headline = turningOff ? text("Turning off…", "Apagando…", locale) : text("Connected", "Conectado", locale);
    const spoken = [headline];
    if (battery)
        spoken.push(text("%1 battery", "%1 de batería", locale).replace("%1", percentText(battery.percent, locale)));
    spoken.push(transportPhrase(value.transport, locale));
    if (note)
        spoken.push(note.toLowerCase());
    return {
        headline: headline,
        percent: battery ? percentText(battery.percent, locale) : "",
        line: transportText(value.transport, locale) + (note ? " · " + note : ""),
        accessible: spoken.join(", ")
    };
}

// Transport glyphs drawn beside the card's artwork, bottom first: the USB
// dongle, then Bluetooth above it when both links are confirmed.
function transportEmblems(value) {
    if (value.state !== "connected")
        return [];
    if (value.transport === "both")
        return ["drive-removable-media-usb-symbolic", "network-bluetooth-symbolic"];
    return [value.transport === "bluetooth" ? "network-bluetooth-symbolic" : "drive-removable-media-usb-symbolic"];
}

// The whole-view message for every state without a confirmed link, and for
// pairing, which replaces the link. Each state has its own words and its own
// artwork treatment: which artwork, dimmed or not, which state emblem, and
// whether the view waits. A power-off running without a confirmed link waits
// here too; with one, the headset card says it.
function placeholder(status, value, battery, pairing, turningOff, locale) {
    const headset = "audio-headset";
    if (pairing)
        return {state: "pairing", artwork: headset, dimmed: false, emblem: "", busy: true,
                title: text("Pairing…", "Emparejando…", locale),
                explanation: text("Keep the headset in pairing mode. This can take up to a minute.",
                                  "Mantén el auricular en modo de emparejamiento. Puede tardar hasta un minuto.", locale)};
    if (turningOff && value.state !== "connected")
        return {state: "turning-off", artwork: headset, dimmed: false, emblem: "", busy: true,
                title: text("Turning off…", "Apagando…", locale), explanation: ""};
    switch (value.state) {
    case "connected":
        return {state: "connected", artwork: headset, dimmed: false, emblem: "", busy: false, title: "", explanation: ""};
    case "disconnected":
        return {state: "disconnected", artwork: headset, dimmed: true, emblem: "", busy: false,
                title: text("Disconnected", "Desconectado", locale),
                explanation: adapterMissing(status)
                    ? text("Turn on the headset or plug in the USB dongle.",
                           "Enciende el auricular o conecta el dongle USB.", locale)
                    : text("Turn on the headset.", "Enciende el auricular.", locale)};
    case "unknown": {
        let explanation;
        if (status.usb.adapter === "multiple")
            explanation = text("More than one Barracuda USB dongle is plugged in. Leave only one.",
                               "Hay más de un dongle USB Barracuda conectado. Deja solo uno.", locale);
        else if (status.usb.driver === false)
            explanation = text("Install or update the Barracuda driver.",
                               "Instala o actualiza el driver del Barracuda.", locale);
        else
            explanation = text("The headset may still be on.", "El auricular puede seguir encendido.", locale);
        if (battery)
            explanation += " " + text("Last battery reading: %1.", "Última lectura de batería: %1.", locale)
                .replace("%1", percentText(battery.percent, locale));
        return {state: "unknown", artwork: headset, dimmed: false, emblem: "emblem-question", busy: false,
                title: text("Link not confirmed", "Conexión no confirmada", locale), explanation: explanation};
    }
    case "no-adapter":
        // The missing object is the dongle, so the dongle is what is shown.
        return {state: "no-adapter", artwork: "drive-removable-media-usb", dimmed: true, emblem: "", busy: false,
                title: text("USB dongle not detected", "Dongle USB no detectado", locale),
                explanation: text("Plug in the dongle, or use the headset over Bluetooth.",
                                  "Conecta el dongle o usa el auricular por Bluetooth.", locale)};
    case "unavailable":
        // What the user does, not which helper failed.
        return {state: "unavailable", artwork: headset, dimmed: false, emblem: "emblem-warning", busy: false,
                title: text("Status unavailable", "Estado no disponible", locale),
                explanation: text("Install or update the barracuda-pair package.",
                                  "Instala o actualiza el paquete barracuda-pair.", locale)};
    default:
        return {state: "checking", artwork: headset, dimmed: true, emblem: "", busy: true,
                title: text("Checking…", "Comprobando…", locale), explanation: ""};
    }
}

// The tooltip's sub text: one line of facts joined with " · ", as the
// Bluetooth applet writes it.
function toolTip(value, battery, locale) {
    const parts = [connectionText(value, locale, false)];
    if (value.state === "connected")
        parts.push(transportText(value.transport, locale));
    if (battery)
        parts.push(text("%1 Battery", "%1 de batería", locale).replace("%1", percentText(battery.percent, locale)));
    const note = value.state === "connected" && battery ? chargeNote(battery, locale) : "";
    if (note)
        parts.push(note);
    return parts.join(" · ");
}

// A popup setting in the middle of a sentence.
function settingName(feature, locale) {
    return ({dnd: text("the Do not disturb setting", "el ajuste No molestar", locale),
             gaming: text("Bluetooth gaming mode", "el modo gaming Bluetooth", locale),
             devices: text("the list of Bluetooth devices", "la lista de dispositivos Bluetooth", locale)})[feature] || "";
}

// Error codes after which the user has something to do; the others (a
// headset that did not answer, an unexpected reply) only need a retry.
function actionableError(code) {
    return ["driver-required", "permission-denied", "helper-missing", "bluetooth-runtime-unavailable",
            "route-failed", "missing-adapter", "busy", "bluetooth-unsupported"].includes(code);
}

// The popup's feedback for a failed settings request: "feature" is the
// setting a change was for, or empty for the read of every setting. A read
// adds the reason only when the user can act on it; a change always does.
function settingsFailure(feature, code, reason, locale) {
    if (feature === "")
        return text("Couldn't read the headset.", "No se pudo leer el auricular.", locale)
            + (actionableError(code) ? " " + reason : "");
    const change = {dnd: text("Couldn't change the Do not disturb setting.", "No se pudo cambiar el ajuste No molestar.", locale),
                    gaming: text("Couldn't change Bluetooth gaming mode.", "No se pudo cambiar el modo gaming Bluetooth.", locale),
                    devices: text("Couldn't switch devices.", "No se pudo cambiar de dispositivo.", locale)}[feature]
        || text("Couldn't change the setting.", "No se pudo cambiar el ajuste.", locale);
    return change + " " + reason;
}

// The settings one reading could not return.
function readFailure(features, locale) {
    if (features.length !== 1)
        return text("Couldn't read some settings.", "No se pudieron leer algunos ajustes.", locale);
    return text("Couldn't read %1.", "No se pudo leer %1.", locale).replace("%1", settingName(features[0], locale));
}

// The one line under the Bluetooth Devices heading, when there is one.
function devicesNote(devices, reading, gaming, locale) {
    if (devices === null)
        return reading ? text("Reading…", "Leyendo…", locale) : "";
    if (devices.length === 0)
        return text("No known devices.", "Sin dispositivos conocidos.", locale);
    if (gaming === true)
        return text("Turn off Bluetooth gaming mode to switch devices.",
                    "Desactiva el modo gaming Bluetooth para cambiar de dispositivo.", locale);
    if (gaming !== false)
        return text("Switching devices needs Bluetooth gaming mode to be read first.",
                    "Para cambiar de dispositivo, primero hay que leer el modo gaming Bluetooth.", locale);
    return "";
}
