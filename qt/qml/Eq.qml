import QtQuick

// Egaliseur de la pilule : trois barres. Pendant la lecture, une animation
// tourne sur le thread de rendu (YAnimator) ; quand le visualiseur envoie
// des bandes, les barres suivent le son (« live »).
Row {
    id: eq
    property bool running: false
    readonly property bool live: Ilot.live
    spacing: 2
    height: 12

    Repeater {
        model: 3
        Item {
            id: bar
            required property int index
            width: 3
            height: 12
            clip: true

            // niveau du visualiseur : moyenne d'un groupe de 8 bandes
            readonly property real level: {
                const s = Ilot.shown
                let v = 0
                for (let i = index * 8; i < index * 8 + 8; i++)
                    v += s[i] || 0
                return v / 8
            }

            // a l'arret : 4 px
            Rectangle {
                visible: !eq.running && !eq.live
                width: 3
                height: 4
                radius: 2
                y: 8
                color: Theme.primary
            }
            // lecture sans visualiseur (@keyframes eq : 3 -> 12 -> 6 px, en alternance)
            Rectangle {
                id: idle
                visible: eq.running && !eq.live
                width: 3
                height: 12
                radius: 2
                y: [9, 0.6, 4.3][bar.index]
                // suite des hauteurs (y) apres le decalage de phase
                readonly property var seq: bar.index === 2 ? [0, 9, 0, 6] : [6, 0, 9, 0]
                color: Theme.primary

                SequentialAnimation {
                    running: idle.visible && eq.visible
                    // decalage de phase (animation-delay negatif : -0.35 s, -0.7 s)
                    SequentialAnimation {
                        YAnimator { target: idle; to: [0, 0, 6][bar.index]; duration: [500, 150, 300][bar.index]; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                    }
                    SequentialAnimation {
                        loops: Animation.Infinite
                        YAnimator { target: idle; to: idle.seq[0]; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                        YAnimator { target: idle; to: idle.seq[1]; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                        YAnimator { target: idle; to: idle.seq[2]; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                        YAnimator { target: idle; to: idle.seq[3]; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
                    }
                }
            }
            // visualiseur : 3 + niveau x 9 px
            Rectangle {
                visible: eq.live
                width: 3
                radius: 2
                height: 3 + bar.level * 9
                y: 12 - height
                color: Theme.primary
                Behavior on height { NumberAnimation { duration: 50 } }
            }
        }
    }
}
