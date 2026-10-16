import QtQuick

// Fond « Aurore boreale » de l'ilot : quatre voiles colores qui derivent et
// suivent les graves, mediums et aigus de la musique (visualiseur).
Item {
    id: au
    clip: true
    readonly property var s: Ilot.shown
    function band(a, b) {
        let t = 0
        for (let i = a; i < b; i++)
            t += s[i] || 0
        return t / Math.max(1, b - a)
    }
    readonly property real bass: band(0, 3)
    readonly property real mid: band(3, 12)
    readonly property real high: band(12, 24)
    readonly property bool moving: visible && !Theme.reduced && !Ilot.fullscreen
    // plus vite pendant la lecture
    readonly property real speed: Ilot.media.playing ? 0.5 : 1
    scale: 1 + bass * 0.12
    Behavior on scale { NumberAnimation { duration: 120 } }

    component Veil: Glow {
        id: v
        property real dx: 0
        property real dy: 0
        property int period: 17000
        core: 0.15
        opacity: Theme.light ? 0.35 : 0.8
        SequentialAnimation on dx {
            running: au.moving
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: v.period * au.speed; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: v.period * au.speed; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on dy {
            running: au.moving
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: v.period * 0.7 * au.speed; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: v.period * 0.7 * au.speed; easing.type: Easing.InOutSine }
        }
    }

    Veil {
        color: Theme.alpha(Theme.primary, 0.75)
        width: au.width * 0.75
        height: au.height * 1.4
        x: -au.width * 0.2 + dx * au.width * 0.25
        y: -au.height * 0.3 + dy * au.height * 0.2
        period: 17000
        opacity: (Theme.light ? 0.35 : 1) * (0.5 + au.bass * 0.5)
    }
    Veil {
        color: Theme.alpha(Theme.tertiary, 0.7)
        width: au.width * 0.75
        height: au.height * 1.4
        x: au.width * 0.3 - dx * au.width * 0.2
        y: -au.height * 0.1 - dy * au.height * 0.2
        period: 21000
        opacity: (Theme.light ? 0.35 : 1) * (0.5 + au.bass * 0.5)
    }
    Veil {
        color: Theme.alpha(Theme.secondary, 0.6)
        width: au.width * 0.75
        height: au.height * 1.4
        x: au.width * 0.55 - dx * au.width * 0.3
        y: -au.height * 0.4 + dy * au.height * 0.3
        period: 25000
        opacity: (Theme.light ? 0.35 : 1) * (0.45 + au.mid * 0.55)
    }
    Veil {
        color: Qt.rgba(0.24, 0.86, 0.59, 0.6)
        width: au.width * 1.1
        height: au.height * 0.6
        x: au.width * 0.1 + dx * au.width * 0.15
        y: au.height * 0.2 + dy * au.height * 0.2
        period: 13000
        opacity: (Theme.light ? 0.35 : 1) * (0.3 + au.high * 0.7)
    }
}
