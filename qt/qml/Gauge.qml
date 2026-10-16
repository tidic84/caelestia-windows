import QtQuick
import QtQuick.Shapes

// .gauge : anneau de 44 px, icone au centre, libelle et valeur a droite
Item {
    id: g
    property real frac: 0
    property string icon: ""
    property string label: ""
    property string value: "-"
    // l'anneau ne s'anime que s'il se voit (sinon une animation tourne pour rien)
    property bool animate: true
    readonly property bool hot: frac > 0.9
    implicitWidth: 44 + 10 + texts.implicitWidth
    implicitHeight: 44

    property real shownFrac: Math.max(0, Math.min(1, frac))
    Behavior on shownFrac {
        enabled: g.animate
        NumberAnimation { duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
    }

    Shape {
        width: 44
        height: 44
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.surfaceHighest
            strokeWidth: 4.5
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: g.hot ? Theme.error : Theme.primary
            strokeWidth: g.shownFrac > 0.001 ? 4.5 : 0
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: 360 * g.shownFrac }
        }
    }
    Ms {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        name: g.icon
        color: Theme.inkVariant
    }
    Column {
        id: texts
        x: 54
        anchors.verticalCenter: parent.verticalCenter
        Txt {
            text: g.label
            weight: Font.Medium
            px: 12
            color: Theme.inkVariant
        }
        Txt {
            text: g.value
            weight: Font.Medium
            px: 15
            tnum: true
        }
    }
}
