import QtQuick

// Barre de defilement fine (::-webkit-scrollbar : 6 px, outline-variant)
Rectangle {
    id: s
    property Flickable flick
    visible: !!flick && flick.contentHeight > flick.height + 1
    x: flick ? flick.x + flick.width - width + 4 : 0
    width: 6
    radius: 3
    color: Theme.outlineVariant
    // course sur la hauteur restante (la poignee fait au moins 20 px)
    y: flick ? flick.y + (flick.visibleArea.heightRatio < 1 ? Math.max(0, Math.min(1, flick.visibleArea.yPosition / (1 - flick.visibleArea.heightRatio))) * (flick.height - height) : 0) : 0
    height: flick ? Math.max(20, Math.min(1, flick.visibleArea.heightRatio) * flick.height) : 0
    MouseArea {
        anchors.fill: parent
        anchors.margins: -3
        preventStealing: true
        property real grab: 0
        onPressed: m => grab = m.y
        onPositionChanged: m => {
            if (!pressed)
                return
            const f = s.flick
            const dy = (m.y - grab) * (f.contentHeight - f.height) / Math.max(1, f.height - s.height)
            f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + dy))
        }
    }
}
