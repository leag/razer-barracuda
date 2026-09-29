.pragma library

function available(sink) {
    return Boolean(sink) && sink.name !== "auto_null";
}

function audioCommand(request) {
    // Quote JSON as one POSIX shell argument, including user profile names.
    return "barracuda-audio --request '" + JSON.stringify(request).replace(/'/g, "'\\''") + "'";
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

function battery(data, sources) {
    for (const source of sources) {
        const item = data[source];
        if (!item || item["Is Power Supply"] !== false || item.Type !== "Headset"
                || item.Product !== "Razer Barracuda X (2022)" || item["Plugged in"] !== true)
            continue;
        const percent = item.Percent;
        if (typeof percent !== "number" || !isFinite(percent) || percent < 0 || percent > 100)
            return null;
        // KDE can expose zero when the underlying percentage is unavailable.
        if (percent === 0 && item.State === "Unknown")
            return null;
        return {percent: Math.round(percent), state: item.State};
    }
    return null;
}

function batteryText(value, locale) {
    if (!value)
        return text("Battery unavailable", "Batería no disponible", locale);
    const level = value.percent + "%";
    switch (value.state) {
    case "Charging":
        return level + " · " + text("Charging", "Cargando", locale);
    case "FullyCharged":
        return level + " · " + text("Fully charged", "Carga completa", locale);
    case "Discharging":
        return level + " · " + text("On battery", "Con batería", locale);
    default:
        return level + " · " + text("Charge state unknown", "Estado de carga desconocido", locale);
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
