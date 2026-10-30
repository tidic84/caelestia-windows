pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Lecteur de planches de sprites pour un compagnon en pack (PackStage.qml).
// Une PNG par animation (<base><nom>.png), images de meme taille cote a cote.
// meta = sprites.json : { w, h, ground, anims: { nom: [ { ancre: [x, y] } ] } }
// (w, h : taille d'une image ; ground : ligne des pieds ; une liste d'ancres
// par image, en pixels de la planche).
//
// La planche est chargee a la taille affichee (sourceSize x DPR : net, sans
// mipmap ni texture pleine resolution) et decoupee par un Item qui clippe :
// changer d'image ne fait que deplacer la planche, aucun decodage.
// Au repos, seul le Timer d'animation tourne (fps du pack) ; en marche, l'image
// suit la distance parcourue (walkStep), sans Timer.
Item {
    id: sp

    property url base               // dossier des PNG, slash final
    property var meta: null
    property real k: 0.4            // pixels affiches par pixel de planche
    property int dir: 1             // 1 : regarde a droite, -1 : a gauche
    // position : centre horizontal et sol, en coordonnees du parent
    property real px: 0
    property real groundY: parent ? parent.height : 0
    property real lift: 0
    property real fps: 12
    property string restAnim: "idle"
    property string walkAnim: "walk"
    property bool paused: false
    property bool walking: false

    // teinte (silhouette coloree par-dessus) et halo (silhouette floue derriere)
    property real tint: 0
    property color tintColor: "#9fe4ff"
    property real halo: 0
    property color haloColor: "#966eff"
    property real haloScale: 1.12
    property real haloBlur: 0.6

    property string anim: restAnim
    property int frame: 0
    property real dist: 0

    readonly property real fw: meta ? meta.w * k : 0
    readonly property real fh: meta ? meta.h * k : 0
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property int sheetH: Math.max(1, Math.ceil(fh * dpr))

    width: fw
    height: fh
    x: px - width / 2
    y: groundY - (meta ? meta.ground * k : 0) - lift
    visible: meta !== null

    function frames(name) {
        return meta && meta.anims && meta.anims[name] ? meta.anims[name].length : 0
    }
    function has(name) {
        return frames(name) > 0
    }

    // ------------------------------------------------------------ lecture
    property string mode: ""        // "", "loop", "play", "walk"
    property real curFps: fps
    property int _to: 0
    property int _step: 1
    property var _done: null

    Timer {
        id: tick
        repeat: true
        interval: Math.max(10, 1000 / Math.max(1, sp.curFps))
        running: !sp.paused && (sp.mode === "loop" || sp.mode === "play")
        onTriggered: sp._tick()
    }
    function _tick() {
        if (mode === "loop") {
            frame = (frame + 1) % Math.max(1, frames(anim))
        } else if (mode === "play") {
            if (frame === _to) {
                mode = ""
                _finish()
            } else {
                frame += _step
            }
        }
    }
    // une lecture interrompue rend quand meme la main
    function _finish() {
        const d = _done
        _done = null
        if (d)
            d()
    }
    // joue name de from a to (a l'envers si to < from), puis garde la derniere
    // image ; done() a la fin. Rend la duree en ms.
    function play(name, fps, from, to, done) {
        _finish()
        const n = frames(name)
        if (!n) {
            if (done)
                done()
            return 0
        }
        const a = Math.max(0, Math.min(n - 1, from === undefined || from === null ? 0 : from))
        const b = Math.max(0, Math.min(n - 1, to === undefined || to === null ? n - 1 : to))
        curFps = fps || sp.fps
        anim = name
        frame = a
        _to = b
        _step = b >= a ? 1 : -1
        _done = done || null
        mode = "play"
        if (!paused)
            tick.restart()
        return (Math.abs(b - a) + 1) * 1000 / curFps
    }
    function loop(name, fps) {
        _finish()
        if (!has(name))
            return
        curFps = fps || sp.fps
        anim = name
        frame = 0
        mode = "loop"
        if (!paused)
            tick.restart()
    }
    // fige l'image en cours (fin d'une boucle)
    function hold() {
        _finish()
        mode = ""
    }
    function rest() {
        walking = false
        loop(restAnim)
    }
    // marche : l'image suit la distance (un cycle par demi-largeur)
    function walkStep(d) {
        if (mode !== "walk") {
            _finish()
            mode = "walk"
            anim = walkAnim
        }
        walking = true
        dist += Math.abs(d)
        const n = Math.max(1, frames(walkAnim))
        frame = Math.floor(dist / Math.max(1, fw * 0.5) * n) % n
    }
    // sous-ensemble de l'API de Pet.qml
    function trick(name) {
        return play(name, sp.fps, 0, null, () => sp.rest())
    }
    function stopTricks() {
        rest()
    }

    // ------------------------------------------------------------ ancres
    // ancre de l'image courante, en coordonnees de l'item (retournement compris)
    function anchorAt(name, dx, dy) {
        const fa = meta && meta.anims ? meta.anims[anim] : null
        const fr = fa && fa.length ? fa[Math.min(frame, fa.length - 1)] : null
        const p = fr ? fr[name] : null
        if (!p)
            return [width / 2, height / 2]
        const ax = p[0] + (dx || 0), ay = p[1] + (dy || 0)
        return [dir > 0 ? ax * k : (meta.w - ax) * k, ay * k]
    }
    // meme chose en coordonnees du parent
    function at(name, dx, dy) {
        const a = anchorAt(name, dx, dy)
        return [x + a[0], y + a[1]]
    }

    // ------------------------------------------------------------ dessin
    // garde toutes les planches en memoire (cache partage), pour que changer
    // d'animation soit immediat
    Repeater {
        model: sp.meta && sp.meta.anims ? Object.keys(sp.meta.anims) : []
        delegate: Image {
            required property string modelData
            visible: false
            asynchronous: true
            source: String(sp.base) ? sp.base + modelData + ".png" : ""
            sourceSize.height: sp.sheetH
        }
    }

    // une image de la planche ; a, f : animation et image affichees
    component Cut: Item {
        id: cut
        property string a: sp.anim
        property int f: sp.frame
        width: sp.fw
        height: sp.fh
        clip: true
        Image {
            x: -cut.f * sp.fw
            width: Math.max(1, sp.frames(cut.a)) * sp.fw
            height: sp.fh
            source: cut.a && String(sp.base) ? sp.base + cut.a + ".png" : ""
            sourceSize.height: sp.sheetH
            smooth: true
            fillMode: Image.Stretch
        }
    }

    Item {
        id: flip
        anchors.fill: parent
        transform: Scale { origin.x: flip.width / 2; xScale: sp.dir < 0 ? -1 : 1 }

        // halo : la silhouette est mise dans une boite avec marge, pour que le
        // flou ne soit pas coupe au bord de l'image
        Item {
            id: haloBox
            readonly property real pad: Math.ceil(sp.fh * 0.2)
            visible: sp.halo > 0.01
            opacity: Math.min(1, sp.halo)
            x: -pad
            y: -pad
            width: sp.fw + 2 * pad
            height: sp.fh + 2 * pad
            transform: Scale {
                origin.x: haloBox.width / 2
                origin.y: haloBox.pad + (sp.meta ? sp.meta.ground * sp.k : 0)
                xScale: sp.haloScale
                yScale: sp.haloScale
            }
            Cut {
                x: haloBox.pad
                y: haloBox.pad
            }
            layer.enabled: visible
            layer.effect: MultiEffect {
                brightness: 1
                colorization: 1
                colorizationColor: sp.haloColor
                blurEnabled: true
                blur: sp.haloBlur
                blurMax: 32
            }
        }
        Cut {}
        Cut {
            visible: sp.tint > 0.01
            opacity: Math.min(1, sp.tint)
            layer.enabled: visible
            layer.effect: MultiEffect {
                brightness: 1
                colorization: 1
                colorizationColor: sp.tintColor
            }
        }
    }

    // ------------------------------------------------------------ images remanentes
    // silhouette coloree de l'image courante, laissee sur place, qui s'efface.
    // Reserve de 8 elements crees une fois (pas d'objet ni d'effet cree a
    // chaque appel) ; l'effet d'un element n'est actif que pendant son fondu.
    property int _ghostNext: 0
    component Ghost: Item {
        id: gh
        property alias a: gcut.a
        property alias f: gcut.f
        property int gdir: 1
        property color col: "white"
        width: sp.fw
        height: sp.fh
        opacity: 0
        visible: opacity > 0
        transform: Scale { origin.x: gh.width / 2; xScale: gh.gdir < 0 ? -1 : 1 }
        Cut {
            id: gcut
            a: ""
            f: 0
            layer.enabled: gh.visible
            layer.effect: MultiEffect {
                brightness: 1
                colorization: 1
                colorizationColor: gh.col
            }
        }
        NumberAnimation {
            id: fade
            target: gh
            property: "opacity"
            from: 0.3
            to: 0
            duration: 220
        }
        // chaque increment relance le fondu
        property int shot: 0
        onShotChanged: fade.restart()
    }
    // calque des remanences, pose sous le sprite dans le parent (elles ne
    // suivent pas le sprite)
    Item {
        parent: sp.parent
        x: 0
        y: 0
        z: sp.z - 0.5
        Repeater {
            id: ghosts
            model: 8
            delegate: Ghost {}
        }
    }
    function ghost(rgb) {
        if (!parent || !meta)
            return
        const p = String(rgb || "190,240,255").split(",")
        const g = ghosts.itemAt(_ghostNext) as Ghost
        _ghostNext = (_ghostNext + 1) % ghosts.count
        if (!g)
            return
        g.x = x
        g.y = y
        g.a = anim
        g.f = frame
        g.gdir = dir
        g.col = Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, 1)
        g.shot++
    }
}
