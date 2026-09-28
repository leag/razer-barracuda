.pragma library

// Device identity is presentation only, never evidence of a wireless link.
function icon(sink) {
    if (!sink || sink.name === "auto_null")
        return "audio-card";
    var props = sink.properties || {};
    var components = String(props["alsa.components"] || "");
    if (/(^| )USB1532:0552( |$)/i.test(components)
            || (String(props["device.vendor.id"]).toLowerCase() === "0x1532"
                && String(props["device.product.id"]).toLowerCase() === "0x0552"))
        return "audio-headphones";
    if (sink.formFactor === "headphone" || sink.formFactor === "headset")
        return "audio-headphones";
    var ports = sink.ports || [];
    var port = ports[sink.activePortIndex];
    if (port && /headphone|headset/.test(port.name))
        return "audio-headphones";
    return sink.iconName || "audio-speakers";
}

function text(english, spanish, locale) {
    return /^es([_-]|$)/i.test(locale) ? spanish : english;
}

// Select KDE Breeze's detailed variants, not its small monochrome variants.
// Files remain owned by breeze-icons; no theme artwork is copied into this package.
function artwork(iconName) {
    if (/^audio-(headphones|headset)(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-headphones.svg";
    if (/^audio-speakers(-|$)/.test(iconName))
        return "file:///usr/share/icons/breeze/devices/64/audio-speakers.svg";
    return iconName;
}
