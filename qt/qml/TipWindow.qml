import QtQuick

// Fenetre unique des info-bulles (Ilot.tip : texte et position a l'ecran)
Window {
    id: w
    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    visible: Ilot.tip !== null && label.text !== ""
    width: bubble.width
    height: bubble.height
    x: Ilot.tip ? Math.round(Ilot.tip.x - width / 2) : 0
    y: Ilot.tip ? Math.round(Ilot.tip.y) : 0

    Rectangle {
        id: bubble
        width: label.implicitWidth + 16
        height: label.implicitHeight + 10
        radius: 8
        color: Theme.surfaceHighest
        border.width: 1
        border.color: Theme.outlineVariant
        Txt {
            id: label
            anchors.centerIn: parent
            text: Ilot.tip ? Ilot.tip.text : ""
            px: 11.5
        }
    }
}
