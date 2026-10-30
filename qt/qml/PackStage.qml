import QtQuick
import QtQuick.Shapes

// Scene d'un compagnon en pack (sprites + attaques) dans un rectangle : il
// arrive, se promene (marche, pauses, demi-tours) et lance une attaque toutes
// les 15 a 20 s, comptees depuis la fin de la precedente, jamais deux fois la
// meme d'affilee. Theme.reduced : ni promenade ni attaque, juste le repos.
// Generique : le personnage vient d'un pack hors du depot.
//
// SECURITE : un pack execute du QML (Attacks.qml) avec les droits de
// l'appli. N'installer que des packs de confiance, faits soi-meme.
//
// Interface (PetWindow.qml) :
//   pack    : { id, name, url, json[, meta] } ; url = file:///…/pets/<id>/
//             (slash final), json = pack.json, meta.sprites = sprites.json
//             deja lu (sinon lu ici par XMLHttpRequest, ce qui demande
//             QML_XHR_ALLOW_FILE_READ=1) ;
//   running : faux = tout s'arrete (aucun Timer ni animation ; une attaque en
//             cours est abandonnee) ;
//   leave() : il s'en va, puis signal gone() ;
//   remplit son parent, sol en bas.
//
// pack.json (cles lues ici) :
//   sprites : { dir, meta, fps, idle ("idle"), walk ("walk") }
//   sizes   : { s, m, l } hauteur d'une image du sprite en px, selon
//             Ilot.cfg.pet_size (defaut 110 / 150 / 200) ;
//   greet   : animation jouee a l'arrivee et au depart (facultatif) ;
//   attacks : fichier QML des attaques, relatif au pack (facultatif).
//
// Attaques (pack.url + json.attacks) : un objet QML (QtObject) cree avec
//   fx     : le PetFx (effets, horloge, play/loopAnim/at, voir PetFx.qml),
//   sprite : le SpritePet (px, dir, lift, tint, halo, fw, fh...),
//   stage  : ce PackStage,
// et qui expose « list » : [{ id, name, run }], ou run() rend un iterateur de
// generateur (function* ...) lance par fx.co() : « yield promesse » attend
// (fx.wait, fx.tween, fx.play, tableau = toutes). A la fin (ou si l'attaque
// echoue), PackStage remet le sprite au repos (tint, halo, lift, aura a 0).
Item {
    id: st
    anchors.fill: parent

    property var pack: null
    property bool running: true
    signal gone()

    // hauteur d'une image du sprite (0 : selon pack.json et la taille choisie)
    property real petHeight: 0

    readonly property var pj: pack && pack.json ? pack.json : ({})
    readonly property var sj: pj.sprites || ({})
    readonly property bool reduced: Theme.reduced
    readonly property string sizeKey: Ilot.cfg && Ilot.cfg.pet_size ? Ilot.cfg.pet_size : "m"
    readonly property real petH: {
        if (petHeight > 0)
            return petHeight
        const s = pj.sizes || {}
        return Number(s[sizeKey]) || ({ s: 110, m: 150, l: 200 })[sizeKey] || 150
    }
    readonly property real groundY: height - 4
    property var meta: null
    property var atk: null
    property var atkComp: null
    readonly property var attacks: atk && atk.list ? atk.list : []

    property bool arrived: false
    // entree en scene terminee (salut fait)
    property bool entered: false
    property bool leaving: false
    property bool busy: false
    property string lastAtk: ""
    property int atkGen: 0

    function rand(a, b) {
        return a + Math.random() * (b - a)
    }
    function pick(a) {
        return a[Math.floor(Math.random() * a.length)]
    }
    function clampX(x) {
        const m = sp.fw * 0.6
        return Math.max(m, Math.min(width - m, x))
    }

    // ------------------------------------------------------------ scene
    PetFx {
        id: fx
        anchors.fill: parent
        pet: sp
        u: Math.max(0.42, sp.fh / 240)
        groundY: st.groundY

        // ombre au sol
        Shape {
            id: shadow
            readonly property real d: Math.max(1, sp.fw * 0.72)
            visible: sp.visible && sp.opacity > 0
            width: d
            height: d
            x: sp.px + 6 * sp.k * sp.dir - d / 2
            y: st.groundY - 1 - d / 2
            opacity: sp.opacity * 0.45 * (1 - Math.max(0, Math.min(0.8, sp.lift / Math.max(1, 120 * sp.k))))
            transform: Scale { origin.y: shadow.d / 2; yScale: 0.16 }
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: shadow.d / 2
                    centerY: shadow.d / 2
                    centerRadius: shadow.d / 2
                    focalX: shadow.d / 2
                    focalY: shadow.d / 2
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
                PathRectangle { width: shadow.d; height: shadow.d }
            }
        }
        SpritePet {
            id: sp
            z: 1
            // vide tant que pack.json n'est pas lu (sinon la racine du pack)
            base: st.pack && st.pj.sprites ? st.pack.url + (st.sj.dir ? st.sj.dir + "/" : "") : ""
            meta: st.meta
            k: st.meta ? st.petH / st.meta.h : 0.4
            groundY: st.groundY
            fps: st.sj.fps || 12
            restAnim: st.sj.idle || "idle"
            walkAnim: st.sj.walk || "walk"
            paused: !st.running
            px: st.width / 2
        }
    }

    // ------------------------------------------------------------ chargement
    property bool _ready: false
    property bool _goneSent: false
    Component.onCompleted: {
        _ready = true
        load()
    }
    onPackChanged: if (_ready) load()
    function load() {
        abortAttack()
        clearSteps()
        atkT.stop()
        leaveA.stop()
        fadeA.stop()
        dropA.stop()
        leaving = false
        arrived = false
        entered = false
        meta = null
        if (atk) {
            atk.destroy()
            atk = null
        }
        if (!pack || !pack.url)
            return
        if (pack.meta && pack.meta.sprites)
            meta = pack.meta.sprites
        else
            readMeta()
        loadAttacks()
        // au tour suivant : les liaisons (pj, sj, taille) suivent alors le
        // nouveau pack
        if (meta)
            Qt.callLater(st.start)
    }
    function readMeta() {
        const p = pack
        const js = pack.json && pack.json.sprites ? pack.json.sprites : ({})
        const url = pack.url + (js.dir ? js.dir + "/" : "") + (js.meta || "sprites.json")
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || st.pack !== p)
                return
            try {
                st.meta = JSON.parse(x.responseText)
                st.start()
            } catch (e) {
                console.warn("PackStage: sprites.json illisible", url, e)
            }
        }
        x.open("GET", url)
        x.send()
    }
    // fichier relatif au pack, sans remonter ni sortir du dossier
    function safeRel(p) {
        return typeof p === "string" && p.length > 0 && p.indexOf("..") < 0 && p.indexOf(":") < 0
               && p[0] !== "/" && p[0] !== "\\"
    }
    function loadAttacks() {
        // pack.json lu ici, pas par pj : appele depuis onPackChanged, avant
        // que la liaison de pj soit recalculee
        const j = pack && pack.json ? pack.json : ({})
        if (!safeRel(j.attacks))
            return
        const p = pack
        // gardé en propriété : un composant encore en chargement, seulement
        // tenu par une variable locale, peut être ramassé avant la fin
        const c = atkComp = Qt.createComponent(pack.url + j.attacks)
        const make = () => {
            if (c.status === Component.Loading)
                return
            if (st.pack !== p)
                return
            if (c.status === Component.Ready)
                st.atk = c.createObject(st, { fx: fx, sprite: sp, stage: st })
            else if (c.status === Component.Error)
                console.warn("PackStage: attaques illisibles", c.errorString())
        }
        if (c.status === Component.Loading)
            c.statusChanged.connect(make)
        else
            make()
    }
    function start() {
        if (!arrived && !leaving && running && meta && width > 0)
            arrive()
    }
    onWidthChanged: {
        if (!arrived)
            start()
        else if (!leaving && !busy && !walking)
            sp.px = clampX(sp.px)
    }

    // ------------------------------------------------------------ etapes
    // comme PetWindow : nombre = attente (ms) ; fonction qui rend une attente,
    // -1 (attendre resume()) ou rien
    property var queue: []
    property bool waiting: false
    Timer {
        id: stepT
        onTriggered: st.step()
    }
    function steps(list) {
        stepT.stop()
        waiting = false
        queue = list
        step()
    }
    function step() {
        stepT.stop()
        while (queue.length && running && !busy) {
            const s = queue.shift()
            const r = typeof s === "number" ? s : s()
            if (r === -1) {
                waiting = true
                return
            }
            if (r > 0) {
                stepT.interval = r
                stepT.start()
                return
            }
        }
        if (!queue.length && running && !busy && !leaving)
            idleLoop()
    }
    function resume() {
        if (!waiting)
            return
        waiting = false
        Qt.callLater(step)
    }
    function clearSteps() {
        stepT.stop()
        queue = []
        waiting = false
        walking = false
    }

    // ------------------------------------------------------------ marche
    property real tx: 0
    property real speed: 50
    property bool walking: false
    function walkTo(x, s, free) {
        tx = free ? x : clampX(x)
        speed = s || 50
        if (Math.abs(tx - sp.px) < 1)
            return 0
        sp.dir = tx >= sp.px ? 1 : -1
        walking = true
        return -1
    }
    FrameAnimation {
        running: st.walking && st.running
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            const d = st.tx - sp.px
            const s = st.speed * dt
            if (Math.abs(d) <= s) {
                sp.px = st.tx
                st.walking = false
                sp.rest()
                st.resume()
                return
            }
            sp.dir = Math.sign(d)
            sp.px += Math.sign(d) * s
            sp.walkStep(s)
        }
    }

    // promenade : marche, pause, parfois un demi-tour
    function idleLoop() {
        if (reduced || leaving || !running) {
            sp.rest()
            return
        }
        const sc = Math.max(0.6, sp.fh / 240)
        const list = [() => st.walkTo(sp.px + st.rand(-1, 1) * Math.min(st.width * 0.4, 600), st.rand(40, 60) * sc),
                      () => st.rand(800, 2200)]
        if (Math.random() < 0.3)
            list.push(() => { sp.dir = -sp.dir; return 600 })
        steps(list)
    }

    // ------------------------------------------------------------ attaques
    Timer {
        id: atkT
        onTriggered: st.attack()
    }
    Timer {
        id: guardT
        interval: 30000
        onTriggered: st.attackFailed(st.atkGen)
    }
    // attaques chargees apres l'arrivee : on programme la premiere
    onAttacksChanged: {
        if (entered && !leaving && !busy && !atkT.running)
            scheduleAttack(rand(4000, 7000))
    }
    function scheduleAttack(ms) {
        atkT.stop()
        if (reduced || !attacks.length)
            return
        atkT.interval = ms
        atkT.start()
    }
    function attack(id) {
        if (!running || leaving || busy || reduced || !arrived || !attacks.length)
            return
        let a = null
        if (id)
            a = attacks.find(x => x.id === id) || null
        if (!a) {
            const pool = attacks.length > 1 ? attacks.filter(x => x.id !== lastAtk) : attacks
            a = pick(pool)
        }
        clearSteps()
        atkT.stop()
        sp.rest()
        lastAtk = a.id
        busy = true
        const gen = ++atkGen
        guardT.restart()
        fx.co(a.run).then(() => st.attackDone(gen), e => {
            console.warn("PackStage: attaque", a.id, e)
            st.attackFailed(gen)
        })
    }
    function resetPose() {
        sp.tint = 0
        sp.halo = 0
        sp.lift = 0
        fx.aura = 0
        sp.px = clampX(sp.px)
        sp.rest()
    }
    function attackDone(gen) {
        if (gen !== atkGen || !busy)
            return
        guardT.stop()
        busy = false
        resetPose()
        scheduleAttack(rand(15000, 20000))
        steps([rand(600, 1200)])
    }
    // attaque en echec ou trop longue : ses effets sans fin sont coupes
    function attackFailed(gen) {
        if (gen !== atkGen || !busy)
            return
        fx.reset()
        attackDone(gen)
    }
    // attaque abandonnee (arret, depart) : effets coupes net
    function abortAttack() {
        guardT.stop()
        if (!busy)
            return
        atkGen++
        busy = false
        fx.reset()
        resetPose()
    }

    // ------------------------------------------------------------ arrivee
    function greet() {
        if (!sj || !pj.greet || !sp.has(pj.greet))
            return 0
        return sp.play(pj.greet, 14, 0, null, () => { sp.rest(); st.resume() }) > 0 ? -1 : 0
    }
    function arrive() {
        arrived = true
        leaving = false
        clearSteps()
        leaveA.stop()
        _goneSent = false
        sp.opacity = 1
        sp.lift = 0
        sp.px = clampX(width / 2 + rand(-120, 120))
        sp.rest()
        if (reduced) {
            sp.opacity = 0
            fadeA.to = 1
            fadeA.restart()
            return
        }
        const m = pick(["run", "drop"])
        if (m === "drop") {
            // tombe du haut de la zone, atterrit dans la poussiere
            sp.dir = pick([-1, 1])
            sp.lift = height
            steps([() => { dropA.restart(); return -1 },
                   () => { fx.dust(sp.px, 18); fx.shake(4 * fx.u); return 250 },
                   () => st.greet(),
                   () => { st.entered = true; st.scheduleAttack(st.rand(4000, 7000)) }])
        } else {
            const from = Math.random() < 0.5 ? -1 : 1
            sp.px = from < 0 ? -sp.fw : width + sp.fw
            steps([() => st.walkTo(st.clampX(st.width / 2 + st.rand(-200, 200)), 170, true),
                   () => st.greet(),
                   () => { st.entered = true; st.scheduleAttack(st.rand(4000, 7000)) }])
        }
    }
    NumberAnimation {
        id: dropA
        target: sp
        property: "lift"
        to: 0
        duration: 650
        easing.type: Easing.InQuad
        onFinished: st.resume()
    }
    NumberAnimation {
        id: fadeA
        target: sp
        property: "opacity"
        duration: 400
        onFinished: if (st.leaving) st.finish()
    }

    // ------------------------------------------------------------ depart
    function leave() {
        if (leaving)
            return
        leaving = true
        entered = false
        abortAttack()
        clearSteps()
        atkT.stop()
        dropA.stop()
        if (!running || !meta || !arrived) {
            Qt.callLater(st.finish)
            return
        }
        if (reduced) {
            fadeA.to = 0
            fadeA.restart()
            return
        }
        sp.dir = sp.px < width / 2 ? 1 : -1
        leaveA.restart()
    }
    // il rugit, puis s'envole hors de la zone
    SequentialAnimation {
        id: leaveA
        ScriptAction { script: st.greet() }
        PauseAnimation { duration: 1100 }
        ScriptAction { script: { fx.dust(sp.px, 14); sp.rest() } }
        ParallelAnimation {
            NumberAnimation { target: sp; property: "lift"; to: st.height + sp.fh; duration: 600; easing.type: Easing.InQuad }
            NumberAnimation { target: sp; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
        }
        ScriptAction { script: st.finish() }
    }
    function finish() {
        if (_goneSent)
            return
        _goneSent = true
        gone()
    }

    // ------------------------------------------------------------ arret / reprise
    onRunningChanged: {
        if (running) {
            if (leaving) {
                Qt.callLater(st.finish)
            } else if (!arrived) {
                start()
            } else {
                resetPose()
                scheduleAttack(rand(15000, 20000))
                idleLoop()
            }
        } else {
            abortAttack()
            fx.reset()
            clearSteps()
            atkT.stop()
            dropA.stop()
            if (leaving) {
                leaveA.stop()
                fadeA.stop()
                finish()
            }
        }
    }
    onReducedChanged: {
        if (!arrived || leaving || !running)
            return
        abortAttack()
        clearSteps()
        atkT.stop()
        resetPose()
        if (!reduced) {
            scheduleAttack(rand(15000, 20000))
            idleLoop()
        }
    }
}
