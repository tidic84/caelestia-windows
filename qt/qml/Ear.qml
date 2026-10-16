import QtQuick
import QtQuick.Shapes

// Coin concave : l'ilot « sort » du bord de l'ecran (::before / ::after en CSS)
Shape {
    id: ear
    property real size: 22
    property bool mirrored: false
    width: 22
    height: Math.max(0, size)
    visible: size > 0
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { origin.x: 11; xScale: ear.mirrored ? -1 : 1 }

    ShapePath {
        strokeWidth: -1
        fillColor: Theme.surface
        startX: 0; startY: 0
        PathLine { x: 22; y: 0 }
        PathLine { x: 22; y: ear.size }
        // quart de cercle creuse, centre en bas a gauche
        PathArc { x: 22 - ear.size; y: 0; radiusX: ear.size; radiusY: ear.size; direction: PathArc.Counterclockwise }
        PathLine { x: 0; y: 0 }
    }
}
