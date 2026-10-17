import QtQuick

// Meteo animee derriere la pilule (Apparence > Meteo animee) : pluie, neige,
// etoiles, halo du soleil, nuages qui passent, eclairs d'orage.
Item {
    id: fx
    clip: true
    // codes OMM d'Open-Meteo -> genre d'animation
    readonly property string kind: {
        const w = Ilot.weather
        if (!w || w.code === undefined)
            return ""
        const c = w.code
        if (!w.day && c <= 1)
            return "night"
        if (c <= 1)
            return "sun"
        if (c <= 3)
            return "cloud"
        if (c <= 48)
            return "fog"
        if (c >= 95)
            return "storm"
        if ((c >= 71 && c <= 77) || c === 85 || c === 86)
            return "snow"
        if ([65, 67, 82].indexOf(c) >= 0)
            return "heavy"
        return "rain"
    }
    readonly property bool rain: kind === "rain" || kind === "heavy" || kind === "storm"
    readonly property bool on: !!Ilot.cfg.wxfx && kind !== "" && !Theme.reduced && Ilot.mode !== "open" && !Ilot.act
    opacity: on ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 800 } }
    // temps des animations : horloge d'ambiance (Ilot.amb, 25 images/s),
    // fige quand personne ne regarde
    property real t: 0
    Binding on t {
        when: fx.visible && Ilot.ambient
        value: Ilot.amb
        restoreMode: Binding.RestoreNone
    }

    // positions et rythmes tires au hasard une fois
    readonly property var drops: {
        const l = []
        for (let i = 0; i < 18; i++)
            l.push({ x: Math.random(), y: Math.random() * 0.9, d: 550 + Math.random() * 500, w: Math.random() * 3000 })
        return l
    }

    // halo du soleil
    Glow {
        visible: fx.kind === "sun"
        x: -50
        y: -80
        width: 140
        height: 140
        core: 0.1
        color: Qt.rgba(1, 0.75, 0.32, 0.45)
        scale: visible ? 1 + 0.18 * Ilot.wave(fx.t, 5000) : 1
    }

    // nuages / brouillard qui passent
    Rectangle {
        visible: ["cloud", "fog", "rain", "heavy", "storm", "snow"].indexOf(fx.kind) >= 0
        x: visible ? -100 + 80 * Ilot.wave(fx.t, 14000) : -100
        y: fx.kind === "fog" ? 0 : -20
        width: fx.width + 120
        height: fx.kind === "fog" ? fx.height : 40
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.4; color: Qt.rgba(0.82, 0.82, 0.86, fx.kind === "fog" ? 0.22 : 0.16) }
            GradientStop { position: 0.8; color: "transparent" }
        }
    }

    // gouttes, flocons, etoiles
    Repeater {
        model: fx.kind === "rain" || fx.kind === "heavy" || fx.kind === "storm" || fx.kind === "snow" || fx.kind === "night" ? fx.drops : []
        Rectangle {
            id: d
            required property var modelData
            readonly property bool star: fx.kind === "night"
            readonly property bool flake: fx.kind === "snow"
            // chute : attente de `w` ms, puis descente (y) et glissement (x)
            readonly property real fall: modelData.d * (flake ? 4 : fx.kind === "heavy" ? 0.7 : 1)
            readonly property real drift: modelData.d * (flake ? 4 : 1)
            // ms depuis le debut de la chute (negatif : en attente, hors champ)
            readonly property real p: star ? 0 : fx.t % (modelData.w + Math.max(fall, drift)) - modelData.w
            x: modelData.x * fx.width + (star || p < 0 ? 0 : (flake ? -3 : -8) * Math.min(1, p / drift))
            y: star ? modelData.y * fx.height : p < 0 ? -14 : -14 + 90 * Math.min(1, p / fall)
            width: star ? 2 : flake ? 4 : 1.5
            height: star ? 2 : flake ? 4 : fx.kind === "heavy" ? 14 : 10
            radius: star || flake ? width / 2 : 1
            color: star || flake ? "white" : "#9ecbff"
            // scintillement des etoiles : attente de `w` ms, puis 0,15 -> 0,9 -> 0,15
            readonly property real tw: star ? fx.t % (modelData.w + modelData.d * 3) - modelData.w : -1
            readonly property real twinkle: tw < 0 ? 0.15 : 0.15 + 0.75 * Ilot.wave(tw, modelData.d * 3)
            opacity: star ? twinkle : flake ? 0.8 : 0.75
        }
    }

    // eclairs
    Rectangle {
        visible: fx.kind === "storm"
        anchors.fill: parent
        color: Qt.rgba(0.86, 0.9, 1, 0.55)
        // toutes les 7 s : deux eclairs (monte en 70 ms, retombe en 140,
        // remonte en 70, s'eteint en 300)
        readonly property real q: visible ? fx.t % 6980 - 6400 : -1
        opacity: q < 0 ? 0 : q < 70 ? q / 70 : q < 210 ? 1 - (q - 70) / 140 : q < 280 ? (q - 210) / 70 : Math.max(0, 1 - (q - 280) / 300)
    }
}
