import QtQuick

// Fenetre unique des info-bulles (Ilot.tip : texte et position a l'ecran).
// Placee avant d'etre affichee, puis remise au premier plan.
Window {
    id: w
    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    visible: false
    width: bubble.width
    height: bubble.height

    Connections {
        target: Ilot
        function onTipChanged() { w.place() }
    }
    function place() {
        const t = Ilot.tip
        if (!t || !t.text) {
            visible = false
            return
        }
        label.text = t.text
        // reste centree si sa taille change pendant l'affichage
        x = Qt.binding(() => Math.round(t.x - w.width / 2))
        y = Math.round(t.y)
        visible = true
        raise()
    }

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
            px: 11.5
        }
    }
}
