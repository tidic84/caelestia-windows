import QtQuick
import QtQuick.Shapes

// Coin concave : l'ilot « sort » du bord de l'ecran (::before / ::after en CSS).
// Carre de cote `r` creuse d'un quart de cercle centre en bas, du cote de
// l'exterieur ; seule la hauteur `visibleH` est montree (le coin s'arrete
// ou commence l'arrondi du bas de l'ilot).
Item {
    id: ear
    property real r: 22
    property real visibleH: r
    property bool mirrored: false
    property color color: Theme.islandBg
    width: r + 1
    height: Math.max(0, Math.min(r, visibleH))
    visible: r > 0.5 && height > 0.5
    clip: true

    Shape {
        width: ear.r + 1
        height: ear.r
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.x: (ear.r + 1) / 2; xScale: ear.mirrored ? -1 : 1 }
        ShapePath {
            strokeWidth: -1
            fillColor: ear.color
            startX: 0; startY: 0
            PathLine { x: ear.r + 1; y: 0 }
            PathLine { x: ear.r + 1; y: ear.r }
            PathLine { x: ear.r; y: ear.r }
            PathArc { x: 0; y: 0; radiusX: ear.r; radiusY: ear.r; direction: PathArc.Counterclockwise }
        }
    }
}
