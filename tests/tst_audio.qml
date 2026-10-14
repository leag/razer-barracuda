import QtQuick
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/code/output.js" as Output

Item {
    id: host
    width: 600
    height: 700
    QtObject {
        id: fake
        property bool busy: false
        property string error: ""
        property string message: ""
        property var response: null
        property var requests: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]); }
    }
    AudioController {
        id: backend
        engine: ""
    }
    QtObject {
        id: fakeHeadset
        property bool busy: false
        property var response: null
        property string error: ""
        property string message: ""
        property var requests: []
        signal loaded(var result)
        function request(value) { requests = requests.concat([value]); }
        function errorLabel(code) { return code; }
    }
    HeadsetSettings {
        id: nativeSettings
        anchors.fill: parent
        visible: false
        controller: fakeHeadset
        audioController: fake
    }
    HeadsetController { id: nativeBackend; engine: "" }
    TestCase {
        name: "HeadsetSettings"
        when: windowShown
        function test_helper_errors_are_visible() {
            backend.newData("fake", {stdout: "", "exit code": 127});
            verify(backend.error.length > 0);
            backend.newData("fake", {stdout: JSON.stringify({ok: false, error: "missing-microphone"}), "exit code": 1});
            verify(backend.error.length > 0);
            verify(!backend.busy);
        }
        function test_native_readback_and_unavailable_controls() {
            nativeSettings.visible = true;
            const eq = {enabled: false};
            fake.response = {state: {equalizers: {output: eq, microphone: eq}, sidetone: {enabled: false}}};
            const result = {ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0],
                                             gaming: false, dnd: null, standby: 15, devices: []},
                            errors: {dnd: "timeout"}};
            fakeHeadset.response = result;
            fakeHeadset.loaded(result);
            wait(20);
            const selector = findChild(nativeSettings, "nativeProfileSelector");
            compare(selector.currentIndex, 1);
            compare(selector.currentText, "Game");
            compare(nativeSettings.confirmedPresetIcon, "input-gamepad");
            // The equalizer section shows only EQ controls.
            verify(findChild(nativeSettings, "equalizerSection").visible);
            verify(!findChild(nativeSettings, "powerSaving").visible);
            verify(!selector.wheelEnabled);
            selector.activated(3);
            compare(fakeHeadset.requests[0].feature, "preset");
            compare(fakeHeadset.requests[0].value, 9);
            compare(nativeSettings.state.preset, 7);
            compare(selector.currentIndex, 1);
            // Do Not Disturb lives in the popup, not on this page.
            compare(findChild(nativeSettings, "nativeDnd"), null);
            nativeSettings.section = "powerSaving";
            verify(findChild(nativeSettings, "powerSaving").visible);
            verify(!findChild(nativeSettings, "equalizerSection").visible);
            // Power saving and Quick Connect are separate sections.
            verify(!findChild(nativeSettings, "quickConnect").visible);
            const standby = findChild(nativeSettings, "nativeStandby");
            verify(!standby.wheelEnabled);
            compare(standby.currentIndex, 2);
            standby.activated(3);
            compare(fakeHeadset.requests[1].value, 30);
            // Bluetooth gaming mode lives in the popup, not on this page.
            compare(findChild(nativeSettings, "nativeGaming"), null);
            // Quick Connect is blocked while gaming mode is on.
            nativeSettings.section = "quickConnect";
            verify(findChild(nativeSettings, "quickConnect").visible);
            verify(!findChild(nativeSettings, "powerSaving").visible);
            fakeHeadset.response = {ok: true, state: Object.assign({}, result.state, {
                gaming: true, devices: [{address: "01:02:03:04:05:06", name: "Phone", active: false}]})};
            const device = () => findChild(findChild(nativeSettings, "quickConnectDevices").children
                .find(child => child.text === "Phone"), "quickConnectButton");
            verify(!device().enabled);
            verify(findChild(nativeSettings, "quickConnectBlocked").visible);
            fakeHeadset.response = {ok: true, state: Object.assign({}, result.state, {
                devices: [{address: "01:02:03:04:05:06", name: "Phone", active: false}]})};
            verify(device().enabled);
            verify(!findChild(nativeSettings, "quickConnectBlocked").visible);
            device().clicked();
            compare(fakeHeadset.requests[fakeHeadset.requests.length - 1].value, "01:02:03:04:05:06");
            // The active source has no switch button; an empty list explains itself.
            fakeHeadset.response = {ok: true, state: Object.assign({}, result.state, {
                devices: [{address: "01:02:03:04:05:06", name: "Phone", active: true}]})};
            verify(!device().visible);
            verify(!findChild(nativeSettings, "quickConnectEmpty").visible);
            fakeHeadset.response = result;
            verify(findChild(nativeSettings, "quickConnectEmpty").visible);
            nativeSettings.section = "equalizer";
            fakeHeadset.busy = true;
            verify(!selector.enabled);
            fakeHeadset.busy = false;
            nativeSettings.localeName = "es_CL";
            tryCompare(selector, "currentText", "Juegos");
            fakeHeadset.response = null;
            compare(selector.currentIndex, 1);
            verify(!selector.enabled);
            nativeSettings.applyingPreset = false;
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
            nativeSettings.section = "quickConnect";
            compare(nativeSettings.settingsError, "");
            nativeSettings.section = "equalizer";
            fakeHeadset.response = {state: {preset: null}, errors: {preset: "unknown-link", bands: "timeout"}};
            verify(nativeSettings.settingsError.includes("Equalizer: unknown-link"));
            verify(nativeSettings.settingsError.includes("Custom EQ: timeout"));
            nativeSettings.localeName = "es_CL";
            verify(nativeSettings.settingsError.includes("Ecualizador:"));
            fakeHeadset.response = null;
            nativeSettings.localeName = "en_US";
        }
        function test_profile_confirmation_failure_and_custom_bands() {
            nativeSettings.visible = true;
            nativeSettings.localeName = "en_US";
            fakeHeadset.requests = [];
            const selector = findChild(nativeSettings, "nativeProfileSelector");
            const custom = findChild(nativeSettings, "nativeCustomBands");
            const result = {ok: true, state: {preset: 8, bands: [0,0,0,0,0,0,0,0,0,0]}};
            fakeHeadset.response = result;
            fakeHeadset.loaded(result);
            compare(selector.currentIndex, 2);
            verify(!custom.visible);
            selector.currentIndex = 4;
            selector.activated(4);
            fakeHeadset.busy = true;
            compare(selector.currentIndex, 2);
            verify(!selector.enabled);
            verify(!custom.visible);
            verify(findChild(nativeSettings, "nativeProfileStatus").text.includes("Applying"));
            const confirmed = {ok: true, sent: "preset", state: {preset: 255, bands: result.state.bands}};
            fakeHeadset.response = confirmed;
            fakeHeadset.loaded(confirmed);
            fakeHeadset.busy = false;
            compare(selector.currentIndex, 4);
            verify(custom.visible);
            findChild(nativeSettings, "resetNativeBands").clicked();
            verify(!nativeSettings.bandsDirty);
            // Bands are sent by the configuration window's Apply, not a page button.
            compare(findChild(nativeSettings, "applyNativeBands"), null);
            compare(findChild(nativeSettings, "bandsUnit").text, "Hz");
            verify(!nativeSettings.unsavedBands);
            nativeSettings.applyBands();
            compare(fakeHeadset.requests.length, 1);
            nativeSettings.bands = [1,0,0,0,0,0,0,0,0,0];
            nativeSettings.bandsDirty = true;
            verify(nativeSettings.unsavedBands);
            nativeSettings.applyBands();
            compare(fakeHeadset.requests[1].feature, "bands");
            compare(fakeHeadset.requests[1].value[0], 1);
            selector.activated(0);
            fakeHeadset.busy = true;
            fakeHeadset.response = null;
            fakeHeadset.error = "Change could not be confirmed";
            fakeHeadset.busy = false;
            compare(selector.currentIndex, 4);
            verify(!selector.enabled);
            verify(findChild(nativeSettings, "nativeProfileStatus").text.includes("Last confirmed"));
            verify(!custom.visible);
            nativeSettings.bandsDirty = false;
            fakeHeadset.error = "";
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
            fakeHeadset.response = result;
            fakeHeadset.loaded(result);
            // One help button in the equalizer section, none in the other.
            for (const name of ["dndHelp", "standbyHelp", "quickConnectHelp", "refreshHelp"])
                compare(findChild(nativeSettings, name), null);
            const profile = findChild(nativeSettings, "profileHelp");
            verify(profile.visible);
            for (const locale of ["en_US", "es_CL"]) {
                nativeSettings.localeName = locale;
                verify(profile.toolTipText.includes(locale === "en_US" ? "select Apply" : "selecciona Aplicar"));
            }
            nativeSettings.section = "powerSaving";
            verify(!findChild(nativeSettings, "profileHelp").visible);
            nativeSettings.section = "equalizer";
            nativeSettings.localeName = "en_US";
            fakeHeadset.response = null;
            nativeSettings.visible = false;
        }
        function test_refresh_only_when_needed() {
            nativeSettings.visible = true;
            const ok = {ok: true, state: {preset: 7, bands: [0,0,0,0,0,0,0,0,0,0], devices: []}};
            fakeHeadset.response = ok;
            fakeHeadset.message = "";
            fakeHeadset.error = "";
            verify(!findChild(nativeSettings, "nativeSettingsError").visible);
            verify(!findChild(nativeSettings, "nativeSettingsMessage").visible);
            // A confirmed change needs no refresh.
            fakeHeadset.response = Object.assign({sent: "preset"}, ok);
            fakeHeadset.message = "Change confirmed";
            compare(findChild(nativeSettings, "nativeSettingsMessage").actions.length, 0);
            // A device switch request offers it.
            fakeHeadset.response = Object.assign({sent: "devices"}, ok);
            fakeHeadset.message = "Connection switch requested";
            compare(findChild(nativeSettings, "nativeSettingsMessage").actions.length, 1);
            fakeHeadset.message = "";
            fakeHeadset.response = null;
            nativeSettings.visible = false;
        }
        function test_command_quotes_profile_names() {
            const command = Output.audioCommand({op: "save", name: "My ' $(touch nope) profile"});
            verify(command.startsWith("barracuda-audio --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
