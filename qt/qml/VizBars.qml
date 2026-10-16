import QtQuick

// Visualiseur : 24 barres arrondies en haut (paintBars d'app.js)
// mirror : onglet Media de la branche (drawBars d'app.js, { mirror: true }) :
// graves au centre, aigus vers les bords, degrade primaire / tertiaire /
// secondaire sur toute la hauteur, fondu vers le haut
Item {
    id: v
    // ne suit le son que s'il se voit
    property bool active: true
    property bool mirror: false
    readonly property int bands: 24
    readonly property int n: mirror ? bands * 2 : bands
    readonly property real gap: mirror ? 3 : width / n * 0.28
    readonly property real bw: mirror ? (width - gap * (n - 1)) / n : width / n - gap

    // degrade de toute la hauteur (0 = haut) : opaque sur les 30 % du bas,
    // transparent en haut (masque CSS de la branche)
    readonly property var stops: [
        [0.0, Qt.alpha(Theme.secondary, 0)],
        [0.4, Qt.alpha(Theme.tertiary, 0.57)],
        [0.7, Qt.tint(Theme.tertiary, Qt.alpha(Theme.primary, 0.5))],
        [1.0, Theme.primary]
    ]
    function col(p) {
        for (let i = 1; i < stops.length; i++) {
            if (p <= stops[i][0]) {
                const a = stops[i - 1], b = stops[i]
                const t = (p - a[0]) / (b[0] - a[0])
                return Qt.rgba(a[1].r + (b[1].r - a[1].r) * t, a[1].g + (b[1].g - a[1].g) * t,
                               a[1].b + (b[1].b - a[1].b) * t, a[1].a + (b[1].a - a[1].a) * t)
            }
        }
        return stops[stops.length - 1][1]
    }

    Repeater {
        model: v.n
        Rectangle {
            id: bar
            required property int index
            readonly property int band: v.mirror ? (index < v.bands ? v.bands - 1 - index : index - v.bands) : index
            readonly property real level: v.active ? (Ilot.shown[band] || 0) : 0
            x: v.mirror ? index * (v.bw + v.gap) : index * (v.bw + v.gap) + v.gap / 2
            width: v.bw
            height: v.mirror ? Math.max(2, level * v.height) : Math.max(v.bw * 0.6, level * v.height)
            y: v.height - height
            visible: v.active && Ilot.live
            topLeftRadius: v.mirror ? Math.min(v.bw / 2, 4) : Math.min(v.bw / 2, height / 2)
            topRightRadius: topLeftRadius
            bottomLeftRadius: v.mirror ? topLeftRadius : 0
            bottomRightRadius: bottomLeftRadius
            color: Theme.primary
            // part du degrade global couverte par la barre
            readonly property real from: v.height > 0 ? y / v.height : 0
            function at(p) { return Math.max(0, Math.min(1, (p - from) / Math.max(0.001, 1 - from))) }
            gradient: v.mirror ? grad : null
            Gradient {
                id: grad
                GradientStop { position: 0; color: v.col(bar.from) }
                GradientStop { position: bar.at(0.4); color: v.col(Math.max(0.4, bar.from)) }
                GradientStop { position: bar.at(0.7); color: v.col(Math.max(0.7, bar.from)) }
                GradientStop { position: 1; color: Theme.primary }
            }
        }
    }
}
