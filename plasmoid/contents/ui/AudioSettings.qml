import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

ColumnLayout {
    id: page
    objectName: "audioSettings"
    required property var controller
    property var draft: null
    property string section: "output"
    readonly property string target: section === "microphone" ? "microphone" : "output"
    onSectionChanged: {
        profileName = findProfile();
        restartConfirmation = false;
        showBands = false;
        showProfiles = false;
        if (scroller.contentItem)
            scroller.contentItem.contentY = 0;
    }
    property string profileName: "Flat"
    property bool restartConfirmation: false
    property bool dirty: false
    property bool showMicrophoneControls: false
    property bool showBands: false
    property bool showProfiles: false
    property bool showMicrophoneEqualizer: false
    readonly property var equalizer: draft ? draft.equalizers[target] : null
    readonly property var profileNames: {
        if (!draft || !controller.response)
            return [];
        const names = Object.keys(controller.response.presets[target]).concat(Object.keys(equalizer.custom));
        return names.sort((a, b) => Number(equalizer.favorites.includes(b)) - Number(equalizer.favorites.includes(a)) || a.localeCompare(b));
    }
    function label(en, es) { return Output.text(en, es, Qt.locale().name); }
    function findProfile() {
        if (!equalizer || !controller.response)
            return "";
        return profileNames.find(name => JSON.stringify(equalizer.custom[name] || controller.response.presets[target][name])
            === JSON.stringify(equalizer.gains)) || "";
    }
    function edit(mutator) {
        const next = JSON.parse(JSON.stringify(draft));
        mutator(next);
        draft = next;
        dirty = true;
    }
    function chooseProfile(name) {
        const curve = equalizer.custom[name] || controller.response.presets[target][name];
        if (!curve)
            return;
        profileName = name;
        edit(next => next.equalizers[target].gains = curve.slice());
    }
    function profileLabel(name) {
        const labels = {Flat: label("Flat", "Plano"), Game: label("Game", "Juegos"),
                        Music: label("Music", "Música"), Movie: label("Movie", "Cine"),
                        Clarity: label("Clarity", "Claridad"), Warm: label("Warm", "Cálido"),
                        Bright: label("Bright", "Brillante")};
        return labels[name] || name;
    }
    function save() { controller.request({op: "save", state: draft}); }
    Connections {
        target: page.controller
        function onLoaded(result) {
            page.draft = JSON.parse(JSON.stringify(result.state));
            page.dirty = false;
            page.profileName = page.findProfile();
        }
    }
    PC3.ScrollView {
        id: scroller
        objectName: "settingsScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: 0
        implicitWidth: Kirigami.Units.gridUnit * 22
        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
        PC3.ScrollBar.vertical.policy: PC3.ScrollBar.AsNeeded
        contentWidth: availableWidth
        ColumnLayout {
            width: scroller.availableWidth
            spacing: Kirigami.Units.largeSpacing
            PlasmaExtras.Heading {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                level: 2
                text: page.section === "system" ? page.label("Audio system", "Sistema de audio")
                    : page.section === "microphone" ? page.label("Microphone", "Micrófono")
                    : page.label("Headphone equalizer", "Ecualizador de auriculares")
            }
            PC3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: page.controller.busy
                visible: running
            }
            PC3.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                text: page.controller.error || page.controller.message
                visible: text.length > 0
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: page.controller.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
            ColumnLayout {
                objectName: "microphoneSection"
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                visible: page.draft !== null && page.section === "microphone"
                enabled: !page.controller.busy

                PC3.Label {
                    objectName: "sidetoneStatus"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: {
                        const saved = page.controller.response;
                        if (!saved || !page.draft)
                            return "";
                        if (JSON.stringify(page.draft.sidetone) !== JSON.stringify(saved.state.sidetone))
                            return page.label("Sidetone: unsaved changes. Save, then apply if requested.",
                                              "Sidetone: cambios sin guardar. Guarda y aplica si se indica.");
                        if (saved.sidetone_running)
                            return page.label("Sidetone: active", "Sidetone: activo");
                        if (saved.sidetone_loaded)
                            return page.label("Sidetone: loaded, waiting for audio devices", "Sidetone: cargado, esperando los dispositivos de audio");
                        return saved.state.sidetone.enabled
                            ? page.label("Sidetone: saved, pending application", "Sidetone: guardado, pendiente de aplicar")
                            : page.label("Sidetone: disabled", "Sidetone: desactivado");
                    }
                }
                PC3.Label {
                    Layout.fillWidth: true
                    visible: page.controller.response !== null && !page.controller.response.has_microphone
                    wrapMode: Text.Wrap
                    text: page.label("The current audio profile does not expose the Barracuda microphone. Check Sound settings to use microphone features.",
                                     "El perfil de audio actual no expone el micrófono del Barracuda. Revisa Ajustes de sonido para usar las funciones del micrófono.")
                }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.label("Hear your voice in the headset. The physical mute button also silences sidetone.",
                                     "Escucha tu voz en los auriculares. El botón físico de silencio también silencia el sidetone.")
                }
                PC3.CheckBox {
                    text: page.label("Enable sidetone", "Activar sidetone")
                    checked: page.draft ? page.draft.sidetone.enabled : false
                    onToggled: page.edit(next => next.sidetone.enabled = checked)
                }
                RowLayout {
                    Layout.fillWidth: true
                    ScrollSafeSlider {
                        scrollItem: scroller.contentItem
                        Layout.fillWidth: true
                        objectName: "sidetoneLevel"
                        enabled: page.draft !== null && page.draft.sidetone.enabled
                        from: 0; to: 100; stepSize: 1
                        value: page.draft ? page.draft.sidetone.level : 15
                        Accessible.name: page.label("Sidetone level", "Nivel de sidetone")
                        onMoved: page.edit(next => next.sidetone.level = Math.round(value))
                    }
                    PC3.Label { text: page.draft ? page.draft.sidetone.level + "%" : "" }
                }
                PC3.CheckBox {
                    text: page.label("Show software microphone controls", "Mostrar controles del micrófono por software")
                    checked: page.showMicrophoneControls
                    onToggled: page.showMicrophoneControls = checked
                }
                PC3.Label {
                    Layout.fillWidth: true
                    visible: page.showMicrophoneControls
                    wrapMode: Text.Wrap
                    text: page.label("These optional controls are separate from the headset's physical mute button. They do not report its position.",
                                     "Estos controles optativos son independientes del botón físico de silencio. No indican su posición.")
                }
                RowLayout {
                    visible: page.showMicrophoneControls
                    PC3.Button {
                        text: page.label("Mute microphone", "Silenciar micrófono")
                        enabled: page.controller.response ? page.controller.response.has_microphone && !page.dirty : false
                        onClicked: page.controller.request({op: "microphone", muted: true})
                    }
                    PC3.Button {
                        text: page.label("Unmute microphone", "Activar micrófono")
                        enabled: page.controller.response ? page.controller.response.has_microphone && !page.dirty : false
                        onClicked: page.controller.request({op: "microphone", muted: false})
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.showMicrophoneControls
                    ScrollSafeSlider {
                        scrollItem: scroller.contentItem
                        id: microphoneVolume
                        Layout.fillWidth: true
                        from: 0; to: 100; stepSize: 1; value: 50
                        Accessible.name: page.label("Microphone volume to apply", "Volumen de micrófono a aplicar")
                    }
                    PC3.Label { text: Math.round(microphoneVolume.value) + "%" }
                    PC3.Button {
                        text: page.label("Set mic volume", "Fijar volumen del micrófono")
                        enabled: page.controller.response ? page.controller.response.has_microphone && !page.dirty : false
                        onClicked: page.controller.request({op: "microphone", volume: Math.round(microphoneVolume.value)})
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true }
                PC3.ToolButton {
                    Layout.fillWidth: true
                    text: page.label("Microphone equalizer", "Ecualizador del micrófono")
                    icon.name: page.showMicrophoneEqualizer ? "arrow-down" : "arrow-right"
                    onClicked: page.showMicrophoneEqualizer = !page.showMicrophoneEqualizer
                }
            }
            ColumnLayout {
                objectName: "equalizerSection"
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                visible: page.draft !== null && (page.section === "output" || (page.section === "microphone" && page.showMicrophoneEqualizer))
                enabled: !page.controller.busy
                PC3.Label {
                    Layout.fillWidth: true
                    text: page.label("Sound profile", "Perfil de sonido")
                    font.bold: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    PC3.ComboBox {
                        wheelEnabled: false
                        objectName: "profileSelector"
                        Accessible.name: page.label("Sound profile", "Perfil de sonido")
                        Layout.fillWidth: true
                        model: page.profileNames
                        currentIndex: page.profileNames.indexOf(page.profileName)
                        displayText: currentIndex < 0 ? page.label("Custom", "Personalizado") : currentText
                        onActivated: {
                            page.chooseProfile(page.profileNames[currentIndex]);
                        }
                    }
                    PC3.ToolButton {
                        icon.name: page.equalizer && page.equalizer.favorites.includes(page.profileName) ? "rating" : "rating-unrated"
                        text: page.label("Favorite", "Favorito")
                        enabled: page.profileNames.includes(page.profileName)
                        onClicked: page.edit(next => {
                            const favorites = next.equalizers[page.target].favorites;
                            const i = favorites.indexOf(page.profileName);
                            if (i >= 0) favorites.splice(i, 1); else favorites.push(page.profileName);
                        })
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Repeater {
                        model: (page.target === "output" ? ["Flat", "Game", "Music", "Movie"]
                                : ["Flat", "Clarity", "Warm", "Bright"]).filter(name => page.profileNames.includes(name))
                        PC3.Button {
                            required property string modelData
                            Layout.fillWidth: true
                            text: page.profileLabel(modelData)
                            checkable: true
                            checked: page.profileName === modelData
                            onClicked: page.chooseProfile(modelData)
                        }
                    }
                }
                PC3.CheckBox {
                    text: page.label("Enable this equalizer", "Activar este ecualizador")
                    checked: page.equalizer ? page.equalizer.enabled : false
                    onToggled: page.edit(next => next.equalizers[page.target].enabled = checked)
                }
                PC3.ToolButton {
                    objectName: "bandsToggle"
                    Layout.fillWidth: true
                    text: page.label("Adjust frequency bands", "Ajustar bandas de frecuencia")
                    icon.name: page.showBands ? "arrow-down" : "arrow-right"
                    onClicked: page.showBands = !page.showBands
                }
                ColumnLayout {
                    objectName: "frequencyEditor"
                    Layout.fillWidth: true
                    visible: page.showBands
                    spacing: Kirigami.Units.largeSpacing
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        uniformCellSizes: true
                        Repeater {
                            model: page.equalizer ? 10 : 0
                            ColumnLayout {
                                required property int index
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                Layout.maximumWidth: Infinity
                                PC3.Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (page.equalizer.gains[index] > 0 ? "+" : "") + page.equalizer.gains[index]
                                    font: Kirigami.Theme.smallFont
                                }
                                ScrollSafeSlider {
                                    objectName: "equalizerBand" + index
                                    scrollItem: scroller.contentItem
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: Kirigami.Units.gridUnit * 7
                                    orientation: Qt.Vertical
                                    from: -12; to: 12; stepSize: 1
                                    value: page.equalizer.gains[index]
                                    Accessible.name: page.controller.response.frequencies[page.target][index] + " Hz"
                                    onMoved: {
                                        page.edit(next => next.equalizers[page.target].gains[index] = value);
                                        page.profileName = "";
                                    }
                                }
                                PC3.Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    readonly property int frequency: page.controller.response.frequencies[page.target][index]
                                    text: frequency >= 1000 ? frequency / 1000 + "k" : frequency
                                    font: Kirigami.Theme.smallFont
                                }
                            }
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        text: page.target === "microphone"
                            ? page.label("±12 dB · Frequencies in Hz · 75 Hz high-pass filter", "±12 dB · Frecuencias en Hz · Filtro paso alto de 75 Hz")
                            : page.label("±12 dB · Frequencies in Hz · Automatic preamp", "±12 dB · Frecuencias en Hz · Preamplificador automático")
                    }
                }
                PC3.ToolButton {
                    Layout.fillWidth: true
                    text: page.label("Manage custom profiles", "Gestionar perfiles personalizados")
                    icon.name: page.showProfiles ? "arrow-down" : "arrow-right"
                    onClicked: page.showProfiles = !page.showProfiles
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: page.showProfiles
                    PC3.TextField {
                        id: newProfile
                        Layout.fillWidth: true
                        maximumLength: 60
                        placeholderText: page.label("New profile name", "Nombre del nuevo perfil")
                    }
                    PC3.Button {
                        text: page.label("Add", "Añadir")
                        enabled: newProfile.text.trim().length > 0 && !page.profileNames.includes(newProfile.text.trim())
                        onClicked: {
                            const name = newProfile.text.trim();
                            page.edit(next => next.equalizers[page.target].custom[name] = page.equalizer.gains.slice());
                            page.profileName = name;
                            newProfile.clear();
                        }
                    }
                    PC3.ToolButton {
                        icon.name: "edit-delete"
                        text: page.label("Delete", "Eliminar")
                        enabled: page.equalizer && Object.keys(page.equalizer.custom).includes(page.profileName)
                        onClicked: {
                            page.edit(next => {
                                delete next.equalizers[page.target].custom[page.profileName];
                                next.equalizers[page.target].favorites = next.equalizers[page.target].favorites.filter(name => name !== page.profileName);
                            });
                            page.profileName = "";
                        }
                    }
                }
            }
            ColumnLayout {
                objectName: "systemSection"
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                visible: page.draft !== null && page.section === "system"
                enabled: !page.controller.busy
                PlasmaExtras.Heading { level: 3; text: page.label("Latency and stability", "Latencia y estabilidad") }
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.label("Buffer and sample-rate settings affect the whole audio session. Smaller buffers reduce latency but may cause crackling. Start with system defaults.",
                                     "El búfer y la frecuencia afectan a toda la sesión de audio. Los búferes menores reducen la latencia, pero pueden causar chasquidos. Empieza con los valores del sistema.")
                }
                PC3.ComboBox {
                    wheelEnabled: false
                    Layout.fillWidth: true
                    model: [page.label("System buffer", "Búfer del sistema"), "256 frames", "512 frames", "1024 frames"]
                    currentIndex: page.draft ? [0, 256, 512, 1024].indexOf(page.draft.tuning.quantum) : 0
                    onActivated: page.edit(next => next.tuning.quantum = [0, 256, 512, 1024][currentIndex])
                }
                PC3.CheckBox {
                    text: page.label("Use 48 kHz for the audio session", "Usar 48 kHz en la sesión de audio")
                    checked: page.draft ? page.draft.tuning.fixed_rate : false
                    onToggled: page.edit(next => next.tuning.fixed_rate = checked)
                }
                PC3.CheckBox {
                    text: page.label("Keep Barracuda audio nodes awake", "Mantener activos los nodos de audio del Barracuda")
                    checked: page.draft ? page.draft.tuning.never_suspend : false
                    onToggled: page.edit(next => next.tuning.never_suspend = checked)
                }
                PC3.ComboBox {
                    wheelEnabled: false
                    Layout.fillWidth: true
                    model: [page.label("System output headroom", "Margen de salida del sistema"), "512 frames", "1024 frames", "2048 frames"]
                    currentIndex: page.draft ? [0, 512, 1024, 2048].indexOf(page.draft.tuning.headroom) : 0
                    onActivated: page.edit(next => next.tuning.headroom = [0, 512, 1024, 2048][currentIndex])
                }
                PC3.Button {
                    text: page.label("Disable effects and use system tuning", "Desactivar efectos y usar ajustes del sistema")
                    onClicked: page.edit(next => {
                        next.equalizers.output.enabled = false;
                        next.equalizers.microphone.enabled = false;
                        next.sidetone.enabled = false;
                        next.tuning = {quantum: 0, fixed_rate: false, never_suspend: false, headroom: 0};
                    })
                }
            }
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }
    RowLayout {
        objectName: "audioActions"
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        enabled: !page.controller.busy
        PC3.ToolButton {
            icon.name: "view-refresh"
            text: page.label("Reload", "Recargar")
            enabled: !page.dirty
            onClicked: page.controller.request({op: "status"})
        }
        Item { Layout.fillWidth: true }
        PC3.Button {
            text: page.label("Save", "Guardar")
            enabled: page.draft !== null && page.dirty
            onClicked: page.save()
        }
        PC3.Button {
            text: page.label("Apply and restart…", "Aplicar y reiniciar…")
            enabled: page.draft !== null && !page.dirty
            onClicked: page.restartConfirmation = true
        }
    }
    PC3.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: page.restartConfirmation
        wrapMode: Text.Wrap
        text: page.label("Restart PipeWire and WirePlumber now? Playback and calls will be interrupted briefly.",
                         "¿Reiniciar PipeWire y WirePlumber ahora? La reproducción y las llamadas se interrumpirán brevemente.")
    }
    RowLayout {
        Layout.alignment: Qt.AlignRight
        Layout.margins: Kirigami.Units.smallSpacing
        visible: page.restartConfirmation
        enabled: !page.controller.busy
        PC3.Button {
            text: page.label("Restart audio", "Reiniciar audio")
            onClicked: { page.restartConfirmation = false; page.controller.request({op: "apply", confirmed: true}); }
        }
        PC3.Button {
            text: page.label("Cancel", "Cancelar")
            onClicked: page.restartConfirmation = false
        }
    }
}
