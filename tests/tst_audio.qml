import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../plasmoid/contents/ui"
import "../plasmoid/contents/code/output.js" as Output

Item {
    id: host
    width: 600
    height: 700
    QtObject {
        id: fakeHeadset
        property bool busy: false
        property var response: null
        property string error: ""
        property string message: ""
        property var requests: []
        property var chains: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]); }
        function requestChain(values) { chains = chains.concat([values]); busy = true; }
        function errorLabel(code) { return code; }
    }
    HeadsetSettings {
        id: nativeSettings
        anchors.fill: parent
        visible: false
        controller: fakeHeadset
    }
    // An unknown engine name runs nothing; an empty one would keep the
    // component's executable engine.
    HeadsetController { id: nativeBackend; engine: "barracuda-test-none" }
    TestCase {
        name: "HeadsetSettings"
        when: windowShown
        // A reply as HeadsetController delivers it: busy ends, then the reply.
        function reply(result) {
            fakeHeadset.busy = false;
            fakeHeadset.response = result;
            fakeHeadset.loaded(result);
        }
        function findAll(item, test) {
            let found = test(item) ? [item] : [];
            for (const child of item.children)
                found = found.concat(findAll(child, test));
            return found;
        }
        function test_native_readback_and_sections() {
            nativeSettings.visible = true;
            nativeSettings.section = "equalizer";
            const result = {ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0],
                                             gaming: false, dnd: null, standby: 15, devices: []},
                            errors: {dnd: "timeout"}};
            reply(result);
            wait(20);
            const selector = findChild(nativeSettings, "nativeProfileSelector");
            compare(selector.currentIndex, 1);
            compare(selector.currentText, "Game");
            compare(nativeSettings.confirmedPresetIcon, "input-gamepad");
            verify(!selector.wheelEnabled);
            // The equalizer section shows only EQ controls; the popup's
            // settings have no copy here.
            verify(findChild(nativeSettings, "equalizerSection").visible);
            verify(!findChild(nativeSettings, "powerSaving").visible);
            for (const name of ["quickConnect", "quickConnectDevices", "quickConnectBlocked", "nativeDnd", "nativeGaming"])
                compare(findChild(nativeSettings, name), null);
            compare(nativeSettings.settingsError, "");
            nativeSettings.section = "powerSaving";
            verify(findChild(nativeSettings, "powerSaving").visible);
            verify(!findChild(nativeSettings, "equalizerSection").visible);
            const standby = findChild(nativeSettings, "nativeStandby");
            verify(!standby.wheelEnabled);
            compare(standby.currentIndex, 2);
            compare(standby.currentText, "15 min");
            compare(standby.Accessible.name, "Turn off when idle");
            nativeSettings.localeName = "es_CL";
            compare(standby.Accessible.name, "Apagar por inactividad");
            nativeSettings.localeName = "en_US";
            nativeSettings.section = "equalizer";
            fakeHeadset.busy = true;
            verify(!selector.enabled);
            fakeHeadset.busy = false;
            nativeSettings.localeName = "es_CL";
            tryCompare(selector, "currentText", "Juegos");
            fakeHeadset.response = null;
            compare(selector.currentIndex, 1);
            verify(!selector.enabled);
            nativeSettings.localeName = "en_US";
            nativeSettings.visible = false;
        }
        function test_profile_waits_for_apply() {
            nativeSettings.visible = true;
            nativeSettings.section = "equalizer";
            fakeHeadset.requests = [];
            fakeHeadset.chains = [];
            const selector = findChild(nativeSettings, "nativeProfileSelector");
            const custom = findChild(nativeSettings, "nativeCustomBands");
            reply({ok: true, state: {preset: 8, bands: [0,0,0,0,0,0,0,0,0,0]}});
            compare(selector.currentIndex, 2);
            verify(!custom.visible);
            verify(!nativeSettings.unsavedChanges);
            // Choosing a profile sends nothing; Plasma's Apply is enabled.
            selector.activated(1);
            compare(fakeHeadset.requests.length, 0);
            compare(fakeHeadset.chains.length, 0);
            compare(selector.currentIndex, 1);
            compare(selector.currentText, "Game");
            compare(nativeSettings.selectedPresetIcon, "input-gamepad");
            verify(nativeSettings.unsavedChanges);
            // Choosing the stored profile again leaves nothing to apply.
            selector.activated(2);
            verify(!nativeSettings.unsavedChanges);
            compare(selector.currentIndex, 2);
            // With nothing unsaved, Apply sends nothing.
            nativeSettings.save();
            compare(fakeHeadset.chains.length, 0);
            // Apply or OK sends the chosen profile.
            selector.activated(3);
            nativeSettings.save();
            compare(fakeHeadset.chains.length, 1);
            compare(fakeHeadset.chains[0], [{op: "set", feature: "preset", value: 9}]);
            verify(nativeSettings.saving);
            verify(!nativeSettings.unsavedChanges);
            fakeHeadset.busy = true;
            const sending = findChild(nativeSettings, "nativeSettingsSaving");
            verify(sending.visible);
            compare(sending.text, "Sending changes to the headset…");
            verify(!findChild(nativeSettings, "nativeSettingsReading").visible);
            nativeSettings.localeName = "es_CL";
            compare(sending.text, "Enviando cambios al auricular…");
            nativeSettings.localeName = "en_US";
            reply({ok: true, sent: "preset", state: {preset: 9, bands: [0,0,0,0,0,0,0,0,0,0]}});
            tryVerify(() => !nativeSettings.saving);
            compare(nativeSettings.pendingPreset, -1);
            compare(selector.currentIndex, 3);
            verify(!nativeSettings.unsavedChanges);
            fakeHeadset.response = null;
            nativeSettings.visible = false;
        }
        function test_custom_profile_and_bands_go_in_one_chain() {
            nativeSettings.visible = true;
            nativeSettings.section = "equalizer";
            fakeHeadset.requests = [];
            fakeHeadset.chains = [];
            const curve = [2, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            const selector = findChild(nativeSettings, "nativeProfileSelector");
            const custom = findChild(nativeSettings, "nativeCustomBands");
            reply({ok: true, state: {preset: 8, bands: curve.slice()}});
            verify(!custom.visible);
            // Choosing Custom shows the stored curve for editing.
            selector.activated(4);
            verify(custom.visible);
            compare(nativeSettings.bands, curve);
            // Unchanged bands: only the profile is sent.
            compare(nativeSettings.changes(), [{op: "set", feature: "preset", value: 255}]);
            const sliders = findAll(custom, item => item.orientation === Qt.Vertical && item.from === -5);
            compare(sliders.length, 10);
            // As a drag does, without replacing the slider's binding.
            for (let step = 0; step < 5; ++step)
                sliders[0].decrease();
            sliders[0].moved();
            verify(nativeSettings.bandsDirty);
            verify(nativeSettings.unsavedBands);
            const edited = [-3, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            // Edited bands follow the profile in one chain.
            nativeSettings.save();
            compare(fakeHeadset.chains.length, 1);
            compare(fakeHeadset.chains[0], [{op: "set", feature: "preset", value: 255},
                                            {op: "set", feature: "bands", value: edited}]);
            // The chain stops at the first failure and the choices are kept;
            // the error at the top offers Refresh, after which Apply can send
            // them again.
            fakeHeadset.busy = true;
            fakeHeadset.busy = false;
            fakeHeadset.response = null;
            fakeHeadset.error = "The change could not be confirmed. Refresh before trying again.";
            tryVerify(() => !nativeSettings.saving);
            compare(selector.currentIndex, 4);
            compare(nativeSettings.bands, edited);
            const error = findChild(nativeSettings, "nativeSettingsError");
            verify(error.visible);
            compare(error.actions[0].objectName, "refreshNativeSettings");
            verify(error.actions[0].enabled);
            error.actions[0].trigger();
            compare(fakeHeadset.requests[fakeHeadset.requests.length - 1], {op: "status"});
            fakeHeadset.error = "";
            reply({ok: true, state: {preset: 8, bands: curve.slice()}});
            verify(nativeSettings.unsavedChanges);
            compare(nativeSettings.bands, edited);
            // Refresh would not discard the choices, but it waits for Apply.
            verify(!error.actions[0].enabled);
            nativeSettings.save();
            compare(fakeHeadset.chains.length, 2);
            reply({ok: true, sent: "bands", state: {preset: 255, bands: edited.slice()}});
            tryVerify(() => !nativeSettings.saving);
            verify(!nativeSettings.unsavedChanges);
            compare(nativeSettings.pendingPreset, -1);
            compare(selector.currentIndex, 4);
            compare(nativeSettings.bands, edited);
            // Reset Bands is a change like any other.
            const reset = findChild(nativeSettings, "resetNativeBands");
            compare(reset.text, "Reset Bands");
            reset.clicked();
            verify(nativeSettings.unsavedBands);
            compare(nativeSettings.changes(), [{op: "set", feature: "bands", value: [0,0,0,0,0,0,0,0,0,0]}]);
            nativeSettings.localeName = "es_CL";
            compare(reset.text, "Restablecer bandas");
            nativeSettings.localeName = "en_US";
            // Bands are sent by the window's Apply, not a page button.
            compare(findChild(nativeSettings, "applyNativeBands"), null);
            compare(findChild(nativeSettings, "bandsUnit").text, "Hz");
            nativeSettings.bandsDirty = false;
            fakeHeadset.response = null;
            nativeSettings.visible = false;
        }
        function test_idle_shutdown_waits_for_apply() {
            nativeSettings.visible = true;
            nativeSettings.section = "powerSaving";
            fakeHeadset.requests = [];
            fakeHeadset.chains = [];
            const standby = findChild(nativeSettings, "nativeStandby");
            reply({ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0], standby: 15}});
            compare(standby.currentIndex, 2);
            verify(!nativeSettings.unsavedChanges);
            standby.activated(3);
            compare(fakeHeadset.requests.length, 0);
            compare(standby.currentIndex, 3);
            verify(nativeSettings.unsavedChanges);
            standby.activated(2);
            verify(!nativeSettings.unsavedChanges);
            standby.activated(0);
            compare(standby.currentText, "Never");
            compare(nativeSettings.changes(), [{op: "set", feature: "standby", value: 0}]);
            nativeSettings.save();
            compare(fakeHeadset.chains, [[{op: "set", feature: "standby", value: 0}]]);
            reply({ok: true, sent: "standby", state: {preset: 7, standby: 0}});
            tryVerify(() => !nativeSettings.saving);
            compare(nativeSettings.pendingStandby, -1);
            compare(standby.currentIndex, 0);
            verify(!nativeSettings.unsavedChanges);
            nativeSettings.localeName = "es_CL";
            tryCompare(standby, "currentText", "Nunca");
            nativeSettings.localeName = "en_US";
            // Each category sends only its own changes.
            nativeSettings.pendingPreset = 9;
            compare(nativeSettings.changes(), []);
            verify(!nativeSettings.unsavedChanges);
            nativeSettings.pendingPreset = -1;
            fakeHeadset.response = null;
            nativeSettings.section = "equalizer";
            nativeSettings.visible = false;
        }
        function test_repeated_errors_share_one_notice() {
            nativeSettings.localeName = "en_US";
            fakeHeadset.response = {state: {preset: null}, errors: {
                preset: "unknown-link", bands: "unknown-link", gaming: "unknown-link",
                dnd: "unknown-link", standby: "unknown-link", devices: "unknown-link"}};
            compare(nativeSettings.settingsError, "unknown-link");
            const notice = findChild(nativeSettings, "nativeSettingsError");
            compare(notice.text, "unknown-link");
            // Refresh is offered inside the notice, not as a separate row.
            compare(notice.actions.length, 1);
            compare(notice.actions[0].objectName, "refreshNativeSettings");
            notice.actions[0].trigger();
            compare(fakeHeadset.requests[fakeHeadset.requests.length - 1].op, "status");
            // Each section reports only its own errors.
            fakeHeadset.response = {state: {preset: null}, errors: {preset: "unknown-link", standby: "timeout"}};
            compare(nativeSettings.settingsError, "unknown-link");
            nativeSettings.section = "powerSaving";
            compare(nativeSettings.settingsError, "timeout");
            nativeSettings.section = "equalizer";
            // Quick Connect, Do Not Disturb and gaming errors belong to the popup.
            fakeHeadset.response = {state: {preset: 7}, errors: {devices: "timeout", dnd: "timeout", gaming: "timeout"}};
            compare(nativeSettings.settingsError, "");
            fakeHeadset.response = {state: {preset: null}, errors: {preset: "unknown-link", bands: "timeout"}};
            compare(nativeSettings.settingsError, "Equalizer: unknown-link Custom EQ: timeout");
            nativeSettings.localeName = "es_CL";
            verify(nativeSettings.settingsError.includes("Ecualizador:"));
            fakeHeadset.response = null;
            nativeSettings.localeName = "en_US";
        }
        function test_loaded_custom_bands_reach_the_sliders() {
            nativeSettings.visible = true;
            nativeSettings.bandsDirty = false;
            const curve = [2, 1, 0, -1, 0, 1, 2, 3, 1, 0];
            const result = {ok: true, state: {preset: 255, bands: curve.slice()}};
            fakeHeadset.response = result;
            // The reply reaches the page as a var signal argument.
            fakeHeadset.loaded(result);
            compare(nativeSettings.bands, curve);
            verify(Array.isArray(nativeSettings.bands));
            const custom = findChild(nativeSettings, "nativeCustomBands");
            verify(custom.visible);
            const sliders = [];
            const collect = item => {
                if (item.orientation === Qt.Vertical && item.from === -5)
                    sliders.push(item);
                for (const child of item.children)
                    collect(child);
            };
            collect(custom);
            compare(sliders.length, 10);
            compare(sliders.map(slider => slider.value), curve);
            // A reply without ten values keeps the current curve.
            const partial = {ok: true, state: {preset: 255, bands: [1, 2]}};
            fakeHeadset.response = partial;
            fakeHeadset.loaded(partial);
            compare(nativeSettings.bands, curve);
            fakeHeadset.response = null;
            nativeSettings.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            nativeSettings.visible = false;
        }
        function test_native_error_clears_confirmed_state() {
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: "unconfirmed"})});
            compare(nativeBackend.response, null);
            verify(nativeBackend.error.length > 0);
            nativeBackend.localeName = "es_CL";
            nativeBackend.newData("fake", {stdout: JSON.stringify({ok: false, error: "gaming-not-applied"})});
            verify(nativeBackend.error.includes("no cambió de modo"));
            compare(nativeBackend.response, null);
            nativeBackend.localeName = "en_US";
            verify(nativeBackend.errorLabel("gaming-not-applied").includes("did not change"));
        }
        function test_error_labels_name_the_usb_dongle() {
            const expected = {
                "missing-adapter": ["USB dongle not detected.", "Dongle USB no detectado."],
                "route-failed": ["Could not restore the USB dongle route. Reconnect the dongle.",
                                 "No se pudo restaurar la ruta del dongle USB. Reconecta el dongle."],
                "gaming-active": ["Turn off Bluetooth Gaming Mode before switching Bluetooth devices.",
                                  "Desactiva el modo gaming Bluetooth antes de cambiar de dispositivo Bluetooth."],
                "unknown-device": ["The headset no longer lists this device. Refresh to read its known devices.",
                                   "El auricular ya no tiene este dispositivo en su lista. Actualiza para leer sus dispositivos conocidos."]
            };
            for (const code of Object.keys(expected)) {
                nativeBackend.localeName = "en_US";
                compare(nativeBackend.errorLabel(code), expected[code][0]);
                nativeBackend.localeName = "es_CL";
                compare(nativeBackend.errorLabel(code), expected[code][1]);
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
            compare(nativeBackend.message, "Change confirmed by the headset.");
            nativeBackend.response = null;
            nativeBackend.message = "";
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
        function test_contextual_help_translation() {
            nativeSettings.visible = true;
            const result = {ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0],
                                             gaming: false, dnd: false, standby: 15, devices: []}};
            reply(result);
            // One help button in the equalizer section, none in the other.
            for (const name of ["dndHelp", "standbyHelp", "quickConnectHelp", "refreshHelp"])
                compare(findChild(nativeSettings, name), null);
            const profile = findChild(nativeSettings, "profileHelp");
            verify(profile.visible);
            nativeSettings.localeName = "en_US";
            compare(profile.toolTipText, "Profiles are stored on the headset. Choose a profile, or Custom to adjust the bands "
                    + "(0 is neutral), then select Apply to send it; Cancel discards it. The Game profile is independent "
                    + "of Bluetooth Gaming Mode in the popup.");
            nativeSettings.localeName = "es_CL";
            compare(profile.toolTipText, "Los perfiles se guardan en el auricular. Elige un perfil, o Personalizado para "
                    + "ajustar las bandas (0 es neutro), y selecciona Aplicar para enviarlo; Cancelar lo descarta. El perfil "
                    + "Juegos es independiente del modo gaming Bluetooth de la ventana emergente.");
            nativeSettings.section = "powerSaving";
            verify(!findChild(nativeSettings, "profileHelp").visible);
            nativeSettings.section = "equalizer";
            nativeSettings.localeName = "en_US";
            fakeHeadset.response = null;
            nativeSettings.visible = false;
        }
        function test_messages_at_the_top_offer_refresh() {
            nativeSettings.visible = true;
            nativeSettings.section = "equalizer";
            nativeSettings.localeName = "en_US";
            fakeHeadset.requests = [];
            const top = name => findChild(nativeSettings, name).mapToItem(nativeSettings, 0, 0).y;
            const reading = findChild(nativeSettings, "nativeSettingsReading");
            const error = findChild(nativeSettings, "nativeSettingsError");
            const stale = findChild(nativeSettings, "nativeSettingsStale");
            const message = findChild(nativeSettings, "nativeSettingsMessage");
            const ok = {ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0], standby: 15}};
            reply(ok);
            fakeHeadset.message = "";
            fakeHeadset.error = "";
            for (const item of [reading, error, stale, message])
                verify(!item.visible);
            // Reading, above the controls.
            fakeHeadset.busy = true;
            verify(reading.visible);
            compare(reading.text, "Reading headset…");
            tryVerify(() => top("nativeSettingsReading") < top("equalizerSection"));
            nativeSettings.localeName = "es_CL";
            compare(reading.text, "Leyendo auricular…");
            nativeSettings.localeName = "en_US";
            fakeHeadset.busy = false;
            // An error, above the controls, with Refresh.
            fakeHeadset.error = "The headset did not answer. Its state is unknown.";
            verify(error.visible);
            compare(error.type, Kirigami.MessageType.Warning);
            tryVerify(() => top("nativeSettingsError") < top("equalizerSection"));
            compare(error.actions.length, 1);
            compare(error.actions[0].text, "Refresh");
            error.actions[0].trigger();
            compare(fakeHeadset.requests[fakeHeadset.requests.length - 1], {op: "status"});
            fakeHeadset.error = "";
            // No reading and nothing else to explain it: say so, with Refresh.
            fakeHeadset.response = null;
            nativeSettings.confirmedPreset = -1;
            verify(stale.visible);
            compare(stale.text, "Applied profile unknown. Refresh to read the headset.");
            compare(stale.actions.length, 1);
            compare(stale.actions[0].objectName, "refreshNativeSettings");
            tryVerify(() => top("nativeSettingsStale") < top("equalizerSection"));
            nativeSettings.confirmedPreset = 7;
            compare(stale.text, "Last confirmed profile. Refresh to read the current setting.");
            nativeSettings.localeName = "es_CL";
            compare(stale.text, "Último perfil confirmado. Actualiza para leer el ajuste actual.");
            compare(stale.actions[0].text, "Actualizar");
            nativeSettings.confirmedPreset = -1;
            compare(stale.text, "Perfil aplicado desconocido. Actualiza para leer el auricular.");
            nativeSettings.section = "powerSaving";
            compare(stale.text, "Apagado por inactividad desconocido. Actualiza para leer el auricular.");
            nativeSettings.localeName = "en_US";
            compare(stale.text, "Idle shutdown unknown. Refresh to read the headset.");
            // Not while reading, nor next to an error.
            fakeHeadset.busy = true;
            verify(!stale.visible);
            fakeHeadset.busy = false;
            fakeHeadset.error = "Native controls require barracuda-headset on PATH.";
            verify(!stale.visible);
            fakeHeadset.error = "";
            nativeSettings.section = "equalizer";
            // A confirmed change needs no Refresh.
            reply(Object.assign({sent: "preset"}, ok));
            fakeHeadset.message = "Change confirmed by the headset.";
            verify(message.visible);
            compare(message.type, Kirigami.MessageType.Positive);
            compare(message.actions.length, 0);
            tryVerify(() => top("nativeSettingsMessage") < top("equalizerSection"));
            fakeHeadset.message = "";
            fakeHeadset.response = null;
            nativeSettings.confirmedPreset = -1;
            nativeSettings.visible = false;
        }
        function test_command_quotes_arguments() {
            const command = Output.headsetCommand({op: "status"}, {transport: "bluetooth", address: "' $(touch nope)"});
            verify(command.startsWith("barracuda-headset --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
