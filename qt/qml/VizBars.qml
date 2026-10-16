import QtQuick
import QtQuick.Effects

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
    readonly property bool on: active && Ilot.live

    Item {
        id: bars
        anchors.fill: parent
        // en miroir, les barres ne servent que de masque au degrade
        visible: !v.mirror
        layer.enabled: v.mirror

        Repeater {
            model: v.n
            Rectangle {
                required property int index
                readonly property int band: v.mirror ? (index < v.bands ? v.bands - 1 - index : index - v.bands) : index
                readonly property real level: v.active ? (Ilot.shown[band] || 0) : 0
                x: v.mirror ? index * (v.bw + v.gap) : index * (v.bw + v.gap) + v.gap / 2
                width: v.bw
                height: v.mirror ? Math.max(2, level * v.height) : Math.max(v.bw * 0.6, level * v.height)
                y: v.height - height
                visible: v.on
                topLeftRadius: v.mirror ? Math.min(v.bw / 2, 4) : Math.min(v.bw / 2, height / 2)
                topRightRadius: topLeftRadius
                bottomLeftRadius: v.mirror ? topLeftRadius : 0
                bottomRightRadius: bottomLeftRadius
                color: Theme.primary
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: v.mirror && v.on
        // opaque sur les 30 % du bas, transparent en haut (masque CSS de la branche)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.secondary.alpha(0) }
            GradientStop { position: 0.4; color: Theme.tertiary.alpha(0.57) }
            GradientStop { position: 0.7; color: Qt.tint(Theme.tertiary, Qt.alpha(Theme.primary, 0.5)) }
            GradientStop { position: 1.0; color: Theme.primary }
        }
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bars
        }
    }
}
