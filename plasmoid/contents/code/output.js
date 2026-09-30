.pragma library

function available(sink) {
    return Boolean(sink) && sink.name !== "auto_null";
}

function audioCommand(request) {
    // Quote JSON as one POSIX shell argument, including user profile names.
    return "barracuda-audio --request '" + JSON.stringify(request).replace(/'/g, "'\\''") + "'";
}

function headsetCommand(request, sink) {
    const command = Object.assign({}, request);
    if (bluetooth(sink)) {
        command.transport = "bluetooth";
        command.address = bluetoothAddress(sink);
    }
    return "barracuda-headset --request '" + JSON.stringify(command).replace(/'/g, "'\\''") + "'";
}

function pairingCommand(locale) {
    // Called only after explicit confirmation in the native UI.
    return "barracuda-pair --yes --timeout 60 --language "
        + (/^es([_-]|$)/i.test(locale) ? "es" : "en");
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

function deviceName(sink, locale) {
    if (!available(sink))
        return text("No audio output", "Sin salida de audio", locale);
    const name = sink.description || sink.name;
    return bluetooth(sink) && name === "Razer Barracuda X (BT)" ? "Razer Barracuda X" : name;
}

function battery(data, sources, sink) {
    const preferred = bluetooth(sink) ? "Razer Barracuda X (BT)" : "Razer Barracuda X (2022)";
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

function volumePercent(sink) {
    if (!available(sink) || typeof sink.volume !== "number"
            || !isFinite(sink.volume) || sink.volume < 0)
        return null;
    // PulseAudio's PA_VOLUME_NORM is 65536; amplification may exceed 100%.
    return Math.round(sink.volume * 100 / 65536);
}

function status(sink, locale) {
    if (!available(sink))
        return text("No audio output", "Sin salida de audio", locale);
    var volume = volumePercent(sink);
    var level = volume === null
        ? text("Volume unavailable", "Volumen no disponible", locale)
        : text("Volume: ", "Volumen: ", locale) + volume + "%";
    return sink.muted ? text("Muted", "Silenciado", locale) + " · " + level : level;
}

// Device identity is presentation only, never evidence of a wireless link.
function icon(sink) {
    if (!sink || sink.name === "auto_null")
        return "audio-card";
    var props = sink.properties || {};
    var components = String(props["alsa.components"] || "");
    if (/(^| )USB1532:0552( |$)/i.test(components)
            || (String(props["device.vendor.id"]).toLowerCase() === "0x1532"
                && String(props["device.product.id"]).toLowerCase() === "0x0552"))
        return "audio-headset";
    if (bluetooth(sink) && (sink.description === "Razer Barracuda X (BT)"
            || props["device.icon_name"] === "audio-headset"))
        return "audio-headset";
    if (sink.formFactor === "headphone" || sink.formFactor === "headset")
        return "audio-headset";
    var ports = sink.ports || [];
    var port = ports[sink.activePortIndex];
    if (port && /headphone|headset/.test(port.name))
        return "audio-headset";
    return sink.iconName || "audio-speakers";
}

function text(english, spanish, locale) {
    return /^es([_-]|$)/i.test(locale) ? spanish : english;
}

// Select KDE Breeze's detailed variants, not its small monochrome variants.
// Files remain owned by breeze-icons; no theme artwork is copied into this package.
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
