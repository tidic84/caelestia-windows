import QtQuick
import QtQuick.Effects
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

    Ear {
        x: -island.ear
        y: island.earTop
        r: island.ear
        visibleH: island.height - island.r - island.earTop
    }
    Ear {
        x: island.width - 1
        y: island.earTop
        r: island.ear
        visibleH: island.height - island.r - island.earTop
        mirrored: true
    }

    // fond d'ecran floute derriere l'ilot (Reglages > Fond de l'ilot)
    Item {
        id: wallLayer
        anchors.fill: parent
        visible: Ilot.wallBg !== ""
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shapeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Item {
            id: wallSrc
            // le fond, cale comme a l'ecran (« remplir ») : l'ilot est centre en haut
            readonly property size natural: Ilot.wallBg ? Backend.imageSize(Ilot.wallBg) : Qt.size(1, 1)
            readonly property real k: Math.max(Ilot.screenW / Math.max(1, natural.width), Ilot.screenH / Math.max(1, natural.height))
            width: natural.width * k
            height: natural.height * k
            x: (island.width - width) / 2
            y: -(height - Ilot.screenH) / 2
            visible: false
            Image {
                anchors.fill: parent
                source: Ilot.wallBg
                fillMode: Image.Stretch
                asynchronous: true
                sourceSize.width: 960
            }
        }
        MultiEffect {
            source: wallSrc
            x: wallSrc.x
            y: wallSrc.y
            width: wallSrc.width
            height: wallSrc.height
            blurEnabled: true
            blurMax: 48
            blur: 0.7
            saturation: 0.4
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.surface, 0.5)
        }
    }
    Rectangle {
        id: shapeMask
        anchors.fill: parent
        visible: false
        layer.enabled: Ilot.wallBg !== ""
        bottomLeftRadius: island.r
        bottomRightRadius: island.r
        color: "black"
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        visible: Ilot.wallBg === ""
        color: Theme.islandBg
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: island.r
        bottomRightRadius: island.r
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
