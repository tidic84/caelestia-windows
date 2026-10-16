import QtQuick
import QtQuick.Effects

// Lecteur : pochette floutee en fond, grande pochette, progression
Rectangle {
    id: tab
    radius: 22
    color: Theme.surfaceLow
    clip: true

    // fond : la pochette floutee (filter: blur(40px) en CSS). Le flou n'est
    // recalcule que quand la pochette change.
    Image {
        id: bgArt
        anchors.fill: parent
        source: media.hasArt ? "image://art/" + media.artSerial : ""
        sourceSize.width: 256
        fillMode: Image.PreserveAspectCrop
        cache: false
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        anchors.margins: -40
        source: bgArt
        visible: bgArt.status === Image.Ready
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: 0.3
        opacity: 0.35
    }

    VizBars { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 120; opacity: 0.3 }

    Row {
        anchors.centerIn: parent
        spacing: 32
        RoundArt { width: 240; height: 240; radius: 28 }
        Column {
            width: 300
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            Text { text: win.hasMedia ? media.title || "Sans titre" : "Rien en lecture"; width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Medium; color: Theme.ink }
            Text { text: media.artist; width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 15; color: Theme.inkVariant }
            Text { text: media.album; width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13; color: Theme.inkVariant }
            Text { text: media.app; font.family: Theme.font; font.pixelSize: 11; color: Theme.outlineVariant }
            Item { width: 1; height: 10 }
            Progress { width: parent.width; times: true; active: tab.visible && win.mode === "open" }
            Item { width: 1; height: 6 }
            Controls { anchors.horizontalCenter: parent.horizontalCenter }
        }
    }
}
