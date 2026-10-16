import QtQuick

// Compagnon baladeur : apres 90 s sans clavier ni souris, il descend de la
// pilule et se promene au-dessus de la barre des taches ; il remonte des que
// tu reviens (Watch.petOut). Fenetre transparente qui laisse passer la souris.
Window {
    id: w
    property var host
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: "Ilot compagnon"
    readonly property var scr: host ? host.screen : null
    width: scr ? scr.width : 1200
    height: 90
    x: scr ? scr.virtualX : 0
    // au-dessus de la barre des taches
    y: scr ? scr.virtualY + scr.height - height - 48 : 0
    // la fenetre reste le temps de l'animation de depart
    visible: Watch.petOut || leaving.running

    property real px: width / 2 - 20
    property real target: px
    property int dir: 1
    property string mode: "idle"
    readonly property bool sleepy: Watch.idle > 600 || new Date().getHours() < 6

    onVisibleChanged: if (visible) arrive()
    function arrive() {
        // arrive depuis la pilule (centre de l'ecran) en tombant
        px = width / 2 - 20
        walker.y = -90
        walker.opacity = 1
        drop.restart()
        mode = "idle"
        next.interval = 1500
        next.restart()
    }
    Connections {
        target: Watch
        function onPetOutChanged() {
            if (!Watch.petOut && w.visible)
                leaving.restart()
        }
    }
    NumberAnimation {
        id: drop
        target: walker
        property: "y"
        to: w.height - 44
        duration: 900
        easing.type: Easing.OutBack
    }
    ParallelAnimation {
        id: leaving
        NumberAnimation { target: walker; property: "y"; to: -100; duration: 700; easing.type: Easing.InQuad }
        NumberAnimation { target: walker; property: "opacity"; to: 0; duration: 700 }
    }

    // choix de la prochaine envie : marcher, sauter, dire quelque chose, dormir
    Timer {
        id: next
        running: w.visible && w.mode !== "walk"
        onTriggered: {
            const r = Math.random()
            if (w.sleepy) {
                w.mode = "sleep"
                pet.fx("z")
                interval = 6000
            } else if (r < 0.55) {
                w.target = Math.max(10, Math.min(w.width - 50, w.px + (Math.random() - 0.5) * w.width * 0.6))
                w.mode = "walk"
            } else {
                w.mode = "idle"
                if (r < 0.7)
                    pet.hop()
                else if (r < 0.8)
                    pet.fx(["♥", "♪", "!", "?"][Math.floor(Math.random() * 4)])
                interval = 2500 + Math.random() * 3500
            }
            if (Math.random() < 0.3)
                pet.doBlink()
        }
    }
    // marche a 55 px/s
    Timer {
        interval: 33
        repeat: true
        running: w.visible && w.mode === "walk"
        onTriggered: {
            const d = w.target - w.px
            w.dir = Math.sign(d) || w.dir
            w.px += Math.sign(d) * Math.min(Math.abs(d), 55 * 0.033)
            if (Math.abs(w.target - w.px) < 1) {
                w.mode = "idle"
                next.interval = 1500 + Math.random() * 2500
                next.restart()
            }
        }
    }

    Item {
        id: walker
        x: w.px
        width: 40
        height: 40
        Pet {
            id: pet
            k: 2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            mood: w.mode === "sleep" ? "sleep" : "idle"
            walking: w.mode === "walk"
            transform: Scale {
                origin.x: pet.width / 2
                xScale: w.dir
            }
        }
    }
}
