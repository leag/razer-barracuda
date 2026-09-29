import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import "../code/output.js" as Output

ColumnLayout {
    id: summary

    required property var sink
    property string localeName: Qt.locale().name
    property bool pairingBusy: false
    property string pairingError: ""
    property string pairingResult: ""
    property bool confirmingPairing: false
    property bool activeView: true
    onActiveViewChanged: {
        if (!activeView)
            confirmingPairing = false;
    }
    property var battery: null
    readonly property bool batteryAvailable: battery !== null
    onBatteryAvailableChanged: {
        if (batteryAvailable)
            confirmingPairing = false;
    }
    readonly property bool hasOutput: Output.available(sink)
    readonly property string deviceName: hasOutput ? (sink.description || sink.name)
        : label("No audio output", "Sin salida de audio")
    readonly property string deviceIcon: Output.icon(sink)
    readonly property string deviceArtwork: Output.artwork(deviceIcon)
    readonly property string statusText: Output.status(sink, localeName)
    signal settingsRequested()
    signal pairingRequested()

    function label(english, spanish) {
        return Output.text(english, spanish, localeName)
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: implicitHeight
    spacing: Kirigami.Units.largeSpacing

    PlasmaExtras.Heading {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        level: 2
        text: summary.label("Current Audio Output", "Salida de audio actual")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Item {
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
            Image {
                id: artwork
                anchors.fill: parent
                source: summary.deviceArtwork.startsWith("file:") ? summary.deviceArtwork : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                source: summary.deviceIcon
                visible: artwork.status !== Image.Ready
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            PC3.Label {
                Layout.fillWidth: true
                text: summary.deviceName
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.bold: true
            }
            PC3.Label {
                Layout.fillWidth: true
                visible: summary.hasOutput
                text: summary.statusText
                wrapMode: Text.Wrap
            }
        }
    }

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        text: summary.hasOutput
            ? summary.label("Default output for audio playback.", "Salida predeterminada para reproducir audio.")
            : summary.label("Connect an audio device to see its output here.", "Conecta un dispositivo de audio para ver su salida aquí.")
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    Item { Layout.fillHeight: true }

    Kirigami.Separator { Layout.fillWidth: true }

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        text: summary.label("Barracuda X (2022)", "Barracuda X (2022)")
        font.bold: true
    }

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        text: Output.batteryText(summary.battery, summary.localeName)
        wrapMode: Text.Wrap
    }

    PC3.ProgressBar {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.battery !== null
        from: 0
        to: 100
        value: summary.battery ? summary.battery.percent : 0
        Accessible.name: summary.label("Barracuda battery", "Batería del Barracuda")
    }

    PC3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.pairingBusy || summary.confirmingPairing || summary.pairingResult.length > 0
        text: summary.pairingBusy
            ? summary.label("Pairing… Keep the headset in pairing mode. Searching can take up to a minute; the result will appear here.",
                            "Emparejando… Mantén los auriculares en modo de emparejamiento. La búsqueda puede tardar un minuto; el resultado aparecerá aquí.")
            : summary.confirmingPairing
                ? summary.label("Connect the Barracuda dongle and put the headset in pairing mode. Continue? This replaces the dongle's current pairing.",
                                "Conecta el adaptador Barracuda y pon los auriculares en modo de emparejamiento. ¿Continuar? Esto reemplaza el emparejamiento actual del adaptador.")
                : summary.pairingResult
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    PC3.ProgressBar {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: summary.pairingBusy
        indeterminate: summary.pairingBusy
        Accessible.name: summary.label("Pairing in progress", "Emparejamiento en curso")
    }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        visible: summary.pairingError.length > 0
        contentWidth: availableWidth
        PC3.TextArea {
            text: summary.pairingError
            textFormat: TextEdit.PlainText
            readOnly: true
            color: Kirigami.Theme.negativeTextColor
            wrapMode: TextEdit.Wrap
        }
    }

    PC3.Button {
        objectName: "pairingButton"
        Layout.leftMargin: Kirigami.Units.largeSpacing
        text: summary.label("Pair Barracuda…", "Emparejar Barracuda…")
        icon.name: "network-wireless"
        enabled: !summary.pairingBusy
        visible: !summary.confirmingPairing
        onClicked: summary.confirmingPairing = true
    }

    RowLayout {
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: summary.confirmingPairing
        PC3.Button {
            objectName: "confirmPairingButton"
            text: summary.label("Pair", "Emparejar")
            enabled: !summary.pairingBusy
            onClicked: {
                summary.confirmingPairing = false;
                summary.pairingRequested();
            }
        }
        PC3.Button {
            objectName: "cancelPairingButton"
            text: summary.label("Cancel", "Cancelar")
            onClicked: summary.confirmingPairing = false
        }
    }

    PC3.ToolButton {
        Layout.alignment: Qt.AlignRight
        Layout.margins: Kirigami.Units.largeSpacing
        icon.name: "configure"
        text: summary.label("Sound settings…", "Ajustes de sonido…")
        onClicked: summary.settingsRequested()
    }
}
