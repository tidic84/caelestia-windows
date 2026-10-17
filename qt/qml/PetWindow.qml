import QtQuick
import QtQuick.Shapes

// Promenade du compagnon : apres un moment sans clavier ni souris
// (Reglages > Compagnon), il arrive au-dessus de la barre des taches (en
// parachute, par un portail ou en courant) et s'occupe : balade, sieste,
// ballon, papillon, montgolfiere, peche, skate, bulles, lecture, avion en
// papier, jardinage, cache-cache, meditation, danse (musique), etoiles filantes
// (nuit), cafe (matin), parapluie (pluie), bonhomme de neige (neige) et un tour
// propre a son espece. Des que tu reviens, il te fait coucou et remonte dans la
// pilule. Fenetre transparente qui laisse passer la souris, chargee seulement
// pendant la promenade (Main.qml, Watch.petWinOn).
Window {
    id: w
    property var host
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: "Ilot compagnon"
    readonly property var scr: host ? host.screen : null
    width: scr ? scr.width : 1200
    height: 260
    x: scr ? scr.virtualX : 0
    // au-dessus de la barre des taches
    y: scr ? scr.virtualY + scr.height - height - 48 : 0
    visible: true

    // taille (Reglages > Compagnon > Taille en promenade)
    readonly property real k: ({ s: 1.6, m: 2, l: 2.6 })[Ilot.cfg.pet_size] || 2
    readonly property real pw: 20 * k
    readonly property real ph: 18 * k
    // sol (bas du compagnon) ; position : centre et hauteur au-dessus du sol
    readonly property real gy: height - 6
    property real px: width / 2
    property real py: 0
    property int dir: 1
    property string scene: ""
    property string lastScene: ""
    property bool leaving: false
    property string petMood: "idle"
    readonly property int hour: Ilot.now.getHours()
    readonly property bool night: hour >= 20 || hour < 6
    readonly property bool sleepy: Watch.idle > 900 || hour < 6 || hour >= 23
    // pose (allonge, a plat ventre...) : etirement et rotation autour des pieds
    property real poseSx: 1
    property real poseSy: 1
    property real poseRot: 0

    function rand(a, b) {
        return a + Math.random() * (b - a)
    }
    function pick(a) {
        return a[Math.floor(Math.random() * a.length)]
    }
    function clampX(x) {
        return Math.max(pw * 1.5, Math.min(width - pw * 1.5, x))
    }
    // reperes a l'ecran : haut de la tete, bouche, main
    function headY() {
        return gy - ph + py + pet.geo.hat[1] * k
    }
    function mouthX() {
        return px + (pet.geo.mouth[0] - 10) * k * dir
    }
    function mouthY() {
        return gy - ph + py + pet.geo.mouth[1] * k
    }
    function faceTo(x) {
        dir = x >= px ? 1 : -1
    }
    // regard vers un point de l'ecran (coordonnees du compagnon retourne)
    function lookAt(x, y) {
        pet.look = Math.max(-1.5, Math.min(1.5, (x - px) / 70)) * dir
        pet.lookY = Math.max(-1, Math.min(1, (y - (gy - ph / 2 + py)) / 70))
    }
    function say(sym, o) {
        pet.fx(sym, o)
    }

    // ===================================================== deplacement
    property real tx: px
    property real speed: 55
    property bool walking: false
    property bool backwards: false
    property bool riding: false
    // poursuite : cible mouvante, et condition d'arrivee
    property var follow: null
    property var followDone: null
    function walkTo(x, s, free) {
        tx = free ? x : clampX(x)
        speed = s || 55
        follow = null
        walking = true
        return -1
    }
    function chase(target, done, s) {
        follow = target
        followDone = done
        speed = s || 110
        walking = true
        return -1
    }
    FrameAnimation {
        running: w.walking
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            if (w.follow)
                w.tx = w.clampX(w.follow())
            const d = w.tx - w.px
            const st = w.speed * dt
            if (Math.abs(d) <= st) {
                w.px = w.tx
                if (!w.follow || w.followDone()) {
                    w.walking = false
                    w.follow = null
                    w.resume()
                }
                return
            }
            w.dir = (w.backwards ? -1 : 1) * Math.sign(d)
            w.px += Math.sign(d) * st
            w.trailStep(st)
        }
    }
    // glissements et sauts scenarises
    NumberAnimation {
        id: pyAnim
        target: w
        property: "py"
        function go(v, ms, ease) {
            pyAnim.stop()
            pyAnim.from = w.py
            pyAnim.to = v
            pyAnim.duration = ms
            pyAnim.easing.type = ease === undefined ? Easing.InOutSine : ease
            pyAnim.start()
            return ms
        }
    }
    NumberAnimation {
        id: pxAnim
        target: w
        property: "px"
        function go(v, ms, ease) {
            pxAnim.stop()
            pxAnim.from = w.px
            pxAnim.to = v
            pxAnim.duration = ms
            pxAnim.easing.type = ease === undefined ? Easing.InOutSine : ease
            pxAnim.start()
            return ms
        }
    }
    // saut en arc jusqu'a x (lapin, chat qui bondit)
    function leap(x, ms, hgt) {
        faceTo(x)
        pxAnim.go(x, ms, Easing.Linear)
        leapA.hgt = hgt
        leapA.ms = ms
        leapA.restart()
        return ms + 60
    }
    SequentialAnimation {
        id: leapA
        property real hgt: 30
        property int ms: 500
        NumberAnimation { target: w; property: "py"; to: -leapA.hgt; duration: leapA.ms / 2; easing.type: Easing.OutQuad }
        NumberAnimation { target: w; property: "py"; to: 0; duration: leapA.ms / 2; easing.type: Easing.InQuad }
        ScriptAction { script: pet.trick("land") }
    }

    // ===================================================== scenes
    // une scene est une liste d'etapes : un nombre (attente en ms) ou une
    // fonction qui rend une attente (ms), -1 (attendre resume() : arrivee,
    // atterrissage...) ou rien (etape suivante tout de suite)
    property var queue: []
    property bool waiting: false
    Timer {
        id: stepT
        onTriggered: w.step()
    }
    function play(steps) {
        stepT.stop()
        waiting = false
        queue = steps
        step()
    }
    function step() {
        stepT.stop()
        while (queue.length && !leaving) {
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
        if (!leaving)
            sceneDone()
    }
    function resume() {
        if (!waiting)
            return
        waiting = false
        Qt.callLater(step)
    }
    function sceneDone() {
        cleanup()
        lastScene = scene
        scene = ""
        stepT.interval = rand(1200, 3500)
        queue = [() => w.startScene(w.pickScene())]
        stepT.start()
    }
    function cleanup() {
        stepT.stop()
        queue = []
        waiting = false
        walking = false
        follow = null
        backwards = false
        riding = false
        sleeping = false
        floating = false
        petMood = "idle"
        pet.stopTricks()
        pet.face = ""
        pet.tempHat = ""
        pet.tempFace = ""
        pet.mouthOpen = 0
        pet.blush = 0
        pet.look = 0
        pet.lookY = 0
        pet.tongue = 0
        poseSx = 1
        poseSy = 1
        poseRot = 0
        walker.opacity = 1
        for (const p of [chute, portal, ball, bfly, balloon, pond, rod, board, wand, book, plane, can, aura, disco, sky, mug,
                         cloud, umbrella, laser, fly, carrot, minis, beam, ice, battery])
            p.on = false
        snowing = false
        spores = false
        leapA.stop()
        pxAnim.stop()
        if (!leaving && py !== 0)
            pyAnim.go(0, 400)
    }

    function pickScene() {
        const req = Watch.petScene
        if (req) {
            Watch.petScene = ""
            return req
        }
        if (sleepy && lastScene !== "sleep" && Math.random() < 0.7)
            return "sleep"
        const code = Ilot.weather ? Ilot.weather.code : 0
        const rain = (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95
        const snow = (code >= 71 && code <= 77) || code === 85 || code === 86
        const winter = [11, 0, 1].indexOf(Ilot.now.getMonth()) >= 0
        const opts = [
            ["stroll", 3], ["ball", 2], ["butterfly", night ? 0 : 2], ["balloon", 1.3], ["fishing", 1.3], ["skate", 1.3],
            ["bubbles", 1.4], ["read", 1.2], ["plane", 1.3], ["garden", night ? 0 : 1.2], ["hide", 1], ["meditate", 1],
            ["special", 2.6], ["dance", Ilot.media.playing ? 7 : 0], ["stars", night ? 3 : 0],
            ["coffee", (hour >= 6 && hour < 11) || (hour >= 15 && hour < 18) ? 1.8 : 0.3],
            ["umbrella", rain ? 5 : 0.3], ["snow", snow ? 5 : winter ? 1 : 0], ["sleep", Watch.idle > 300 ? 1.5 : 0.3]
        ].filter(o => o[0] !== lastScene && o[1] > 0)
        let r = Math.random() * opts.reduce((a, o) => a + o[1], 0)
        for (const o of opts) {
            r -= o[1]
            if (r <= 0)
                return o[0]
        }
        return "stroll"
    }
    function startScene(name) {
        cleanup()
        // arrivee interrompue (apercu des reglages) : de retour a l'ecran
        if (px < pw || px > width - pw)
            px = clampX(px)
        scene = name
        switch (name) {
        case "sleep": return sSleep()
        case "ball": return sBall()
        case "butterfly": return sButterfly()
        case "balloon": return sBalloon()
        case "fishing": return sFishing()
        case "skate": return sSkate()
        case "bubbles": return sBubbles()
        case "read": return sRead()
        case "plane": return sPlane()
        case "garden": return sGarden()
        case "hide": return sHide()
        case "meditate": return sMeditate()
        case "dance": return sDance()
        case "stars": return sStars()
        case "coffee": return sCoffee()
        case "umbrella": return sUmbrella()
        case "snow": return sSnow()
        case "special": return sSpecial()
        default:
            scene = "stroll"
            return sStroll()
        }
    }
    Connections {
        target: Watch
        function onPetOutChanged() {
            if (!Watch.petOut)
                w.leave()
            else if (w.leaving) {
                // revenu se promener pendant qu'il remontait
                leaveA.stop()
                w.leaving = false
                w.arrive()
            }
        }
        // apercu des reglages : une scene tout de suite
        function onPetSceneRequest(name) {
            if (!w.leaving && name)
                w.startScene(name)
        }
    }

    // ------------------------------------------------------ arrivee
    Component.onCompleted: arrive()
    function arrive() {
        cleanup()
        scene = "arrive"
        px = clampX(width / 2 + rand(-120, 120))
        py = 0
        const m = pick(["chute", "chute", "portal", "run"])
        if (m === "chute") {
            py = -(height + 30)
            chute.on = true
            pet.face = "happy"
            play([() => pyAnim.go(0, 2800, Easing.OutSine),
                  () => { chute.on = false; pet.face = ""; return pet.trick("land") },
                  300, () => pet.trick("wave")])
        } else if (m === "portal") {
            portal.on = true
            walker.opacity = 0
            play([700,
                  () => { walker.opacity = 1; sparkle(px, gy - ph / 2, 8); return pet.trick("jump") },
                  () => { portal.on = false; return pet.trick("wave") }])
        } else {
            const from = Math.random() < 0.5 ? -1 : 1
            px = from < 0 ? -pw : width + pw
            play([() => walkTo(clampX(width / 2 + rand(-200, 200)), 170, true),
                  () => pet.trick("wave")])
        }
    }

    // ------------------------------------------------------ depart
    // il te fait coucou, puis saute dans la pilule
    function leave() {
        if (leaving)
            return
        cleanup()
        leaving = true
        pyAnim.stop()
        dir = px < width / 2 ? 1 : -1
        leaveA.restart()
    }
    SequentialAnimation {
        id: leaveA
        ScriptAction { script: { pet.lookY = -1; pet.trick("surprise") } }
        PauseAnimation { duration: 450 }
        ScriptAction { script: pet.trick("wave") }
        PauseAnimation { duration: 1100 }
        NumberAnimation { target: w; property: "poseSy"; to: 0.8; duration: 120 }
        ParallelAnimation {
            NumberAnimation { target: w; property: "poseSy"; to: 1.15; duration: 200 }
            NumberAnimation { target: w; property: "py"; to: -(w.height + 60); duration: 600; easing.type: Easing.InQuad }
            NumberAnimation { target: walker; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
        }
        ScriptAction { script: Watch.petReturned() }
    }

    // ===================================================== scenes
    function sStroll() {
        const st = []
        const n = 1 + Math.floor(Math.random() * 3)
        for (let i = 0; i < n; i++) {
            st.push(() => w.walkTo(w.px + (Math.random() - 0.5) * w.width * 0.5, w.rand(45, 75)))
            st.push(rand(400, 1200))
            if (Math.random() < 0.5)
                st.push(() => pet.trick(w.pick(["look", "hop", "stretch", "nod", "spin", "blep", "sneeze", "wave", "giggle", "flip"])))
            if (Math.random() < 0.3)
                st.push(() => { w.say(w.pick(["♪", "♥", "✦", "?"])) })
        }
        play(st)
    }

    // sieste : bonnet de nuit, bulle qui gonfle et des z
    property bool sleeping: false
    function sSleep() {
        const nap = sleepy ? rand(25000, 50000) : rand(9000, 16000)
        play([() => w.walkTo(w.px + w.rand(-150, 150), 40),
              () => pet.trick("yawn"),
              () => {
                  pet.face = "closed"
                  if (pet.hat === "none")
                      pet.tempHat = "nightcap"
                  w.sleeping = true
                  w.poseSx = 1.1
                  w.poseSy = 0.86
                  return nap
              },
              () => { w.sleeping = false; w.poseSx = 1; w.poseSy = 1; pet.face = ""; pet.tempHat = ""; return pet.trick("stretch") },
              () => pet.trick("shake")])
    }
    Timer {
        interval: 1500
        repeat: true
        running: w.sleeping
        onTriggered: w.part({ sym: "z", x: w.px + 6 * w.k * w.dir, y: w.headY() - 4 * w.k, x1: w.px + w.dir * w.rand(20, 40), y1: w.headY() - 50,
                              size: 6 * w.k, grow: 1.8, color: Theme.primary, life: 2200, fadeIn: true })
    }
    // bulle de nez
    Rectangle {
        id: snoreBubble
        visible: w.sleeping && !w.leaving
        readonly property real s: 2 + 4 * snore.v
        width: s * w.k
        height: width
        radius: width / 2
        x: w.mouthX() + w.dir * 2 * w.k - width / 2
        y: w.mouthY() - height * 0.8
        color: Qt.rgba(0.75, 0.9, 1, 0.35)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.7)
        // gonfle et degonfle (horloge d'ambiance : la sieste peut durer)
        QtObject {
            id: snore
            readonly property real v: snoreBubble.visible ? Ilot.wave(Ilot.amb, 3000) : 0
        }
    }

    // ballon de plage : il le pousse trois fois, en courant derriere
    function sBall() {
        const side = px < width / 2 ? 1 : -1
        const kicks = []
        for (let i = 0; i < 3; i++) {
            kicks.push(() => {
                w.kickDir = ball.bx < w.width / 2 ? 1 : -1
                return w.chase(() => ball.bx - w.kickDir * (ball.r + w.pw * 0.45), () => ball.resting(), 120)
            })
            kicks.push(() => { w.dir = w.kickDir; ball.kick(w.kickDir); return pet.trick("kick") })
            kicks.push(() => w.say(w.pick(["!", "♪", "✦"])))
            kicks.push(900)
        }
        play([() => { ball.drop(w.clampX(w.px + side * w.rand(140, 240))); w.dir = side; return 500 },
              () => pet.trick("surprise")].concat(kicks).concat([
              () => { ball.on = false; return pet.trick("love") }]))
    }
    property int kickDir: 1

    // papillon : il essaie de l'attraper, puis il se pose sur sa tete
    function sButterfly() {
        play([() => { bfly.enter(); return 2600 },
              () => pet.trick("surprise"),
              1200,
              () => { w.faceTo(bfly.bx); return pet.trick("jump") },
              () => { bfly.dodge(); w.say("?"); return 1300 },
              () => w.walkTo(bfly.bx, 95),
              () => { w.faceTo(bfly.bx); return pet.trick("jump") },
              () => { bfly.dodge(); return 1500 },
              () => { bfly.mode = "land"; return 2600 },
              () => { pet.face = "happy"; pet.blush = 0.8; w.say("♥"); return 3500 },
              () => { pet.face = ""; pet.blush = 0; bfly.mode = "leave"; return pet.trick("wave") },
              1600])
    }

    // ballon gonflable : il s'envole... jusqu'a ce qu'il eclate
    function sBalloon() {
        play([() => { balloon.inflate(); return 900 },
              () => pet.trick("hop"),
              () => { pet.face = "happy"; w.say("♪"); pxAnim.go(w.clampX(w.px + w.rand(-200, 200)), 4200); return pyAnim.go(-w.rand(90, 140), 4200) },
              () => { w.say("♥"); return 1400 },
              () => {
                  balloon.on = false
                  w.burst(balloon.cx, balloon.cy, 9, balloon.color)
                  w.part({ sym: "POP", x: balloon.cx - 10, y: balloon.cy, x1: balloon.cx - 10, y1: balloon.cy - 20, size: 8 * w.k, color: Theme.tertiary, life: 700 })
                  pet.face = "wide"
                  return 350
              },
              () => pyAnim.go(0, 520, Easing.InQuad),
              () => { pet.face = ""; return pet.trick("land") },
              () => pet.trick("dizzy")])
    }

    // peche : une mare, une canne, et une prise (ou une botte)
    function sFishing() {
        const side = px < width - 260 ? 1 : -1
        let prize = ""
        play([() => w.walkTo(Math.max(160, Math.min(w.width - 220, w.px)), 55),
              () => { w.dir = side; pond.open(w.px + side * 34 * w.k); return 800 },
              () => { rod.on = true; return 500 },
              () => { rod.cast(); return 1000 },
              () => w.rand(2500, 5000),
              () => { rod.nibble(); return 900 },
              () => w.rand(700, 1800),
              () => { rod.bite(); return pet.trick("surprise") },
              () => {
                  const r = Math.random()
                  prize = r < 0.5 ? "🐟" : r < 0.75 ? "🐠" : r < 0.9 ? "👢" : "⭐"
                  rod.reel()
                  w.part({ sym: prize, x: pond.cx, y: w.gy - 10, x1: w.px - 6, y1: w.headY() - 20, size: 9 * w.k, life: 1100, ease: Easing.OutBack })
                  return 1100
              },
              () => pet.trick(prize === "👢" ? "sad" : pet.species === "cat" ? "eat" : "love"),
              () => { rod.on = false; pond.on = false; return 900 }])
    }

    // skate : il traverse l'ecran, avec un ollie au milieu
    function sSkate() {
        const to = px < width / 2 ? width - 120 : 120
        const mid = (px + to) / 2
        play([() => { board.on = true; return 400 },
              () => { pyAnim.go(-2.6 * w.k, 200); return pet.trick("hop") },
              () => { w.riding = true; return w.walkTo(mid, 230) },
              () => { board.flip(); pyAnim.go(-34, 260, Easing.OutQuad); return 260 },
              () => pyAnim.go(-2.6 * w.k, 260, Easing.InQuad),
              () => { w.say("✦"); return w.walkTo(to, 230) },
              () => { w.riding = false; return pet.trick("spin") },
              () => { board.on = false; pyAnim.go(0, 200); return pet.trick("land") },
              () => w.say("♪")])
    }

    // bulles de savon
    function sBubbles() {
        const st = [() => { wand.on = true; return 600 }]
        for (let i = 0; i < 10; i++) {
            st.push(() => { pet.mouthOpen = 0.6; w.blowBubble(); return 260 })
            st.push(() => { pet.mouthOpen = 0; return w.rand(150, 450) })
        }
        st.push(() => { wand.on = false; pet.lookY = -1; return 1300 })
        st.push(() => pet.trick("jump"))
        st.push(() => { w.popBubble(); w.say("✧"); return 1500 })
        st.push(() => { pet.lookY = 0; return pet.trick("giggle") })
        play(st)
    }

    // lecture : lunettes, pages qui tournent, et ses reactions
    function sRead() {
        play([() => w.walkTo(w.px + w.rand(-120, 120), 50),
              () => { book.on = true; if (pet.faceAcc === "none") pet.tempFace = "glasses"; pet.lookY = 0.9; w.reading = true; return 3800 },
              () => { book.turn(); return 3200 },
              () => {
                  const r = w.pick(["!", "?", "♥", "…", "hi hi"])
                  w.say(r)
                  return r === "hi hi" ? pet.trick("giggle") : r === "!" ? pet.trick("surprise") : 1200
              },
              () => { pet.lookY = 0.9; book.turn(); return 3400 },
              () => { book.turn(); return 2600 },
              () => { w.reading = false; book.on = false; pet.tempFace = ""; pet.lookY = 0; return pet.trick("stretch") }])
    }
    property bool reading: false
    SequentialAnimation {
        running: w.reading
        loops: Animation.Infinite
        NumberAnimation { target: pet; property: "look"; from: -1; to: 1; duration: 1400; easing.type: Easing.Linear }
        NumberAnimation { target: pet; property: "look"; to: -1; duration: 200 }
    }

    // avion en papier
    function sPlane() {
        play([() => { plane.hold(); return pet.trick("nod") },
              () => { w.faceTo(w.width / 2); pet.trick("kick"); plane.launch(w.dir); return -1 },
              () => w.say("✧"),
              () => w.walkTo(plane.px - (plane.vx >= 0 ? 1 : -1) * 14 * w.k, 120),
              () => { w.faceTo(w.width / 2); plane.hold(); return pet.trick("hop") },
              () => { pet.trick("kick"); plane.launch(w.dir); return -1 },
              () => pet.trick("love"),
              () => { plane.on = false; return 300 }])
    }

    // jardinage : il creuse, arrose, et une fleur pousse (elle reste un moment)
    function sGarden() {
        let fx = 0
        play([() => w.walkTo(w.px + w.rand(-200, 200), 55),
              () => { fx = w.px + w.dir * 16 * w.k; w.dig(fx); return pet.trick("peck") },
              () => { w.dig(fx); return pet.trick("peck") },
              () => { can.on = true; return 500 },
              () => { w.watering = true; return 1800 },
              () => { w.watering = false; can.on = false; w.plant(fx); return 1600 },
              () => { w.say("✦"); return pet.trick("love") },
              () => pet.trick("nod")])
    }
    property bool watering: false
    Timer {
        interval: 70
        repeat: true
        running: w.watering
        onTriggered: w.part({ x: can.spoutX + w.rand(-2, 2), y: can.spoutY, x1: can.spoutX + w.dir * w.rand(4, 10), y1: w.gy - 2,
                              size: 2.2 * w.k, color: "#7cc7ff", life: 520, ease: Easing.InQuad })
    }

    // cache-cache : il sort de l'ecran, puis surgit de l'autre cote
    function sHide() {
        const e = px < width / 2 ? -1 : 1
        const out = e < 0 ? -pw : width + pw
        play([() => { w.say("?"); return w.walkTo(out, 95, true) },
              () => w.rand(1500, 2600),
              () => w.peek(e),
              1800,
              () => { w.px = out; return 1300 },
              () => w.peek(-e),
              1500,
              () => { pet.face = "happy"; w.say("coucou !", { size: 6 }); return w.walkTo(-e < 0 ? 150 : w.width - 150, 150, true) },
              () => { pet.face = ""; return pet.trick("wave") }])
    }
    function peek(e) {
        px = e < 0 ? pw * 0.12 : width - pw * 0.12
        dir = e < 0 ? 1 : -1
        return pet.trick("surprise")
    }

    // meditation : il s'eleve, entoure d'ondes
    property bool floating: false
    property real floatPhase: 0
    NumberAnimation on floatPhase {
        running: w.floating
        from: 0
        to: Math.PI * 2
        duration: 3000
        loops: Animation.Infinite
    }
    function sMeditate() {
        play([() => { pet.face = "closed"; aura.on = true; return pyAnim.go(-16 * w.k, 1600) },
              () => { w.floating = true; return w.rand(7000, 11000) },
              () => { w.floating = false; aura.on = false; return pyAnim.go(0, 700, Easing.InOutQuad) },
              () => { pet.face = ""; return pet.trick("stretch") }])
    }

    // danse (musique en cours) : projecteurs, moonwalk, salto
    function sDance() {
        play([() => { disco.on = true; w.petMood = "music"; return 400 },
              () => pet.trick("dance"),
              () => { w.backwards = true; return w.walkTo(w.px - w.dir * 130, 70) },
              () => { w.backwards = false; return pet.trick("spin") },
              () => pet.trick("flip"),
              () => pet.trick("dance"),
              () => { w.say("♫"); return w.walkTo(w.px + w.rand(-120, 120), 80) },
              () => pet.trick("jump"),
              () => pet.trick("dance"),
              () => { disco.on = false; return pet.trick("wave") }])
    }

    // etoiles filantes (le soir) : il fait un voeu
    function sStars() {
        play([() => { sky.on = true; w.poseSy = 0.92; pet.lookY = -1; return w.rand(3000, 4500) },
              () => { sky.shoot(); return 900 },
              () => pet.trick("surprise"),
              () => { pet.face = "closed"; w.say("✦", { color: "#ffd84a" }); return 2400 },
              () => { pet.face = ""; pet.lookY = -1; return 3000 },
              () => { sky.shoot(); return 1600 },
              () => { sky.on = false; w.poseSy = 1; pet.lookY = 0; return pet.trick("love") }])
    }

    // cafe (le matin) ou the (l'apres-midi)
    function sCoffee() {
        const st = [() => { mug.on = true; return 700 }]
        for (let i = 0; i < 3; i++) {
            st.push(() => { mug.sip = true; pet.face = "closed"; return 900 })
            st.push(() => { mug.sip = false; pet.face = ""; return w.rand(1200, 2200) })
        }
        st.push(() => { w.say("♥"); mug.on = false; return pet.trick("stretch") })
        play(st)
    }

    // pluie : un petit nuage le suit, il ouvre son parapluie
    function sUmbrella() {
        play([() => { cloud.on = true; return 1200 },
              () => { pet.lookY = -1; w.say("?"); return 900 },
              () => pet.trick("shiver"),
              () => { umbrella.on = true; pet.lookY = 0; return 700 },
              () => w.walkTo(w.px + w.rand(-260, 260), 45),
              1200,
              () => w.walkTo(w.px + w.rand(-200, 200), 45),
              () => { cloud.on = false; return 1500 },
              () => { umbrella.on = false; return pet.trick("shake") }])
    }

    // neige : il fait un bonhomme de neige (qui fond plus tard)
    property bool snowing: false
    Timer {
        interval: 120
        repeat: true
        running: w.snowing
        onTriggered: {
            const x = w.rand(0, w.width)
            w.part({ sym: Math.random() < 0.5 ? "❄" : "•", x: x, y: -10, x1: x + w.rand(-40, 40), y1: w.gy, size: w.rand(4, 8) * w.k * 0.6,
                     color: "#ffffff", life: w.rand(3500, 6000), ease: Easing.Linear, fadeIn: true })
        }
    }
    function sSnow() {
        let sx = 0
        play([() => { w.snowing = true; pet.lookY = -1; return 1500 },
              () => { pet.lookY = 0; return pet.trick("giggle") },
              () => { sx = w.clampX(w.px + w.dir * 30 * w.k); return 300 },
              () => { w.snowman(sx, 0); return pet.trick("peck") },
              () => { w.snowman(sx, 1); return pet.trick("peck") },
              () => { w.snowman(sx, 2); return pet.trick("hop") },
              () => { w.say("✦"); return pet.trick("love") },
              3000,
              () => { w.snowing = false; return 1500 }])
    }

    // tour propre a l'espece
    function sSpecial() {
        switch (pet.species) {
        case "blob": return spSplit()
        case "cat": return spLaser()
        case "ghost": return spBoo()
        case "bunny": return spCarrot()
        case "frog": return spFly()
        case "penguin": return spSlide()
        case "chick": return spPeck()
        case "robot": return spScan()
        case "axolotl": return spSwim()
        default: return spSpores()
        }
    }
    // blob : il se divise en deux petits blobs, qui se rejoignent
    function spSplit() {
        play([() => pet.trick("melt"),
              () => { minis.split(); walker.opacity = 0; return 2600 },
              () => { minis.merge(); return 900 },
              () => { minis.on = false; walker.opacity = 1; w.sparkle(w.px, w.gy - w.ph / 2, 6); return pet.trick("land") },
              () => pet.trick("giggle")])
    }
    // chat : il chasse un point laser
    function spLaser() {
        const st = [() => { laser.place(w.clampX(w.px + w.rand(-260, 260))); return 900 }]
        for (let i = 0; i < 3; i++) {
            st.push(() => { w.faceTo(laser.lx); pet.look = 1.2; return pet.trick("crouch") })
            st.push(() => w.leap(laser.lx, 520, 34))
            st.push(() => {
                if (i < 2) {
                    laser.place(w.clampX(w.px + w.pick([-1, 1]) * w.rand(120, 300)))
                    w.say("?")
                } else {
                    laser.on = false
                    w.say("♥")
                }
                return 700
            })
        }
        st.push(() => pet.trick("love"))
        play(st)
    }
    // fantome : il disparait et surgit ailleurs
    function spBoo() {
        play([() => { pet.face = "happy"; return 400 },
              () => { fadeA.go(0.08); return 700 },
              () => { w.px = w.clampX(w.px + w.pick([-1, 1]) * w.rand(150, 320)); return 600 },
              () => { fadeA.go(1); return pet.trick("boo") },
              () => { fadeA.go(0.08); return 800 },
              () => { w.px = w.clampX(w.width / 2 + w.rand(-300, 300)); return 600 },
              () => { fadeA.go(1); return pet.trick("boo") },
              () => pet.trick("giggle")])
    }
    NumberAnimation {
        id: fadeA
        target: walker
        property: "opacity"
        duration: 500
        function go(v) {
            fadeA.stop()
            fadeA.to = v
            fadeA.start()
        }
    }
    // lapin : une carotte pousse, il y va en bondissant
    function spCarrot() {
        const cx = clampX(px + pick([-1, 1]) * rand(200, 360))
        const st = [() => { carrot.place(cx); w.faceTo(cx); return pet.trick("surprise") }]
        for (let i = 0; i < 4; i++)
            st.push(() => {
                const d = cx - w.dir * 14 * w.k - w.px
                return Math.abs(d) < 8 ? 0 : w.leap(w.px + Math.sign(d) * Math.min(Math.abs(d), 90), 420, 26)
            })
        st.push(() => w.walkTo(cx - w.dir * 14 * w.k, 60))
        st.push(() => { carrot.pull(); return pet.trick("stretch") })
        st.push(() => { carrot.on = false; return pet.trick("eat") })
        st.push(() => pet.trick("hop"))
        play(st)
    }
    // grenouille : une mouche, et la langue
    function spFly() {
        play([() => { fly.enter(); return 2600 },
              () => w.tongueAt(false),
              () => { fly.dodge(); w.say("?"); return 1600 },
              () => w.tongueAt(false),
              () => { fly.dodge(); return 1600 },
              () => w.tongueAt(true),
              () => { fly.on = false; return pet.trick("eat") },
              () => w.say("♪")])
    }
    function tongueAt(hit) {
        // vers la mouche, dans le repere du compagnon (retourne selon dir)
        const ox = mouthX(), oy = mouthY()
        const fx = hit ? fly.fx : fly.fx + rand(14, 24) * (Math.random() < 0.5 ? -1 : 1)
        const fy = hit ? fly.fy : fly.fy - rand(10, 20)
        faceTo(fx)
        const dx = (fx - ox) * dir, dy = fy - oy
        pet.tongueAngle = Math.atan2(dy, dx) * 180 / Math.PI
        tongueA.len = Math.min(220, Math.hypot(dx, dy))
        tongueA.hit = hit
        tongueA.restart()
        return 520
    }
    SequentialAnimation {
        id: tongueA
        property real len: 60
        property bool hit: false
        NumberAnimation { target: pet; property: "tongue"; to: tongueA.len; duration: 140; easing.type: Easing.OutQuad }
        ScriptAction { script: if (tongueA.hit) fly.caught = true }
        NumberAnimation { target: pet; property: "tongue"; to: 0; duration: 220; easing.type: Easing.InQuad }
    }
    // pingouin : glissade sur le ventre
    function spSlide() {
        const to = px < width / 2 ? width - 160 : 160
        play([() => { ice.place(w.px, to); return 600 },
              () => pet.trick("jump"),
              () => { w.faceTo(to); w.poseRot = 80 * w.dir; w.poseSy = 0.95; pet.face = "happy"; w.riding = true; w.sliding = true; return w.walkTo(to, 260) },
              () => { w.sliding = false; w.riding = false; w.poseRot = 0; w.poseSy = 1; pet.face = ""; return pet.trick("land") },
              () => { ice.on = false; return pet.trick("shake") },
              () => w.say("♪")])
    }
    property bool sliding: false
    Timer {
        interval: 60
        repeat: true
        running: w.sliding
        onTriggered: w.part({ sym: "✧", x: w.px - w.dir * w.pw * 0.5, y: w.gy - w.rand(2, 10), x1: w.px - w.dir * w.rand(30, 60), y1: w.gy - w.rand(10, 30),
                              size: 5 * w.k, color: "#bfe8ff", life: 600 })
    }
    // poussin : il picore des graines
    function spPeck() {
        const xs = []
        for (let i = 0; i < 5; i++)
            xs.push(clampX(px + rand(-260, 260)))
        seeds.model = xs
        const st = [() => { w.say("!"); return 600 }]
        xs.slice().sort((a, b) => Math.abs(a - px) - Math.abs(b - px)).forEach(x => {
            st.push(() => w.walkTo(x - w.dir * 8 * w.k, 80))
            st.push(() => { w.faceTo(x); w.eatSeed(x); return pet.trick("peck") })
            st.push(() => { pet.mouthOpen = 0.8; w.say("♪"); return 250 })
            st.push(() => { pet.mouthOpen = 0; return 300 })
        })
        st.push(() => { seeds.model = []; return pet.trick("love") })
        play(st)
    }
    // robot : balayage laser, ondes radio, recharge
    function spScan() {
        play([() => { beam.on = true; w.say("bip", { size: 6 }); return 3200 },
              () => { beam.on = false; w.radio = true; return 2400 },
              () => { w.radio = false; battery.on = true; return 2600 },
              () => { battery.on = false; w.say("⚡", { color: "#ffd84a" }); return pet.trick("jump") }])
    }
    property bool radio: false
    Timer {
        interval: 450
        repeat: true
        running: w.radio
        onTriggered: ringC.createObject(w.contentItem, { cx: w.px, cy: w.headY() - 2 * w.k, color: Theme.tertiary, r1: 40 * w.k / 2 })
    }
    // axolotl : il nage dans les airs
    function spSwim() {
        play([() => pyAnim.go(-22 * w.k, 1200),
              () => { w.floating = true; w.swim = true; pet.face = "happy"; return w.walkTo(w.px + w.pick([-1, 1]) * w.rand(220, 380), 70) },
              () => w.walkTo(w.px + w.pick([-1, 1]) * w.rand(150, 300), 70),
              () => { w.swim = false; w.floating = false; pet.face = ""; return pyAnim.go(0, 900, Easing.InOutQuad) },
              () => pet.trick("land")])
    }
    property bool swim: false
    Timer {
        interval: 220
        repeat: true
        running: w.swim
        onTriggered: w.part({ sym: "○", x: w.mouthX(), y: w.mouthY(), x1: w.mouthX() - w.dir * w.rand(5, 20), y1: w.mouthY() - w.rand(30, 60),
                              size: w.rand(4, 7) * w.k * 0.7, color: "#bfe8ff", life: 1400 })
    }
    // champignon : des spores lumineuses et des bebes champignons
    property bool spores: false
    function spSpores() {
        play([() => pet.trick("shake"),
              () => { w.spores = true; return 2000 },
              () => { babies.model = [w.px - 30 * w.k, w.px + 26 * w.k, w.px + 44 * w.k]; return 3600 },
              () => { w.spores = false; return pet.trick("love") },
              () => { babies.model = []; return 600 }])
    }
    Timer {
        interval: 90
        repeat: true
        running: w.spores
        onTriggered: w.part({ x: w.px + w.rand(-8, 8) * w.k, y: w.headY() + 2 * w.k, x1: w.px + w.rand(-50, 50), y1: w.headY() - w.rand(40, 110),
                              size: w.rand(2, 3.5) * w.k, color: w.pick(["#e6ff8a", "#fff6a8", "#b8ffcf"]), life: w.rand(1800, 2800), fadeIn: true })
    }

    // ===================================================== effets
    // particules (texte ou point) qui s'envolent ou tombent ; 90 au plus
    property int partLive: 0
    function part(o) {
        if (partLive >= 90)
            return
        partC.createObject(w.contentItem, o)
    }
    function sparkle(x, y, n) {
        for (let i = 0; i < n; i++)
            part({ sym: "✦", x: x, y: y, x1: x + rand(-40, 40), y1: y + rand(-50, 10), size: rand(4, 7) * k,
                   color: pick([Theme.primary, "#ffd84a", Theme.tertiary]), life: rand(600, 1000) })
    }
    function burst(x, y, n, c) {
        for (let i = 0; i < n; i++) {
            const a = Math.PI * 2 * i / n
            part({ x: x, y: y, x1: x + Math.cos(a) * rand(25, 45), y1: y + Math.sin(a) * rand(25, 45), size: 2.4 * k, color: c, life: 500 })
        }
    }
    Component {
        id: partC
        Item {
            id: pt
            property string sym: ""
            property color color: "white"
            property real size: 6
            property real x1: x
            property real y1: y
            property int life: 1200
            property int ease: Easing.OutQuad
            property real grow: 1
            property bool fadeIn: false
            property bool hold: false
            width: size
            height: size
            Component.onCompleted: {
                w.partLive++
                ptAnim.start()
            }
            Component.onDestruction: w.partLive--
            Rectangle {
                visible: pt.sym === ""
                anchors.fill: parent
                radius: width / 2
                color: pt.color
            }
            Txt {
                visible: pt.sym !== ""
                anchors.centerIn: parent
                text: pt.sym
                px: pt.size
                weight: Font.DemiBold
                color: pt.color
            }
            ParallelAnimation {
                id: ptAnim
                NumberAnimation { target: pt; property: "x"; to: pt.x1; duration: pt.life; easing.type: Easing.OutSine }
                NumberAnimation { target: pt; property: "y"; to: pt.y1; duration: pt.life; easing.type: pt.ease }
                NumberAnimation { target: pt; property: "scale"; to: pt.grow; duration: pt.life }
                SequentialAnimation {
                    NumberAnimation { target: pt; property: "opacity"; from: pt.fadeIn ? 0 : 1; to: 1; duration: pt.life * (pt.hold ? 0.1 : 0.2) }
                    PauseAnimation { duration: pt.hold ? pt.life * 0.6 : 0 }
                    NumberAnimation { target: pt; property: "opacity"; to: 0; duration: pt.life * (pt.hold ? 0.3 : 0.8); easing.type: Easing.InQuad }
                }
                onFinished: pt.destroy()
            }
        }
    }
    // onde circulaire (aura, radio)
    Component {
        id: ringC
        Rectangle {
            id: rg
            property real cx
            property real cy
            property real r1: 60
            width: 2
            height: 2
            radius: width / 2
            x: cx - width / 2
            y: cy - height / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            Component.onCompleted: rgA.start()
            ParallelAnimation {
                id: rgA
                NumberAnimation { target: rg; property: "width"; to: rg.r1 * 2; duration: 1300; easing.type: Easing.OutQuad }
                NumberAnimation { target: rg; property: "height"; to: rg.r1 * 2; duration: 1300; easing.type: Easing.OutQuad }
                NumberAnimation { target: rg; property: "opacity"; from: 0.8; to: 0; duration: 1300 }
                onFinished: rg.destroy()
            }
        }
    }

    // trainee pendant la marche (Reglages > Compagnon > Trainee)
    property real trailAcc: 0
    property int trailN: 0
    function trailStep(d) {
        const t = Ilot.cfg.pet_trail || "none"
        if (t === "none" || leaving)
            return
        trailAcc += d
        if (trailAcc < (t === "steps" ? 9 * k : t === "rainbow" ? 4 : 12))
            return
        trailAcc = 0
        trailN++
        const bx = px - dir * pw * 0.3, by = gy + py
        switch (t) {
        case "sparkle":
            part({ sym: "✦", x: bx, y: by - rand(4, 14) * k, x1: bx - dir * rand(4, 12), y1: by - rand(16, 30) * k, size: rand(3, 5) * k,
                   color: pick([Theme.primary, "#ffd84a", Theme.tertiary, "#ffffff"]), life: 900 })
            break
        case "hearts":
            part({ sym: "♥", x: bx, y: by - 10 * k, x1: bx - dir * rand(2, 10), y1: by - rand(20, 34) * k, size: rand(4, 6) * k, color: "#ff5d8f", life: 1100 })
            break
        case "bubbles":
            part({ sym: "○", x: bx, y: by - 8 * k, x1: bx + rand(-10, 10), y1: by - rand(26, 44) * k, size: rand(4, 7) * k, color: "#bfe8ff", life: 1500 })
            break
        case "flowers":
            part({ sym: pick(["✿", "❀", "✾"]), x: bx, y: by - 4 * k, x1: bx, y1: by - 4 * k, size: rand(4, 6) * k, grow: 1.3,
                   color: pick(["#ff8fb8", "#ffd84a", "#b28dff", "#7cc7ff", "#ffffff"]), life: 4200, hold: true, fadeIn: true })
            break
        case "steps":
            part({ x: bx + (trailN % 2 ? 2 : -2) * k, y: by - 1.5 * k + (trailN % 2 ? 0 : 1.5 * k), x1: bx, y1: by - 1.5 * k,
                   size: 2.2 * k, color: Qt.rgba(0, 0, 0, 0.35), life: 3000, hold: true })
            break
        case "rainbow":
            part({ x: bx, y: by - 9 * k, x1: bx, y1: by - 9 * k, size: 3.4 * k, color: Qt.hsva((trailN * 0.035) % 1, 0.65, 1, 1), life: 800 })
            break
        }
    }

    // ===================================================== decor
    // fleurs du jardin et bonhommes de neige : ils restent un moment
    Item {
        id: decor
        anchors.fill: parent
    }
    function dig(x) {
        for (let i = 0; i < 5; i++)
            part({ x: x, y: gy - 2, x1: x + rand(-24, 24), y1: gy - rand(10, 30), size: rand(1.6, 2.6) * k, color: "#8a5a3c", life: 500, ease: Easing.OutQuad })
    }
    function plant(x) {
        if (decor.children.length >= 8)
            decor.children[0].destroy()
        flowerC.createObject(decor, { x: x, hue: pick(["#ff8fb8", "#ffd84a", "#b28dff", "#ff7a59", "#7cc7ff"]) })
    }
    Component {
        id: flowerC
        Item {
            id: fl
            property color hue: "pink"
            property real grow: 0
            property real wilt: 0
            y: w.gy
            Component.onCompleted: flA.start()
            SequentialAnimation {
                id: flA
                NumberAnimation { target: fl; property: "grow"; to: 1; duration: 1500; easing.type: Easing.OutBack }
                PauseAnimation { duration: 60000 }
                NumberAnimation { target: fl; property: "wilt"; to: 1; duration: 2500 }
                ScriptAction { script: fl.destroy() }
            }
            opacity: 1 - fl.wilt
            rotation: fl.wilt * 40
            transformOrigin: Item.Bottom
            // butte, tige, feuilles, fleur
            Rectangle {
                width: 12 * w.k
                height: 3 * w.k
                radius: height / 2
                x: -width / 2
                y: -height / 2
                color: "#7a5236"
            }
            Rectangle {
                width: 1.2 * w.k
                height: 14 * w.k * fl.grow
                x: -width / 2
                y: -height
                color: "#5aa850"
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    width: 4 * w.k
                    height: 2 * w.k
                    radius: height / 2
                    color: "#6cc56b"
                    x: index ? 0 : -width
                    y: -(5 + index * 3) * w.k * fl.grow
                    rotation: index ? -30 : 30
                    scale: fl.grow
                }
            }
            Item {
                x: 0
                y: -14 * w.k * fl.grow
                scale: Math.max(0, fl.grow)
                rotation: (1 - fl.grow) * 180
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        width: 3.4 * w.k
                        height: width
                        radius: width / 2
                        color: fl.hue
                        x: Math.cos(index * 1.2566) * 2.2 * w.k - width / 2
                        y: Math.sin(index * 1.2566) * 2.2 * w.k - height / 2
                    }
                }
                Rectangle {
                    width: 2.6 * w.k
                    height: width
                    radius: width / 2
                    x: -width / 2
                    y: -height / 2
                    color: "#fff1a8"
                }
            }
        }
    }
    function snowman(x, n) {
        if (n === 0) {
            if (decor.children.length >= 8)
                decor.children[0].destroy()
            lastSnowman = snowC.createObject(decor, { x: x })
        } else if (lastSnowman) {
            lastSnowman.parts = n + 1
        }
    }
    property var lastSnowman: null
    Component {
        id: snowC
        Item {
            id: sm
            property int parts: 1
            property real melt: 0
            y: w.gy
            Component.onCompleted: smA.start()
            SequentialAnimation {
                id: smA
                PauseAnimation { duration: 60000 }
                NumberAnimation { target: sm; property: "melt"; to: 1; duration: 4000 }
                ScriptAction { script: sm.destroy() }
            }
            transform: Scale { origin.y: 0; yScale: 1 - sm.melt * 0.8 }
            opacity: 1 - sm.melt
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real r: [6.5, 5, 3.8][index] * w.k
                    readonly property real base: [0, 11.5, 20.5][index] * w.k
                    visible: index < sm.parts
                    scale: visible ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                    width: r * 2
                    height: r * 2
                    radius: r
                    x: -r
                    y: -base - r * 2
                    color: "#f4f8ff"
                    border.width: 1
                    border.color: "#cfdcf0"
                }
            }
            // yeux, nez carotte, boutons
            Item {
                visible: sm.parts >= 3
                y: -25 * w.k
                Rectangle { x: -1.8 * w.k; y: -1.6 * w.k; width: 1.1 * w.k; height: width; radius: width / 2; color: "#26262e" }
                Rectangle { x: 0.8 * w.k; y: -1.6 * w.k; width: 1.1 * w.k; height: width; radius: width / 2; color: "#26262e" }
                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillColor: "#ff8a3c"
                        PathSvg { path: `M0 ${0.2 * w.k} L${4 * w.k} ${0.9 * w.k} L0 ${1.4 * w.k} Z` }
                    }
                }
            }
            Repeater {
                model: sm.parts >= 2 ? 2 : 0
                Rectangle {
                    required property int index
                    x: -0.6 * w.k
                    y: -(14 + index * 3) * w.k
                    width: 1.2 * w.k
                    height: width
                    radius: width / 2
                    color: "#26262e"
                }
            }
        }
    }

    // ===================================================== accessoires
    // chaque accessoire a un interrupteur `on` (fondu)
    component Prop: Item {
        property bool on: false
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // parachute (arrivee)
    Prop {
        id: chute
        x: w.px - 16 * w.k
        y: w.gy - w.ph + w.py - 26 * w.k
        width: 32 * w.k
        height: 26 * w.k
        rotation: w.poseRot * 0.6
        transformOrigin: Item.Bottom
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(w.k, w.k)
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.7)
                strokeWidth: 0.5 * w.k
                PathSvg { path: "M2 10 L12 25 M10 10.8 L14 25 M22 10.8 L18 25 M30 10 L20 25" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: Theme.primary
                PathSvg { path: "M1 10 C1 3 8 0 16 0 C24 0 31 3 31 10 Q27 8 23.5 10.6 Q20 8.4 16 10.6 Q12 8.4 8.5 10.6 Q5 8 1 10 Z" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: "M8.5 10.6 Q8 4 12 0.4 Q14 0.1 16 0 Q11.6 4 12 9.6 Q10 9.4 8.5 10.6 Z M23.5 10.6 Q24 4 20 0.4 Q18 0.1 16 0 Q20.4 4 20 9.6 Q22 9.4 23.5 10.6 Z" }
            }
        }
    }
    SequentialAnimation {
        running: chute.on
        loops: Animation.Infinite
        NumberAnimation { target: w; property: "poseRot"; to: 9; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { target: w; property: "poseRot"; to: -9; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) w.poseRot = 0
    }
    // portail (arrivee)
    Prop {
        id: portal
        x: w.px - 22 * w.k
        y: w.gy - 5 * w.k
        width: 44 * w.k
        height: 10 * w.k
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.alpha(Theme.primary, 0.35)
            border.width: 2 * w.k
            border.color: Theme.primary
            scale: portal.on ? 1 : 0.2
            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: parent.height * 0.5
                radius: height / 2
                color: Theme.alpha(Theme.tertiary, 0.5)
                RotationAnimation on rotation { running: portal.visible; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
            }
        }
    }

    // ballon de plage (physique simple : gravite, rebonds, roulement)
    Prop {
        id: ball
        property real r: 5 * w.k
        property real bx: 0
        property real by: 0
        property real vx: 0
        property real vy: 0
        property real spin: 0
        x: bx - r
        y: w.gy - 2 * r - by
        width: 2 * r
        height: 2 * r
        rotation: spin
        function drop(x) {
            bx = x
            by = w.height - 2 * r
            vx = 0
            vy = 0
            on = true
        }
        function kick(d) {
            vx = d * w.rand(260, 420)
            vy = w.rand(260, 430)
        }
        function resting() {
            return by < 0.5 && Math.abs(vy) < 1 && Math.abs(vx) < 8
        }
        FrameAnimation {
            running: ball.on
            onTriggered: {
                const dt = Math.min(0.05, frameTime), b = ball
                b.vy -= 900 * dt
                b.by += b.vy * dt
                b.bx += b.vx * dt
                if (b.by <= 0) {
                    b.by = 0
                    if (Math.abs(b.vy) > 70) {
                        b.vy = -b.vy * 0.55
                        b.vx *= 0.85
                    } else {
                        b.vy = 0
                        b.vx *= Math.pow(0.4, dt)
                        if (Math.abs(b.vx) < 5)
                            b.vx = 0
                    }
                }
                if (b.bx < b.r) {
                    b.bx = b.r
                    b.vx = Math.abs(b.vx) * 0.7
                } else if (b.bx > w.width - b.r) {
                    b.bx = w.width - b.r
                    b.vx = -Math.abs(b.vx) * 0.7
                }
                b.spin += b.vx * dt / b.r * 57.3
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(ball.r / 5, ball.r / 5)
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: "M0 5 A5 5 0 1 1 10 5 A5 5 0 1 1 0 5 Z" }
            }
            ShapePath {
                scale: Qt.size(ball.r / 5, ball.r / 5)
                strokeWidth: -1
                fillColor: "#ff5d6c"
                PathSvg { path: "M5 5 L5 0 A5 5 0 0 1 9.33 2.5 Z M5 5 L9.33 7.5 A5 5 0 0 1 5 10 Z M5 5 L0.67 7.5 A5 5 0 0 1 0.67 2.5 Z" }
            }
            ShapePath {
                scale: Qt.size(ball.r / 5, ball.r / 5)
                strokeWidth: -1
                fillColor: "#3aa0ff"
                PathSvg { path: "M5 5 L9.33 2.5 A5 5 0 0 1 9.33 7.5 Z M5 5 L5 10 A5 5 0 0 1 0.67 7.5 Z M5 5 L0.67 2.5 A5 5 0 0 1 5 0 Z" }
            }
            ShapePath {
                scale: Qt.size(ball.r / 5, ball.r / 5)
                strokeWidth: -1
                fillColor: "#ffd84a"
                PathSvg { path: "M3.6 5 A1.4 1.4 0 1 1 6.4 5 A1.4 1.4 0 1 1 3.6 5 Z" }
            }
        }
    }

    // papillon
    Prop {
        id: bfly
        property real bx: -50
        property real by: 100
        property real t: 0
        property string mode: "wander"
        property real flap: 1
        property color hue: Theme.tertiary
        x: bx - 8 * w.k
        y: by - 6 * w.k
        width: 16 * w.k
        height: 12 * w.k
        function enter() {
            const left = Math.random() < 0.5
            bx = left ? -30 : w.width + 30
            by = w.gy - 120
            hue = w.pick([Theme.tertiary, "#ffb347", "#7ad7f0", "#c58bff"])
            mode = "wander"
            on = true
        }
        function dodge() {
            mode = "flee"
            w.later(900, () => { if (bfly.mode === "flee") bfly.mode = "wander" })
        }
        FrameAnimation {
            running: bfly.on
            onTriggered: {
                const dt = Math.min(0.05, frameTime), b = bfly
                b.t += dt
                let tx, ty
                if (b.mode === "land") {
                    tx = w.px + w.dir * 1.5 * w.k
                    ty = w.headY() - 3 * w.k
                } else if (b.mode === "leave") {
                    tx = w.px < w.width / 2 ? w.width + 80 : -80
                    ty = -60
                } else if (b.mode === "flee") {
                    tx = b.bx + Math.sin(b.t * 2) * 40
                    ty = w.gy - 170
                } else {
                    tx = w.px + Math.sin(b.t * 0.9) * 90 + Math.sin(b.t * 2.3) * 30
                    ty = w.gy - 80 + Math.sin(b.t * 1.7) * 30
                }
                const kk = Math.min(1, dt * (b.mode === "land" ? 3 : 1.8))
                b.bx += (tx - b.bx) * kk
                b.by += (ty - b.by) * kk + (b.mode === "land" ? 0 : Math.sin(b.t * 9) * 0.8)
                if (!w.leaving)
                    w.lookAt(b.bx, b.by)
                if (b.mode === "leave" && (b.bx < -60 || b.bx > w.width + 60))
                    b.on = false
            }
        }
        SequentialAnimation on flap {
            running: bfly.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: bfly.mode === "land" ? 500 : 110 }
            NumberAnimation { to: 1; duration: bfly.mode === "land" ? 500 : 110 }
        }
        Repeater {
            model: 2
            Item {
                id: wing
                required property int index
                anchors.fill: parent
                transform: Scale { origin.x: bfly.width / 2; xScale: (wing.index ? 1 : -1) * bfly.flap }
                Rectangle {
                    x: bfly.width / 2
                    y: 0
                    width: 6.5 * w.k
                    height: 6 * w.k
                    radius: width / 2
                    color: bfly.hue
                    Rectangle { x: parent.width * 0.45; y: parent.height * 0.3; width: parent.width * 0.3; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.6) }
                }
                Rectangle {
                    x: bfly.width / 2
                    y: 5.4 * w.k
                    width: 4.6 * w.k
                    height: 4.6 * w.k
                    radius: width / 2
                    color: Qt.darker(bfly.hue, 1.15)
                }
            }
        }
        Rectangle {
            x: bfly.width / 2 - width / 2
            y: 1 * w.k
            width: 1.4 * w.k
            height: 9 * w.k
            radius: width / 2
            color: "#3a2c36"
        }
    }

    // ballon gonflable et sa ficelle
    Prop {
        id: balloon
        property color color: "#ff6b6b"
        readonly property real cx: w.px + w.dir * 6 * w.k + Math.sin(sway) * 3 * w.k
        readonly property real cy: w.gy - w.ph + w.py - 18 * w.k
        property real sway: 0
        property real size: 0
        function inflate() {
            color = w.pick(["#ff6b6b", "#ffd93d", "#6bcbff", "#b28dff", "#5ee0a0"])
            size = 0.1
            on = true
            infl.restart()
        }
        NumberAnimation { id: infl; target: balloon; property: "size"; to: 1; duration: 800; easing.type: Easing.OutBack }
        NumberAnimation on sway {
            running: balloon.visible
            from: 0
            to: Math.PI * 2
            duration: 2200
            loops: Animation.Infinite
        }
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.7)
                strokeWidth: 1
                PathSvg {
                    path: `M${w.px + w.dir * 6 * w.k} ${w.gy - w.ph * 0.4 + w.py} Q${balloon.cx - 6 * w.k * w.dir} ${(balloon.cy + w.gy - w.ph * 0.4 + w.py) / 2} ${balloon.cx} ${balloon.cy + 6 * w.k * balloon.size}`
                }
            }
        }
        Rectangle {
            width: 12 * w.k * balloon.size
            height: 14 * w.k * balloon.size
            radius: width / 2
            x: balloon.cx - width / 2
            y: balloon.cy - height / 2 - 1 * w.k
            color: balloon.color
            Rectangle { x: parent.width * 0.2; y: parent.height * 0.15; width: parent.width * 0.22; height: parent.height * 0.3; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.45) }
        }
    }

    // mare et canne a peche
    Prop {
        id: pond
        property real cx: 0
        x: cx - 22 * w.k
        y: w.gy - 4 * w.k
        width: 44 * w.k
        height: 8 * w.k
        function open(x) {
            cx = x
            on = true
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: pond.width / 2; xScale: pond.on ? 1 : 0.1; Behavior on xScale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                fillColor: "#3d8fd1"
                strokeColor: "#7cc7ff"
                strokeWidth: 1.2 * w.k
                PathSvg { path: "M0.6 4 C0.6 1.6 10 0.4 22 0.4 C34 0.4 43.4 1.6 43.4 4 C43.4 6.4 34 7.6 22 7.6 C10 7.6 0.6 6.4 0.6 4 Z" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.35 * (0.5 + 0.5 * Math.sin(rod.bob)))
                strokeWidth: 0.6 * w.k
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M8 3 Q13 2.2 18 3 M26 5.2 Q31 4.4 36 5.2" }
            }
        }
    }
    Prop {
        id: rod
        anchors.fill: parent
        property real t: 0
        property real dip: 0
        property real bob: 0
        readonly property real hx: w.px + w.dir * 7 * w.k
        readonly property real hy: w.gy + w.py - 8 * w.k
        readonly property real tipX: w.px + w.dir * 24 * w.k
        readonly property real tipY: w.gy + w.py - 32 * w.k
        readonly property real fx: tipX + (pond.cx - tipX) * t
        readonly property real fy: tipY + (w.gy - 3 * w.k - tipY) * t - Math.sin(Math.PI * t) * 40 + (t >= 1 ? Math.sin(bob) * 1.2 + dip : 0)
        function cast() {
            castA.to = 1
            castA.restart()
        }
        function reel() {
            castA.to = 0
            castA.restart()
        }
        function nibble() {
            nibA.restart()
        }
        function bite() {
            dip = 6
        }
        onOnChanged: if (on) { t = 0; dip = 0 }
        NumberAnimation { id: castA; target: rod; property: "t"; duration: 800; easing.type: Easing.OutQuad }
        SequentialAnimation {
            id: nibA
            loops: 2
            NumberAnimation { target: rod; property: "dip"; to: 3; duration: 120 }
            NumberAnimation { target: rod; property: "dip"; to: 0; duration: 200 }
        }
        NumberAnimation on bob {
            running: rod.visible
            from: 0
            to: Math.PI * 2
            duration: 1800
            loops: Animation.Infinite
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#9a6b3f"
                strokeWidth: 1.4 * w.k
                capStyle: ShapePath.RoundCap
                PathSvg { path: `M${rod.hx} ${rod.hy} Q${(rod.hx + rod.tipX) / 2} ${rod.tipY + 4 * w.k} ${rod.tipX} ${rod.tipY}` }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.6)
                strokeWidth: 1
                PathSvg { path: `M${rod.tipX} ${rod.tipY} Q${(rod.tipX + rod.fx) / 2} ${Math.max(rod.tipY, rod.fy) + 6} ${rod.fx} ${rod.fy}` }
            }
        }
        Rectangle {
            width: 3.4 * w.k
            height: width
            radius: width / 2
            x: rod.fx - width / 2
            y: rod.fy - height / 2
            color: "#ffffff"
            Rectangle { width: parent.width; height: parent.height / 2; radius: 0; color: "#ff4d4d" }
        }
    }

    // skateboard
    Prop {
        id: board
        x: w.px - 13 * w.k
        y: w.gy + w.py - 0.4 * w.k
        width: 26 * w.k
        height: 4 * w.k
        property real flipT: 0
        function flip() {
            flipA.restart()
        }
        NumberAnimation { id: flipA; target: board; property: "flipT"; from: 0; to: 1; duration: 520 }
        transform: [
            Scale { origin.y: board.height / 2; yScale: Math.cos(board.flipT * Math.PI * 2) },
            Rotation { origin.x: board.width / 2; origin.y: board.height / 2; angle: Math.sin(board.flipT * Math.PI) * 12 * w.dir }
        ]
        Rectangle {
            width: parent.width
            height: 1.8 * w.k
            radius: height / 2
            color: "#ff7a59"
            Rectangle { x: parent.width * 0.1; width: parent.width * 0.8; height: parent.height * 0.45; color: "#2b2b33"; radius: height / 2 }
        }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                width: 2.6 * w.k
                height: width
                radius: width / 2
                x: index ? board.width * 0.72 : board.width * 0.18
                y: 1.4 * w.k
                color: "#fff1a8"
                border.width: 0.5 * w.k
                border.color: "#2b2b33"
            }
        }
    }
    Timer {
        interval: 70
        repeat: true
        running: w.riding && w.walking && board.on
        onTriggered: w.part({ x: w.px - w.dir * 14 * w.k, y: w.gy - w.rand(4, 26), x1: w.px - w.dir * w.rand(50, 90), y1: w.gy - w.rand(4, 26),
                              size: 1.4 * w.k, color: Qt.rgba(1, 1, 1, 0.6), life: 380 })
    }

    // bulles de savon : un anneau, des bulles qui montent et eclatent
    Prop {
        id: wand
        x: w.mouthX() + w.dir * 5 * w.k - 3 * w.k
        y: w.mouthY() - 3 * w.k
        width: 6 * w.k
        height: 6 * w.k
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 0.8 * w.k
            border.color: Theme.tertiary
        }
        Rectangle {
            x: parent.width / 2 - width / 2
            y: parent.height
            width: 0.8 * w.k
            height: 7 * w.k
            color: Theme.tertiary
        }
    }
    Item {
        id: bubbles
        anchors.fill: parent
    }
    function blowBubble() {
        bubbleC.createObject(bubbles, { x: mouthX() + dir * 8 * k, y: mouthY() - 2 * k, size: rand(4, 9) * k, vx: dir * rand(10, 40) })
    }
    function popBubble() {
        let best = null
        for (const b of bubbles.children)
            if (!best || Math.abs(b.x - px) < Math.abs(best.x - px))
                best = b
        if (best)
            best.pop()
    }
    Component {
        id: bubbleC
        Rectangle {
            id: bb
            property real size: 10
            property real vx: 20
            property real t: 0
            property real x0: 0
            width: size
            height: size
            radius: size / 2
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Qt.hsva((x0 / 300) % 1, 0.35, 1, 0.8)
            Component.onCompleted: x0 = x
            Rectangle { x: parent.width * 0.2; y: parent.height * 0.18; width: parent.width * 0.25; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.7) }
            function pop() {
                w.part({ sym: "✧", x: x, y: y, x1: x, y1: y - 10, size: 5 * w.k, color: "#ffffff", life: 400 })
                destroy()
            }
            FrameAnimation {
                running: true
                onTriggered: {
                    const dt = Math.min(0.05, frameTime)
                    bb.t += dt
                    bb.y -= (28 + bb.size) * dt
                    bb.x = bb.x0 + bb.vx * bb.t + Math.sin(bb.t * 3) * 6
                    if (bb.t > 3 + bb.size / 20 || bb.y < 0)
                        bb.pop()
                }
            }
        }
    }

    // livre
    Prop {
        id: book
        x: w.px - 9 * w.k
        y: w.gy - 9 * w.k
        width: 18 * w.k
        height: 8 * w.k
        property real turnA: 0
        function turn() {
            turnAnim.restart()
        }
        NumberAnimation { id: turnAnim; target: book; property: "turnA"; from: 0; to: -180; duration: 600; easing.type: Easing.InOutQuad }
        scale: on ? 1 : 0.4
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -0.8 * w.k
            radius: 1.2 * w.k
            color: Theme.tertiary
        }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                x: index ? book.width / 2 : 0
                width: book.width / 2
                height: book.height
                color: "#fbf7ee"
                Column {
                    x: 1.4 * w.k
                    y: 1.4 * w.k
                    spacing: 1.1 * w.k
                    Repeater {
                        model: 4
                        Rectangle { width: (5 + (index * 7) % 3) * w.k; height: 0.5 * w.k; color: "#c9c2b4" }
                    }
                }
            }
        }
        // page qui tourne
        Rectangle {
            visible: book.turnA < 0 && book.turnA > -180
            x: book.width / 2
            width: book.width / 2
            height: book.height
            color: "#f1ead9"
            transform: Rotation { origin.x: 0; axis { x: 0; y: 1; z: 0 } angle: book.turnA }
        }
    }

    // avion en papier
    Prop {
        id: plane
        property real px: 0
        property real py: 0
        property real vx: 0
        property real t: 0
        property real y0: 0
        property bool flying: false
        property real tilt: 0
        x: px - 6 * w.k
        y: py - 3 * w.k
        width: 12 * w.k
        height: 6 * w.k
        rotation: tilt
        function hold() {
            flying = false
            px = w.px + w.dir * 4 * w.k
            py = w.headY() - 6 * w.k
            tilt = 0
            on = true
        }
        function launch(d) {
            vx = d * w.rand(240, 320)
            t = 0
            y0 = py
            flying = true
        }
        FrameAnimation {
            running: plane.on && plane.flying
            onTriggered: {
                const dt = Math.min(0.05, frameTime), p = plane
                p.t += dt
                p.px += p.vx * dt
                const ny = p.y0 + 22 * Math.sin(p.t * 3) * Math.exp(-p.t * 0.5) + 26 * p.t
                p.tilt = Math.atan2(ny - p.py, Math.abs(p.vx) * dt) * 57.3 * Math.sign(p.vx)
                p.py = ny
                if (p.px < 20 || p.px > w.width - 20)
                    p.vx = -p.vx * 0.6
                if (p.py >= w.gy - 3 * w.k) {
                    p.py = w.gy - 3 * w.k
                    p.tilt = 0
                    p.flying = false
                    w.resume()
                }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: plane.width / 2; xScale: plane.vx < 0 ? -1 : 1 }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: "M12 2.6 L0 0 L4 3 Z M12 2.6 L4 3 L1.4 6 Z" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: "#d8dcea"
                PathSvg { path: "M12 2.6 L4 3 L3 4.6 Z" }
            }
        }
    }

    // arrosoir
    Prop {
        id: can
        readonly property real spoutX: w.px + w.dir * 15 * w.k
        readonly property real spoutY: w.gy - 12 * w.k
        x: w.px + w.dir * 5 * w.k - (w.dir < 0 ? 8 * w.k : 0)
        y: w.gy - 13 * w.k
        width: 8 * w.k
        height: 7 * w.k
        rotation: w.watering ? 25 * w.dir : 0
        Behavior on rotation { NumberAnimation { duration: 300 } }
        Rectangle { y: 1 * w.k; width: 6 * w.k; height: 6 * w.k; radius: 1.2 * w.k; color: "#5ec8a8"; x: w.dir < 0 ? 2 * w.k : 0 }
        Rectangle { x: w.dir < 0 ? 0 : 5 * w.k; y: 2 * w.k; width: 3 * w.k; height: 1 * w.k; color: "#5ec8a8"; rotation: -30 * w.dir }
    }

    // aura (meditation) : ondes et etincelles qui tournent
    Prop {
        id: aura
        anchors.fill: parent
        property real a: 0
        NumberAnimation on a {
            running: aura.visible
            from: 0
            to: Math.PI * 2
            duration: 3000
            loops: Animation.Infinite
        }
        Timer {
            interval: 900
            repeat: true
            running: aura.on
            onTriggered: ringC.createObject(w.contentItem, { cx: w.px, cy: w.gy - w.ph / 2 + w.py, r1: 34 * w.k / 2 + 20 })
        }
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real t: aura.a + index * 2.094
                width: 2.4 * w.k
                height: width
                radius: width / 2
                color: ["#ffd84a", Theme.primary, Theme.tertiary][index]
                x: w.px + Math.cos(t) * 16 * w.k - width / 2
                y: w.gy - w.ph / 2 + w.py + Math.sin(t) * 5 * w.k - height / 2
                opacity: 0.6 + 0.4 * Math.sin(t)
            }
        }
    }

    // projecteurs de la danse
    Prop {
        id: disco
        anchors.fill: parent
        property real a: 0
        NumberAnimation on a {
            running: disco.visible
            from: 0
            to: Math.PI * 2
            duration: 4000
            loops: Animation.Infinite
        }
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 46 * w.k
                height: 9 * w.k
                radius: height / 2
                x: w.px + Math.sin(disco.a * 2 + index * 2.1) * 30 * w.k - width / 2
                y: w.gy - height / 2
                color: Qt.hsva((disco.a / 6.283 + index / 3) % 1, 0.7, 1, 0.22)
            }
        }
        Timer {
            interval: 500
            repeat: true
            running: disco.on
            onTriggered: w.part({ sym: w.pick(["♪", "♫", "✦"]), x: w.px + w.rand(-30, 30), y: w.gy - w.ph, x1: w.px + w.rand(-60, 60), y1: w.gy - w.ph - w.rand(40, 80),
                                  size: 7 * w.k * 0.8, color: Qt.hsva(Math.random(), 0.6, 1, 1), life: 1500 })
        }
    }

    // ciel etoile, etoile filante
    Prop {
        id: sky
        anchors.fill: parent
        property var stars: []
        onOnChanged: if (on) stars = Array.from({ length: 12 }, () => [w.rand(0.05, 0.95), w.rand(0.05, 0.5), w.rand(0, 3000)])
        function shoot() {
            shootA.restart()
        }
        Repeater {
            model: sky.stars
            Txt {
                id: st
                required property var modelData
                text: "✦"
                px: 5 * w.k
                color: "#fff6c8"
                x: st.modelData[0] * w.width
                y: st.modelData[1] * w.height
                SequentialAnimation on opacity {
                    running: sky.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: st.modelData[2] }
                    NumberAnimation { from: 0.2; to: 1; duration: 900 }
                    NumberAnimation { to: 0.2; duration: 900 }
                }
            }
        }
        Rectangle {
            id: comet
            width: 60 * w.k
            height: 1.2 * w.k
            radius: height / 2
            opacity: 0
            rotation: -14
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#fffbe0" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        ParallelAnimation {
            id: shootA
            NumberAnimation { target: comet; property: "x"; from: w.width * 0.8; to: w.width * 0.25; duration: 900; easing.type: Easing.InQuad }
            NumberAnimation { target: comet; property: "y"; from: 10; to: 80; duration: 900; easing.type: Easing.InQuad }
            SequentialAnimation {
                NumberAnimation { target: comet; property: "opacity"; from: 0; to: 1; duration: 150 }
                PauseAnimation { duration: 450 }
                NumberAnimation { target: comet; property: "opacity"; to: 0; duration: 300 }
            }
        }
    }

    // tasse et vapeur
    Prop {
        id: mug
        property bool sip: false
        readonly property bool tea: w.hour >= 12
        x: w.px + w.dir * (mug.sip ? 3 : 7) * w.k - 3 * w.k
        y: w.gy - (mug.sip ? 12 : 8) * w.k
        width: 6 * w.k
        height: 6 * w.k
        rotation: mug.sip ? -30 * w.dir : 0
        Behavior on x { NumberAnimation { duration: 300 } }
        Behavior on y { NumberAnimation { duration: 300 } }
        Behavior on rotation { NumberAnimation { duration: 300 } }
        Rectangle {
            x: w.dir > 0 ? 4.6 * w.k : -1.6 * w.k
            y: 1.2 * w.k
            width: 3 * w.k
            height: 3 * w.k
            radius: width / 2
            color: "transparent"
            border.width: 0.8 * w.k
            border.color: mug.tea ? "#7cc49a" : Theme.tertiary
        }
        Rectangle {
            width: 6 * w.k
            height: 6 * w.k
            radius: 1.4 * w.k
            color: mug.tea ? "#7cc49a" : Theme.tertiary
            Rectangle { y: 0.6 * w.k; x: 0.8 * w.k; width: parent.width - 1.6 * w.k; height: 1 * w.k; radius: height / 2; color: mug.tea ? "#c9a46b" : "#6b4430" }
        }
        Repeater {
            model: 2
            Txt {
                id: steam
                required property int index
                text: "~"
                px: 6 * w.k
                color: Qt.rgba(1, 1, 1, 0.7)
                x: (1 + index * 2) * w.k
                rotation: 90
                SequentialAnimation on y {
                    running: mug.visible && !mug.sip
                    loops: Animation.Infinite
                    PauseAnimation { duration: steam.index * 600 }
                    NumberAnimation { from: -2 * w.k; to: -9 * w.k; duration: 1200 }
                }
                SequentialAnimation on opacity {
                    running: mug.visible && !mug.sip
                    loops: Animation.Infinite
                    PauseAnimation { duration: steam.index * 600 }
                    NumberAnimation { from: 0.8; to: 0; duration: 1200 }
                }
            }
        }
    }

    // nuage de pluie et parapluie
    Prop {
        id: cloud
        x: w.px - 18 * w.k
        y: w.gy - w.ph - 40 * w.k
        width: 36 * w.k
        height: 14 * w.k
        Behavior on x { NumberAnimation { duration: 600 } }
        Repeater {
            model: [[2, 6, 10], [9, 1, 14], [20, 3, 12], [26, 7, 9]]
            Rectangle {
                required property var modelData
                x: modelData[0] * w.k
                y: modelData[1] * w.k
                width: modelData[2] * w.k
                height: width
                radius: width / 2
                color: "#9aa3b5"
            }
        }
        Timer {
            interval: 60
            repeat: true
            running: cloud.on
            onTriggered: {
                const x = cloud.x + w.rand(3, 33) * w.k
                const stop = umbrella.on && Math.abs(x - w.px) < 15 * w.k ? umbrella.topY : w.gy
                w.part({ x: x, y: cloud.y + 12 * w.k, x1: x - 4, y1: stop, size: 1.4 * w.k, color: "#8ecbff", life: 380, ease: Easing.InQuad })
            }
        }
    }
    Prop {
        id: umbrella
        readonly property real topY: w.gy - w.ph - 12 * w.k + w.py
        x: w.px - 16 * w.k
        y: topY
        width: 32 * w.k
        height: 30 * w.k
        transform: Scale { origin.x: umbrella.width / 2; xScale: umbrella.on ? 1 : 0.15; Behavior on xScale { NumberAnimation { duration: 450; easing.type: Easing.OutBack } } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(w.k, w.k)
                fillColor: "transparent"
                strokeColor: "#4a4458"
                strokeWidth: 0.8 * w.k
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M16 1 L16 22 Q16 24 14 24" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: Theme.primary
                PathSvg { path: "M1 10 C1 4 8 1 16 1 C24 1 31 4 31 10 Q27 7.6 23.5 10 Q20 7.6 16 10 Q12 7.6 8.5 10 Q5 7.6 1 10 Z" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: Theme.tertiary
                PathSvg { path: "M8.5 10 Q9 4 16 1 Q12 5 12 9.4 Q10 8.8 8.5 10 Z M23.5 10 Q23 4 16 1 Q20 5 20 9.4 Q22 8.8 23.5 10 Z" }
            }
        }
    }

    // point laser (chat)
    Prop {
        id: laser
        property real lx: 0
        function place(x) {
            lx = x
            on = true
        }
        x: lx - 2 * w.k
        y: w.gy - 3 * w.k
        width: 4 * w.k
        height: 4 * w.k
        Behavior on lx { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
        Rectangle { anchors.fill: parent; anchors.margins: -1.5 * w.k; radius: width / 2; color: Qt.rgba(1, 0.2, 0.2, 0.3) }
        Rectangle { anchors.fill: parent; radius: width / 2; color: "#ff3b3b" }
    }

    // mouche (grenouille)
    Prop {
        id: fly
        property real fx: 0
        property real fy: 0
        property real t: 0
        property bool caught: false
        property bool fleeing: false
        x: fx - 3 * w.k
        y: fy - 2 * w.k
        width: 6 * w.k
        height: 4 * w.k
        function enter() {
            fx = w.px < w.width / 2 ? w.width + 20 : -20
            fy = w.gy - 90
            caught = false
            on = true
        }
        function dodge() {
            fleeing = true
            w.later(700, () => { fly.fleeing = false })
        }
        FrameAnimation {
            running: fly.on
            onTriggered: {
                const dt = Math.min(0.05, frameTime), f = fly
                f.t += dt
                if (f.caught) {
                    f.fx = w.mouthX() + Math.cos(pet.tongueAngle * Math.PI / 180) * pet.tongue * w.dir
                    f.fy = w.mouthY() + Math.sin(pet.tongueAngle * Math.PI / 180) * pet.tongue
                    if (pet.tongue < 2)
                        f.opacity = 0
                    return
                }
                const tx = w.px + w.dir * 50 + Math.sin(f.t * 2.1) * 40 + Math.sin(f.t * 7) * 10
                const ty = w.gy - 70 - Math.abs(Math.sin(f.t * 1.3)) * 30 - (f.fleeing ? 60 : 0)
                f.fx += (tx - f.fx) * Math.min(1, dt * 2.5)
                f.fy += (ty - f.fy) * Math.min(1, dt * 2.5) + Math.sin(f.t * 23) * 0.8
                w.lookAt(f.fx, f.fy)
            }
        }
        onOnChanged: if (on) opacity = Qt.binding(() => fly.on ? 1 : 0)
        Rectangle { x: 1.6 * w.k; y: 1 * w.k; width: 2.8 * w.k; height: 2.4 * w.k; radius: width / 2; color: "#2b2b33" }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                x: (index ? 3 : 0.6) * w.k
                y: 0
                width: 2.4 * w.k
                height: 1.6 * w.k
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.65)
                SequentialAnimation on rotation {
                    running: fly.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: index ? 30 : -30; duration: 40 }
                    NumberAnimation { to: 0; duration: 40 }
                }
            }
        }
    }

    // carotte (lapin)
    Prop {
        id: carrot
        property real cx: 0
        property real lift: 0
        function place(x) {
            cx = x
            lift = 0
            on = true
        }
        function pull() {
            pullA.restart()
        }
        NumberAnimation { id: pullA; target: carrot; property: "lift"; to: 8 * w.k; duration: 700; easing.type: Easing.OutBack }
        x: cx - 3 * w.k
        y: w.gy - 4 * w.k - lift
        width: 6 * w.k
        height: 12 * w.k
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: "#6cc56b"
                PathSvg { path: "M3 3 Q1 0 1.6 -2 Q3 0 3 3 Z M3 3 Q5 0 4.6 -2.4 Q3.4 0 3 3 Z M3 3 Q3 -1 3.2 -3 Q2.6 0 3 3 Z" }
            }
            ShapePath {
                scale: Qt.size(w.k, w.k)
                strokeWidth: -1
                fillColor: "#ff8a3c"
                PathSvg { path: "M0.6 3 L5.4 3 L3 12 Z" }
            }
        }
    }

    // mini-blobs (division)
    Prop {
        id: minis
        anchors.fill: parent
        property real spread: 0
        property real hop: 0
        function split() {
            spread = 0
            on = true
            splitA.restart()
        }
        function merge() {
            mergeA.restart()
        }
        SequentialAnimation {
            id: splitA
            NumberAnimation { target: minis; property: "spread"; to: 50; duration: 500; easing.type: Easing.OutQuad }
            SequentialAnimation {
                loops: 4
                NumberAnimation { target: minis; property: "hop"; to: 14; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: minis; property: "hop"; to: 0; duration: 220; easing.type: Easing.OutBounce }
            }
        }
        NumberAnimation { id: mergeA; target: minis; property: "spread"; to: 0; duration: 700; easing.type: Easing.InBack }
        Repeater {
            model: minis.on ? 2 : 0
            Pet {
                required property int index
                k: w.k * 0.62
                listen: false
                look: index ? -1 : 1
                x: w.px + (index ? 1 : -1) * minis.spread - width / 2
                y: w.gy - height - (index ? minis.hop : 14 - minis.hop)
            }
        }
    }

    // faisceau (robot)
    Prop {
        id: beam
        anchors.fill: parent
        property real sweep: 0
        SequentialAnimation on sweep {
            running: beam.visible
            loops: Animation.Infinite
            NumberAnimation { from: -1; to: 1; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: -1; duration: 900; easing.type: Easing.InOutSine }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: w.px; y1: w.gy - w.ph * 0.55
                    x2: w.px; y2: w.gy
                    GradientStop { position: 0; color: Qt.rgba(0.43, 0.95, 1, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(0.43, 0.95, 1, 0.05) }
                }
                PathSvg {
                    readonly property real ex: w.px + w.dir * (4 + beam.sweep * 30) * w.k
                    path: `M${w.px} ${w.gy - w.ph * 0.55} L${ex - 10 * w.k} ${w.gy} L${ex + 10 * w.k} ${w.gy} Z`
                }
            }
        }
    }
    Prop {
        id: battery
        x: w.px - 5 * w.k
        y: w.headY() - 14 * w.k
        width: 10 * w.k
        height: 5 * w.k
        property real lvl: 0
        NumberAnimation on lvl {
            running: battery.visible
            from: 0
            to: 1
            duration: 2200
        }
        Rectangle {
            anchors.fill: parent
            radius: 1 * w.k
            color: "transparent"
            border.width: 0.7 * w.k
            border.color: "#ffffff"
            Rectangle {
                x: 1 * w.k
                y: 1 * w.k
                height: parent.height - 2 * w.k
                width: (parent.width - 2 * w.k) * battery.lvl
                radius: 0.4 * w.k
                color: battery.lvl < 0.3 ? "#ff5d5d" : battery.lvl < 0.7 ? "#ffd84a" : "#5ee08a"
            }
        }
        Rectangle { x: parent.width; y: parent.height * 0.3; width: 1 * w.k; height: parent.height * 0.4; color: "#ffffff" }
    }

    // glace (pingouin)
    Prop {
        id: ice
        property real a: 0
        property real b: 0
        function place(from, to) {
            a = Math.min(from, to) - 30
            b = Math.max(from, to) + 30
            on = true
        }
        x: a
        y: w.gy - 2 * w.k
        width: b - a
        height: 4 * w.k
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(0.75, 0.9, 1, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.8)
        }
    }

    // graines (poussin) et bebes champignons
    Repeater {
        id: seeds
        model: []
        Rectangle {
            required property var modelData
            property bool eaten: w.eaten.indexOf(modelData) >= 0
            visible: !eaten
            x: modelData - width / 2
            y: w.gy - height
            width: 2 * w.k
            height: 1.4 * w.k
            radius: height / 2
            color: "#c8925a"
        }
    }
    property var eaten: []
    onSceneChanged: eaten = []
    function eatSeed(x) {
        eaten = eaten.concat([seeds.model.reduce((b, s) => Math.abs(s - x) < Math.abs(b - x) ? s : b, 1e9)])
    }
    Repeater {
        id: babies
        model: []
        Pet {
            id: baby
            required property var modelData
            required property int index
            k: w.k * 0.45
            listen: false
            species: "mush"
            hat: "none"
            faceAcc: "none"
            neck: "none"
            x: modelData - width / 2
            y: w.gy - height
            scale: 0
            transformOrigin: Item.Bottom
            Component.onCompleted: babyA.start()
            NumberAnimation { id: babyA; target: baby; property: "scale"; to: 1; duration: 500; easing.type: Easing.OutBack }
        }
    }

    // ===================================================== compagnon
    Item {
        id: walker
        x: w.px - w.pw / 2
        y: w.gy - w.ph + w.py + (w.floating ? Math.sin(w.floatPhase) * 4 * w.k : 0) + (w.swim ? Math.sin(w.floatPhase * 3) * 6 * w.k : 0)
        width: w.pw
        height: w.ph
        transform: [
            Scale {
                origin.x: w.pw / 2
                origin.y: w.ph
                xScale: w.poseSx
                yScale: w.poseSy
            },
            Rotation {
                origin.x: w.pw / 2
                origin.y: w.ph
                angle: w.poseRot
            }
        ]
        Pet {
            id: pet
            k: w.k
            listen: false
            look: 0
            mood: w.petMood
            walking: w.walking && !w.riding
            transform: Scale {
                origin.x: pet.width / 2
                xScale: w.dir
            }
        }
    }

    property Component timerComp: Component { Timer {} }
    function later(ms, fn) {
        const t = timerComp.createObject(w, { interval: ms })
        t.triggered.connect(() => {
            fn()
            t.destroy()
        })
        t.start()
    }
}
