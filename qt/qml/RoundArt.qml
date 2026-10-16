import QtQuick
import QtQuick.Effects

// Pochette (image://art) aux coins arrondis, ou une note s'il n'y en a pas
Item {
    id: art
    property real radius: width / 2
    readonly property bool ready: img.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        radius: art.radius
        color: Theme.surfaceHighest
        visible: !art.ready
        Text {
            anchors.centerIn: parent
            text: ""
            font.family: Theme.icons
            font.pixelSize: art.width * 0.4
            color: Theme.inkVariant
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: media.hasArt ? "image://art/" + media.artSerial : ""
        sourceSize.width: art.width * 2
        sourceSize.height: art.height * 2
        fillMode: Image.PreserveAspectCrop
        cache: false
        visible: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: art.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: art.ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
