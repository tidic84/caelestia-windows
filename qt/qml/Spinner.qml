import QtQuick
import QtQuick.Shapes

// Cercle de chargement (bordure dont le haut est transparent, qui tourne)
Shape {
    id: s
    property real size: 28
    property real stroke: 3
    property color color: Theme.primary
    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: s.color
        strokeWidth: s.stroke
        fillColor: "transparent"
        PathAngleArc {
            centerX: s.size / 2
            centerY: s.size / 2
            radiusX: (s.size - s.stroke) / 2
            radiusY: radiusX
            startAngle: -45
            sweepAngle: 270
        }
    }
    RotationAnimator on rotation {
        running: s.visible
        from: 0
        to: 360
        duration: 800
        loops: Animation.Infinite
    }
}
