import QtQuick
import QtQuick.Shapes

// Tache de lumiere ronde (radial-gradient) : halo du soleil, voiles d'aurore
Shape {
    id: g
    property color color: "white"
    // part opaque au centre (0..1)
    property real core: 0.2
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: g.width / 2
            centerY: g.height / 2
            centerRadius: Math.max(g.width, g.height) / 2
            focalX: centerX
            focalY: centerY
            GradientStop { position: 0; color: g.color }
            GradientStop { position: g.core; color: g.color }
            GradientStop { position: 1; color: "transparent" }
        }
        PathRectangle {
            width: g.width
            height: g.height
            radius: Math.min(g.width, g.height) / 2
        }
    }
}
