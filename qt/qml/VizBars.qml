import QtQuick

// Visualiseur : 24 barres arrondies en haut (paintBars d'app.js)
Item {
    id: v
    // ne suit le son que s'il se voit
    property bool active: true
    readonly property int n: 24
    readonly property real gap: width / n * 0.28
    readonly property real bw: width / n - gap

    Repeater {
        model: v.n
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
}
