import QtQuick
import QtQuick.Shapes

// Jauge circulaire (CPU, RAM, disque)
Row {
    id: g
    property string label
    property string text
    property real value: 0
    spacing: 10

    Shape {
        width: 44
        height: 44
        ShapePath {
            strokeColor: Theme.surfaceHighest
            strokeWidth: 4
            fillColor: "transparent"
            PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: g.value > 0.9 ? Theme.tertiary : Theme.primary
            strokeWidth: 4
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, g.value))
                Behavior on sweepAngle { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
            }
        }
    }
    Column {
        anchors.verticalCenter: parent.verticalCenter
        Text { text: g.label; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.inkVariant }
        Text { text: g.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium; color: Theme.ink }
    }
}
