import QtQuick
import QtTest
import "../plasmoid/contents/code/output.js" as Output

TestCase {
    name: "OutputIcon"
    function test_missing() {
        compare(Output.icon(null), "audio-card");
        compare(Output.icon({name: "auto_null"}), "audio-card");
    }
    function test_barracuda() {
        compare(Output.icon({properties: {"alsa.components": "USB1532:0552"}}),
                "audio-headset");
        compare(Output.icon({properties: {"device.vendor.id": "0x1532",
                                         "device.product.id": "0x0552"}}),
                "audio-headset");
        compare(Output.icon({properties: {"alsa.components": "USB1532:05520"}}),
                "audio-speakers");
    }
    function test_device_changes() {
        compare(Output.icon({formFactor: "headset"}), "audio-headset");
        compare(Output.icon({iconName: "video-display"}), "video-display");
        compare(Output.icon({ports: [{name: "analog-output-headphones"}],
                             activePortIndex: 0}), "audio-headset");
        compare(Output.icon({ports: [{name: "analog-output-headphones"}],
                             activePortIndex: 99}), "audio-speakers");
        compare(Output.icon({name: "speaker", muted: true}), "audio-speakers");
    }
    function test_languages() {
        compare(Output.text("Muted", "Silenciado", "es_CL"), "Silenciado");
        compare(Output.text("Muted", "Silenciado", "en_US"), "Muted");
        compare(Output.text("Muted", "Silenciado", "de_DE"), "Muted");
    }
    function test_kde_detailed_artwork() {
        compare(Output.artwork("audio-headset"),
                "file:///usr/share/icons/breeze/devices/64/audio-headset.svg");
        compare(Output.artwork("audio-headset-usb"), Output.artwork("audio-headset"));
        compare(Output.artwork("audio-speakers"),
                "file:///usr/share/icons/breeze/devices/64/audio-speakers.svg");
        compare(Output.artwork("video-display"), "video-display");
        compare(Output.artwork("audio-card"), "audio-card");
    }
}
