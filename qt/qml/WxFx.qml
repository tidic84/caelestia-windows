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
        SequentialAnimation on scale {
            running: fx.visible && fx.kind === "sun"
            loops: Animation.Infinite
            NumberAnimation { to: 1.18; duration: 2500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 2500; easing.type: Easing.InOutSine }
        }
    }

    // nuages / brouillard qui passent
    Rectangle {
        visible: ["cloud", "fog", "rain", "heavy", "storm", "snow"].indexOf(fx.kind) >= 0
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
        SequentialAnimation on x {
            running: fx.visible
            loops: Animation.Infinite
            NumberAnimation { from: -100; to: -20; duration: 7000; easing.type: Easing.InOutSine }
            NumberAnimation { from: -20; to: -100; duration: 7000; easing.type: Easing.InOutSine }
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
            x: modelData.x * fx.width
            y: star ? modelData.y * fx.height : -14
            width: star ? 2 : flake ? 4 : 1.5
            height: star ? 2 : flake ? 4 : fx.kind === "heavy" ? 14 : 10
            radius: star || flake ? width / 2 : 1
            color: star || flake ? "white" : "#9ecbff"
            // scintillement des etoiles (anime a part : la liaison reste)
            property real twinkle: 0.15
            opacity: star ? twinkle : flake ? 0.8 : 0.75
            // chute (pluie, neige)
            SequentialAnimation {
                running: fx.visible && !d.star
                loops: Animation.Infinite
                PauseAnimation { duration: d.modelData.w }
                ParallelAnimation {
                    NumberAnimation { target: d; property: "y"; from: -14; to: 76; duration: d.modelData.d * (d.flake ? 4 : fx.kind === "heavy" ? 0.7 : 1) }
                    NumberAnimation { target: d; property: "x"; from: d.modelData.x * fx.width; to: d.modelData.x * fx.width + (d.flake ? -3 : -8); duration: d.modelData.d * (d.flake ? 4 : 1) }
                }
            }
            // scintillement (etoiles)
            SequentialAnimation on twinkle {
                running: fx.visible && d.star
                loops: Animation.Infinite
                PauseAnimation { duration: d.modelData.w }
                NumberAnimation { to: 0.9; duration: d.modelData.d * 1.5; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.15; duration: d.modelData.d * 1.5; easing.type: Easing.InOutSine }
            }
        }
    }

    // eclairs
    Rectangle {
        visible: fx.kind === "storm"
        anchors.fill: parent
        color: Qt.rgba(0.86, 0.9, 1, 0.55)
        opacity: 0
        SequentialAnimation on opacity {
            running: fx.visible && fx.kind === "storm"
            loops: Animation.Infinite
            PauseAnimation { duration: 6400 }
            NumberAnimation { to: 1; duration: 70 }
            NumberAnimation { to: 0; duration: 140 }
            NumberAnimation { to: 1; duration: 70 }
            NumberAnimation { to: 0; duration: 300 }
        }
    }
}
