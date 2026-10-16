import QtQuick

// Barre de progression ; la position est extrapolee tant qu'elle se voit
Item {
    id: prog
    property bool active: true
    property bool times: false
    height: times ? 22 : 4

    property real now: Date.now()
    Timer {
        interval: 500
        repeat: true
        running: prog.active && media.playing
        onTriggered: prog.now = Date.now()
    }
    readonly property real pos: {
        const p = media.position + (media.playing ? (now - media.stamp) / 1000 : 0)
        return media.duration > 0 ? Math.min(p, media.duration) : p
    }

    Rectangle {
        width: parent.width
        height: 4
        radius: 2
        color: Theme.surfaceHighest
        Rectangle {
            height: parent.height
            radius: 2
            color: Theme.primary
            width: media.duration > 0 ? parent.width * prog.pos / media.duration : 0
        }
    }
    Text {
        visible: prog.times
        y: 8
        text: Theme.time(prog.pos)
        color: Theme.inkVariant
        font.family: Theme.font
        font.pixelSize: 11
    }
    Text {
        visible: prog.times
        y: 8
        anchors.right: parent.right
        text: Theme.time(media.duration)
        color: Theme.inkVariant
        font.family: Theme.font
        font.pixelSize: 11
    }
}
