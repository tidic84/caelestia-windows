import QtQuick
import QtQuick.Shapes

// Heure de la pilule repliee (Apparence > Horloge de la pilule) : classique,
// a volets, a aiguilles, neon ou pixel.
Item {
    id: c
    readonly property string style: Ilot.cfg.clock || "digital"
    readonly property date now: Ilot.now
    readonly property string hh: Ilot.pad(now.getHours())
    readonly property string mm: Ilot.pad(now.getMinutes())
    implicitWidth: style === "analog" ? 20 : style === "flip" ? flip.implicitWidth : label.implicitWidth
    implicitHeight: 20

    // classique, neon, pixel
    Txt {
        id: label
        visible: c.style !== "analog" && c.style !== "flip"
        anchors.centerIn: parent
        text: c.hh + ":" + c.mm
        weight: c.style === "pixel" ? Font.Bold : Font.Medium
        font.letterSpacing: c.style === "pixel" ? 1.2 : 0.3
        font.family: c.style === "pixel" ? "Consolas" : Theme.font
        tnum: true
        color: c.style === "neon" ? Theme.primary : Theme.ink
        style: c.style === "neon" ? Text.Outline : Text.Normal
        styleColor: Theme.alpha(Theme.primary, 0.45)
        // le neon respire doucement (horloge d'ambiance, Ilot.amb)
        opacity: c.style === "neon" && c.visible && Ilot.ambient ? 1 - 0.25 * Ilot.wave(Ilot.amb, 2800) : 1
    }

    // a volets : chaque chiffre bascule quand il change
    Row {
        id: flip
        visible: c.style === "flip"
        anchors.centerIn: parent
        spacing: 1
        Repeater {
            model: [c.hh[0], c.hh[1], ":", c.mm[0], c.mm[1]]
            Item {
                required property var modelData
                width: modelData === ":" ? 5 : 11
                height: 18
                Rectangle {
                    visible: parent.modelData !== ":"
                    anchors.fill: parent
                    radius: 3
                    color: Theme.surfaceHighest
                    Rectangle {
                        width: parent.width
                        height: 1
                        y: parent.height / 2
                        color: Theme.alpha(Theme.surface, 0.6)
                    }
                }
                Txt {
                    id: digit
                    anchors.centerIn: parent
                    text: parent.modelData
                    px: 12
                    weight: Font.DemiBold
                    tnum: true
                    onTextChanged: if (digit.text !== ":" && c.visible) flipAnim.restart()
                    transform: Scale {
                        id: flipScale
                        origin.y: digit.height / 2
                    }
                    SequentialAnimation {
                        id: flipAnim
                        NumberAnimation { target: flipScale; property: "yScale"; from: 0; to: 1; duration: Theme.dur(350); easing.type: Easing.OutBack }
                    }
                }
            }
        }
    }

    // a aiguilles
    Shape {
        id: hands
        visible: c.style === "analog"
        anchors.centerIn: parent
        width: 20
        height: 20
        preferredRendererType: Shape.CurveRenderer
        readonly property real ha: ((c.now.getHours() % 12) * 30 + c.now.getMinutes() * 0.5) * Math.PI / 180
        readonly property real ma: c.now.getMinutes() * 6 * Math.PI / 180
        ShapePath {
            strokeColor: Theme.ink
            strokeWidth: 1.5
            fillColor: "transparent"
            PathAngleArc { centerX: 10; centerY: 10; radiusX: 8.4; radiusY: 8.4; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: Theme.ink
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: 10
            startY: 10
            PathLine { x: 10 + Math.sin(hands.ha) * 4.4; y: 10 - Math.cos(hands.ha) * 4.4 }
        }
        ShapePath {
            strokeColor: Theme.primary
            strokeWidth: 1.4
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: 10
            startY: 10
            PathLine { x: 10 + Math.sin(hands.ma) * 6.6; y: 10 - Math.cos(hands.ma) * 6.6 }
        }
    }
}
