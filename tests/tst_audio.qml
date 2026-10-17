import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../plasmoid/contents/ui"
import "../plasmoid/contents/code/output.js" as Output

Item {
    id: host
    width: 600
    height: 700
    // Stands in for HeadsetController; nothing is sent to a headset.
    QtObject {
        id: fakeHeadset
        property bool busy: false
        property var response: null
        property string error: ""
        property string errorCode: ""
        property string targetKey: "usb"
        property var requests: []
        property var chains: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]); }
        function requestChain(values) { chains = chains.concat([values]); busy = true; }
        function errorLabel(code) { return "label:" + code; }
    }
    HeadsetSettings {
        id: page
        anchors.fill: parent
        visible: false
        controller: fakeHeadset
        localeName: "en_US"
    }
    // An unknown engine name runs nothing; an empty one would keep the
    // component's executable engine.
    HeadsetController { id: nativeBackend; engine: "barracuda-test-none" }
    TestCase {
        name: "HeadsetSettings"
        when: windowShown
        readonly property var flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        // A reply as HeadsetController delivers it: busy ends, then the reply.
        function reply(result) {
            fakeHeadset.busy = false;
            fakeHeadset.response = result;
            fakeHeadset.loaded(result);
        }
        // A failed reply: busy ends, then the error.
        function fail(code, keepResponse) {
            fakeHeadset.busy = false;
            if (!keepResponse)
                fakeHeadset.response = null;
            fakeHeadset.errorCode = code;
            fakeHeadset.error = "label:" + code;
        }
        function findAll(item, test) {
            let found = test(item) ? [item] : [];
            for (const child of item.children)
                found = found.concat(findAll(child, test));
            return found;
        }
        function sliders() {
            return findAll(findChild(page, "customBands"), item => item.orientation === Qt.Vertical && item.from === -5);
        }
        function init() {
            fakeHeadset.busy = false;
            fakeHeadset.response = null;
            fakeHeadset.error = "";
            fakeHeadset.errorCode = "";
            fakeHeadset.requests = [];
            fakeHeadset.chains = [];
            page.localeName = "en_US";
            page.pendingPreset = -1;
            page.pendingStandby = -1;
            page.bands = flat.slice();
            page.bandsDirty = false;
            page.saving = false;
            page.saveFailed = false;
            page.chainFeatures = [];
            page.visible = true;
        }
        function cleanup() {
            page.visible = false;
            fakeHeadset.busy = false;
            fakeHeadset.response = null;
            fakeHeadset.error = "";
            fakeHeadset.errorCode = "";
            page.saving = false;
        }
        function test_placeholders_before_a_reading() {
            const reading = findChild(page, "settingsReading");
            const unread = findChild(page, "settingsUnavailable");
            const form = findChild(page, "profileSelector");
            const message = findChild(page, "settingsMessage");
            // The first reading runs: a loading placeholder, nothing else.
            fakeHeadset.busy = true;
            verify(!page.loaded);
            verify(reading.visible);
            verify(!unread.visible);
            verify(!form.visible);
            verify(!message.visible);
            compare(reading.text, "Reading the headset…");
            page.localeName = "es_CL";
            compare(reading.text, "Leyendo el auricular…");
            page.localeName = "en_US";
            // Nothing was read: a placeholder with Try Again.
            fakeHeadset.busy = false;
            verify(!reading.visible);
            verify(unread.visible);
            compare(unread.text, "Settings not read");
            compare(unread.explanation, "Turn on the headset to read its settings.");
            compare(unread.icon.name, "audio-headset");
            const again = unread.helpfulAction;
            compare(again.objectName, "readAgain");
            compare(again.text, "Try Again");
            compare(again.icon.name, "view-refresh-symbolic");
            verify(again.enabled);
            again.trigger();
            compare(fakeHeadset.requests, [{op: "status"}]);
            page.localeName = "es_CL";
            compare(unread.text, "Ajustes sin leer");
            compare(unread.explanation, "Enciende el auricular para leer sus ajustes.");
            compare(again.text, "Reintentar");
            page.localeName = "en_US";
            // A failed reading says why, in the controller's words.
            fail("timeout");
            compare(unread.explanation, "label:timeout");
            fakeHeadset.busy = true;
            verify(!again.enabled);
            verify(reading.visible);
            fakeHeadset.busy = false;
            // A reply without either setting is not a reading either.
            reply({ok: true, state: {preset: null, standby: null}, errors: {preset: "timeout", standby: "timeout"}});
            fakeHeadset.error = "";
            verify(!page.loaded);
            verify(unread.visible);
            compare(unread.explanation, "Couldn't read the sound profile or idle shutdown. label:timeout");
        }
        function test_readback_on_one_page() {
            reply({ok: true, state: {preset: 7, bands: flat.slice(), gaming: false, dnd: null, standby: 15, devices: []},
                   errors: {dnd: "timeout"}});
            verify(page.loaded);
            verify(!findChild(page, "settingsReading").visible);
            verify(!findChild(page, "settingsUnavailable").visible);
            const profile = findChild(page, "profileSelector");
            const standby = findChild(page, "standbySelector");
            // Both settings are on the page.
            verify(profile.visible);
            verify(standby.visible);
            compare(profile.currentIndex, 1);
            compare(profile.currentText, "Game");
            compare(standby.currentIndex, 2);
            compare(standby.currentText, "15 min");
            verify(!profile.wheelEnabled);
            verify(!standby.wheelEnabled);
            verify(profile.enabled);
            verify(standby.enabled);
            // The popup's settings, and their read errors, are not here.
            for (const name of ["dnd", "gaming", "quickConnect", "deviceRow", "nativeDnd", "nativeGaming"])
                compare(findChild(page, name), null);
            verify(!findChild(page, "settingsMessage").visible);
            // Custom bands only with the Custom profile.
            verify(!findChild(page, "customBands").visible);
            verify(!findChild(page, "resetBands").visible);
            // Labels, profile names and accessible names in both languages.
            const expected = {
                en_US: {profile: "Sound profile:", standby: "Turn off when idle:", bands: "Bands:",
                        names: ["Default", "Game", "Music", "Movie", "Custom"], never: "Never",
                        profileName: "Sound profile", standbyName: "Turn off when idle"},
                es_CL: {profile: "Perfil de sonido:", standby: "Apagar por inactividad:", bands: "Bandas:",
                        names: ["Predeterminado", "Juegos", "Música", "Cine", "Personalizado"], never: "Nunca",
                        profileName: "Perfil de sonido", standbyName: "Apagar por inactividad"}
            };
            for (const locale of ["en_US", "es_CL"]) {
                page.localeName = locale;
                const text = expected[locale];
                compare(profile.parent.Kirigami.FormData.label, text.profile);
                compare(standby.parent.Kirigami.FormData.label, text.standby);
                compare(findChild(page, "customBands").Kirigami.FormData.label, text.bands);
                compare(Array.from(profile.model), text.names);
                compare(standby.model[0], text.never);
                compare(Array.from(standby.model).slice(1), ["5 min", "15 min", "30 min", "45 min", "60 min"]);
                compare(profile.Accessible.name, text.profileName);
                compare(standby.Accessible.name, text.standbyName);
                tryCompare(profile, "currentText", text.names[1]);
            }
            page.localeName = "en_US";
            // A stored profile the page does not know reads Unknown and
            // cannot be changed here.
            reply({ok: true, state: {preset: 3, standby: 15}, errors: {}});
            verify(!profile.enabled);
            compare(profile.currentIndex, -1);
            compare(profile.displayText, "Unknown");
            verify(!profile.enabled);
            page.localeName = "es_CL";
            compare(profile.displayText, "Desconocido");
            page.localeName = "en_US";
            // Nothing can be chosen while a request runs.
            reply({ok: true, state: {preset: 7, standby: 15}, errors: {}});
            fakeHeadset.busy = true;
            verify(!findChild(page, "profileSelector").parent.parent.enabled);
            fakeHeadset.busy = false;
            // A lost reading brings the placeholder back.
            fakeHeadset.response = null;
            verify(!page.loaded);
            verify(findChild(page, "settingsUnavailable").visible);
        }
        function test_profile_waits_for_apply() {
            const profile = findChild(page, "profileSelector");
            const custom = findChild(page, "customBands");
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            compare(profile.currentIndex, 2);
            verify(!custom.visible);
            verify(!page.unsavedChanges);
            // Choosing a profile sends nothing; Plasma's Apply is enabled.
            profile.activated(1);
            compare(fakeHeadset.requests.length, 0);
            compare(fakeHeadset.chains.length, 0);
            compare(profile.currentIndex, 1);
            compare(profile.currentText, "Game");
            verify(page.unsavedChanges);
            // Choosing the stored profile again leaves nothing to apply.
            profile.activated(2);
            verify(!page.unsavedChanges);
            compare(profile.currentIndex, 2);
            // With nothing unsaved, Apply sends nothing.
            page.save();
            compare(fakeHeadset.chains.length, 0);
            // Apply or OK sends the chosen profile.
            profile.activated(3);
            page.save();
            compare(fakeHeadset.chains, [[{op: "set", feature: "preset", value: 9}]]);
            verify(page.saving);
            verify(!page.unsavedChanges);
            // The message slot says the changes are being sent.
            const message = findChild(page, "settingsMessage");
            verify(message.visible);
            compare(message.type, Kirigami.MessageType.Information);
            compare(message.text, "Sending changes to the headset…");
            compare(message.actions.length, 0);
            page.localeName = "es_CL";
            compare(message.text, "Enviando cambios al auricular…");
            page.localeName = "en_US";
            reply({ok: true, sent: "preset", state: {preset: 9, bands: flat.slice(), standby: 15}, errors: {}});
            tryVerify(() => !page.saving);
            compare(page.pendingPreset, -1);
            compare(profile.currentIndex, 3);
            verify(!page.unsavedChanges);
            verify(!message.visible);
        }
        function test_custom_profile_and_bands_go_in_one_chain() {
            const curve = [2, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            const profile = findChild(page, "profileSelector");
            const custom = findChild(page, "customBands");
            const reset = findChild(page, "resetBands");
            const message = findChild(page, "settingsMessage");
            reply({ok: true, state: {preset: 8, bands: curve.slice(), standby: 15}, errors: {}});
            verify(!custom.visible);
            // Choosing Custom shows the stored curve for editing.
            profile.activated(4);
            verify(custom.visible);
            verify(reset.visible);
            compare(page.bands, curve);
            compare(sliders().map(slider => slider.value), curve);
            // Unchanged bands: only the profile is sent.
            compare(page.changes(), [{op: "set", feature: "preset", value: 255}]);
            compare(sliders().length, 10);
            // As a drag does, without replacing the slider's binding.
            for (let step = 0; step < 5; ++step)
                sliders()[0].decrease();
            sliders()[0].moved();
            verify(page.bandsDirty);
            verify(page.unsavedBands);
            const edited = [-3, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            // Edited bands follow the profile in one chain.
            page.save();
            compare(fakeHeadset.chains, [[{op: "set", feature: "preset", value: 255},
                                          {op: "set", feature: "bands", value: edited}]]);
            // The chain stops at a change the headset rejected: the choices
            // stay for another Apply, and the message says the changes were
            // not applied. Try Again is not offered while they wait.
            fail("rejected", true);
            tryVerify(() => !page.saving);
            verify(page.saveFailed);
            compare(profile.currentIndex, 4);
            compare(page.bands, edited);
            verify(page.unsavedChanges);
            verify(message.visible);
            compare(message.type, Kirigami.MessageType.Warning);
            compare(message.text, "Couldn't apply the changes. label:rejected");
            compare(message.actions.length, 0);
            page.localeName = "es_CL";
            compare(message.text, "No se pudieron aplicar los cambios. label:rejected");
            page.localeName = "en_US";
            // Apply again: the message clears as the chain starts.
            page.save();
            compare(fakeHeadset.chains.length, 2);
            fakeHeadset.error = "";
            verify(!page.saveFailed);
            reply({ok: true, sent: "bands", state: {preset: 255, bands: edited.slice(), standby: 15}, errors: {}});
            tryVerify(() => !page.saving);
            verify(!page.unsavedChanges);
            compare(page.pendingPreset, -1);
            compare(profile.currentIndex, 4);
            compare(page.bands, edited);
            verify(!message.visible);
            // Reset Bands is a change like any other.
            compare(reset.text, "Reset Bands");
            compare(reset.icon.name, "edit-reset");
            verify(reset.enabled);
            reset.clicked();
            verify(page.unsavedBands);
            compare(page.changes(), [{op: "set", feature: "bands", value: flat}]);
            verify(!reset.enabled);
            page.localeName = "es_CL";
            compare(reset.text, "Restablecer bandas");
            page.localeName = "en_US";
            // Bands are sent by the window's Apply, not a page button.
            compare(findChild(page, "applyNativeBands"), null);
            compare(findChild(page, "bandsUnit").text, "Hz");
            compare(sliders()[0].Accessible.name, "31 Hz");
            compare(sliders()[9].Accessible.name, "16k Hz");
        }
        function test_failed_apply_that_left_nothing_known() {
            const profile = findChild(page, "profileSelector");
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            profile.activated(1);
            page.save();
            // A change that may have reached the headset drops the reading:
            // the placeholder says the changes were not applied and offers
            // the read again, which keeps the choice for another Apply.
            fail("timeout");
            tryVerify(() => !page.saving);
            const unread = findChild(page, "settingsUnavailable");
            verify(unread.visible);
            compare(unread.explanation, "Couldn't apply the changes. label:timeout");
            verify(unread.helpfulAction.enabled);
            unread.helpfulAction.trigger();
            compare(fakeHeadset.requests, [{op: "status"}]);
            fakeHeadset.busy = true;
            fakeHeadset.error = "";
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            verify(!page.saveFailed);
            compare(profile.currentIndex, 1);
            verify(page.unsavedChanges);
        }
        function test_idle_shutdown_waits_for_apply() {
            const standby = findChild(page, "standbySelector");
            reply({ok: true, state: {preset: 7, bands: flat.slice(), standby: 15}, errors: {}});
            compare(standby.currentIndex, 2);
            verify(!page.unsavedChanges);
            standby.activated(3);
            compare(fakeHeadset.requests.length, 0);
            compare(standby.currentIndex, 3);
            verify(page.unsavedChanges);
            standby.activated(2);
            verify(!page.unsavedChanges);
            standby.activated(0);
            compare(standby.currentText, "Never");
            compare(page.changes(), [{op: "set", feature: "standby", value: 0}]);
            page.save();
            compare(fakeHeadset.chains, [[{op: "set", feature: "standby", value: 0}]]);
            reply({ok: true, sent: "standby", state: {preset: 7, standby: 0}, errors: {}});
            tryVerify(() => !page.saving);
            compare(page.pendingStandby, -1);
            compare(standby.currentIndex, 0);
            verify(!page.unsavedChanges);
            page.localeName = "es_CL";
            tryCompare(standby, "currentText", "Nunca");
        }
        function test_every_change_goes_in_one_chain() {
            const profile = findChild(page, "profileSelector");
            const standby = findChild(page, "standbySelector");
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            profile.activated(4);
            sliders()[9].increase();
            sliders()[9].moved();
            standby.activated(5);
            // The profile, then its bands, then idle shutdown.
            compare(page.changes(), [{op: "set", feature: "preset", value: 255},
                                     {op: "set", feature: "bands", value: [0, 0, 0, 0, 0, 0, 0, 0, 0, 1]},
                                     {op: "set", feature: "standby", value: 60}]);
            page.save();
            compare(fakeHeadset.chains.length, 1);
            compare(fakeHeadset.chains[0].length, 3);
            // One request at a time: a second Apply while it runs sends nothing.
            page.save();
            compare(fakeHeadset.chains.length, 1);
        }
        function test_chain_reply_names_only_its_last_step() {
            const profile = findChild(page, "profileSelector");
            const standby = findChild(page, "standbySelector");
            // Bands, then idle shutdown: the chain prints the idle shutdown
            // reply, and the bands it applied before are no longer unsaved.
            reply({ok: true, state: {preset: 255, bands: flat.slice(), standby: 15}, errors: {}});
            sliders()[9].increase();
            sliders()[9].moved();
            standby.activated(3);
            const edited = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
            compare(page.changes(), [{op: "set", feature: "bands", value: edited},
                                     {op: "set", feature: "standby", value: 30}]);
            page.save();
            reply({ok: true, sent: "standby", state: {preset: 255, bands: edited.slice(), standby: 30}, errors: {}});
            tryVerify(() => !page.saving);
            compare(page.chainFeatures, []);
            verify(!page.bandsDirty);
            verify(!page.unsavedBands);
            verify(!page.unsavedChanges);
            compare(page.changes(), []);
            compare(page.pendingStandby, -1);
            compare(page.bands, edited);
            // A profile, then idle shutdown: the profile is no longer pending.
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            profile.activated(1);
            standby.activated(3);
            page.save();
            compare(fakeHeadset.chains[1], [{op: "set", feature: "preset", value: 7},
                                            {op: "set", feature: "standby", value: 30}]);
            reply({ok: true, sent: "standby", state: {preset: 7, bands: flat.slice(), standby: 30}, errors: {}});
            tryVerify(() => !page.saving);
            compare(page.pendingPreset, -1);
            compare(page.pendingStandby, -1);
            verify(!page.unsavedChanges);
            // A later reading after an outside change shows it as stored,
            // with nothing to apply.
            reply({ok: true, state: {preset: 9, bands: flat.slice(), standby: 30}, errors: {}});
            compare(page.selectedPreset, 9);
            compare(profile.currentIndex, 3);
            verify(!page.unsavedChanges);
            compare(page.changes(), []);
            // The profile, its bands and idle shutdown in one chain.
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}});
            profile.activated(4);
            sliders()[0].increase();
            sliders()[0].moved();
            standby.activated(1);
            page.save();
            compare(fakeHeadset.chains[2].map(request => request.feature), ["preset", "bands", "standby"]);
            reply({ok: true, sent: "standby", state: {preset: 255, bands: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0], standby: 5},
                   errors: {}});
            tryVerify(() => !page.saving);
            compare(page.pendingPreset, -1);
            verify(!page.bandsDirty);
            verify(!page.unsavedChanges);
        }
        function test_read_failures_name_the_setting() {
            const standby = findChild(page, "standbySelector");
            const message = findChild(page, "settingsMessage");
            // Idle shutdown could not be read: Unknown and disabled, never a
            // default that looks real, and the message offers the read again.
            reply({ok: true, state: {preset: 8, bands: flat.slice(), standby: null}, errors: {standby: "timeout"}});
            verify(page.loaded);
            verify(!standby.enabled);
            compare(standby.currentIndex, -1);
            compare(standby.displayText, "Unknown");
            verify(message.visible);
            compare(message.type, Kirigami.MessageType.Warning);
            compare(message.text, "Couldn't read idle shutdown. label:timeout");
            compare(message.actions.length, 1);
            compare(message.actions[0].objectName, "readAgain");
            compare(message.actions[0].text, "Try Again");
            message.actions[0].trigger();
            compare(fakeHeadset.requests, [{op: "status"}]);
            page.localeName = "es_CL";
            compare(standby.displayText, "Desconocido");
            compare(message.text, "No se pudo leer el apagado por inactividad. label:timeout");
            compare(message.actions[0].text, "Reintentar");
            page.localeName = "en_US";
            // Each failed setting is named; the first one's reason follows.
            reply({ok: true, state: {preset: null, bands: null, standby: 15},
                   errors: {preset: "busy", bands: "timeout"}});
            compare(message.text, "Couldn't read the sound profile or the custom bands. label:busy");
            verify(!findChild(page, "profileSelector").enabled);
            compare(findChild(page, "profileSelector").displayText, "Unknown");
            page.localeName = "es_CL";
            compare(message.text, "No se pudo leer el perfil de sonido ni las bandas personalizadas. label:busy");
            page.localeName = "en_US";
            reply({ok: true, state: {preset: 255, bands: null, standby: null},
                   errors: {preset: "busy", bands: "timeout", standby: "timeout"}});
            compare(message.text, "Couldn't read the sound profile, the custom bands or idle shutdown. label:busy");
            page.localeName = "es_CL";
            compare(message.text,
                    "No se pudo leer el perfil de sonido, las bandas personalizadas ni el apagado por inactividad. label:busy");
            page.localeName = "en_US";
            // The popup's settings are read on the same reply, but their
            // errors belong to the popup.
            reply({ok: true, state: {preset: 7, standby: 15}, errors: {devices: "timeout", dnd: "timeout", gaming: "timeout"}});
            verify(!message.visible);
            compare(page.problem, "");
            // Try Again waits while a reading runs.
            reply({ok: true, state: {preset: 7, standby: null}, errors: {standby: "timeout"}});
            fakeHeadset.busy = true;
            verify(!message.actions[0].enabled);
        }
        function test_loaded_custom_bands_reach_the_sliders() {
            const curve = [2, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            const result = {ok: true, state: {preset: 255, bands: curve.slice(), standby: 15}, errors: {}};
            fakeHeadset.response = result;
            // The reply reaches the page as a var signal argument.
            fakeHeadset.loaded(result);
            compare(page.bands, curve);
            verify(Array.isArray(page.bands));
            verify(findChild(page, "customBands").visible);
            compare(sliders().length, 10);
            compare(sliders().map(slider => slider.value), curve);
            // A reply without ten values keeps the current curve.
            const partial = {ok: true, state: {preset: 255, bands: [1, 2], standby: 15}, errors: {}};
            fakeHeadset.response = partial;
            fakeHeadset.loaded(partial);
            compare(page.bands, curve);
        }
        function test_contextual_help_translation() {
            reply({ok: true, state: {preset: 7, bands: flat.slice(), gaming: false, dnd: false, standby: 15, devices: []},
                   errors: {}});
            // The page's only help button, next to the sound profile.
            compare(findAll(page, item => item.toolTipText !== undefined && item.visible).length, 1);
            for (const name of ["dndHelp", "standbyHelp", "quickConnectHelp", "refreshHelp", "bandsHelp"])
                compare(findChild(page, name), null);
            const help = findChild(page, "profileHelp");
            verify(help.visible);
            compare(help.toolTipText, "Profiles and the custom bands are stored on the headset. With Custom, each band "
                    + "is relative and 0 is neutral. Apply sends the changes; Cancel discards them. The Game profile "
                    + "is not Bluetooth gaming mode.");
            page.localeName = "es_CL";
            compare(help.toolTipText, "Los perfiles y las bandas personalizadas se guardan en el auricular. Con "
                    + "Personalizado, cada banda es relativa y 0 es neutro. Aplicar envía los cambios; Cancelar los "
                    + "descarta. El perfil Juegos no es el modo gaming Bluetooth.");
        }
        function test_transport_change_drops_pending_choices() {
            reply({ok: true, state: {preset: 8, standby: 15}, errors: {}});
            findChild(page, "standbySelector").activated(1);
            verify(page.unsavedChanges);
            // Another headset target: nothing chosen for the old one is kept,
            // even once the new one has been read.
            fakeHeadset.targetKey = "01:02:03:04:05:06";
            compare(page.pendingStandby, -1);
            reply({ok: true, state: {preset: 8, standby: 15}, errors: {}});
            verify(!page.unsavedChanges);
            fakeHeadset.targetKey = "usb";
        }
        function test_native_error_clears_confirmed_state() {
            // A failed read leaves nothing known.
            nativeBackend.chainLength = 1;
            nativeBackend.requestFeature = "";
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: "rejected"})});
            compare(nativeBackend.response, null);
            compare(nativeBackend.errorCode, "rejected");
            // A change that may have reached the headset leaves nothing known.
            nativeBackend.requestFeature = "dnd";
            for (const code of ["timeout", "unconfirmed", "invalid-response", "bluetooth-unavailable", "route-failed"]) {
                nativeBackend.response = {state: {dnd: true}};
                nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: code})});
                compare(nativeBackend.response, null, code);
                compare(nativeBackend.errorCode, code);
                compare(nativeBackend.error, nativeBackend.errorLabel(code));
            }
            // A change the headset certainly did not apply keeps the reading,
            // so the controls stay at confirmed values.
            for (const code of ["rejected", "busy", "gaming-active", "unknown-device", "gaming-not-applied",
                                "missing-adapter", "unknown-link", "permission-denied", "driver-required"]) {
                const reading = {state: {dnd: true}};
                nativeBackend.response = reading;
                nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: code})});
                compare(nativeBackend.response, reading, code);
                compare(nativeBackend.errorCode, code);
            }
            // An unreadable reply means the helper is missing or too old; its
            // output goes to the journal, not to the view.
            nativeBackend.newData("fake", {stdout: "barracuda-headset: command not found", stderr: ""});
            compare(nativeBackend.response, null);
            compare(nativeBackend.errorCode, "helper-missing");
            compare(nativeBackend.error, "Install or update the barracuda-pair package.");
            nativeBackend.requestFeature = "";
            nativeBackend.error = "";
            nativeBackend.errorCode = "";
        }
        function test_error_labels_in_plain_language() {
            const expected = {
                "helper-missing": ["Install or update the barracuda-pair package.",
                                   "Instala o actualiza el paquete barracuda-pair."],
                "driver-required": ["Install or update the Barracuda driver.",
                                    "Instala o actualiza el driver del Barracuda."],
                "missing-adapter": ["Plug in the USB dongle.", "Conecta el dongle USB."],
                "unknown-link": ["The headset link is not confirmed.", "La conexión del auricular no está confirmada."],
                "permission-denied": ["Install or update the Barracuda driver and add your user to the audio group.",
                                      "Instala o actualiza el driver del Barracuda y añade tu usuario al grupo audio."],
                "bluetooth-runtime-unavailable": ["Install or update the barracuda-pair package to use Bluetooth.",
                                                  "Instala o actualiza el paquete barracuda-pair para usar Bluetooth."],
                "bluetooth-unsupported": ["This headset can't be controlled over Bluetooth.",
                                          "Este auricular no se puede controlar por Bluetooth."],
                "bluetooth-unavailable": ["The headset didn't answer over Bluetooth.", "El auricular no respondió por Bluetooth."],
                "invalid-response": ["The headset sent an unexpected answer.", "El auricular envió una respuesta inesperada."],
                "busy": ["Another headset command is running. Try again in a moment.",
                         "Hay otra orden en curso. Vuelve a intentarlo en un momento."],
                "timeout": ["The headset didn't answer.", "El auricular no respondió."],
                "route-failed": ["Unplug the USB dongle and plug it in again.", "Desconecta el dongle USB y vuelve a conectarlo."],
                "rejected": ["The headset rejected the change.", "El auricular rechazó el cambio."],
                "unconfirmed": ["The headset didn't confirm the change.", "El auricular no confirmó el cambio."],
                "gaming-active": ["Turn off Bluetooth gaming mode first.", "Desactiva primero el modo gaming Bluetooth."],
                "unknown-device": ["The headset no longer knows this device.", "El auricular ya no conoce este dispositivo."],
                "gaming-not-applied": ["The headset didn't change Bluetooth gaming mode.",
                                       "El auricular no cambió el modo gaming Bluetooth."],
                "device-error": ["This setting isn't available on this headset.",
                                 "Este ajuste no está disponible en este auricular."]
            };
            for (const code of Object.keys(expected)) {
                nativeBackend.localeName = "en_US";
                compare(nativeBackend.errorLabel(code), expected[code][0]);
                nativeBackend.localeName = "es_CL";
                compare(nativeBackend.errorLabel(code), expected[code][1]);
            }
            // No label names a helper command, PATH or HID.
            for (const locale of ["en_US", "es_CL"]) {
                nativeBackend.localeName = locale;
                for (const code of Object.keys(expected))
                    verify(!/barracuda-headset|PATH|HID/.test(nativeBackend.errorLabel(code)), code);
            }
            nativeBackend.localeName = "en_US";
        }
        function test_controller_remembers_the_requested_feature() {
            // Feedback appears beside the control whose request produced it.
            nativeBackend.request({op: "set", feature: "devices", value: "01:02:03:04:05:06"});
            verify(nativeBackend.busy);
            compare(nativeBackend.requestFeature, "devices");
            compare(nativeBackend.connectedSources.length, 1);
            verify(nativeBackend.connectedSources[0].includes('"feature":"devices"'));
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: false, error: "gaming-active"})});
            verify(!nativeBackend.busy);
            compare(nativeBackend.requestFeature, "devices");
            compare(nativeBackend.error, nativeBackend.errorLabel("gaming-active"));
            nativeBackend.request({op: "status"});
            compare(nativeBackend.requestFeature, "");
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: true, transport: "usb", state: {dnd: true}, errors: {}})});
            verify(!nativeBackend.busy);
            compare(nativeBackend.error, "");
            compare(nativeBackend.response.state.dnd, true);
            nativeBackend.response = null;
        }
        function test_controller_chains_configuration_changes() {
            const values = [{op: "set", feature: "preset", value: 255},
                            {op: "set", feature: "bands", value: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]}];
            nativeBackend.requestChain([]);
            verify(!nativeBackend.busy);
            nativeBackend.requestChain(values);
            verify(nativeBackend.busy);
            compare(nativeBackend.requestFeature, "bands");
            compare(nativeBackend.connectedSources, [Output.headsetChainCommand(values, nativeBackend.target)]);
            // One request at a time.
            nativeBackend.requestChain(values);
            nativeBackend.request({op: "status"});
            compare(nativeBackend.connectedSources.length, 1);
            // The chain prints its last reply.
            nativeBackend.newData(nativeBackend.connectedSources[0], {stdout: JSON.stringify(
                {ok: true, sent: "bands", transport: "usb", state: {preset: 255, bands: values[1].value}, errors: {}}) + "\n"});
            verify(!nativeBackend.busy);
            compare(nativeBackend.response.state.preset, 255);
            // A change shows in the reading it returns, not in a message.
            compare(nativeBackend.error, "");
            compare(nativeBackend.message, undefined);
            nativeBackend.response = null;
        }
        function test_failed_chain_leaves_nothing_known() {
            const reading = {ok: true, transport: "usb", state: {preset: 8, bands: flat.slice(), standby: 15}, errors: {}};
            const values = [{op: "set", feature: "preset", value: 255},
                            {op: "set", feature: "bands", value: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]}];
            // The reply is the failing step's; a step before it may already
            // have changed the headset, even when the failure itself left the
            // headset as it was.
            for (const code of ["rejected", "busy"]) {
                nativeBackend.response = reading;
                nativeBackend.requestChain(values);
                compare(nativeBackend.chainLength, 2);
                nativeBackend.newData(nativeBackend.connectedSources[0],
                                      {stdout: JSON.stringify({ok: false, error: code}) + "\n"});
                verify(!nativeBackend.busy);
                compare(nativeBackend.response, null, code);
                compare(nativeBackend.errorCode, code);
                compare(nativeBackend.error, nativeBackend.errorLabel(code));
            }
            // A chain of one change is a single request: a change the headset
            // certainly did not apply keeps the reading.
            nativeBackend.response = reading;
            nativeBackend.requestChain(values.slice(0, 1));
            compare(nativeBackend.chainLength, 1);
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: false, error: "rejected"}) + "\n"});
            compare(nativeBackend.response, reading);
            // A single request counts as one again after a chain.
            nativeBackend.requestChain(values);
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: true, sent: "bands", transport: "usb",
                                                           state: {preset: 255, bands: values[1].value}, errors: {}})});
            nativeBackend.request({op: "set", feature: "dnd", value: true});
            compare(nativeBackend.chainLength, 1);
            const kept = nativeBackend.response;
            nativeBackend.newData(nativeBackend.connectedSources[0],
                                  {stdout: JSON.stringify({ok: false, error: "rejected"})});
            compare(nativeBackend.response, kept);
            nativeBackend.response = null;
            nativeBackend.error = "";
            nativeBackend.errorCode = "";
            nativeBackend.requestFeature = "";
        }
        function test_transport_change_drops_old_reply() {
            nativeBackend.target = {transport: "usb"};
            nativeBackend.requestedKey = "usb";
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.target = {transport: "bluetooth", address: "01:02:03:04:05:06"};
            compare(nativeBackend.response, null);
            nativeBackend.newData("old request", {stdout: JSON.stringify({ok: true, state: {preset: 9}})});
            compare(nativeBackend.response, null);
            nativeBackend.requestedKey = nativeBackend.targetKey;
            nativeBackend.newData("current request", {stdout: JSON.stringify({ok: true, state: {preset: 0}, transport: "bluetooth"})});
            compare(nativeBackend.response.state.preset, 0);
            nativeBackend.target = {transport: "usb"};
            nativeBackend.requestedKey = nativeBackend.targetKey;
        }
        function test_command_quotes_arguments() {
            const command = Output.headsetCommand({op: "status"}, {transport: "bluetooth", address: "' $(touch nope)"});
            verify(command.startsWith("barracuda-headset --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
