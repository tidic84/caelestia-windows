import QtQuick
import QtQuick.Effects

// Pilule : heure, pochette qui tourne et egaliseur (replie) ; titre et
// progression (survol).
Item {
    id: pill
    readonly property bool peek: win.mode === "peek"

    // ---------------------------------------------------------- replie
    Row {
        anchors.centerIn: parent
        spacing: 10
        opacity: pill.peek ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Item {
            width: 18
            height: 18
            visible: win.hasMedia && media.hasArt
            anchors.verticalCenter: parent.verticalCenter
            RoundArt {
                id: mini
                anchors.fill: parent
                // ne tourne que si la pilule repliee se voit
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 8000; loops: Animation.Infinite
                    running: media.playing && win.mode === "collapsed"
                }
            }
        }

        Text {
            text: Qt.formatTime(win.now, "hh:mm")
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            visible: win.hasMedia
            spacing: 2
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: 3
                Rectangle {
                    id: bar
                    required property int index
                    width: 3
                    height: 12
                    radius: 1.5
                    color: Theme.primary
                    // trames du visualiseur : moyenne de 8 bandes
                    property real level: {
                        const b = viz.bands
                        let s = 0
                        for (let i = index * 8; i < index * 8 + 8; i++) s += b[i] || 0
                        return (3 + s / 8 * 9) / 12
                    }
                    transform: Scale {
                        id: sc
                        origin.y: 12
                        yScale: viz.live ? bar.level : 0.33
                        Behavior on yScale { enabled: viz.live; NumberAnimation { duration: 50 } }
                    }
                    // sans trames (silence) : animation de repos, seulement si visible
                    SequentialAnimation {
                        running: media.playing && !viz.live && win.mode === "collapsed"
                        loops: Animation.Infinite
                        PauseAnimation { duration: bar.index * 350 }
                        NumberAnimation { target: sc; property: "yScale"; to: 1; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                        NumberAnimation { target: sc; property: "yScale"; to: 0.25; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- survol
    Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        opacity: pill.peek ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Row {
            visible: win.hasMedia
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 12
            RoundArt { width: 52; height: 52; radius: 14 }
            Column {
                width: parent.width - 64
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: media.title || "Sans titre"; color: Theme.ink; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight; width: parent.width }
                Text { text: media.artist; color: Theme.inkVariant; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                Progress { width: parent.width; active: pill.peek }
            }
        }
        Row {
            visible: !win.hasMedia
            anchors.centerIn: parent
            spacing: 10
            Text { text: Qt.formatTime(win.now, "hh:mm"); color: Theme.ink; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Medium }
            Text { text: win.now.toLocaleDateString(Theme.locale, "ddd d MMM"); color: Theme.inkVariant; font.family: Theme.font; font.pixelSize: 13; anchors.baseline: parent.children[0].baseline }
        }
    }
}
