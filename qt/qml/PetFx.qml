import QtQuick

// Moteur d'effets des compagnons en pack (PackStage.qml) : eclairs, orbes,
// anneaux, impacts, etincelles, braises, fumee, poussiere, tremblement...
// Deux Canvas (derriere et devant le sprite, qu'on met entre les deux comme
// enfant : default property). Les couleurs sont des chaines "r,g,b".
//
// Rien ne tourne au repos : l'horloge (FrameAnimation) ne marche que tant
// qu'il reste une tache (tween, attente, every) ou un effet, et les Canvas ne
// sont peints (et visibles) que s'ils ont quelque chose a montrer.
//
// Cout : les Canvas sont repeints 60 fois par seconde au plus, et chacun
// n'occupe que la bande horizontale utile (pleine hauteur), arrondie a 256 px.
// Chaque effet peut donner sa bande par box() -> [x0, x1] (null : ne dessine
// rien) ; un effet sans box() demande toute la largeur. Les briques ci-dessous
// renseignent box() elles-memes.
//
// Les attaques s'ecrivent en generateurs lances par co() : on y fait
// « yield fx.wait(300) » ou « yield fx.tween(...) » la ou on ferait
// « await » (QML n'a pas async/await). Toutes les tailles se multiplient
// par u (echelle des effets, 1 pour un sprite de 240 px).
Item {
    id: fxr

    default property alias content: mid.data
    property var pet: null            // SpritePet
    property real u: 1
    property real groundY: height - 4
    // lueur autour du sprite (sous lui), 0 a 1
    property real aura: 0
    property string auraRgb: "120,205,255"
    property string auraAnchor: "chest"
    property real now: 0              // horloge des effets (s)
    property var c: null              // contexte en cours de dessin
    readonly property bool live: _live

    property bool _live: false
    property real _shake: 0
    property int _epoch: 0
    property var _tasks: []
    property var _fx: []
    property var _ps: []
    property bool _backDrawn: false
    property bool _frontDrawn: false
    property var _cache: ({})
    property real _sincePaint: 1

    transform: Translate { id: shk }
    onAuraChanged: if (aura > 0.01) _kick()

    Canvas {
        id: back
        width: fxr.width
        height: fxr.height
        visible: false
        onPaint: fxr._paint(back, true)
    }
    Item {
        id: mid
        anchors.fill: parent
    }
    Canvas {
        id: front
        width: fxr.width
        height: fxr.height
        visible: false
        onPaint: fxr._paint(front, false)
    }
    FrameAnimation {
        running: fxr._live
        onTriggered: fxr._tick(Math.min(0.05, Math.max(0, frameTime)))
    }

    // ------------------------------------------------------------ outils
    function rand(a, b) { return a + Math.random() * (b - a) }
    function pick(a) { return a[Math.floor(Math.random() * a.length)] }
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
    function lerp(a, b, t) { return a + (b - a) * t }
    function ease(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2 }
    function easeOut(t) { return 1 - Math.pow(1 - t, 3) }
    function easeIn(t) { return t * t * t }
    function linear(t) { return t }

    function _kick() {
        if (!_live)
            _live = true
    }

    // ------------------------------------------------------------ temps
    // tween(ms, fn(e, t), easing) : Promise ; fn est appele tout de suite avec 0
    function tween(ms, fn, e) {
        const ez = e || ease
        return new Promise(res => {
            fn(ez(0), 0)
            _tasks.push({ kind: "tween", el: 0, ms: Math.max(1, ms), fn: fn, ez: ez, res: res })
            _kick()
        })
    }
    function wait(ms) {
        return new Promise(res => {
            _tasks.push({ kind: "wait", el: 0, ms: ms, res: res })
            _kick()
        })
    }
    function after(ms, fn) {
        const t = { kind: "wait", el: 0, ms: ms, res: fn }
        _tasks.push(t)
        _kick()
        return () => { t.dead = true }
    }
    // fn tout de suite, puis toutes les ms ; rend la fonction d'arret
    function every(ms, fn) {
        fn()
        const t = { kind: "every", acc: 0, ms: Math.max(1, ms), fn: fn }
        _tasks.push(t)
        _kick()
        return () => { t.dead = true }
    }
    // lance un generateur ; chaque valeur produite (Promise, tableau de
    // Promise...) est attendue. Rend une Promise. reset() l'abandonne.
    function co(gen) {
        const epoch = _epoch
        return new Promise((ok, ko) => {
            let it
            try {
                it = gen()
            } catch (e) {
                ko(e)
                return
            }
            const nx = v => {
                if (epoch !== fxr._epoch)
                    return
                let r
                try {
                    r = it.next(v)
                } catch (e) {
                    ko(e)
                    return
                }
                if (r.done) {
                    ok(r.value)
                    return
                }
                const p = Array.isArray(r.value) ? Promise.all(r.value) : Promise.resolve(r.value)
                p.then(nx, ko)
            }
            nx()
        })
    }
    // tout arreter : effets, taches, coroutines en cours
    function reset() {
        _epoch++
        _tasks = []
        _fx = []
        _ps = []
        _shake = 0
        aura = 0
        shk.x = 0
        shk.y = 0
        _live = false
        _clear()
    }

    // ------------------------------------------------------------ sprite
    function play(name, fps, from, to) {
        return new Promise(res => {
            if (!pet) {
                res()
                return
            }
            pet.play(name, fps, from, to, res)
        })
    }
    // boucle ; rend la fonction d'arret (l'image en cours reste)
    function loopAnim(name, fps) {
        if (pet)
            pet.loop(name, fps)
        return () => { if (pet && pet.mode === "loop" && pet.anim === name) pet.hold() }
    }
    function at(name, dx, dy) {
        return pet ? pet.at(name, dx, dy) : [width / 2, groundY]
    }
    function petW() {
        return pet ? pet.fw : 60
    }
    // se tourne vers le cote le plus long s'il manque de place devant
    function faceRoom(need) {
        if (!pet)
            return
        const room = pet.dir > 0 ? width - pet.px : pet.px
        if (room < need)
            pet.dir = -pet.dir
    }
    function trailPush(rgb) {
        if (pet)
            pet.ghost(rgb || "190,240,255")
    }

    // ------------------------------------------------------------ effets
    // o : { life (s), layer: "back"|"front", upd(dt) -> false pour finir, draw(ctx) }
    function add(o) {
        o.t = 0
        o.layer = o.layer || "front"
        _fx.push(o)
        _kick()
        return o
    }
    function spawn(p) {
        p.age = 0
        p.drag = p.drag || 0
        p.g = p.g || 0
        _ps.push(p)
        _kick()
        return p
    }
    function shake(a) {
        _shake = Math.max(_shake, a)
        _kick()
    }

    function sparks(x, y, n, o) {
        o = o || {}
        for (let i = 0; i < n; i++) {
            const a = o.angle !== undefined ? o.angle + rand(-o.spread, o.spread) : rand(0, Math.PI * 2)
            const v = rand(o.vmin || 120, o.vmax || 420) * u
            spawn({ kind: "streak", x: x, y: y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: rand(0.25, o.life || 0.6),
                    size: rand(1.2, 2.6) * u, rgb: o.rgb || "190,240,255", drag: 3, g: (o.g === undefined ? 300 : o.g) * u })
        }
    }
    function embers(x, y, n, rgb, o) {
        o = o || {}
        for (let i = 0; i < n; i++) {
            const a = rand(0, Math.PI * 2), v = rand(20, o.v || 160) * u
            spawn({ kind: "dot", x: x, y: y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - (o.up || 0) * u, life: rand(0.3, o.life || 0.9),
                    size: rand(2, o.size || 6) * u, rgb: rgb, drag: 2, g: (o.g || 0) * u })
        }
    }
    function smoke(x, y, n, o) {
        o = o || {}
        for (let i = 0; i < n; i++)
            spawn({ kind: "smoke", x: x + rand(-10, 10) * u, y: y + rand(-4, 4) * u, vx: rand(-1, 1) * (o.v || 60) * u, vy: -rand(5, o.up || 40) * u,
                    life: rand(0.6, o.life || 1.4), size: rand(10, o.size || 26) * u, grow: o.grow || 1.8, rgb: o.rgb || "120,125,140",
                    a0: o.a || 0.45, drag: 1.5, back: true })
    }
    function dust(x, n) {
        smoke(x, groundY - 2, n === undefined ? 14 : n, { v: 120, up: 25, size: 18, life: 0.9, rgb: "150,150,165", a: 0.5 })
    }
    // particules qui convergent vers un point
    function converge(x, y, r, rgb, n) {
        n = n === undefined ? 3 : n
        for (let i = 0; i < n; i++) {
            const a = rand(0, Math.PI * 2), d = r * rand(0.7, 1.3), life = rand(0.3, 0.55)
            spawn({ kind: "dot", x: x + Math.cos(a) * d, y: y + Math.sin(a) * d, vx: -Math.cos(a) * d / life, vy: -Math.sin(a) * d / life,
                    life: life, size: rand(1.5, 3.5) * u, rgb: rgb, fadeIn: true })
        }
    }

    // eclairs : deplacement du point milieu + branches
    function boltPaths(x1, y1, x2, y2, disp, depth, branches) {
        let pts = [[x1, y1], [x2, y2]]
        for (let d = 0; d < depth; d++) {
            const np = [pts[0]]
            for (let i = 0; i < pts.length - 1; i++) {
                const a = pts[i], b = pts[i + 1], dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy) || 1
                const o = rand(-disp, disp)
                np.push([(a[0] + b[0]) / 2 - dy / L * o, (a[1] + b[1]) / 2 + dx / L * o], b)
            }
            pts = np
            disp *= 0.55
        }
        const paths = [pts]
        for (let b = 0; b < branches; b++) {
            const i = Math.floor(rand(pts.length * 0.2, pts.length * 0.8)), s = pts[i]
            const ang = Math.atan2(y2 - y1, x2 - x1) + rand(-0.9, 0.9), L = Math.hypot(x2 - x1, y2 - y1) * rand(0.15, 0.4)
            const sub = boltPaths(s[0], s[1], s[0] + Math.cos(ang) * L, s[1] + Math.sin(ang) * L, disp * 2.2, Math.max(2, depth - 2), 0)
            for (const p of sub) {
                p.br = 1
                paths.push(p)
            }
        }
        return paths
    }
    function strokePaths(paths, w, rgb, a) {
        const g = c
        g.save()
        g.globalCompositeOperation = "lighter"
        g.lineJoin = "round"
        g.lineCap = "round"
        const layers = [[7, rgb, 0.04], [4, rgb, 0.08], [2.2, rgb, 0.25], [1, rgb, 0.9], [0.42, "255,255,255", 1]]
        for (const l of layers) {
            for (const p of paths) {
                g.lineWidth = w * l[0] * (p.br ? 0.5 : 1)
                g.strokeStyle = "rgba(" + l[1] + "," + (l[2] * a * (p.br ? 0.8 : 1)) + ")"
                g.beginPath()
                g.moveTo(p[0][0], p[0][1])
                for (let i = 1; i < p.length; i++)
                    g.lineTo(p[i][0], p[i][1])
                g.stroke()
            }
        }
        g.restore()
    }
    function bolt(x1, y1, x2, y2, o) {
        o = o || {}
        const L = Math.hypot(x2 - x1, y2 - y1)
        const make = () => boltPaths(x1, y1, x2, y2, o.disp !== undefined ? o.disp : L * 0.18, o.depth || 6, o.branches !== undefined ? o.branches : 2)
        let paths = make(), acc = 0
        const pad = (o.w || 3) * u * 4
        return add({ life: o.life || 0.25, layer: o.layer,
            box() {
                let a = 1e9, b = -1e9
                for (const p of paths)
                    for (const q of p) {
                        if (q[0] < a) a = q[0]
                        if (q[0] > b) b = q[0]
                    }
                return [a - pad, b + pad]
            },
            upd(dt) {
                acc += dt
                if (acc > (o.flick || 0.05)) {
                    acc = 0
                    paths = make()
                }
            },
            draw() {
                const t = this.t / this.life
                fxr.strokePaths(paths, (o.w || 3) * fxr.u, o.rgb || "120,205,255", (o.alpha || 1) * (1 - t * t * t))
            } })
    }
    // petits arcs sur le corps du sprite
    function bodyArc(rgb) {
        if (!pet)
            return
        const ch = at("chest"), w = pet.fw, h = pet.fh
        const x = ch[0] + rand(-0.32, 0.32) * w, y = ch[1] + rand(-0.38, 0.42) * h, a = rand(0, Math.PI * 2), L = rand(14, 34) * u
        bolt(x, y, x + Math.cos(a) * L, y + Math.sin(a) * L, { life: rand(0.08, 0.16), w: 1.4, depth: 4, branches: 0, rgb: rgb || "120,205,255" })
    }
    function ring(x, y, r0, r1, life, rgb, w, sy) {
        w = w || 4
        sy = sy || 1
        return add({ life: life, box: () => [x - r1 - w * u * 3, x + r1 + w * u * 3], draw() {
            const g = fxr.c, e = fxr.easeOut(this.t / this.life)
            g.save()
            g.globalCompositeOperation = "lighter"
            g.translate(x, y)
            g.scale(1, sy)
            for (const l of [[3, 0.18], [1, 0.9]]) {
                g.lineWidth = w * fxr.u * l[0] * (1 - e * 0.7)
                g.strokeStyle = "rgba(" + rgb + "," + (l[1] * (1 - e)) + ")"
                g.beginPath()
                g.arc(0, 0, fxr.lerp(r0, r1, e), 0, Math.PI * 2, false)
                g.stroke()
            }
            g.restore()
        } })
    }
    // brulure au sol
    function scorch(x, r, rgb, life) {
        return add({ layer: "back", life: life || 1.6, box: () => [x - r * 1.3, x + r * 1.3], draw() {
            const t = this.t / this.life
            fxr.glow(x, fxr.groundY - 2, r * (1 + t * 0.3), rgb, 0.8 * (1 - t), 0.22)
        } })
    }
    // orbe d'energie : coeur, halo, anneaux qui tournent, arcs en surface.
    // Rend { x, y, r, a, kill() } a piloter.
    function orbFx(rgb, rgb2, o) {
        o = o || {}
        const st = { x: 0, y: 0, r: 0, a: 1, spin: 0, arcs: o.arcs !== false, dead: false }
        let arcT = 0, arcs = []
        st.fx = add({ life: 1e9,
            box: () => st.r > 0 ? [st.x - st.r * 2.7, st.x + st.r * 2.7] : null,
            upd(dt) {
                if (st.dead)
                    return false
                st.spin += dt * (o.spinSpeed || 5)
                arcT += dt
                if (st.arcs && arcT > 0.06 && st.r > 4) {
                    arcT = 0
                    arcs = []
                    for (let i = 0; i < 3; i++) {
                        const a1 = fxr.rand(0, 6.3), a2 = a1 + fxr.rand(0.6, 1.8)
                        arcs.push(fxr.boltPaths(st.x + Math.cos(a1) * st.r * 0.9, st.y + Math.sin(a1) * st.r * 0.9,
                                              st.x + Math.cos(a2) * st.r * 0.9, st.y + Math.sin(a2) * st.r * 0.9, st.r * 0.25, 4, 0))
                    }
                }
                return true
            },
            draw() {
                if (st.r <= 0)
                    return
                const g = fxr.c, r = st.r, a = st.a
                fxr.glow(st.x, st.y, r * 2.6, rgb, 0.55 * a)
                fxr.glow(st.x, st.y, r * 1.2, rgb2, 0.9 * a)
                g.save()
                g.globalCompositeOperation = "lighter"
                g.translate(st.x, st.y)
                for (let i = 0; i < 3; i++) {
                    g.save()
                    g.rotate(st.spin * (i % 2 ? -1 : 1) + i * 1.05)
                    g.scale(1, 0.35)
                    g.lineWidth = 2 * fxr.u
                    g.strokeStyle = "rgba(" + rgb2 + "," + (0.7 * a) + ")"
                    g.beginPath()
                    g.arc(0, 0, r * 1.05, 0, Math.PI * 1.3, false)
                    g.stroke()
                    g.restore()
                }
                g.restore()
                for (const p of arcs)
                    fxr.strokePaths(p, 1.3 * fxr.u, rgb, a)
            } })
        st.kill = () => { st.dead = true }
        return st
    }
    // impact : flash, anneaux, eclairs, etincelles, braises, brulure, poussiere
    function boom(x, y, o) {
        o = o || {}
        const rgb = o.rgb || "120,205,255", rgb2 = o.rgb2 || "190,240,255", big = o.big || 1
        shake(9 * big * u)
        add({ life: 0.35, box: () => [x - 240 * u * big, x + 240 * u * big], draw() {
            const e = this.t / this.life
            fxr.glow(x, y, 120 * fxr.u * big * (1 + e), rgb2, 1 - e)
        } })
        ring(x, y, 6, 150 * u * big, 0.55, rgb2, 5)
        ring(x, groundY - 2, 10, 210 * u * big, 0.7, rgb, 4, 0.22)
        if (o.bolts !== false)
            for (let i = 0; i < 8; i++) {
                const a = rand(0, Math.PI * 2), L = rand(70, 150) * u * big
                bolt(x, y, x + Math.cos(a) * L, y + Math.sin(a) * L, { life: rand(0.18, 0.32), w: 2.4, branches: 1, rgb: rgb })
            }
        sparks(x, y, Math.round(40 * big), { rgb: rgb2, vmax: 520 * big, life: 0.7 })
        embers(x, y, 18, rgb, { v: 220, life: 0.8 })
        scorch(x, 120 * u * big, rgb)
        dust(x, 16)
    }

    // ------------------------------------------------------------ dessin
    // degrades radiaux unitaires, en cache par contexte et par couleur
    function _grad(kind, rgb) {
        const key = (c === back.context ? "b" : "f") + kind + rgb
        let gr = _cache[key]
        if (gr)
            return gr
        gr = c.createRadialGradient(0, 0, 0, 0, 0, 1)
        if (kind === "g") {
            gr.addColorStop(0, "rgba(255,255,255,1)")
            gr.addColorStop(0.18, "rgba(" + rgb + ",1)")
            gr.addColorStop(0.5, "rgba(" + rgb + ",0.35)")
            gr.addColorStop(1, "rgba(" + rgb + ",0)")
        } else {
            gr.addColorStop(0, "rgba(" + rgb + ",1)")
            gr.addColorStop(0.55, "rgba(" + rgb + ",0.55)")
            gr.addColorStop(1, "rgba(" + rgb + ",0)")
        }
        _cache[key] = gr
        return gr
    }
    // lueur additive (coeur blanc) de rayon r ; sy aplatit verticalement
    function glow(x, y, r, rgb, a, sy) {
        if (a === undefined)
            a = 1
        if (a <= 0 || r <= 0)
            return
        const g = c
        g.save()
        g.globalCompositeOperation = "lighter"
        g.globalAlpha = clamp(a, 0, 1)
        g.translate(x, y)
        g.scale(r, r * (sy || 1))
        g.fillStyle = _grad("g", rgb)
        g.fillRect(-1, -1, 2, 2)
        g.restore()
    }
    // tache douce (fumee, nuage, ombre), melange normal
    function soft(x, y, r, rgb, a) {
        if (a <= 0 || r <= 0)
            return
        const g = c
        g.save()
        g.globalAlpha = clamp(a, 0, 1)
        g.translate(x, y)
        g.scale(r, r)
        g.fillStyle = _grad("s", rgb)
        g.fillRect(-1, -1, 2, 2)
        g.restore()
    }

    function _tick(dt) {
        now += dt
        // taches (les rappels peuvent en ajouter : on garde les nouvelles)
        const ts = _tasks
        _tasks = []
        const keep = []
        for (const t of ts) {
            if (t.dead)
                continue
            try {
                if (t.kind === "tween") {
                    t.el += dt * 1000
                    const p = Math.min(1, t.el / t.ms)
                    t.fn(t.ez(p), p)
                    if (p >= 1)
                        t.res()
                    else
                        keep.push(t)
                } else if (t.kind === "wait") {
                    t.el += dt * 1000
                    if (t.el >= t.ms)
                        t.res()
                    else
                        keep.push(t)
                } else {
                    t.acc += dt * 1000
                    let n = 0
                    while (t.acc >= t.ms && n < 3 && !t.dead) {
                        t.acc -= t.ms
                        t.fn()
                        n++
                    }
                    if (n >= 3)
                        t.acc = 0
                    if (!t.dead)
                        keep.push(t)
                }
            } catch (e) {
                // tache fautive abandonnee ; les autres continuent
                console.warn("PetFx:", e)
            }
        }
        _tasks = keep.concat(_tasks)
        // effets
        const fs = _fx
        for (let i = fs.length - 1; i >= 0; i--) {
            const f = fs[i]
            f.t += dt
            let end = f.t >= f.life
            try {
                if (f.upd && f.upd(dt) === false)
                    end = true
            } catch (e) {
                console.warn("PetFx:", e)
                end = true
            }
            if (end)
                fs.splice(i, 1)
        }
        // particules
        const ps = _ps, gy = groundY
        for (let i = ps.length - 1; i >= 0; i--) {
            const p = ps[i]
            p.age += dt
            if (p.age >= p.life) {
                ps.splice(i, 1)
                continue
            }
            p.vx *= 1 - p.drag * dt
            p.vy *= 1 - p.drag * dt
            p.vy += p.g * dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            if (p.kind === "streak" && p.y > gy) {
                p.y = gy
                p.vy *= -0.35
            }
        }
        // tremblement de toute la scene (sprite compris)
        _shake = Math.max(0, _shake - dt * 22)
        if (_shake > 0.2) {
            shk.x = rand(-1, 1) * _shake
            shk.y = rand(-1, 1) * _shake * 0.6
        } else {
            shk.x = 0
            shk.y = 0
        }
        // peinture, seulement si un calque a (ou avait) quelque chose
        let hb = aura > 0.01, hf = false
        for (const f of fs) {
            if (f.layer === "back") hb = true
            else hf = true
        }
        for (const p of ps) {
            if (p.back) hb = true
            else hf = true
        }
        _sincePaint += dt
        const paintNow = _sincePaint >= 1 / 60 - 0.002
        if (paintNow)
            _sincePaint = 0
        if (paintNow && (hb || _backDrawn)) {
            _fit(back, true)
            back.visible = true
            back.requestPaint()
        }
        if (paintNow && (hf || _frontDrawn)) {
            _fit(front, false)
            front.visible = true
            front.requestPaint()
        }
        if (!_tasks.length && !fs.length && !ps.length && _shake <= 0 && aura <= 0.01 && !hb && !hf) {
            _live = false
            back.visible = false
            front.visible = false
            _backDrawn = false
            _frontDrawn = false
        }
    }
    // bande horizontale utile d'un calque, arrondie a 256 px (moins de
    // changements de taille, donc de reallocations du Canvas)
    function _fit(cv, isBack) {
        let a = 1e9, b = -1e9, full = false
        const grow = (x0, x1) => {
            if (x0 < a) a = x0
            if (x1 > b) b = x1
        }
        for (const f of _fx) {
            if ((f.layer === "back") !== isBack)
                continue
            if (!f.box) {
                full = true
                break
            }
            let r = null
            try {
                r = f.box()
            } catch (e) {
                full = true
                break
            }
            if (r)
                grow(r[0], r[1])
        }
        if (!full) {
            for (const p of _ps) {
                if (!!p.back !== isBack)
                    continue
                const m = p.kind === "smoke" ? p.size * (1 + p.grow) : p.kind === "streak" ? Math.abs(p.vx) * 0.035 + p.size : p.size * 2.5
                grow(p.x - m, p.x + m)
            }
            if (isBack && aura > 0.01 && pet)
                grow(pet.px - pet.fh * 0.7, pet.px + pet.fh * 0.7)
        }
        let x0 = 0, x1 = width
        if (!full && b > a) {
            x0 = Math.max(0, Math.floor((a - 8) / 256) * 256)
            x1 = Math.min(width, Math.ceil((b + 8) / 256) * 256)
        }
        if (x1 <= x0)
            x1 = Math.min(width, x0 + 256)
        cv.x = x0
        cv.width = x1 - x0
    }
    function _clear() {
        back.visible = false
        front.visible = false
        _backDrawn = false
        _frontDrawn = false
    }
    function _paint(cv, isBack) {
        const g = cv.getContext("2d")
        c = g
        g.setTransform(1, 0, 0, 1, 0, 0)
        g.globalCompositeOperation = "source-over"
        g.globalAlpha = 1
        g.clearRect(0, 0, cv.width, cv.height)
        g.translate(-cv.x, 0)
        let drew = false
        for (const f of _fx) {
            if ((f.layer === "back") !== isBack)
                continue
            drew = true
            try {
                f.draw(g)
            } catch (e) {
                console.warn("PetFx:", e)
                f.t = f.life
            }
        }
        for (const p of _ps) {
            if (!!p.back !== isBack)
                continue
            drew = true
            _drawParticle(g, p)
        }
        if (isBack && aura > 0.01 && pet) {
            drew = true
            const ch = pet.at(auraAnchor)
            glow(ch[0], ch[1], pet.fh * 0.62, auraRgb, aura * 0.55)
        }
        if (isBack)
            _backDrawn = drew
        else
            _frontDrawn = drew
    }
    function _drawParticle(g, p) {
        const t = p.age / p.life, a = p.fadeIn ? Math.sin(t * Math.PI) : 1 - t
        if (p.kind === "streak") {
            g.save()
            g.globalCompositeOperation = "lighter"
            g.lineCap = "round"
            g.strokeStyle = "rgba(" + p.rgb + "," + a + ")"
            g.lineWidth = p.size
            g.beginPath()
            g.moveTo(p.x, p.y)
            g.lineTo(p.x - p.vx * 0.035, p.y - p.vy * 0.035)
            g.stroke()
            g.restore()
        } else if (p.kind === "dot") {
            glow(p.x, p.y, p.size * 2.2, p.rgb, a)
        } else if (p.kind === "rock") {
            g.save()
            g.globalAlpha = Math.min(1, t * 4) * (1 - t)
            g.fillStyle = "rgb(62,60,78)"
            g.strokeStyle = "rgba(" + (p.edge || "90,230,255") + ",0.8)"
            g.lineWidth = 0.8
            g.translate(p.x, p.y)
            g.rotate(p.age * 2)
            g.fillRect(-p.size, -p.size * 0.7, p.size * 2, p.size * 1.4)
            g.strokeRect(-p.size, -p.size * 0.7, p.size * 2, p.size * 1.4)
            g.restore()
        } else if (p.kind === "smoke") {
            soft(p.x, p.y, p.size * (1 + t * p.grow), p.rgb, p.a0 * (1 - t))
        }
    }
}
