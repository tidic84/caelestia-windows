import QtQuick
import QtQuick.Window

// Fenetre transparente en haut de l'ecran principal ; seule la zone de
// l'ilot recoit la souris (island.setHit -> masque de la fenetre).
Window {
    id: win
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.NoDropShadowWindowHint
    color: "transparent"
    width: 800
    height: 600
    x: Screen.virtualX + (Screen.width - width) / 2
    y: Screen.virtualY
    visible: !island.fullscreen
    title: "Ilot (Qt)"

    // collapsed -> (survol) peek -> (clic) open
    property string mode: startOpen ? "open" : "collapsed"
    property string tab: "home"
    readonly property bool hasMedia: media.has && (media.title !== "" || media.artist !== "")
    readonly property int ear: 22

    // le visualiseur ne tourne que s'il se voit (comme updateViz dans app.js)
    Binding {
        target: viz
        property: "active"
        value: media.playing && !island.fullscreen && (win.mode !== "open" || win.tab === "home" || win.tab === "media")
    }

    // heure : relue chaque seconde, mais `now` ne change qu'a la minute (rien
    // a reevaluer ni a redessiner entre deux)
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date()
            if (d.getMinutes() !== win.now.getMinutes() || d.getHours() !== win.now.getHours())
                win.now = d
        }
    }

    Timer {
        id: leave
        interval: 450
        onTriggered: win.mode = "collapsed"
    }

    Item {
        id: shell
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: win.mode === "open" ? 740 : win.mode === "peek" ? (win.hasMedia ? 400 : 300) : (win.hasMedia ? 190 : 132)
        height: win.mode === "open" ? 540 : win.mode === "peek" ? (win.hasMedia ? 80 : 56) : 30
        readonly property real radius: win.mode === "open" ? 30 : win.mode === "peek" ? 24 : 15

        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

        onXChanged: Qt.callLater(updateHit)
        onWidthChanged: Qt.callLater(updateHit)
        onHeightChanged: Qt.callLater(updateHit)
        function updateHit() {
            island.setHit(Qt.rect(x - win.ear, 0, width + 2 * win.ear, height))
        }
        Component.onCompleted: updateHit()

        Ear { x: -win.ear; size: Math.min(win.ear, shell.height - shell.radius) }
        Ear { x: shell.width; size: Math.min(win.ear, shell.height - shell.radius); mirrored: true }

        Rectangle {
            id: bg
            anchors.fill: parent
            color: Theme.surface
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: shell.radius
            bottomRightRadius: shell.radius
            clip: true

            Pill {
                anchors.fill: parent
                opacity: win.mode === "open" ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Panel {
                width: 740
                height: 540
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: win.mode === "open" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    leave.stop()
                    if (win.mode === "collapsed")
                        win.mode = "peek"
                } else {
                    leave.start()
                }
            }
        }
        TapHandler {
            enabled: win.mode !== "open"
            onTapped: win.mode = "open"
        }
    }
}
