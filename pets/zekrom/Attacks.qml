import QtQuick

// Attaques de Zekrom (pack hors depot, usage personnel). Portage de
// %USERPROFILE%\.ilot\zekrom\zekrom.html : chaque attaque est un generateur
// lance par fx.co() ; « yield » remplace « await ».
// Contrat avec PackStage.qml : proprietes fx (PetFx), sprite (SpritePet),
// stage (PackStage) et liste « list » de { id, name, run }.
QtObject {
    id: root
    property var fx: null
    property var sprite: null
    property var stage: null

    readonly property string elec: "120,205,255"
    readonly property string elec2: "190,240,255"
    readonly property string dragon: "150,110,255"
    readonly property string dragon2: "90,230,255"
    readonly property string fire: "255,140,60"
    readonly property string fire2: "255,220,120"

    readonly property var list: [
        { id: "chargeFoudre", name: "Charge Foudre", run: () => root.chargeFoudre() },
        { id: "eclairCroix", name: "Éclair Croix", run: () => root.eclairCroix() },
        { id: "dracoChoc", name: "Draco-Choc", run: () => root.dracoChoc() },
        { id: "dracoMeteore", name: "Draco-Météore", run: () => root.dracoMeteore() },
        { id: "fatalFoudre", name: "Fatal-Foudre", run: () => root.fatalFoudre() }
    ]

    // les generateurs (QML n'accepte pas « function* » comme methode)
    readonly property var gens: ({
        // Charge Foudre : la turbine s'emballe, l'electricite l'enveloppe, il fonce et percute
        chargeFoudre: function* () {
            const F = root.fx, S = root.sprite, u = F.u, ELEC = root.elec, ELEC2 = root.elec2
            F.faceRoom(F.petW() * 2.4)
            const orb = F.orbFx(ELEC, ELEC2, { spinSpeed: 14 })
            F.play("charge", 9)
            const sConv = F.every(35, () => { const p = F.at("turbine"); orb.x = p[0]; orb.y = p[1]; F.converge(p[0], p[1], 80 * u, ELEC2, 2) })
            const sArcs = F.every(55, () => F.bodyArc(ELEC))
            yield F.tween(1600, e => {
                const p = F.at("turbine"); orb.x = p[0]; orb.y = p[1]; orb.r = 22 * u * e
                F.aura = e; S.tint = 0.12 + 0.25 * e * Math.random(); F.shake(1.5 * e)
            })
            sConv()
            F.dust(S.px, 18); F.shake(6 * u)
            const stopDash = F.loopAnim("dash", 24)
            S.tint = 0.35
            const x0 = S.px, dist = Math.min(F.petW() * 2.2, (S.dir > 0 ? F.width - S.px : S.px) - F.petW() * 0.6)
            let last = F.at("chest"), trailT = 0
            yield F.tween(460, e => {
                S.px = x0 + dist * S.dir * e
                const tp = F.at("turbine"); orb.x = tp[0]; orb.y = tp[1]
                const ch = F.at("chest")
                // allege : un eclair toutes les 3 images (au lieu de chaque image)
                if (++trailT % 4 === 0) F.trailPush(ELEC2)
                if (trailT % 3 === 0) {
                    F.bolt(last[0] - 40 * u * S.dir, last[1] + F.rand(-50, 50) * u, ch[0], ch[1] + F.rand(-50, 50) * u, { life: 0.24, w: 2.4, depth: 5, branches: 1, rgb: ELEC })
                    last = ch
                }
                if (trailT % 2 === 0)
                    F.sparks(ch[0], ch[1] + F.rand(-40, 40) * u, 4, { angle: S.dir > 0 ? Math.PI : 0, spread: 0.4, vmin: 200, vmax: 500, g: 0, rgb: ELEC2 })
            }, F.easeIn)
            stopDash(); sArcs()
            const hd = F.at("head", 40, 20)
            F.boom(hd[0] + 30 * u * S.dir, hd[1], { big: 1.25, rgb: ELEC, rgb2: ELEC2 })
            S.tint = 0
            const back = F.play("charge", 12, 11, 0)
            yield F.tween(900, e => { F.aura = 1 - e; orb.r = 22 * u * (1 - e); orb.a = 1 - e })
            orb.kill()
            yield back
        },

        // Eclair Croix : il s'entoure d'une sphere de plasma, bondit et explose en croix
        eclairCroix: function* () {
            const F = root.fx, S = root.sprite, u = F.u, ELEC = root.elec, ELEC2 = root.elec2
            F.faceRoom(F.petW() * 2.6)
            yield F.play("roar", 14, 0, 6)
            const orb = F.orbFx(ELEC, ELEC2, { spinSpeed: 8 })
            const sArcs = F.every(45, () => F.bodyArc(ELEC2))
            const sConv = F.every(30, () => { const p = F.at("chest"); F.converge(p[0], p[1], S.fh * 0.9, ELEC2, 3) })
            // des eclairs tombent sur lui depuis le haut
            const sSky = F.every(220, () => { const p = F.at("head"); F.bolt(p[0] + F.rand(-80, 80) * u, -10, p[0], p[1], { life: 0.2, w: 3, branches: 2, rgb: ELEC }) })
            yield F.tween(1300, e => { const p = F.at("chest"); orb.x = p[0]; orb.y = p[1]; orb.r = S.fh * 0.5 * F.easeOut(e); S.tint = 0.5 * e; F.aura = e })
            sSky(); sConv(); F.shake(5 * u)
            // bond : la sphere et lui traversent l'ecran en arc
            const stopDash = F.loopAnim("dash", 22)
            const x0 = S.px, dist = Math.min(F.petW() * 2.3, (S.dir > 0 ? F.width - S.px : S.px) - F.petW() * 0.6)
            let n = 0
            yield F.tween(620, e => {
                S.px = x0 + dist * S.dir * e; S.lift = Math.sin(e * Math.PI) * 120 * u
                const p = F.at("chest"); orb.x = p[0]; orb.y = p[1]
                if (++n % 4 === 0) F.trailPush(ELEC2)
                F.embers(p[0] - orb.r * 0.6 * S.dir, p[1], 3, ELEC2, { v: 80, life: 0.5 })
            }, F.ease)
            stopDash(); sArcs()
            S.lift = 0
            const cp = F.at("chest")
            const bx = cp[0] + 50 * u * S.dir, by = cp[1]
            orb.kill(); S.tint = 0
            // la croix : deux faisceaux qui s'etirent puis se resorbent
            F.boom(bx, by, { big: 1.4, rgb: ELEC, rgb2: ELEC2 })
            F.add({ life: 0.9, box: () => [bx - 400 * u, bx + 400 * u], draw(g) {
                const t = this.t / this.life, e = t < 0.25 ? F.easeOut(t / 0.25) : 1 - F.easeIn((t - 0.25) / 0.75)
                const Lh = 260 * u * e, Lv = 190 * u * e, w = 16 * u * e
                g.save(); g.globalCompositeOperation = "lighter"; g.lineCap = "round"
                for (const l of [[7, ELEC, 0.05], [4.5, ELEC, 0.1], [2.6, ELEC, 0.25], [1.5, ELEC2, 0.6], [0.9, ELEC2, 0.9], [0.4, "255,255,255", 1]]) {
                    g.strokeStyle = "rgba(" + l[1] + "," + l[2] + ")"; g.lineWidth = Math.max(0.01, w * l[0])
                    g.beginPath(); g.moveTo(bx - Lh, by); g.lineTo(bx + Lh, by); g.moveTo(bx, by - Lv); g.lineTo(bx, by + Lv * 0.55); g.stroke()
                }
                g.restore(); F.glow(bx, by, 70 * u * e, ELEC2, 1)
            } })
            for (let i = 0; i < 4; i++)
                F.bolt(bx, by, bx + [-1, 1, 0, 0][i] * 260 * u, by + [0, 0, -1, 0.55][i] * 190 * u, { life: 0.5, w: 3, branches: 2, rgb: ELEC })
            const back = F.play("charge", 16, 11, 0)
            yield F.tween(600, e => { F.aura = 1 - e })
            yield back
        },

        // Draco-Choc (comme dans les jeux) : energie draconique concentree dans
        // la gueule puis onde de choc en anneaux, tiree en biais vers le coin
        // haut le plus loin ; le flot s'efface avant le bord (pas de coupure)
        dracoChoc: function* () {
            const F = root.fx, S = root.sprite, u = F.u, DRAGON = root.dragon, DRAGON2 = root.dragon2
            S.dir = S.px < F.width / 2 ? 1 : -1          // il tire du cote le plus long
            yield F.play("beam", 14, 0, 6)
            // 1. charge : pierres qui levitent, spirale (sans aura autour de lui, a la demande de l'utilisateur)
            const orb = F.orbFx(DRAGON, DRAGON2, { spinSpeed: 9, arcs: false })
            const sRocks = F.every(90, () => F.spawn({ kind: "rock", x: S.px + F.rand(-1.2, 1.2) * F.petW(), y: F.groundY - 2, vx: F.rand(-8, 8) * u, vy: -F.rand(25, 60) * u,
                                                       life: F.rand(1.4, 2.2), size: F.rand(1.5, 3.5) * u, drag: 0.3, g: 0, back: true, edge: DRAGON2 }))
            const sSwirl = F.every(25, () => { const p = F.at("mouth"); root.swirl(p[0], p[1], 110 * u) })
            yield F.tween(1400, e => {
                const p = F.at("mouth"); orb.x = p[0]; orb.y = p[1]; orb.r = 24 * u * F.easeOut(e)
                F.shake(2 * e)
            })
            sSwirl()
            // 2. tir : l'onde file vers le coin haut le plus loin
            const mp = F.at("mouth"), mx = mp[0], my = mp[1], dir = S.dir
            const tx = dir > 0 ? F.width : 0, ang = Math.atan2(-my, tx - mx)
            const ca = Math.cos(ang), sa = Math.sin(ang)
            const edge = Math.min(Math.hypot(tx - mx, my), F.width * 0.45)
            const B = { start: 0, len: 0, w: 15 * u, a: 1, phase: 0, rings: [], ringT: 0, speed: 1500, stopRings: false, dead: false,
                        ca: ca, sa: sa, ang: ang, max: edge }
            const pad = 15 * u * 1.5 * 3.6 + 20
            F.shake(8 * u)
            F.ring(mx, my, 6, 80 * u, 0.45, DRAGON2, 4)
            F.add({ life: 1e9, box: () => { const x1 = mx + edge * ca; return [Math.min(mx, x1) - pad, Math.max(mx, x1) + pad] }, upd(dt) {
                B.phase += dt * 20
                B.ringT += dt
                if (!B.stopRings && B.ringT > 0.07) { B.ringT = 0; B.rings.push({ d: 0 }) }
                for (const r of B.rings) r.d += dt * B.speed
                B.rings = B.rings.filter(r => r.d < B.len)
                return !B.dead
            }, draw(g) { if (B.len > B.start) root.drawBeam(g, mx, my, dir, B, u) } })
            const sPart = F.every(16, () => {
                const d = F.rand(B.start, B.len), o = F.rand(-1, 1) * B.w * 1.3, v = F.rand(600, 1000) * u
                if (Math.random() > root.beamFade(B, d)) return
                F.spawn({ kind: "streak", x: mx + d * ca - o * sa, y: my + d * sa + o * ca, vx: ca * v, vy: sa * v,
                          life: F.rand(0.15, 0.3), size: F.rand(1, 2.2) * u, rgb: Math.random() < 0.5 ? DRAGON2 : "255,255,255", drag: 0, g: 0 })
            })
            yield F.tween(edge / B.speed * 1000, e => { B.len = edge * e }, F.linear)
            // 3. le flot dure, en trois vagues ; il recule sous le recul
            const x0 = S.px
            for (let k2 = 0; k2 < 3; k2++) {
                yield F.tween(650, e => {
                    const s = Math.sin(e * Math.PI)
                    B.w = 15 * u * (1 + 0.5 * s)
                    S.px = x0 - dir * (6 + k2 * 5 + 5 * s) * u
                    F.shake(2.5 * u + 3.5 * u * s)
                    const p = F.at("mouth"); orb.x = p[0]; orb.y = p[1]
                })
            }
            // 4. fin : le flot se detache de la gueule et file hors de l'ecran
            B.stopRings = true; sPart(); sRocks()
            F.ring(mx, my, 4, 60 * u, 0.4, DRAGON2, 3)
            yield F.tween(edge / B.speed * 1000, e => { B.start = edge * e; orb.a = 1 - e }, F.linear)
            B.dead = true; orb.kill()
            yield F.play("beam", 18, 6, 0)
        },

        // Draco-Meteore : boule de feu lancee vers le ciel, qui retombe en pluie de meteores
        dracoMeteore: function* () {
            const F = root.fx, S = root.sprite, u = F.u, FIRE = root.fire, FIRE2 = root.fire2
            F.faceRoom(F.petW() * 2)
            yield F.play("skyroar", 14, 0, 7)
            const orb = F.orbFx(FIRE, FIRE2, { spinSpeed: 10, arcs: false })
            const sConv = F.every(30, () => { const p = F.at("mouth", 0, -10); F.converge(p[0], p[1], 80 * u, Math.random() < 0.5 ? FIRE : FIRE2, 3) })
            yield F.tween(800, e => { const p = F.at("mouth", 0, -14); orb.x = p[0]; orb.y = p[1]; orb.r = 20 * u * e; F.shake(1.5 * e) })
            sConv()
            // tir vers le ciel
            const sx = orb.x, sy = orb.y
            F.shake(5 * u)
            yield F.tween(450, e => {
                orb.y = F.lerp(sy, -60, e); orb.x = sx
                orb.a = F.clamp(orb.y / (160 * u), 0, 1)   // s'efface avant le bord haut
                if (Math.random() < orb.a) {
                    F.smoke(orb.x, orb.y + 20, 1, { rgb: "255,150,90", a: 0.35, size: 14, up: 10 })
                    F.embers(orb.x, orb.y + 10, 2, FIRE, { v: 60 })
                }
            }, F.easeIn)
            orb.kill()
            yield F.wait(350)
            // lueur dans le ciel, assez basse pour ne pas etre coupee par le bord haut
            F.add({ life: 0.6, box: () => [sx - 230 * u, sx + 230 * u], draw() { const e = this.t / this.life; F.glow(sx, 165 * u, 220 * u, FIRE, 0.5 * Math.sin(e * Math.PI)) } })
            // la pluie
            const n = 6, base = S.px + S.dir * F.petW() * 0.9
            const hits = []
            for (let i = 0; i < n; i++) {
                const gx = F.clamp(base + S.dir * (i * 70 + F.rand(-30, 30)) * u, 40, F.width - 40)
                hits.push(new Promise(res => F.after(i * 230 + F.rand(0, 80), () => root.meteor(gx, res))))
            }
            yield hits
            yield F.play("skyroar", 18, 7, 0)
        },

        // Fatal-Foudre : nuage d'orage, il envoie la foudre vers le ciel, l'orage frappe le sol
        fatalFoudre: function* () {
            const F = root.fx, S = root.sprite, u = F.u, ELEC = root.elec, ELEC2 = root.elec2
            F.faceRoom(F.petW() * 2)
            const cx = F.clamp(S.px + S.dir * F.petW() * 1.5, 120, F.width - 120), cy = Math.max(70, 150 * u + 16)   // lueur du nuage entiere sous le bord haut
            const cloud = { a: 0, lit: 0, dead: false }
            const blobs = []
            for (let i = 0; i < 16; i++)
                blobs.push([F.rand(-150, 150) * u, F.rand(-25, 25) * u, F.rand(34, 60) * u])
            F.add({ layer: "back", life: 1e9, box: () => [cx - 230 * u, cx + 230 * u], upd(dt) { cloud.lit = Math.max(0, cloud.lit - dt * 4); return !cloud.dead }, draw() {
                for (const b of blobs) F.soft(cx + b[0], cy + b[1], b[2], "38,42,58", 0.9 * cloud.a)
                if (cloud.lit > 0) F.glow(cx + F.rand(-60, 60) * u, cy, 150 * u, ELEC, cloud.lit * cloud.a * 0.7)
            } })
            F.play("skyroar", 14, 0, 7)
            const orb = F.orbFx(ELEC, ELEC2, { spinSpeed: 12 })
            const sArcs = F.every(60, () => F.bodyArc(ELEC))
            const sCl = F.every(140, () => {
                cloud.lit = 1
                F.bolt(cx + F.rand(-120, 120) * u, cy + F.rand(-10, 15) * u, cx + F.rand(-120, 120) * u, cy + F.rand(-10, 15) * u, { life: 0.12, w: 1.6, branches: 1, depth: 5, rgb: ELEC })
            })
            yield F.tween(1200, e => { cloud.a = e; const p = F.at("turbine"); orb.x = p[0]; orb.y = p[1]; orb.r = 18 * u * e; F.aura = e * 0.8 })
            // il envoie la foudre dans le nuage
            const hp = F.at("head", 0, -20)
            F.bolt(hp[0], hp[1], cx, cy + 20 * u, { life: 0.35, w: 4, branches: 3, rgb: ELEC })
            cloud.lit = 1
            yield F.wait(250)
            for (let i = 0; i < 4; i++) {
                const gx = F.clamp(cx + F.rand(-110, 110) * u, 40, F.width - 40), gy = F.groundY - 2
                cloud.lit = 1
                F.bolt(cx + F.rand(-40, 40) * u, cy + 25 * u, gx, gy, { life: 0.32, w: 5, branches: 4, disp: (gy - cy) * 0.22, rgb: ELEC })
                F.sparks(gx, gy, 24, { angle: -Math.PI / 2, spread: 1.3, vmax: 420, g: 800, rgb: ELEC2 })
                F.ring(gx, gy, 6, 120 * u, 0.5, ELEC2, 4, 0.25)
                F.scorch(gx, 80 * u, ELEC, 1.8)
                F.smoke(gx, gy - 6, 5, { rgb: "90,95,110", a: 0.4, size: 18, up: 50 })
                F.shake(7 * u)
                yield F.wait(F.rand(260, 420))
            }
            sArcs(); sCl()
            yield F.tween(700, e => { cloud.a = 1 - e; orb.a = 1 - e; F.aura = 0.8 * (1 - e) })
            cloud.dead = true; orb.kill()
            yield F.play("skyroar", 18, 7, 0)
        }
    })

    function chargeFoudre() { return gens.chargeFoudre() }
    function eclairCroix() { return gens.eclairCroix() }
    function dracoChoc() { return gens.dracoChoc() }
    function dracoMeteore() { return gens.dracoMeteore() }
    function fatalFoudre() { return gens.fatalFoudre() }

    // energie qui s'enroule en spirale vers la gueule
    function swirl(x, y, r) {
        const F = fx
        const a0 = F.rand(0, Math.PI * 2), life = F.rand(0.45, 0.7), turns = F.rand(0.8, 1.4) * (Math.random() < 0.5 ? 1 : -1)
        const rgb = Math.random() < 0.5 ? dragon : dragon2, sz = F.rand(1.5, 3.2) * F.u
        F.add({ life: life, box: () => [x - r - 10, x + r + 10], draw() {
            const t = this.t / life, rr = r * (1 - F.easeIn(t)), a = a0 + turns * Math.PI * 2 * t
            F.glow(x + Math.cos(a) * rr, y + Math.sin(a) * rr * 0.7, sz * 2.4, rgb, Math.sin(t * Math.PI))
        } })
    }
    // fondu du flot draconique a la distance d de la gueule (1 puis 0 au bout)
    function beamFade(B, d) {
        return B.max > 0 ? Math.max(0, Math.min(1, (B.max - d) / (0.4 * B.max))) : 0
    }
    // flot draconique : coeur, rubans en helice, anneaux d'onde de choc qui
    // filent ; dessine dans un repere tourne (axe x = direction du tir)
    function drawBeam(g, mx, my, dir, B, u) {
        const F = fx, DRAGON = dragon, DRAGON2 = dragon2
        const sx = B.start, ex = B.len, a = B.a, w = B.w
        const fade = (rgb, al) => {
            const gr = g.createLinearGradient(0, 0, B.max, 0)
            gr.addColorStop(0, "rgba(" + rgb + "," + al + ")"); gr.addColorStop(0.6, "rgba(" + rgb + "," + al + ")"); gr.addColorStop(1, "rgba(" + rgb + ",0)")
            return gr
        }
        g.save(); g.translate(mx, my); g.rotate(B.ang); g.globalCompositeOperation = "lighter"; g.lineCap = "round"
        for (const l of [[4.5, DRAGON, 0.09], [2.3, DRAGON, 0.25], [1.1, DRAGON2, 0.7], [0.38, "255,255,255", 1]]) {
            g.strokeStyle = fade(l[1], l[2] * a); g.lineWidth = w * l[0]
            g.beginPath(); g.moveTo(sx, 0); g.lineTo(ex, 0); g.stroke()
        }
        for (const r of [[0, DRAGON2, 2.6], [Math.PI, DRAGON, 2.6]]) {
            g.strokeStyle = fade(r[1], 0.85 * a); g.lineWidth = r[2] * u; g.beginPath()
            for (let d = sx; d <= ex; d += 6) {
                const y = Math.sin(d * 0.04 - B.phase + r[0]) * w * 1.2 * Math.min(1, d / 50)
                if (d === sx) g.moveTo(d, y)
                else g.lineTo(d, y)
            }
            g.stroke()
        }
        // anneaux : l'onde de choc caracteristique
        for (const r of B.rings) {
            if (r.d < sx) continue
            const kr = a * root.beamFade(B, r.d)
            if (kr <= 0) continue
            const grow = 1 + Math.min(1, r.d / 300) * 0.6
            g.save(); g.translate(r.d, 0); g.scale(0.32, 1)
            g.strokeStyle = "rgba(" + DRAGON2 + "," + (0.75 * kr) + ")"; g.lineWidth = 2.6 * u / 0.32 * 0.35
            g.beginPath(); g.arc(0, 0, w * 1.9 * grow, 0, Math.PI * 2, false); g.stroke()
            g.strokeStyle = "rgba(255,255,255," + (0.5 * kr) + ")"; g.lineWidth = 1.2 * u / 0.32 * 0.35
            g.beginPath(); g.arc(0, 0, w * 1.5 * grow, 0, Math.PI * 2, false); g.stroke()
            g.restore()
        }
        g.restore()
        const kh = a * root.beamFade(B, ex), hx = mx + ex * B.ca, hy = my + ex * B.sa
        F.glow(hx, hy, w * 3.5, DRAGON, 0.6 * kh); F.glow(hx, hy, w * 1.5, DRAGON2, 0.9 * kh)
    }
    // un meteore qui tombe en biais et explose au sol ; done() a l'impact
    function meteor(gx, done) {
        const F = fx, u = F.u, FIRE = fire, FIRE2 = fire2
        const x0 = gx - 220 * u * (Math.random() < 0.5 ? 1 : -1) * 0.6, y0 = -40, y1 = F.groundY - 6, dur = 0.55
        F.add({ life: dur, x: null, y: null, box: () => [Math.min(x0, gx) - 170 * u, Math.max(x0, gx) + 170 * u], upd() {
            const e = F.easeIn(Math.min(1, this.t / dur))
            this.x = F.lerp(x0, gx, e); this.y = F.lerp(y0, y1, e)
            // braises et fumee suivent le meme fondu que la tete
            if (Math.random() < Math.min(1, this.y / (160 * u))) {
                F.embers(this.x, this.y, 2, Math.random() < 0.5 ? FIRE : FIRE2, { v: 40, life: 0.5, size: 7 })
                F.smoke(this.x, this.y, 1, { rgb: "90,70,70", a: 0.4, size: 12, up: 5, life: 1 })
            }
            return true
        }, draw(g) {
            if (this.x === null) return
            // apparition en fondu sur les 160 premiers px : pas de bord coupe en haut de la fenetre
            const fade = Math.max(0, Math.min(1, this.y / (160 * u)))
            if (fade <= 0) return
            const ang = Math.atan2(y1 - y0, gx - x0)
            g.save(); g.globalCompositeOperation = "lighter"; g.lineCap = "round"
            const tx = this.x - Math.cos(ang) * 120 * u, ty = this.y - Math.sin(ang) * 120 * u
            const gr = g.createLinearGradient(tx, ty, this.x, this.y)
            gr.addColorStop(0, "rgba(" + FIRE + ",0)"); gr.addColorStop(1, "rgba(" + FIRE2 + "," + (0.95 * fade) + ")")
            g.strokeStyle = gr; g.lineWidth = 16 * u; g.beginPath(); g.moveTo(tx, ty); g.lineTo(this.x, this.y); g.stroke(); g.restore()
            F.glow(this.x, this.y, 46 * u, FIRE, 0.9 * fade); F.glow(this.x, this.y, 16 * u, FIRE2, fade)
        } })
        F.after(dur * 1000, () => {
            F.shake(7 * u)
            F.add({ life: 0.45, box: () => [gx - 250 * u, gx + 250 * u], draw() { const e = this.t / this.life; F.glow(gx, y1, 120 * u * (1 + e), FIRE, 1 - e); F.glow(gx, y1, 50 * u, FIRE2, 1 - e) } })
            F.ring(gx, y1, 8, 150 * u, 0.6, FIRE2, 4, 0.25)
            F.sparks(gx, y1, 26, { rgb: FIRE2, angle: -Math.PI / 2, spread: 1.2, vmax: 480, g: 700 })
            F.embers(gx, y1 - 10, 16, FIRE, { v: 200, up: 120, g: 200, life: 1 })
            F.smoke(gx, y1 - 10, 10, { rgb: "70,60,65", a: 0.55, size: 26, up: 60, life: 1.8 })
            F.scorch(gx, 90 * u, FIRE, 2.2)
            done()
        })
    }
}
