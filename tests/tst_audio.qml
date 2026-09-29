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
    AudioSettings {
        id: settings
        anchors.fill: parent
        controller: fake
    }
    AudioController {
        id: backend
        engine: ""
    }
    TestCase {
        name: "AudioSettings"
        when: windowShown
        function test_native_settings_and_persistence_request() {
            const eq = {enabled: false, gains: [0,0,0,0,0,0,0,0,0,0], custom: {}, favorites: []};
            const result = {state: {version: 1, equalizers: {output: eq, microphone: eq},
                                   sidetone: {enabled: false, level: 15},
                                   tuning: {quantum: 0, fixed_rate: false, never_suspend: false, headroom: 0}},
                            presets: {output: {Flat: eq.gains, Music: [0,0,0,0,0,1,1,0,0,0]}, microphone: {Flat: eq.gains}},
                            frequencies: {output: [31,63,125,250,500,1000,2000,4000,8000,16000],
                                          microphone: [100,200,300,500,800,1500,3000,5000,8000,12000]},
                            has_microphone: false};
            fake.response = result;
            fake.loaded(result);
            compare(fake.requests.length, 0);
            verify(!settings.showMicrophoneControls);
            verify(!settings.dirty);
            const selector = findChild(settings, "profileSelector");
            compare(selector.count, 2);
            verify(selector.visible);
            verify(selector.width > 0);
            verify(!settings.showBands);
            verify(!settings.showProfiles);
            verify(!selector.wheelEnabled);
            settings.chooseProfile("Music");
            compare(settings.profileName, "Music");
            compare(settings.equalizer.gains[5], 1);
            compare(fake.requests.length, 0);
            settings.edit(next => next.equalizers.output.gains[2] = 4);
            compare(settings.draft.equalizers.output.gains[2], 4);
            compare(result.state.equalizers.output.gains[2], 0);
            verify(settings.dirty);
            settings.save();
            compare(fake.requests.length, 1);
            compare(fake.requests[0].op, "save");
            compare(fake.requests[0].state.equalizers.output.gains[2], 4);
            settings.section = "microphone";
            wait(1);
            compare(settings.equalizer.gains[2], 0);
            verify(findChild(settings, "microphoneSection").visible);
            verify(findChild(settings, "sidetoneStatus").text.includes("disabled"));
            settings.edit(next => next.sidetone.enabled = true);
            verify(findChild(settings, "sidetoneStatus").text.includes("unsaved"));
            verify(!findChild(settings, "systemSection").visible);
            settings.section = "system";
            verify(!findChild(settings, "equalizerSection").visible);
            verify(!findChild(settings, "microphoneSection").visible);
            verify(findChild(settings, "systemSection").visible);
            settings.section = "output";
            compare(settings.equalizer.gains[2], 4);
            const footer = findChild(settings, "audioActions");
            verify(footer.visible);
            verify(footer.y + footer.height <= settings.height);
            settings.showBands = true;
            settings.showProfiles = true;
            host.height = 420;
            wait(100);
            const scroller = findChild(settings, "settingsScroll");
            const band = findChild(settings, "equalizerBand0");
            verify(band.visible);
            const before = band.value;
            const scrollBefore = scroller.contentItem.contentY;
            mouseWheel(band, band.width / 2, band.height / 2, 0, -120);
            wait(100);
            compare(band.value, before);
            compare(settings.equalizer.gains[0], before);
            verify(scroller.contentItem.contentY > scrollBefore);
            band.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Up);
            compare(band.value, before + 1);
            compare(settings.equalizer.gains[0], before + 1);
            host.height = 700;
        }
        function test_helper_errors_are_visible() {
            backend.newData("fake", {stdout: "", "exit code": 127});
            verify(backend.error.length > 0);
            backend.newData("fake", {stdout: JSON.stringify({ok: false, error: "missing-microphone"}), "exit code": 1});
            verify(backend.error.length > 0);
            verify(!backend.busy);
        }
        function test_command_quotes_profile_names() {
            const command = Output.audioCommand({op: "save", name: "My ' $(touch nope) profile"});
            verify(command.startsWith("barracuda-audio --request '"));
            verify(command.includes("'\\''"));
        }
    }
}
