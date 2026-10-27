import QtQuick
import Ilot
import IlotCore

// Fenetre de l'ilot : transparente, en haut de l'ecran choisi, sur toute la
// largeur avec la barre. Seules les zones declarees (ilot, barre, apercu)
// recoivent la souris ; ailleurs, les clics passent aux fenetres dessous.
Window {
    id: win
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: "Ilot"
    width: 800
    height: 600
    visible: false
    // nom de l'ecran (donne par Shell)
    property string screenName: ""

    // un champ qui avait le clavier est desactive (changement d'onglet) : le
    // focus tombe sur contentItem, et Echap n'arrivait plus a root
    onActiveFocusItemChanged: {
        if (activeFocusItem === contentItem)
            root.forceActiveFocus()
    }

    // appele par Shell quand le coeur Rust tourne
    function start() {
        Ilot.start()
        Qt.callLater(updateHit)
    }

    WinCtl {
        id: ctl
        window: win
        label: "island"
        // masquage auto : une bande au bord de l'ecran affiche la barre, qui
        // reste tant que la souris est dessus
        topBand: Ilot.barAuto && !Ilot.covered ? (Ilot.barPeek ? Ilot.barH + 8 : 2) : 0
        // Reglages > Jeu et absence > Îlot en plein écran
        fsMode: Ilot.cfg.fs_hide || "normal"
        fsApps: Ilot.fsApps
        onTopHoverChanged: Ilot.setAtTop(topHover)
        onFullscreenChanged: Ilot.setFullscreen(fullscreen)
        onCoveredChanged: Ilot.covered = covered
        onFsExeChanged: Qt.callLater(Ilot.sawFullscreen, fsExe)
    }
    Connections {
        target: Ilot
        function onReleaseFocus() { ctl.releaseFocus() }
        function onGrabFocus() { ctl.grabFocus() }
    }
    onActiveChanged: if (!active) Ilot.blurred()

    Binding { target: Ilot; property: "screenW"; value: win.Screen.width }
    Binding { target: Ilot; property: "screenH"; value: win.Screen.height }

    TipWindow {}
    // bandeau des sous-titres en direct ; promenade du compagnon, chargee
    // seulement pendant qu'il est dehors
    Captions { host: win }
    Loader {
        active: Watch.petWinOn
        sourceComponent: PetWindow { host: win }
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        // survol de l'ilot (hoverZone, plus bas) : vu depuis la racine, qui
        // recoit le survol de tous ses enfants sans le leur prendre. Un
        // HoverHandler sur hoverZone, au-dessus de tout, privait les boutons
        // du panneau de survol (ni info-bulle, ni surbrillance).
        HoverHandler {
            id: rootHover
        }
        readonly property bool overIsland: {
            if (!rootHover.hovered)
                return false
            const p = rootHover.point.position
            return p.x >= hoverZone.x && p.x < hoverZone.x + hoverZone.width
                && p.y >= hoverZone.y && p.y < hoverZone.y + hoverZone.height
        }
        // differe : setHovered change la taille de l'ilot, donc hoverZone, dont
        // depend overIsland (boucle de liaison si on l'appelle tout de suite)
        onOverIslandChanged: Qt.callLater(syncHover)
        // dernier etat envoye : setHovered seulement s'il a vraiment change
        property bool sentHover: false
        function syncHover() {
            if (overIsland === sentHover)
                return
            sentHover = overIsland
            Ilot.setHovered(overIsland)
        }

        // Echap : referme la feuille, le jour du calendrier, puis l'ilot.
        // Touche Windows remappee (F24) : quand l'ilot a le clavier, elle
        // arrive ici au lieu de passer par le hook ; seule, elle le referme.
        property bool winTap: false
        Keys.onPressed: e => {
            if (e.key === Qt.Key_F24) {
                if (!e.isAutoRepeat)
                    winTap = true
                e.accepted = true
                return
            }
            winTap = false
            if (e.key !== Qt.Key_Escape || Ilot.mode !== "open")
                return
            e.accepted = true
            if (Ilot.overlay !== "")
                return Ilot.escapeKey()
            Ilot.close()
        }
        Keys.onReleased: e => {
            if (e.key !== Qt.Key_F24 || !winTap)
                return
            winTap = false
            e.accepted = true
            if (Ilot.mode === "open")
                Ilot.close()
        }

        BarContent {
            id: bar
            width: parent.width
            label: "island"
            hasIsland: true
            visible: !!Ilot.cfg.bar
            shown: Ilot.barVisible
            onLayoutChanged: Qt.callLater(win.updateHit)
        }

        Island {
            id: island
            x: (parent.width - width) / 2
            y: 0
            onXChanged: Qt.callLater(win.updateHit)
            onWidthChanged: Qt.callLater(win.updateHit)
            onHeightChanged: Qt.callLater(win.updateHit)
            onRChanged: Qt.callLater(win.updateBackdrop)
            onEarChanged: Qt.callLater(win.updateHit)
            onEarTopChanged: Qt.callLater(win.updateBackdrop)
        }

        // zone de survol : l'ilot (et ses coins) d'apres sa taille cible, avec
        // un peu de marge sous l'ilot replie pour l'attraper facilement
        Item {
            id: hoverZone
            readonly property var s: Ilot.size
            // Apparence > Taille de la pilule
            readonly property real k: Ilot.pillK
            x: (win.width - (s.w + Ilot.ear * 2) * k) / 2
            y: 0
            width: (s.w + Ilot.ear * 2) * k
            height: (s.h + (Ilot.mode === "collapsed" ? 6 : 2)) * k
        }
    }

    // zones cliquables (masque de la fenetre)
    // pendant une animation, la zone de l'ilot couvre sa taille de depart et
    // d'arrivee (+10 % pour le rebond du ressort) et ne fait que grandir :
    // le masque de la fenetre (SetWindowRgn) n'est pas refait a chaque image.
    // Au repos, elle reprend la taille exacte de l'ilot.
    property var hitBox: null
    function updateHit() {
        const rects = [{ x: hoverZone.x, y: 0, w: hoverZone.width, h: hoverZone.height }]
        const k = Ilot.pillK
        const s = Ilot.size
        let w = island.width, h = island.height, e = island.ear
        if (Math.abs(w - s.w) < 0.5 && Math.abs(h - s.h) < 0.5 && Math.abs(e - Ilot.ear) < 0.5) {
            hitBox = null
        } else {
            const b = hitBox || { w: 0, h: 0, e: 0 }
            w = Math.max(w, s.w * 1.1, b.w)
            h = Math.max(h, s.h * 1.1, b.h)
            e = Math.max(e, Ilot.ear, b.e)
            hitBox = { w: w, h: h, e: e }
        }
        // centre comme l'ilot (island.x = (largeur - island.width) / 2)
        rects.push({ x: island.parent.width / 2 - (w / 2 + e) * k, y: 0, w: (w + e * 2) * k, h: (h + 2) * k })
        if (bar.visible)
            for (const r of bar.hitRects())
                rects.push(r)
        ctl.setHit(rects)
        updateBackdrop()
    }

    // flou acrylique : la forme de l'ilot (coins concaves compris) et de la
    // barre, dessinee par Windows sous la fenetre
    function updateBackdrop() {
        if (!Ilot.acrylic || Ilot.fullscreen)
            return ctl.setBackdrop([])
        const k = Ilot.pillK
        const w = island.width * k, h = island.height * k, ix = island.x + island.width * (1 - k) / 2, r = island.r * k
        const shapes = [{ kind: "island", x: ix, y: 0, w: w, h: h, r: r }]
        const e = island.ear * k
        const eh = Math.min(e, h - r - island.earTop)
        if (e > 0.5 && eh > 0.5) {
            shapes.push({ kind: "earLeft", x: ix - e, y: island.earTop, w: e, h: eh, r: e })
            shapes.push({ kind: "earRight", x: ix + w, y: island.earTop, w: e, h: eh, r: e })
        }
        ctl.setBackdrop(shapes.concat(bar.backdropShapes()))
    }
    Connections {
        target: bar
        function onVisChanged() { Qt.callLater(win.updateBackdrop) }
        function onIslandsChanged() { Qt.callLater(win.updateBackdrop) }
    }
    Connections {
        target: Ilot
        function onSizeChanged() { Qt.callLater(win.updateHit) }
        function onEarChanged() { Qt.callLater(win.updateHit) }
        function onModeChanged() { Qt.callLater(win.updateHit) }
        function onBarVisibleChanged() { Qt.callLater(win.updateHit) }
        function onAcrylicChanged() { Qt.callLater(win.updateBackdrop) }
        function onPillKChanged() { Qt.callLater(win.updateHit) }
        function onFullscreenChanged() { Qt.callLater(win.updateBackdrop) }
    }
    onWidthChanged: Qt.callLater(updateHit)
}
