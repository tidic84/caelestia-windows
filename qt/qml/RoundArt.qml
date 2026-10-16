import QtQuick

// Pochette ronde qui tourne pendant la lecture (mini pochette, disque)
Item {
    id: a
    property real size: 18
    property bool spinning: false
    property int period: 8000
    width: size
    height: size

    ArtImage {
        id: img
        anchors.fill: parent
        radius: a.size / 2
        // rotation sur le thread de rendu, seulement quand elle se voit
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: a.period
            loops: Animation.Infinite
            running: a.spinning && a.visible && img.status === Image.Ready
        }
    }
}
