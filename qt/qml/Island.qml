import QtQuick
import IlotCore

// L'ilot : fond aux coins bas arrondis, coins concaves en haut, pilule
// (replie, survol, activite) et panneau ouvert. Taille, rayon et coins
// s'animent comme dans style.css (#island).
Item {
    id: island

    readonly property var target: Ilot.size
    width: target.w
    height: target.h
    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

    property real r: Ilot.radius
    Behavior on r { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
    // taille des coins concaves (--ear) et haut des coins (sous la barre pleine)
    property real ear: Ilot.ear
    Behavior on ear { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
    readonly property real earTop: Ilot.barDocked ? Ilot.barH : 0

    // jeu en plein ecran : l'ilot remonte et s'efface
    transform: Translate {
        y: Ilot.fullscreen ? -40 : 0
        Behavior on y { NumberAnimation { duration: Ilot.fullscreen ? 350 : 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Ilot.fullscreen ? Theme.std : Theme.emph } }
    }
    opacity: Ilot.fullscreen ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Ilot.fullscreen ? 250 : 300 } }

    // fond et coins concaves en une seule couche : opaques dedans, la
    // transparence s'applique a l'ensemble (sinon les bords qui se
    // chevauchent ressortent plus sombres). Sous la barre pleine, c'est elle
    // qui fait le fond.
    Item {
        id: bg
        x: -island.ear
        y: island.earTop
        width: island.width + island.ear * 2 + 1
        height: Math.max(0, island.height - island.earTop)
        opacity: Theme.islandAlpha
        layer.enabled: opacity < 1
        layer.smooth: true

        Ear {
            x: 0
            r: island.ear
            visibleH: island.height - island.r - island.earTop
            color: Theme.surface
        }
        Ear {
            x: island.ear + island.width - 1
            r: island.ear
            visibleH: island.height - island.r - island.earTop
            mirrored: true
            color: Theme.surface
        }
        Rectangle {
            x: island.ear
            width: island.width
            height: parent.height
            color: Theme.surface
            bottomLeftRadius: island.r
            bottomRightRadius: island.r
        }
    }

    Item {
        id: clipBox
        anchors.fill: parent
        clip: true

        Pill {
            id: pill
            anchors.fill: parent
        }
        Panel {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // fichiers glisses depuis l'Explorateur : l'ilot s'ouvre sur les applis
    DropArea {
        anchors.fill: parent
        enabled: Ilot.mode !== "open" || Ilot.currentTab !== "apps"
        onEntered: d => {
            if (!d.hasUrls)
                return
            Ilot.fileDragOpened = true
            Ilot.pinned = true
            Ilot.open("apps")
        }
    }
}
