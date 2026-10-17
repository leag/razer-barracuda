import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/code/output.js" as Output

// The popup (HeadsetView and its parts) with injected states. Nothing runs a
// helper: the settings controller is a stand-in and the monitors' engine
// loads nothing.
Item {
    id: host
    width: Kirigami.Units.gridUnit * 52
    height: Kirigami.Units.gridUnit * 30
    property string localeName: "en_US"
    property var status: null
    property var battery: null
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool powerBusy: false
    property string powerError: ""
    // main.qml's rule for pairing and power-off.
    readonly property bool commandsEnabled: !pairingBusy && !powerBusy && !Output.adapterMissing(status)
    property int audioTriggers: 0
    property int configureTriggers: 0
    // As main.qml, which starts the command and so ends the question.
    property bool busyOnConfirm: false
    function label(english, spanish) { return Output.text(english, spanish, host.localeName) }

    // main.qml's actions, as Plasma hands them to the view; the commands ask
    // in the view as main.qml's do once the popup is open.
    property list<QtObject> actions: [
        PlasmaCore.Action {
            id: pairAction
            text: host.label("Pair Headset…", "Emparejar auricular…")
            icon.name: "list-add-symbolic"
            priority: PlasmaCore.Action.HighPriority
            enabled: host.commandsEnabled
            onTriggered: {
                if (host.commandsEnabled)
                    view.confirmPairing()
            }
        },
        PlasmaCore.Action {
            id: powerOffAction
            text: host.label("Turn Off Headset…", "Apagar auricular…")
            icon.name: "system-shutdown-symbolic"
            priority: PlasmaCore.Action.NormalPriority
            enabled: host.commandsEnabled
            onTriggered: {
                if (host.commandsEnabled)
                    view.confirmPowerOff()
            }
        },
        PlasmaCore.Action {
            isSeparator: true
            priority: PlasmaCore.Action.NormalPriority
        },
        PlasmaCore.Action {
            id: audioAction
            text: host.label("Configure Audio Devices…", "Configurar dispositivos de sonido…")
            icon.name: "audio-card-symbolic"
            priority: PlasmaCore.Action.NormalPriority
            onTriggered: host.audioTriggers++
        }
    ]
    // Plasma's own configure action, with its accelerator marker.
    PlasmaCore.Action {
        id: configureAction
        text: host.label("&Configure Barracuda Headset…", "&Configurar Auricular Barracuda…")
        icon.name: "configure"
        onTriggered: host.configureTriggers++
    }

    // An unknown engine name loads nothing. An empty one would keep the
    // engine that the component itself sets, and run it.
    BatteryMonitor {
        id: monitor
        // Inject engine events without using the system's power service.
        engine: "barracuda-test-none"
    }
    LinkMonitor {
        id: link
        // Inject command output without running the helper.
        engine: "barracuda-test-none"
    }
    // Stands in for HeadsetController; nothing is sent to a headset.
    QtObject {
        id: fakeSettings
        property bool busy: false
        property var response: null
        property string error: ""
        property string errorCode: ""
        property string requestFeature: ""
        function errorLabel(code) { return "label:" + code }
    }

    // The widget's own popup, in a panel or on the desktop.
    HeadsetView {
        id: view
        width: implicitWidth
        height: implicitHeight
        title: host.label("Barracuda Headset", "Auricular Barracuda")
        localeName: host.localeName
        actions: host.actions
        configureAction: configureAction
        linkStatus: host.status
        battery: host.battery
        settings: fakeSettings
        pairingBusy: host.pairingBusy
        pairingError: host.pairingError
        pairingResult: host.pairingResult
        powerBusy: host.powerBusy
        powerError: host.powerError
        onPairingConfirmed: {
            if (host.busyOnConfirm)
                host.pairingBusy = true
        }
        onPowerOffConfirmed: {
            if (host.busyOnConfirm)
                host.powerBusy = true
        }
    }
    // The system tray's popup: the tray draws the heading.
    HeadsetView {
        id: trayView
        x: view.width + Kirigami.Units.gridUnit
        width: implicitWidth
        height: implicitHeight
        inTray: true
        title: view.title
        localeName: host.localeName
        actions: host.actions
        configureAction: configureAction
        linkStatus: host.status
        battery: host.battery
        settings: fakeSettings
        pairingBusy: host.pairingBusy
        pairingError: host.pairingError
        pairingResult: host.pairingResult
        powerBusy: host.powerBusy
        powerError: host.powerError
    }
    SignalSpy {
        id: pairingSpy
        target: view
        signalName: "pairingConfirmed"
    }
    SignalSpy {
        id: powerSpy
        target: view
        signalName: "powerOffConfirmed"
    }
    SignalSpy {
        id: settingSpy
        target: view
        signalName: "settingChangeRequested"
    }
    SignalSpy {
        id: refreshSpy
        target: view
        signalName: "settingsRefreshRequested"
    }

    TestCase {
        name: "HeadsetView"
        when: windowShown

        readonly property string nbsp: " "
        readonly property var phone: ({address: "0a0b0c0d0e0f", name: "Phone", active: true})
        readonly property var laptop: ({address: "010203040506", name: "", active: false})
        readonly property var tablet: ({address: "a1b2c3d4e5f6", name: "Tablet", active: false})
        readonly property var noDongle: ({ok: true, usb: {adapter: "missing"}, bluetooth: null})

        function linked(value, bluetooth, battery) {
            return {ok: true, usb: {adapter: "present", driver: true, link: value, battery: battery || null},
                    bluetooth: bluetooth === undefined ? null : bluetooth}
        }
        function bluetoothOnly(state) {
            return {ok: true, usb: {adapter: "missing"}, bluetooth: {state: state, address: "A1:B2:C3:D4:E5:F6"}}
        }
        // A status reply from the settings controller.
        function read(state, transport, errors) {
            fakeSettings.response = {ok: true, transport: transport || "usb", state: state, errors: errors || {}}
        }
        function findAll(item, test) {
            let found = test(item) ? [item] : []
            for (const child of item.children)
                found = found.concat(findAll(child, test))
            return found
        }
        function rows(target) {
            return findAll(target || view, item => item.objectName === "deviceRow" && item.visible)
        }
        // The visible feedback message, or null.
        function feedback(target) {
            return findAll(target || view, item => item.objectName === "feedback" && item.visible)[0] || null
        }
        function placeholder(target) {
            return findChild(target || view, "placeholder")
        }
        function yOf(item) {
            return item.mapToItem(view, 0, 0).y
        }
        function closePrompt() {
            if (view.openPrompt !== null)
                view.openPrompt.reject()
            tryCompare(view, "openPrompt", null)
        }
        function openedPrompt() {
            verify(view.openPrompt !== null)
            tryCompare(view.openPrompt, "opened", true)
            return view.openPrompt
        }
        function init() {
            host.localeName = "en_US"
            host.status = null
            host.battery = null
            host.pairingBusy = false
            host.pairingError = ""
            host.pairingResult = ""
            host.powerBusy = false
            host.powerError = ""
            host.busyOnConfirm = false
            fakeSettings.busy = false
            fakeSettings.response = null
            fakeSettings.error = ""
            fakeSettings.errorCode = ""
            fakeSettings.requestFeature = ""
            for (const target of [view, trayView]) {
                target.activeView = true
                target.dismissedNotice = ""
                target.pendingAddress = ""
                findChild(target, "hero").expanded = false
            }
            pairingSpy.clear()
            powerSpy.clear()
            settingSpy.clear()
            refreshSpy.clear()
        }
        function cleanup() {
            closePrompt()
            host.status = null
            fakeSettings.response = null
        }
        function test_heading_title_actions_and_gear() {
            const heading = view.header
            verify(heading.visible)
            // Plasma's heading, with the theme's background and separator.
            compare(heading.background.imagePath, "widgets/plasmoidheading")
            compare(String(heading.background.prefix), "header")
            const title = findChild(heading, "popupTitle")
            const plus = findChild(heading, "primaryAction")
            const more = findChild(heading, "moreActionsButton")
            const gear = findChild(heading, "configureButton")
            for (const locale of ["en_US", "es_CL"]) {
                host.localeName = locale
                const english = locale === "en_US"
                compare(title.text, english ? "Barracuda Headset" : "Auricular Barracuda")
                // The '+' is the pairing action, named by its tooltip.
                compare(plus.text, english ? "Pair Headset…" : "Emparejar auricular…")
                compare(more.text, english ? "More actions" : "Más acciones")
                // Plasma's own configure text, without its accelerator marker.
                compare(gear.text, english ? "Configure Barracuda Headset…" : "Configurar Auricular Barracuda…")
                // More actions: Turn Off, a separator, the audio settings.
                compare(heading.menuActions.map(action => action.isSeparator ? "—" : action.text),
                        english ? ["Turn Off Headset…", "—", "Configure Audio Devices…"]
                                : ["Apagar auricular…", "—", "Configurar dispositivos de sonido…"])
            }
            host.localeName = "en_US"
            compare(plus.display, PC3.AbstractButton.IconOnly)
            compare(plus.contentItem.source, "list-add-symbolic")
            compare(gear.display, PC3.AbstractButton.IconOnly)
            compare(gear.icon.name, "configure")
            compare(more.icon.name, "application-menu")
            verify(more.checkable)
            compare(more.Accessible.role, Accessible.ButtonMenu)
            compare(heading.menuActions[0].icon.name, "system-shutdown-symbolic")
            compare(heading.menuActions[2].icon.name, "audio-card-symbolic")
            // Title, '+', More actions, then the gear at the top right.
            verify(plus.x > title.x)
            verify(more.x > plus.x)
            verify(gear.x > more.x)
            // The gear opens the widget's configuration window.
            mouseClick(gear)
            compare(host.configureTriggers, 1)
            // The '+' asks before pairing.
            host.status = linked("disconnected")
            mouseClick(plus)
            const prompt = openedPrompt()
            compare(prompt.title, "Pair Headset?")
            closePrompt()
            compare(pairingSpy.count, 0)
            // Inside the system tray, the tray draws this row itself.
            verify(!trayView.header.visible)
            // The commands have no second copy in the body.
            for (const name of ["pairButton", "powerOffButton", "deviceCommands", "pairingStatus", "powerStatus",
                                "connectionHelp", "headsetSettings", "detailsToggle", "quickConnect"])
                compare(findChild(view, name), null)
        }
        function test_commands_wait_only_for_a_missing_dongle_or_a_running_command() {
            const plus = findChild(view.header, "primaryAction")
            // Enabled in every state but a confirmed missing dongle, including
            // while the first reading is pending.
            for (const state of [null, {ok: false}, linked("connected"), linked("disconnected"), linked("unknown"),
                                 {ok: true, usb: {adapter: "multiple"}, bluetooth: null},
                                 {ok: true, usb: {adapter: "present", driver: false, link: "unknown"}, bluetooth: null}]) {
                host.status = state
                verify(view.commandsEnabled)
                verify(plus.enabled)
                verify(pairAction.enabled)
                verify(powerOffAction.enabled)
            }
            // Kept visible, greyed, without the dongle, also with Bluetooth connected.
            for (const state of [noDongle, bluetoothOnly("connected"), bluetoothOnly("disconnected")]) {
                host.status = state
                verify(!view.commandsEnabled)
                verify(plus.visible)
                verify(!plus.enabled)
                verify(!powerOffAction.enabled)
            }
            host.status = linked("connected")
            for (const field of ["pairingBusy", "powerBusy"]) {
                host[field] = true
                verify(!plus.enabled)
                verify(!pairAction.enabled)
                verify(!powerOffAction.enabled)
                host[field] = false
            }
            verify(plus.enabled)
        }
        function test_headset_card() {
            host.status = linked("connected")
            host.battery = {percent: 80, state: "Discharging"}
            const hero = findChild(view, "hero")
            const headline = findChild(hero, "heroHeadline")
            const percent = findChild(hero, "heroPercent")
            const bar = findChild(hero, "heroBattery")
            const line = findChild(hero, "heroLine")
            const glyphs = () => findAll(hero, item => item.objectName === "artworkGlyph")
            verify(hero.visible)
            verify(!view.showPlaceholder)
            verify(!findChild(view, "placeholderLoader").active)
            compare(headline.text, "Connected")
            compare(headline.level, 2)
            compare(percent.text, "80%")
            compare(percent.level, 2)
            verify(bar.visible)
            compare(bar.value, 80)
            compare(line.text, "USB dongle")
            compare(hero.Accessible.name, "Connected, 80% battery, USB dongle")
            // The detailed artwork, with the transport glyph beside it.
            compare(String(findChild(hero, "artworkIcon").source),
                    "file:///usr/share/icons/breeze/devices/64/audio-headset.svg")
            verify(!findChild(hero, "artworkEmblem").visible)
            tryCompare(glyphs(), "length", 1)
            compare(glyphs()[0].source, "drive-removable-media-usb-symbolic")
            const artwork = findChild(hero, "heroArtwork")
            verify(glyphs()[0].mapToItem(artwork, 0, 0).x >= artwork.drawingRight)
            host.localeName = "es_CL"
            compare(headline.text, "Conectado")
            compare(percent.text, "80" + nbsp + "%")
            compare(line.text, "Dongle USB")
            compare(hero.Accessible.name, "Conectado, 80" + nbsp + "% de batería, dongle USB")
            host.localeName = "en_US"
            // Bluetooth, and both links with two glyphs, the dongle at the bottom.
            host.status = bluetoothOnly("connected")
            compare(line.text, "Bluetooth")
            tryCompare(glyphs(), "length", 1)
            compare(glyphs()[0].source, "network-bluetooth-symbolic")
            host.status = linked("connected", {state: "connected", address: "A1:B2:C3:D4:E5:F6"})
            compare(line.text, "USB dongle and Bluetooth")
            tryCompare(glyphs(), "length", 2)
            const usbGlyph = glyphs().find(glyph => glyph.source === "drive-removable-media-usb-symbolic")
            const btGlyph = glyphs().find(glyph => glyph.source === "network-bluetooth-symbolic")
            tryVerify(() => usbGlyph.mapToItem(hero, 0, 0).y > btGlyph.mapToItem(hero, 0, 0).y)
            host.localeName = "es_CL"
            compare(line.text, "Dongle USB y Bluetooth")
            host.localeName = "en_US"
            // The charge state follows the transport.
            host.status = linked("connected")
            host.battery = {percent: 60, state: "Charging"}
            compare(line.text, "USB dongle · Charging")
            host.battery = {percent: 100, state: "FullyCharged"}
            compare(line.text, "USB dongle · Fully charged")
            host.battery = {percent: 8, state: "Discharging"}
            compare(line.text, "USB dongle · Low battery")
            compare(percent.text, "8%")
            host.localeName = "es_CL"
            compare(line.text, "Dongle USB · Batería baja")
            host.localeName = "en_US"
            // Without a reading there is no percentage or bar, and the line says so.
            host.battery = null
            verify(!percent.visible)
            verify(!bar.visible)
            compare(line.text, "USB dongle · Battery unavailable")
        }
        function test_headset_card_details() {
            host.status = linked("connected", null, {percent: 65, status: "Charging", cable: true, voltage_mv: 4123})
            host.battery = {percent: 65, state: "Charging"}
            const hero = findChild(view, "hero")
            const details = findChild(hero, "heroDetails")
            const expand = findChild(hero, "heroExpand")
            const keys = () => findAll(details, item => item.objectName === "detailKey").map(item => item.text)
            const values = () => findAll(details, item => item.objectName === "detailValue").map(item => item.text)
            verify(hero.expandable)
            verify(!details.visible)
            verify(expand.visible)
            compare(expand.icon.name, "expand")
            compare(expand.text, "Expand")
            compare(hero.Accessible.description, "Collapsed")
            // A click anywhere on the card opens the details.
            mouseClick(hero, hero.width * 0.4, hero.height / 2)
            verify(hero.expanded)
            verify(details.visible)
            compare(expand.icon.name, "collapse")
            compare(expand.text, "Collapse")
            compare(hero.Accessible.description, "Expanded")
            tryCompare(keys(), "length", 4)
            compare(keys(), ["USB dongle:", "2.4 GHz link:", "Charging cable:", "Battery voltage:"])
            compare(values(), ["Detected", "Connected", "Connected", "4.12 V"])
            host.localeName = "es_CL"
            compare(expand.text, "Contraer")
            compare(hero.Accessible.description, "Expandido")
            tryCompare(values(), "length", 4)
            compare(keys(), ["Dongle USB:", "Enlace 2,4 GHz:", "Cable de carga:", "Voltaje de batería:"])
            compare(values()[3], "4,12 V")
            host.localeName = "en_US"
            // The expand button toggles too.
            mouseClick(expand)
            verify(!hero.expanded)
            compare(hero.Accessible.description, "Collapsed")
            host.localeName = "es_CL"
            compare(expand.text, "Expandir")
            compare(hero.Accessible.description, "Contraído")
            host.localeName = "en_US"
            mouseClick(expand)
            verify(hero.expanded)
            // A discharging battery is named in the details.
            host.battery = {percent: 65, state: "Discharging"}
            tryCompare(keys(), "length", 5)
            compare(keys()[4], "Charge:")
            compare(values()[4], "On battery")
            // Closing the popup folds them again.
            view.activeView = false
            verify(!hero.expanded)
            view.activeView = true
            // While the headset turns off, the card says so and waits.
            mouseClick(expand)
            verify(hero.expanded)
            host.powerBusy = true
            compare(findChild(hero, "heroHeadline").text, "Turning off…")
            verify(findChild(hero, "heroBusy").visible)
            verify(findChild(hero, "heroBusy").running)
            verify(!expand.visible)
            verify(!hero.expanded)
            verify(!details.visible)
            verify(!hero.expandable)
            mouseClick(hero, hero.width * 0.4, hero.height / 2)
            verify(!hero.expanded)
            host.localeName = "es_CL"
            compare(findChild(hero, "heroHeadline").text, "Apagando…")
            host.localeName = "en_US"
            host.powerBusy = false
            verify(!findChild(hero, "heroBusy").visible)
            compare(findChild(hero, "heroHeadline").text, "Connected")
        }
        function test_placeholder_for_every_state_without_a_link() {
            const loader = findChild(view, "placeholderLoader")
            const states = [null, {ok: false}, noDongle, linked("disconnected"), linked("unknown"),
                            {ok: true, usb: {adapter: "multiple"}, bluetooth: null}, bluetoothOnly("disconnected")]
            for (const locale of ["en_US", "es_CL"]) {
                host.localeName = locale
                for (const state of states) {
                    host.status = state
                    verify(view.showPlaceholder)
                    verify(loader.active)
                    // The body has nothing else.
                    verify(!findChild(view, "hero").visible)
                    verify(!findChild(view, "modesHeader").visible)
                    verify(!findChild(view, "devicesHeader").visible)
                    compare(rows().length, 0)
                    const expected = Output.placeholder(state, Output.connection(state), null, false, locale)
                    const message = placeholder()
                    compare(findChild(message, "placeholderTitle").text, expected.title)
                    compare(findChild(message, "placeholderExplanation").text, expected.explanation)
                    compare(findChild(message, "placeholderExplanation").visible, expected.explanation.length > 0)
                    const artwork = findChild(message, "placeholderArtwork")
                    compare(artwork.iconName, expected.artwork)
                    compare(artwork.dimmed, expected.dimmed)
                    const emblem = findChild(message, "artworkEmblem")
                    compare(emblem.visible, expected.emblem !== "")
                    if (expected.emblem !== "")
                        compare(emblem.source, expected.emblem)
                    compare(findChild(message, "placeholderBusy").visible, expected.busy)
                    // Only Disconnected offers a next step.
                    compare(findChild(message, "placeholderAction").visible, expected.state === "disconnected")
                }
            }
            host.localeName = "en_US"
            // The words of each state, as the popup shows them.
            const words = [[null, "Checking…", ""],
                           [linked("disconnected"), "Disconnected", "Turn on the headset."],
                           [linked("unknown"), "Link not confirmed", "The headset may still be on."],
                           [noDongle, "USB dongle not detected", "Plug in the dongle, or use the headset over Bluetooth."],
                           [{ok: false}, "Status unavailable", "Install or update the barracuda-pair package."]]
            for (const [state, title, explanation] of words) {
                host.status = state
                compare(findChild(placeholder(), "placeholderTitle").text, title)
                compare(findChild(placeholder(), "placeholderExplanation").text, explanation)
            }
            // A battery reading kept from before is named as the last one.
            host.status = linked("unknown")
            host.battery = {percent: 80, state: "Discharging"}
            compare(findChild(placeholder(), "placeholderExplanation").text,
                    "The headset may still be on. Last battery reading: 80%.")
            host.localeName = "es_CL"
            compare(findChild(placeholder(), "placeholderExplanation").text,
                    "El auricular puede seguir encendido. Última lectura de batería: 80" + nbsp + "%.")
            host.localeName = "en_US"
            host.battery = null
            // Artwork treatment: dimmed when the object is absent, an emblem
            // when the state is unconfirmed or unreadable.
            host.status = linked("disconnected")
            tryCompare(findChild(placeholder(), "artworkIcon"), "opacity", 0.5)
            host.status = {ok: false}
            tryCompare(findChild(placeholder(), "artworkIcon"), "opacity", 1)
            const emblem = findChild(placeholder(), "artworkEmblem")
            const icon = findChild(placeholder(), "artworkIcon")
            compare(emblem.x + emblem.width, icon.width)
            compare(emblem.y + emblem.height, icon.height)
            compare(emblem.width, Kirigami.Units.iconSizes.medium)
            compare(icon.width, Math.round(Kirigami.Units.iconSizes.huge * 1.5))
            // The missing dongle is drawn as the dongle.
            host.status = noDongle
            compare(String(findChild(placeholder(), "artworkIcon").source),
                    "file:///usr/share/icons/breeze/devices/64/drive-removable-media-usb.svg")
            // Centred in the body.
            const message = placeholder()
            const scroll = findChild(view, "bodyScroll")
            const centre = message.mapToItem(scroll, message.width / 2, message.height / 2)
            verify(Math.abs(centre.x - scroll.width / 2) < Kirigami.Units.gridUnit, centre.x)
            verify(Math.abs(centre.y - scroll.height / 2) < Kirigami.Units.gridUnit * 2, centre.y)
            // Pairing replaces the body, also with a confirmed link.
            host.status = linked("connected")
            verify(!view.showPlaceholder)
            host.pairingBusy = true
            verify(view.showPlaceholder)
            compare(findChild(placeholder(), "placeholderTitle").text, "Pairing…")
            compare(findChild(placeholder(), "placeholderExplanation").text,
                    "Keep the headset in pairing mode. This can take up to a minute.")
            verify(findChild(placeholder(), "placeholderBusy").visible)
            verify(!findChild(placeholder(), "placeholderAction").visible)
            verify(!findChild(view, "hero").visible)
            host.localeName = "es_CL"
            compare(findChild(placeholder(), "placeholderTitle").text, "Emparejando…")
            host.localeName = "en_US"
            host.pairingBusy = false
            verify(!view.showPlaceholder)
        }
        function test_disconnected_placeholder_offers_pairing() {
            // As the Bluetooth applet offers Pair Device… under No devices
            // paired: the heading's own pairing action, as a button.
            host.status = linked("disconnected")
            const plus = findChild(view.header, "primaryAction")
            let button = findChild(placeholder(), "placeholderAction")
            verify(button.visible)
            verify(button.enabled)
            compare(button.text, "Pair Headset…")
            compare(button.icon.name, "list-add-symbolic")
            compare(view.pairAction, pairAction)
            // An enabled next step makes the message actionable.
            compare(findChild(placeholder(), "placeholderTitle").opacity, 1)
            compare(findChild(placeholder(), "placeholderExplanation").opacity, 1)
            // A grid unit under the words, centred.
            tryVerify(() => button.mapToItem(placeholder(), 0, 0).y
                      >= findChild(placeholder(), "placeholderExplanation").mapToItem(placeholder(), 0, 0).y
                         + findChild(placeholder(), "placeholderExplanation").height + Kirigami.Units.gridUnit - 0.5)
            tryVerify(() => Math.abs(button.mapToItem(placeholder(), button.width / 2, 0).x
                                     - placeholder().width / 2) < 1)
            host.localeName = "es_CL"
            compare(button.text, "Emparejar auricular…")
            compare(findChild(placeholder(), "placeholderTitle").text, "Desconectado")
            host.localeName = "en_US"
            // It opens the same confirmation as the '+', which pairs once.
            mouseClick(button)
            let prompt = openedPrompt()
            compare(prompt.title, "Pair Headset?")
            compare(pairingSpy.count, 0)
            mouseClick(prompt.customFooterButton(prompt.customFooterActions[0]))
            tryCompare(view, "openPrompt", null)
            compare(pairingSpy.count, 1)
            // The same enabled rule as the '+', in every Disconnected state.
            for (const [state, busy] of [[linked("disconnected"), ""], [bluetoothOnly("disconnected"), ""],
                                         [{ok: true, usb: {adapter: "missing"}, bluetooth: {state: "disconnected"}}, ""],
                                         [linked("disconnected"), "powerBusy"]]) {
                host.status = state
                if (busy)
                    host[busy] = true
                compare(findChild(placeholder(), "placeholderTitle").text, "Disconnected")
                button = findChild(placeholder(), "placeholderAction")
                verify(button.visible)
                compare(button.enabled, plus.enabled)
                compare(button.enabled, state.usb.adapter !== "missing" && !busy)
                if (busy)
                    host[busy] = false
            }
            // Without the dongle it stays visible, greyed, and the words say
            // what to do; the message is informational.
            host.status = bluetoothOnly("disconnected")
            button = findChild(placeholder(), "placeholderAction")
            verify(button.visible)
            verify(!button.enabled)
            compare(findChild(placeholder(), "placeholderExplanation").text,
                    "Turn on the headset or plug in the USB dongle.")
            compare(findChild(placeholder(), "placeholderTitle").opacity, 0.75)
            mouseClick(button)
            wait(50)
            compare(view.openPrompt, null)
            compare(pairingSpy.count, 1)
            // While pairing, the placeholder waits instead.
            host.status = linked("disconnected")
            host.pairingBusy = true
            verify(!findChild(placeholder(), "placeholderAction").visible)
            host.pairingBusy = false
            // The tray's popup offers it too.
            verify(findChild(placeholder(trayView), "placeholderAction").visible)
            // Down from the heading reaches it; Up returns to the heading.
            host.status = linked("disconnected")
            button = findChild(placeholder(), "placeholderAction")
            plus.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Down)
            tryVerify(() => button.activeFocus)
            keyClick(Qt.Key_Down)
            wait(50)
            verify(button.activeFocus)
            keyClick(Qt.Key_Up)
            tryVerify(() => plus.activeFocus)
            // Without a usable next step, Down from the heading stays there.
            host.status = linked("unknown")
            plus.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Down)
            wait(50)
            verify(plus.activeFocus)
        }
        function test_pairing_prompt() {
            host.status = linked("disconnected")
            view.confirmPairing()
            let prompt = openedPrompt()
            compare(prompt.title, "Pair Headset?")
            compare(prompt.subtitle, "Put the headset in pairing mode. This replaces the dongle's current pairing "
                    + "and can take up to a minute.")
            const verb = prompt.customFooterActions[0]
            const cancel = prompt.customFooterActions[1]
            compare(prompt.customFooterActions.length, 2)
            compare(verb.text, "Pair")
            compare(verb.icon.name, "list-add-symbolic")
            compare(cancel.text, "Cancel")
            compare(cancel.icon.name, "dialog-cancel-symbolic")
            verify(!prompt.showCloseButton)
            // Cancel is the safe default, with visible focus.
            const cancelButton = prompt.customFooterButton(cancel)
            tryVerify(() => cancelButton.activeFocus)
            verify(cancelButton.visualFocus)
            // Over the popup, with a grid unit of it on each side.
            compare(prompt.parent, view)
            verify(prompt.width <= view.width - Kirigami.Units.gridUnit * 2 + 0.5)
            // One question at a time.
            view.confirmPairing()
            view.confirmPowerOff()
            compare(view.openPrompt, prompt)
            mouseClick(cancelButton)
            tryCompare(view, "openPrompt", null)
            compare(pairingSpy.count, 0)
            // Escape cancels.
            view.confirmPairing()
            openedPrompt()
            tryVerify(() => view.openPrompt.customFooterButton(view.openPrompt.customFooterActions[1]).activeFocus)
            keyClick(Qt.Key_Escape)
            tryCompare(view, "openPrompt", null)
            compare(pairingSpy.count, 0)
            // Pair confirms once, also when the command ends the question.
            host.busyOnConfirm = true
            view.confirmPairing()
            prompt = openedPrompt()
            mouseClick(prompt.customFooterButton(prompt.customFooterActions[0]))
            tryCompare(view, "openPrompt", null)
            compare(pairingSpy.count, 1)
            verify(host.pairingBusy)
            // No question while a command runs.
            view.confirmPairing()
            compare(view.openPrompt, null)
            host.pairingBusy = false
            host.busyOnConfirm = false
            // Spanish.
            host.localeName = "es_CL"
            view.confirmPairing()
            prompt = openedPrompt()
            compare(prompt.title, "¿Emparejar el auricular?")
            compare(prompt.subtitle, "Pon el auricular en modo de emparejamiento. Esto reemplaza el emparejamiento "
                    + "actual del dongle y puede tardar hasta un minuto.")
            compare(prompt.customFooterActions[0].text, "Emparejar")
            compare(prompt.customFooterActions[1].text, "Cancelar")
            closePrompt()
            host.localeName = "en_US"
            // Unplugging the dongle rejects an open question, and none opens
            // without it.
            view.confirmPairing()
            openedPrompt()
            host.status = noDongle
            tryCompare(view, "openPrompt", null)
            view.confirmPairing()
            compare(view.openPrompt, null)
            compare(pairingSpy.count, 1)
            // Closing the popup rejects it; nothing is left to take a key.
            host.status = linked("disconnected")
            view.confirmPairing()
            openedPrompt()
            view.activeView = false
            tryCompare(view, "openPrompt", null)
            view.confirmPairing()
            compare(view.openPrompt, null)
            view.activeView = true
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_Return)
            compare(pairingSpy.count, 1)
        }
        function test_power_off_prompt() {
            host.status = linked("connected")
            host.battery = {percent: 80, state: "Discharging"}
            view.confirmPowerOff()
            let prompt = openedPrompt()
            compare(prompt.title, "Turn Off Headset?")
            compare(prompt.subtitle, "Turn it back on with its power button.")
            compare(prompt.customFooterActions[0].text, "Turn Off")
            compare(prompt.customFooterActions[0].icon.name, "system-shutdown-symbolic")
            compare(prompt.customFooterActions[1].text, "Cancel")
            const cancelButton = prompt.customFooterButton(prompt.customFooterActions[1])
            tryVerify(() => cancelButton.activeFocus)
            mouseClick(cancelButton)
            tryCompare(view, "openPrompt", null)
            compare(powerSpy.count, 0)
            host.localeName = "es_CL"
            view.confirmPowerOff()
            prompt = openedPrompt()
            compare(prompt.title, "¿Apagar el auricular?")
            compare(prompt.subtitle, "Vuelve a encenderlo con su botón de encendido.")
            compare(prompt.customFooterActions[0].text, "Apagar")
            compare(prompt.customFooterActions[1].text, "Cancelar")
            host.localeName = "en_US"
            host.busyOnConfirm = true
            mouseClick(prompt.customFooterButton(prompt.customFooterActions[0]))
            tryCompare(view, "openPrompt", null)
            compare(powerSpy.count, 1)
            verify(host.powerBusy)
            view.confirmPowerOff()
            compare(view.openPrompt, null)
            host.powerBusy = false
            // A missing dongle rejects it too.
            host.busyOnConfirm = false
            view.confirmPowerOff()
            openedPrompt()
            host.status = bluetoothOnly("connected")
            tryCompare(view, "openPrompt", null)
            compare(powerSpy.count, 1)
        }
        function test_actions_ask_in_the_popup() {
            host.status = linked("connected")
            pairAction.trigger()
            compare(openedPrompt().title, "Pair Headset?")
            closePrompt()
            powerOffAction.trigger()
            compare(openedPrompt().title, "Turn Off Headset?")
            closePrompt()
            audioAction.trigger()
            compare(host.audioTriggers, 1)
            // A disabled action asks nothing.
            host.status = noDongle
            pairAction.trigger()
            powerOffAction.trigger()
            compare(view.openPrompt, null)
            compare(pairingSpy.count, 0)
            compare(powerSpy.count, 0)
        }
        function test_do_not_disturb_switch() {
            host.status = linked("connected")
            read({dnd: true, gaming: false, devices: []})
            const row = findChild(view, "dnd")
            const control = row.control
            const note = findChild(row, "modeNote")
            const unknown = findChild(row, "modeUnknownLabel")
            const busy = findChild(row, "modeBusy")
            compare(control.text, "Do not disturb")
            verify(control.visible)
            verify(!unknown.visible)
            verify(control.checked)
            verify(control.enabled)
            verify(!note.visible)
            verify(!busy.visible)
            // The row is one list row tall, and the label sits on the device
            // titles' column.
            compare(row.height, Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2)
            compare(control.leftPadding + control.indicator.width + control.spacing, view.titleColumn)
            // A click anywhere on the row asks for the new value; the switch
            // keeps the confirmed one until a reading says otherwise.
            mouseClick(row, row.width * 0.75, row.height / 2)
            compare(settingSpy.count, 1)
            compare(Array.from(settingSpy.signalArguments[0]), ["dnd", false])
            verify(control.checked)
            read({dnd: false, gaming: false, devices: []})
            verify(!control.checked)
            mouseClick(control)
            compare(Array.from(settingSpy.signalArguments[1]), ["dnd", true])
            verify(!control.checked)
            // Its own request shows a busy indicator in the trailing slot.
            fakeSettings.busy = true
            fakeSettings.requestFeature = "dnd"
            verify(busy.visible)
            verify(busy.running)
            verify(!note.visible)
            verify(!control.enabled)
            verify(!findChild(findChild(view, "gaming"), "modeBusy").visible)
            // Disabled while any request or command runs; the value stays.
            fakeSettings.requestFeature = ""
            verify(!busy.visible)
            verify(!control.enabled)
            verify(control.visible)
            fakeSettings.busy = false
            verify(control.enabled)
            for (const field of ["pairingBusy", "powerBusy"]) {
                host[field] = true
                verify(!findChild(view, "dnd").control.enabled)
                host[field] = false
            }
            host.localeName = "es_CL"
            compare(control.text, "No molestar")
            host.localeName = "en_US"
            // An unknown value draws no switch: the label stays on its column
            // and the trailing slot says why.
            read({dnd: null, gaming: false, devices: []})
            verify(!control.visible)
            verify(unknown.visible)
            compare(unknown.text, "Do not disturb")
            compare(unknown.x, view.titleColumn)
            verify(note.visible)
            compare(note.text, "Unknown")
            compare(unknown.Accessible.description, "Unknown")
            host.localeName = "es_CL"
            compare(note.text, "Desconocido")
            compare(unknown.text, "No molestar")
            host.localeName = "en_US"
            // While the reading runs it says so.
            fakeSettings.response = null
            fakeSettings.busy = true
            compare(note.text, "Reading…")
            host.localeName = "es_CL"
            compare(note.text, "Leyendo…")
            host.localeName = "en_US"
            fakeSettings.busy = false
            // The trailing slot ends where the device rows' button text does.
            read({dnd: null, gaming: false, devices: []})
            compare(note.x + note.width, row.width - view.trailingInset)
        }
        function test_gaming_mode_switch() {
            host.status = linked("connected")
            const row = findChild(view, "gaming")
            const control = row.control
            const note = findChild(row, "modeNote")
            // Read through the USB dongle: shown, not settable, and its slot says why.
            read({dnd: false, gaming: false, devices: []})
            compare(control.text, "Bluetooth gaming mode")
            verify(control.visible)
            verify(!control.checked)
            verify(!control.enabled)
            compare(note.text, "Only over Bluetooth")
            compare(control.Accessible.description, "Only over Bluetooth")
            host.localeName = "es_CL"
            compare(control.text, "Modo gaming Bluetooth")
            compare(note.text, "Solo por Bluetooth")
            host.localeName = "en_US"
            // Also with both links, while the settings are read through the dongle.
            host.status = linked("connected", {state: "connected", address: "A1:B2:C3:D4:E5:F6"})
            read({dnd: false, gaming: true, devices: []})
            verify(control.checked)
            verify(!control.enabled)
            compare(note.text, "Only over Bluetooth")
            // Over Bluetooth the switch sets the new value.
            host.status = bluetoothOnly("connected")
            read({dnd: false, gaming: false, devices: []}, "bluetooth")
            verify(control.enabled)
            verify(!note.visible)
            mouseClick(control)
            compare(Array.from(settingSpy.signalArguments[0]), ["gaming", true])
            verify(!control.checked)
            fakeSettings.busy = true
            fakeSettings.requestFeature = "gaming"
            verify(findChild(row, "modeBusy").visible)
            fakeSettings.busy = false
            // Unknown: no switch, and the slot says so.
            read({dnd: false, gaming: null, devices: []}, "bluetooth")
            verify(!control.visible)
            compare(note.text, "Unknown")
            compare(findChild(row, "modeUnknownLabel").text, "Bluetooth gaming mode")
        }
        function test_bluetooth_devices() {
            host.status = linked("connected")
            read({dnd: false, gaming: false, devices: [phone, laptop]})
            const header = findChild(view, "devicesHeader")
            const note = findChild(view, "devicesNote")
            verify(header.visible)
            compare(header.text, "Bluetooth Devices")
            verify(!note.visible)
            tryCompare(rows(), "length", 2)
            const active = rows()[0]
            const other = rows()[1]
            // The active device: bold title, Connected, no button.
            compare(active.title, "Phone")
            compare(active.subtitle, "Connected")
            verify(active.isDefault)
            verify(!active.defaultActionButtonVisible)
            compare(active.icon, "preferences-system-bluetooth")
            // A nameless device shows its formatted address once.
            compare(other.title, "01:02:03:04:05:06")
            compare(other.subtitle, "")
            verify(!other.isDefault)
            verify(other.defaultActionButtonVisible)
            const connect = other.defaultActionButtonAction
            compare(connect.text, "Connect")
            compare(connect.icon.name, "network-connect-symbolic")
            verify(connect.enabled)
            connect.trigger()
            compare(Array.from(settingSpy.signalArguments[0]), ["devices", "010203040506"])
            // While its switch runs, that row waits.
            fakeSettings.busy = true
            fakeSettings.requestFeature = "devices"
            verify(other.isBusy)
            compare(other.subtitle, "Connecting…")
            verify(!active.isBusy)
            verify(!connect.enabled)
            host.localeName = "es_CL"
            compare(header.text, "Dispositivos Bluetooth")
            compare(active.subtitle, "Conectado")
            compare(other.subtitle, "Conectando…")
            compare(connect.text, "Conectar")
            host.localeName = "en_US"
            // The active device changes only with a new reading.
            fakeSettings.busy = false
            compare(view.pendingAddress, "")
            verify(!other.isBusy)
            verify(active.isDefault)
            // Disabled while any command runs.
            host.powerBusy = true
            verify(!connect.enabled)
            host.powerBusy = false
            verify(connect.enabled)
            // Gaming mode on or unknown blocks switching, with one note.
            read({dnd: false, gaming: true, devices: [phone, laptop]})
            tryCompare(rows(), "length", 2)
            verify(note.visible)
            compare(note.text, "Turn off Bluetooth gaming mode to switch devices.")
            verify(!rows()[1].defaultActionButtonAction.enabled)
            host.localeName = "es_CL"
            compare(note.text, "Desactiva el modo gaming Bluetooth para cambiar de dispositivo.")
            host.localeName = "en_US"
            read({dnd: false, gaming: null, devices: [phone, laptop]})
            tryCompare(rows(), "length", 2)
            compare(note.text, "Switching devices needs Bluetooth gaming mode to be read first.")
            verify(!rows()[1].defaultActionButtonAction.enabled)
            // The note sits on the device titles' column.
            compare(note.mapToItem(findChild(view, "deviceList").contentItem, 0, 0).x
                    - findChild(view, "modesHeader").mapToItem(findChild(view, "deviceList").contentItem, 0, 0).x,
                    view.titleColumn)
            // An empty list explains itself.
            read({dnd: false, gaming: false, devices: []})
            tryCompare(rows(), "length", 0)
            verify(header.visible)
            compare(note.text, "No known devices.")
            host.localeName = "es_CL"
            compare(note.text, "Sin dispositivos conocidos.")
            host.localeName = "en_US"
            // While the reading runs.
            fakeSettings.response = null
            fakeSettings.busy = true
            verify(header.visible)
            compare(note.text, "Reading…")
            fakeSettings.busy = false
            // A list the reading could not return is left out.
            read({dnd: false, gaming: false, devices: null}, "usb", {devices: "timeout"})
            verify(!header.visible)
            verify(!note.visible)
            compare(rows().length, 0)
            // Without a confirmed link an earlier list is not shown.
            read({dnd: false, gaming: false, devices: [phone]})
            tryCompare(rows(), "length", 1)
            host.status = linked("unknown")
            compare(rows().length, 0)
        }
        function test_feedback_slot() {
            // A failed pairing: an error with Try Again under the placeholder,
            // which asks again.
            host.status = linked("disconnected")
            host.pairingError = "Couldn't pair."
            let message = feedback()
            verify(message !== null)
            compare(message.type, Kirigami.MessageType.Error)
            compare(message.text, "Couldn't pair.")
            verify(message.showCloseButton)
            tryVerify(() => message.mapToItem(view, 0, 0).y > placeholder().mapToItem(view, 0, 0).y)
            compare(message.actions.length, 1)
            const retry = message.actions[0]
            compare(retry.text, "Try Again")
            compare(retry.icon.name, "view-refresh-symbolic")
            verify(retry.enabled)
            retry.trigger()
            compare(openedPrompt().title, "Pair Headset?")
            closePrompt()
            host.localeName = "es_CL"
            compare(feedback().actions[0].text, "Reintentar")
            host.localeName = "en_US"
            // Try Again waits for the dongle like the command.
            host.status = {ok: true, usb: {adapter: "missing"}, bluetooth: {state: "disconnected"}}
            verify(!feedback().actions[0].enabled)
            host.status = linked("disconnected")
            host.pairingError = ""
            // A successful pairing says what to do next, with nothing to retry.
            host.pairingResult = "Paired."
            compare(feedback().type, Kirigami.MessageType.Positive)
            compare(feedback().actions.length, 0)
            host.pairingResult = ""
            compare(feedback(), null)
            // A failed power-off sits under the headset card and asks again.
            host.status = linked("connected")
            read({dnd: false, gaming: false, devices: []})
            host.powerError = "Couldn't turn off the headset."
            message = feedback()
            compare(message.type, Kirigami.MessageType.Error)
            tryVerify(() => yOf(message) > yOf(findChild(view, "hero")))
            tryVerify(() => yOf(message) < yOf(findChild(view, "modesHeader")))
            message.actions[0].trigger()
            compare(openedPrompt().title, "Turn Off Headset?")
            closePrompt()
            // The command's notice wins over a settings notice.
            fakeSettings.error = "label:timeout"
            fakeSettings.errorCode = "timeout"
            compare(feedback().text, "Couldn't turn off the headset.")
            host.powerError = ""
            fakeSettings.error = ""
            fakeSettings.errorCode = ""
            compare(feedback(), null)
        }
        function test_settings_failures_in_plain_words() {
            host.status = linked("connected")
            // Nothing could be read: the sections go and one warning says so,
            // with Try Again for the one read.
            fakeSettings.error = "label:timeout"
            fakeSettings.errorCode = "timeout"
            verify(view.readFailed)
            verify(!findChild(view, "modesHeader").visible)
            verify(!findChild(view, "dnd").visible)
            verify(!findChild(view, "devicesHeader").visible)
            let message = feedback()
            compare(message.type, Kirigami.MessageType.Warning)
            compare(message.text, "Couldn't read the headset.")
            compare(message.actions.length, 1)
            message.actions[0].trigger()
            compare(refreshSpy.count, 1)
            host.localeName = "es_CL"
            compare(feedback().text, "No se pudo leer el auricular.")
            host.localeName = "en_US"
            // A reason is added when the user can act on it.
            fakeSettings.errorCode = "missing-adapter"
            fakeSettings.error = "label:missing-adapter"
            compare(feedback().text, "Couldn't read the headset. label:missing-adapter")
            fakeSettings.busy = true
            verify(!feedback().actions[0].enabled)
            fakeSettings.busy = false
            // A change the headset rejected keeps the reading: the switch stays
            // to try again and the warning has no action.
            fakeSettings.requestFeature = "dnd"
            fakeSettings.errorCode = "rejected"
            fakeSettings.error = "label:rejected"
            read({dnd: true, gaming: false, devices: [phone]})
            verify(!view.readFailed)
            verify(findChild(view, "dnd").control.visible)
            message = feedback()
            compare(message.type, Kirigami.MessageType.Warning)
            compare(message.text, "Couldn't change the Do not disturb setting. label:rejected")
            compare(message.actions.length, 0)
            host.localeName = "es_CL"
            compare(feedback().text, "No se pudo cambiar el ajuste No molestar. label:rejected")
            host.localeName = "en_US"
            fakeSettings.requestFeature = "devices"
            fakeSettings.errorCode = "gaming-active"
            fakeSettings.error = "label:gaming-active"
            compare(feedback().text, "Couldn't switch devices. label:gaming-active")
            // A change that may have happened leaves nothing known: the read
            // is offered again.
            fakeSettings.response = null
            fakeSettings.requestFeature = "gaming"
            fakeSettings.errorCode = "timeout"
            fakeSettings.error = "label:timeout"
            verify(view.readFailed)
            message = feedback()
            compare(message.text, "Couldn't change Bluetooth gaming mode. label:timeout")
            compare(message.actions.length, 1)
            host.localeName = "es_CL"
            compare(feedback().text, "No se pudo cambiar el modo gaming Bluetooth. label:timeout")
            host.localeName = "en_US"
            fakeSettings.error = ""
            fakeSettings.errorCode = ""
            fakeSettings.requestFeature = ""
            // One setting the reading could not return: named, with Try
            // Again, and its row says Unknown.
            read({dnd: false, gaming: null, devices: [phone]}, "usb", {gaming: "timeout"})
            message = feedback()
            compare(message.type, Kirigami.MessageType.Warning)
            compare(message.text, "Couldn't read Bluetooth gaming mode.")
            compare(findChild(findChild(view, "gaming"), "modeNote").text, "Unknown")
            message.actions[0].trigger()
            compare(refreshSpy.count, 2)
            host.localeName = "es_CL"
            compare(feedback().text, "No se pudo leer el modo gaming Bluetooth.")
            host.localeName = "en_US"
            read({dnd: null, gaming: null, devices: null}, "usb", {dnd: "timeout", gaming: "timeout", devices: "timeout"})
            compare(feedback().text, "Couldn't read some settings.")
            host.localeName = "es_CL"
            compare(feedback().text, "No se pudieron leer algunos ajustes.")
            host.localeName = "en_US"
            // Notices about settings need the confirmed link they describe,
            // also after the popup closes and opens again.
            fakeSettings.error = "label:timeout"
            fakeSettings.errorCode = "timeout"
            for (const state of [linked("disconnected"), linked("unknown"), null, noDongle]) {
                host.status = state
                compare(feedback(), null)
                view.activeView = false
                view.activeView = true
                compare(feedback(), null)
            }
        }
        function test_closed_notice_returns_with_a_new_attempt() {
            host.status = linked("connected")
            fakeSettings.error = "label:timeout"
            fakeSettings.errorCode = "timeout"
            const message = feedback()
            const close = findAll(message, item => item.icon !== undefined && item.icon.name === "dialog-close"
                                  && item.visible)[0]
            verify(close !== undefined)
            // Laid out inside the view before it is clicked.
            tryVerify(() => close.mapToItem(view, 0, 0).x > 0)
            mouseClick(close)
            tryCompare(view, "noticeShown", false)
            tryVerify(() => feedback() === null)
            // The same notice stays closed until something is tried again.
            fakeSettings.errorCode = "timeout"
            compare(feedback(), null)
            fakeSettings.busy = true
            fakeSettings.busy = false
            verify(feedback() !== null)
            // Closing the popup is not a dismissal of the next showing.
            view.dismissedNotice = feedback().text
            compare(feedback(), null)
            view.activeView = false
            view.activeView = true
            verify(feedback() !== null)
            // A new command shows its own notice again.
            view.dismissedNotice = feedback().text
            host.pairingBusy = true
            verify(view.noticeShown)
        }
        function test_sections_in_dependency_order() {
            host.status = linked("connected")
            host.battery = {percent: 80, state: "Discharging"}
            host.powerError = "Couldn't turn off the headset."
            read({dnd: false, gaming: false, devices: [phone, laptop]})
            tryCompare(rows(), "length", 2)
            const order = [findChild(view, "hero"), feedback(), findChild(view, "modesHeader"), findChild(view, "dnd"),
                           findChild(view, "gaming"), findChild(view, "devicesHeader"), rows()[0], rows()[1]]
            for (let index = 1; index < order.length; ++index)
                tryVerify(() => yOf(order[index]) > yOf(order[index - 1]), 5000, order[index].objectName)
            compare(findChild(view, "modesHeader").text, "Modes")
            host.localeName = "es_CL"
            compare(findChild(view, "modesHeader").text, "Modos")
            host.localeName = "en_US"
            // One contextual help in the popup, in the Modes heading.
            const helps = findAll(view, item => item.toolTipText !== undefined && item.visible)
            compare(helps.length, 1)
            compare(helps[0].objectName, "modesHelp")
            compare(helps[0].toolTipText, "Do not disturb keeps calls from a phone connected over Bluetooth from "
                    + "interrupting the dongle's audio; desktop notifications are not affected. Bluetooth gaming mode "
                    + "lowers Bluetooth audio delay; it is not the Game sound profile and changes only over Bluetooth. "
                    + "Bluetooth Devices (Razer Quick Connect) moves the headset's Bluetooth link to a device it already "
                    + "knows, while gaming mode is off.")
            host.localeName = "es_CL"
            compare(helps[0].toolTipText, "No molestar evita que las llamadas de un teléfono conectado por Bluetooth "
                    + "interrumpan el audio del dongle; no afecta a las notificaciones del escritorio. El modo gaming "
                    + "Bluetooth reduce el retraso del audio Bluetooth; no es el perfil de sonido Juegos y solo se cambia "
                    + "por Bluetooth. Dispositivos Bluetooth (Quick Connect de Razer) mueve la conexión Bluetooth del "
                    + "auricular a un dispositivo que ya conoce, con el modo gaming desactivado.")
            host.localeName = "en_US"
        }
        function test_keyboard_moves_through_the_body() {
            host.status = linked("connected", {state: "connected", address: "A1:B2:C3:D4:E5:F6"})
            host.battery = {percent: 80, state: "Discharging"}
            read({dnd: false, gaming: false, devices: [phone, laptop]}, "bluetooth")
            tryCompare(rows(), "length", 2)
            const hero = findChild(view, "hero")
            const dnd = findChild(view, "dnd").control
            const gaming = findChild(view, "gaming").control
            const list = findChild(view, "deviceList")
            const plus = findChild(view.header, "primaryAction")
            plus.forceActiveFocus(Qt.TabFocusReason)
            // Down from the heading enters the body at the headset card,
            // highlighted.
            keyClick(Qt.Key_Down)
            tryVerify(() => hero.activeFocus)
            verify(hero.visualFocus)
            verify(hero.background.children[0].visible)
            keyClick(Qt.Key_Down)
            tryVerify(() => dnd.activeFocus)
            keyClick(Qt.Key_Down)
            tryVerify(() => gaming.activeFocus)
            keyClick(Qt.Key_Down)
            tryVerify(() => list.currentIndex === 0 && list.currentItem.activeFocus)
            // Up walks back to the heading.
            keyClick(Qt.Key_Up)
            tryVerify(() => gaming.activeFocus)
            keyClick(Qt.Key_Up)
            tryVerify(() => dnd.activeFocus)
            keyClick(Qt.Key_Up)
            tryVerify(() => hero.activeFocus)
            keyClick(Qt.Key_Up)
            tryVerify(() => plus.activeFocus)
            // A control that cannot be used is skipped.
            read({dnd: false, gaming: false, devices: [phone, laptop]}, "usb")
            plus.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Down)
            tryVerify(() => dnd.activeFocus)
            keyClick(Qt.Key_Down)
            tryVerify(() => list.currentIndex === 0 && list.currentItem.activeFocus)
            // Down past the last control does not wrap to the top.
            read({dnd: false, gaming: false, devices: []}, "usb")
            dnd.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Down)
            wait(50)
            verify(!hero.activeFocus)
            // In the tray, which draws the heading, Up from the card stays.
            const trayHero = findChild(trayView, "hero")
            trayHero.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Up)
            wait(50)
            verify(trayHero.activeFocus)
            // While the headset turns off, the card takes no focus.
            host.powerBusy = true
            plus.forceActiveFocus(Qt.TabFocusReason)
            compare(view.bodyControls.indexOf(hero), -1)
            host.powerBusy = false
        }
        function test_tray_body_scrolls_without_covering_rows() {
            // The tray gives every applet the same popup size; with more rows
            // than fit, the scrollbar takes the right edge and no row sits
            // under it or scrolls sideways.
            host.status = bluetoothOnly("connected")
            host.battery = {percent: 80, state: "Discharging"}
            read({dnd: true, gaming: true, devices: [phone, laptop, tablet,
                  {address: "112233445566", name: "Desk", active: false}]}, "bluetooth")
            const scroll = findChild(trayView, "bodyScroll")
            const list = findChild(trayView, "deviceList")
            for (const height of [Kirigami.Units.gridUnit * 14, Kirigami.Units.gridUnit * 40]) {
                trayView.height = height
                const scrolling = height < Kirigami.Units.gridUnit * 20
                tryCompare(scroll.PC3.ScrollBar.vertical, "visible", scrolling)
                tryCompare(rows(trayView), "length", 4)
                for (const row of rows(trayView).concat([findChild(trayView, "dnd"), findChild(trayView, "hero")]))
                    tryVerify(() => row.mapToItem(list, row.width, 0).x <= list.width - list.rightMargin + 0.5,
                              5000, row.objectName)
                verify(list.contentWidth <= list.width)
                list.contentX = 0
                mouseWheel(scroll, scroll.width / 2, scroll.height / 2, -120, 0)
                wait(50)
                compare(list.contentX, 0)
            }
            trayView.height = Qt.binding(() => trayView.implicitHeight)
            // A notice that grows the header keeps a list shown from its top
            // at its top.
            tryCompare(list, "contentY", list.originY - list.topMargin)
            host.powerError = "Couldn't turn off the headset."
            wait(50)
            compare(list.contentY, list.originY - list.topMargin)
        }
        function test_fixed_popup_size() {
            // 24 by 24 grid units in a panel and in the tray, in every state.
            for (const state of [null, linked("connected"), linked("disconnected")]) {
                host.status = state
                for (const target of [view, trayView]) {
                    compare(target.implicitWidth, Kirigami.Units.gridUnit * 24)
                    compare(target.implicitHeight, Kirigami.Units.gridUnit * 24)
                    compare(target.Layout.minimumWidth, Kirigami.Units.gridUnit * 24)
                    compare(target.Layout.minimumHeight, Kirigami.Units.gridUnit * 24)
                }
            }
        }
        function test_hidden_settings_page_sends_nothing() {
            // Plasma may create the page without showing it; no command runs.
            const component = Qt.createComponent("../plasmoid/contents/ui/ConfigHeadset.qml")
            compare(component.status, Component.Ready, component.errorString())
            const page = component.createObject(null)
            verify(page !== null)
            verify(!page.shown)
            // Plasma's Apply calls saveConfig(); with nothing unsaved it sends nothing.
            verify(!page.unsavedChanges)
            page.saveConfig()
            wait(20)
            const controller = findChild(page, "headsetController")
            verify(!controller.busy)
            compare(controller.connectedSources.length, 0)
            page.destroy()
        }
        function test_settings_category_and_icon() {
            const model = Qt.createComponent("../plasmoid/contents/config/config.qml").createObject(null)
            verify(model !== null)
            // One page for what the headset stores; its connection is in the popup.
            compare(model.count, 1)
            compare(model.get(0).source, "ConfigHeadset.qml")
            compare(model.get(0).icon, "audio-headset")
            compare(model.get(0).name, Qt.locale().name.startsWith("es") ? "Auricular" : "Headset")
            model.destroy()
            for (const removed of ["ConfigEqualizer.qml", "ConfigPowerSaving.qml", "ConfigQuickConnect.qml"])
                compare(Qt.createComponent("../plasmoid/contents/ui/" + removed).status, Component.Error)
        }
        function test_config_pages_compile() {
            for (const page of ["../plasmoid/contents/ui/ConfigHeadset.qml",
                                "../plasmoid/contents/config/config.qml"]) {
                const component = Qt.createComponent(page)
                compare(component.status, Component.Ready, component.errorString())
            }
        }
        function test_battery_reconnect_and_late_data() {
            const frame = {Product: "Razer Barracuda X (2022)", Type: "Headset",
                           "Is Power Supply": false, "Plugged in": true,
                           Percent: 65, State: "Discharging"}
            monitor.newData("Battery1", frame)
            compare(monitor.battery.percent, 65)
            monitor.sourceRemoved("Battery1")
            compare(monitor.battery, null)
            monitor.sourceAdded("Battery1")
            monitor.newData("Battery1", {})
            compare(monitor.battery, null)
            monitor.newData("Battery1", Object.assign({}, frame, {Percent: 64}))
            compare(monitor.battery.percent, 64)
            monitor.sourceRemoved("Battery1")
            monitor.sourceAdded("Battery2")
            monitor.newData("Battery2", Object.assign({}, frame, {Percent: 63, State: "Charging"}))
            compare(monitor.battery.percent, 63)
            compare(monitor.battery.state, "Charging")
            monitor.newData("Battery2", Object.assign({}, frame, {Percent: 0, State: "Unknown"}))
            compare(monitor.battery, null)
            monitor.newData("Battery2", frame)
            compare(monitor.battery.percent, 65)
            monitor.sourceRemoved("Battery2")
            compare(monitor.battery, null)
        }
        function test_link_monitor_serializes_queries() {
            link.status = null
            link.refresh()
            verify(link.running)
            compare(link.connectedSources.length, 1)
            link.refresh()
            verify(link.pending)
            compare(link.connectedSources.length, 1)
            link.newData(link.connectedSources[0],
                         {stdout: '{"ok": true, "usb": {"adapter": "missing"}, "bluetooth": null}'})
            compare(link.status.usb.adapter, "missing")
            // The pending refresh starts once the previous query finished.
            verify(link.running)
            verify(!link.pending)
            link.newData(link.connectedSources[0], {stdout: ""})
            verify(!link.running)
            compare(link.status.ok, false)
            compare(link.connectedSources.length, 0)
            link.status = null
        }
        function test_main_component_compiles() {
            const component = Qt.createComponent("../plasmoid/contents/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
        }
    }
}
