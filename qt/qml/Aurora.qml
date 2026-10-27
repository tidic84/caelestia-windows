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
    readonly property bool moving: visible && !Theme.reduced && Ilot.ambient
    // plus vite pendant la lecture
    readonly property real speed: Ilot.media.playing ? 0.5 : 1
    // temps des voiles : avance avec l'horloge d'ambiance (Ilot.amb), deux
    // fois plus vite pendant la lecture, sans saut quand la vitesse change
    property real at: 0
    Connections {
        target: Ilot
        enabled: au.moving
        function onAmbChanged() { au.at += Ilot.ambDelta / au.speed }
    }
    scale: 1 + bass * 0.12
    Behavior on scale { NumberAnimation { duration: 120 } }

    component Veil: Glow {
        id: v
        property int period: 17000
        readonly property real dx: Ilot.wave(au.at, v.period * 2)
        readonly property real dy: Ilot.wave(au.at, v.period * 1.4)
        core: 0.15
        opacity: Theme.light ? 0.35 : 0.8
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
