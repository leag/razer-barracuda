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
            compare(findChild(nativeSettings, "toggleHeadsetOptions").text, "More settings");
            verify(!selector.wheelEnabled);
            selector.activated(3);
            compare(fakeHeadset.requests[0].feature, "preset");
            compare(fakeHeadset.requests[0].value, 9);
            compare(nativeSettings.state.preset, 7);
            compare(selector.currentIndex, 1);
            verify(!findChild(nativeSettings, "nativeDnd").enabled);
            verify(!nativeSettings.showOptions);
            findChild(nativeSettings, "toggleHeadsetOptions").clicked();
            verify(findChild(nativeSettings, "headsetOptions").visible);
            const standby = findChild(nativeSettings, "nativeStandby");
            verify(!standby.wheelEnabled);
            compare(standby.currentIndex, 2);
            standby.activated(3);
            compare(fakeHeadset.requests[1].value, 30);
            const gaming = findChild(nativeSettings, "nativeGaming");
            verify(gaming.text.includes("experimental"));
            mouseClick(gaming);
            compare(fakeHeadset.requests[2].feature, "gaming");
            compare(fakeHeadset.requests[2].value, true);
            compare(nativeSettings.state.gaming, false);
            verify(findChild(nativeSettings, "nativeGamingHint").text.includes("Bluetooth"));
            fakeHeadset.busy = true;
            verify(!selector.enabled);
            fakeHeadset.busy = false;
            nativeSettings.localeName = "es_CL";
            tryCompare(selector, "currentText", "Juegos");
            compare(findChild(nativeSettings, "toggleHeadsetOptions").text, "Más ajustes");
            fakeHeadset.response = null;
            verify(!findChild(nativeSettings, "nativeGaming").enabled);
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
            verify(findChild(nativeSettings, "nativeSettingsError").text.startsWith("unknown-link\n"));
            verify(!findChild(nativeSettings, "toggleHeadsetOptions").visible);
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
            nativeSettings.bands = [1,0,0,0,0,0,0,0,0,0];
            nativeSettings.bandsDirty = true;
            findChild(nativeSettings, "applyNativeBands").clicked();
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
        function test_output_change_drops_old_transport_reply() {
            nativeBackend.sink = null;
            nativeBackend.requestedKey = "usb";
            nativeBackend.response = {state: {preset: 7}};
            nativeBackend.sink = {name: "bluez_output.01_02_03_04_05_06.1", properties: {"device.api": "bluez5"}};
            compare(nativeBackend.response, null);
            nativeBackend.newData("old request", {stdout: JSON.stringify({ok: true, state: {preset: 9}})});
            compare(nativeBackend.response, null);
            nativeBackend.requestedKey = nativeBackend.targetKey;
            nativeBackend.newData("current request", {stdout: JSON.stringify({ok: true, state: {preset: 0}, transport: "bluetooth"})});
            compare(nativeBackend.response.state.preset, 0);
            nativeBackend.sink = null;
            nativeBackend.requestedKey = nativeBackend.targetKey;
        }
        function test_command_quotes_profile_names() {
            const command = Output.audioCommand({op: "save", name: "My ' $(touch nope) profile"});
            verify(command.startsWith("barracuda-audio --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
