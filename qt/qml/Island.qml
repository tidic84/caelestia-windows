import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import IlotCore

// L'ilot : fond aux coins bas arrondis, coins concaves en haut, pilule
// (replie, survol, activite) et panneau ouvert. Taille, rayon et coins
// s'animent comme dans style.css (#island).
Item {
    id: island

    readonly property var target: Ilot.size
    width: target.w
    height: target.h
    Behavior on width { NumberAnimation { duration: Theme.dur(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.springCurve } }
    Behavior on height { NumberAnimation { duration: Theme.dur(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.springCurve } }

    property real r: Ilot.radius
    Behavior on r { NumberAnimation { duration: Theme.dur(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
    // taille des coins concaves (--ear) et haut des coins (sous la barre pleine)
    property real ear: Ilot.ear
    Behavior on ear { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
    readonly property real earTop: Ilot.barDocked ? Ilot.barH : 0

    // jeu en plein ecran : l'ilot remonte et s'efface ; Apparence > Taille de
    // la pilule : la pilule repliee est agrandie ou reduite depuis le haut
    transform: [
        Scale {
            origin.x: island.width / 2
            origin.y: 0
            xScale: Ilot.pillK
            yScale: Ilot.pillK
            Behavior on xScale { NumberAnimation { duration: Theme.dur(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
            Behavior on yScale { NumberAnimation { duration: Theme.dur(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
        },
        Translate {
            y: Ilot.fullscreen ? -40 : 0
            Behavior on y { NumberAnimation { duration: Ilot.fullscreen ? 350 : 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Ilot.fullscreen ? Theme.std : Theme.emph } }
        }
    ]
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
            color: Theme.islandSurface
        }
        Ear {
            x: island.ear + island.width - 1
            r: island.ear
            visibleH: island.height - island.r - island.earTop
            mirrored: true
            color: Theme.islandSurface
        }
        Rectangle {
            x: island.ear
            width: island.width
            height: parent.height
            color: Theme.islandSurface
            bottomLeftRadius: island.r
            bottomRightRadius: island.r
        }
    }

    // decor de fond, a la forme de l'ilot : aurore boreale, meteo animee
    Item {
        id: deco
        anchors.fill: parent
        readonly property bool aurora: Ilot.cfg.island_bg === "aurora" && !Theme.highContrast && !Theme.reduced
        visible: aurora || wx.visible
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: decoMask
        }
        Aurora {
            anchors.fill: parent
            visible: deco.aurora
        }
        WxFx {
            id: wx
            anchors.fill: parent
        }
    }
    Rectangle {
        id: decoMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        bottomLeftRadius: island.r
        bottomRightRadius: island.r
    }

    // contour (Apparence > Contour de l'ilot), clignotement « partie trouvee »
    readonly property string border: Ilot.cfg.border || "none"
    readonly property bool flash: Watch.matchFlash
    // horloge d'ambiance (Ilot.amb) : couleurs figees quand personne ne regarde
    property real hue: 0
    Binding on hue {
        when: island.border === "rgb" && Ilot.ambient
        value: (Ilot.amb % 6000) / 6000
        restoreMode: Binding.RestoreNone
    }
    readonly property color lineColor: flash ? Theme.bad : border === "rgb" ? Qt.hsva(hue, 0.85, 1, 1) : Theme.primary
    // 1 -> 0,35 -> 1 ; le clignotement « partie trouvee » continue sans personne
    readonly property bool pulsing: ((island.border === "pulse" && Ilot.ambient) || island.flash) && !Theme.reduced && !Ilot.fullscreen
    readonly property real pulse: pulsing ? 1 - 0.65 * Ilot.wave(Ilot.amb, island.flash ? 800 : Ilot.media.playing ? 1200 : 2400) : 1
    // Trace du contour (SVG), decale de (ox, oy) : il part du bord de
    // l'ecran, suit le coin concave (meme coupe que Ear quand l'arrondi du
    // bas le rogne), descend le cote, fait le tour du bas et remonte.
    function outline(ox, oy) {
        const w = width, h = height, t = earTop, e = ear
        const r = Math.max(0, Math.min(island.r, w / 2, h - t))
        // bas des cotes droits : debut de l'arrondi du bas
        const yc = Math.max(t, h - r)
        const f = n => (Math.round(n * 100) / 100).toString()
        const P = (x, y) => f(x + ox) + " " + f(y + oy)
        let left, right
        if (e > 0.5) {
            const ye = Math.min(t + e, yc)
            const dx = e - Math.sqrt(Math.max(0, e * e - (t + e - ye) * (t + e - ye)))
            left = "M " + P(-e, t) + " A " + f(e) + " " + f(e) + " 0 0 1 " + P(-dx, ye) + " L " + P(0, ye)
            right = " L " + P(w, ye) + " L " + P(w + dx, ye) + " A " + f(e) + " " + f(e) + " 0 0 1 " + P(w + e, t)
        } else {
            left = "M " + P(0, t - 3)
            right = " L " + P(w, t - 3)
        }
        return left + " L " + P(0, yc)
            + " A " + f(r) + " " + f(r) + " 0 0 0 " + P(r, h)
            + " L " + P(w - r, h)
            + " A " + f(r) + " " + f(r) + " 0 0 0 " + P(w, yc)
            + right
    }
    // lueur : le contour epais et flou, sous l'ilot
    Shape {
        id: glow
        visible: island.flash || ["glow", "rgb", "pulse"].indexOf(island.border) >= 0
        readonly property real pad: island.ear + 6
        x: -pad
        y: -6 + 4
        width: island.width + pad * 2
        height: island.height + 12
        z: -1
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: visible
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 24
        }
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 7
            strokeColor: Theme.alpha(island.lineColor, 0.55 * island.pulse)
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: glow.visible ? island.outline(glow.pad, 6) : "" }
        }
    }
    Shape {
        id: edge
        visible: island.flash || island.border !== "none"
        width: island.width
        height: island.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeWidth: island.border === "line" && !island.flash ? 1 : 1.5
            strokeColor: Theme.alpha(island.lineColor, (island.border === "line" && !island.flash ? 0.45 : 0.8) * island.pulse)
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: edge.visible ? island.outline(0, 0) : "" }
        }
    }

    // ilot ouvert : un glisser entre deux zones de depot (vers le bouton
    // Quick Share...) reste « dans » l'ilot, qui ne se referme pas
    DropArea {
        anchors.fill: parent
        enabled: Ilot.mode === "open"
        onEntered: d => {
            if (!d.hasUrls)
                return d.accepted = false
            Ilot.dragIn()
        }
        onExited: Ilot.dragLeft()
        onDropped: Ilot.dragDone()
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
    // (actions sur les fichiers) et le bouton Quick Share s'allume. Ouvert
    // sur les applis, les sons ou Quick Share, leurs propres zones de depot
    // prennent le relais.
    DropArea {
        anchors.fill: parent
        enabled: Ilot.mode !== "open" || (["apps", "sounds"].indexOf(Ilot.currentTab) < 0 && !Watch.shareOpen)
        onEntered: d => {
            if (!d.hasUrls)
                return
            Ilot.dragIn()
            if (Ilot.mode !== "open")
                Ilot.fileDragOpened = true
            Ilot.pinned = true
            Ilot.open("apps")
        }
        // desactivee par l'ouverture : les zones de l'ilot ouvert prennent le relais
        onExited: if (Ilot.mode !== "open") Ilot.dragLeft()
        onDropped: Ilot.dragDone()
    }
}
