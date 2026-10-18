import QtQuick

// Visualiseur : 24 barres arrondies en haut (paintBars d'app.js)
// mirror : onglet Media de la branche (drawBars d'app.js, { mirror: true }) :
// graves au centre, aigus vers les bords, degrade primaire / tertiaire /
// secondaire sur toute la hauteur, fondu vers le haut. Dessine par un seul
// ShaderEffect (shaders/vizbars.frag) : aucun JS par barre et par trame.
Item {
    id: v
    // ne suit le son que s'il se voit
    property bool active: true
    property bool mirror: false
    readonly property int bands: 24
    readonly property int n: mirror ? bands * 2 : bands
    readonly property real gap: mirror ? 3 : width / n * 0.28
    readonly property real bw: mirror ? (width - gap * (n - 1)) / n : width / n - gap

    Repeater {
        model: v.mirror ? 0 : v.n
        Rectangle {
            required property int index
            readonly property real level: v.active ? (Ilot.shown[index] || 0) : 0
            x: index * (v.bw + v.gap) + v.gap / 2
            width: v.bw
            height: Math.max(v.bw * 0.6, level * v.height)
            y: v.height - height
            visible: v.active && Ilot.live
            topLeftRadius: Math.min(v.bw / 2, height / 2)
            topRightRadius: topLeftRadius
            color: Theme.primary
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: v.mirror && v.active && Ilot.live
        fragmentShader: "qrc:/shaders/vizbars.frag.qsb"
        function vec(c) { return Qt.vector4d(c.r, c.g, c.b, c.a) }
        // niveaux 4 par 4 (bandes 0..23)
        function lv(i) {
            const s = Ilot.shown
            return Qt.vector4d(s[i] || 0, s[i + 1] || 0, s[i + 2] || 0, s[i + 3] || 0)
        }
        property size size: Qt.size(Math.max(1, width), Math.max(1, height))
        property real gap: v.gap
        property vector4d l0: visible ? lv(0) : Qt.vector4d(0, 0, 0, 0)
        property vector4d l1: visible ? lv(4) : Qt.vector4d(0, 0, 0, 0)
        property vector4d l2: visible ? lv(8) : Qt.vector4d(0, 0, 0, 0)
        property vector4d l3: visible ? lv(12) : Qt.vector4d(0, 0, 0, 0)
        property vector4d l4: visible ? lv(16) : Qt.vector4d(0, 0, 0, 0)
        property vector4d l5: visible ? lv(20) : Qt.vector4d(0, 0, 0, 0)
        // degrade de toute la hauteur (0 = haut) : opaque sur les 30 % du bas,
        // transparent en haut (masque CSS de la branche)
        property vector4d c0: vec(Qt.alpha(Theme.secondary, 0))
        property vector4d c1: vec(Qt.alpha(Theme.tertiary, 0.57))
        property vector4d c2: vec(Qt.tint(Theme.tertiary, Qt.alpha(Theme.primary, 0.5)))
        property vector4d c3: vec(Theme.primary)
    }
}
