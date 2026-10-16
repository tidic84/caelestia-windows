pragma Singleton
import QtQuick
import IlotCore

// Ce que l'ilot surveille en dehors des pages : activites en cours (mise a
// jour Steam, jeu, GPU), mode jeu, mode absent, partie trouvee, extinction
// programmee, voyant camera / micro, etat des services, sante des disques,
// partage avec le telephone, sous-titres en direct, raccourcis clavier,
// mises a jour, compagnon de la pilule et file des notifications de l'ilot.
Item {
    id: w

    readonly property var cfg: Ilot.cfg

    // ================================================== notifications
    // { app, sym, icon, title, body, action, tab, url, cmd, fn, ms, force, recap }
    // l'ilot s'agrandit quelques secondes ; elles passent l'une apres l'autre
    property var queue: []
    function notify(n) {
        if (!cfg.notif_popups || cfg.dnd || Ilot.fullscreen)
            return
        // mode jeu : pas de notification (sauf bilan, partie trouvee...)
        if (gameOn && !cfg.game_notif && !n.force)
            return
        // mode absent : gardees pour le retour
        if (away.on && !n.recap) {
            if (away.missed.length < 30)
                away.missed.push(n)
            return
        }
        if (queue.length < 5)
            queue = queue.concat([n])
        if (!Ilot.act || Ilot.act.kind !== "notif")
            nextNotif()
    }
    function nextNotif() {
        if (!queue.length || Ilot.mode !== "collapsed")
            return
        const n = queue[0]
        queue = queue.slice(1)
        Ilot.showActivity({
            kind: "notif", ms: n.ms || 5000, pic: n.icon || "", sym: n.sym || "notifications", action: n.action || "",
            title: n.title, sub: n.app + (n.body ? " · " + n.body : ""),
            onClick: () => {
                if (n.url)
                    return Api.invoke("open_url", { url: n.url })
                if (n.fn)
                    return n.fn()
                if (n.cmd)
                    return Api.invoke(n.cmd[0], n.cmd[1] || {})
                Ilot.open(n.tab || null)
            }
        })
    }
    Connections {
        target: Ilot
        function onActChanged() {
            if (!Ilot.act && w.queue.length)
                Ilot.later(350, () => w.nextNotif())
        }
        function onModeChanged() {
            if (Ilot.mode === "collapsed" && w.queue.length)
                Ilot.later(600, () => w.nextNotif())
        }
    }

    // affichage ephemere (volume a la molette, sortie, minuteur...) ; sans
    // `frac`, juste une icone et un texte
    function osd(icon, frac, label) {
        if (frac === null || frac === undefined)
            Ilot.simpleActivity(icon, label, "", { ms: 1600 })
        else
            Ilot.showActivity({ kind: "osd", icon: icon, value: frac, label: String(label), ms: 1600 })
    }

    // ================================================== volume, boost
    // 0-100 % : volume Windows ; 100-200 % : Windows a 100 % + gain reel par le
    // « Preamp » d'Equalizer APO (src/boost.rs), s'il est installe
    property var boost: null
    property real boostAt: 0
    function refreshBoost() {
        return Api.invoke("boost_get").then(b => {
            w.boost = b
            // volume Windows baisse ailleurs (touches, melangeur) : plus de gain
            if (b !== null && b > 1 && Ilot.vol.level < 0.99) {
                w.boost = 1
                Api.invoke("boost_set", { gain: 1 })
            }
        })
    }
    // niveau affiche 0..2
    readonly property real level: boost !== null && boost > 1 ? boost : Ilot.vol.level
    // applique un niveau 0..2 ; le fichier d'Equalizer APO n'est reecrit qu'une
    // fois toutes les 80 ms pendant qu'on fait glisser (force : valeur finale)
    function setLevel(level, force) {
        if (boost === null)
            level = Math.min(level, 1)
        Ilot.setVolume(Math.min(level, 1), false)
        if (boost === null)
            return
        const g = Math.max(1, level)
        const now = Date.now()
        if (g !== boost && (force || g === 1 || now - boostAt > 80)) {
            boost = g
            boostAt = now
            Api.invoke("boost_set", { gain: g })
        }
    }
    // molette sur la pilule : pas de 2 % ; Maj : appli au premier plan
    function wheel(dy, shift) {
        if (shift) {
            Api.invoke("fg_volume", { step: dy > 0 ? 0.04 : -0.04 }).then(r => {
                if (!r)
                    return w.osd("volume_off", null, "Cette appli ne joue pas de son")
                const n = Math.round(r.level * 100)
                Ilot.simpleActivity(n === 0 ? "volume_off" : "tune", r.name, n + " %", { ms: 1600 })
            })
            return
        }
        const v = Math.max(0, Math.min(boost === null ? 100 : 200, Math.round(level * 100) + Math.sign(dy) * 2))
        setLevel(v / 100, true)
        if (Ilot.cfg.osd)
            Ilot.showActivity({ kind: "osd", icon: v === 0 ? "volume_off" : v > 100 ? "campaign" : v < 50 ? "volume_down" : "volume_up",
                value: Math.min(1, v / 100), label: String(v), ms: 1600 })
    }

    // ============================================== activites en cours
    // src/activity.rs (evenement `gaming`) : telechargements Steam, jeu du
    // Launcher, charge / temperature du GPU NVIDIA
    property var gaming: ({ downloads: [], gpu: null, game: null })
    readonly property int gamingLoad: 60
    readonly property var dl: cfg.activity ? (gaming.downloads || []).find(x => x.active) || null : null
    readonly property var game: cfg.activity ? gaming.game : null
    readonly property var gpu: cfg.activity && (gaming.game || (gaming.gpu && gaming.gpu.load >= gamingLoad)) ? gaming.gpu : null
    readonly property bool actShown: !!(dl || game || gpu)
    // relu pour faire avancer le temps de jeu affiche
    property real tick: Date.now()
    Timer {
        interval: w.game && w.game.away ? 1000 : 30000
        running: !!w.game
        repeat: true
        onTriggered: w.tick = Date.now()
    }
    function cover(id) {
        const g = Ilot.games.find(x => x.id === id)
        return g ? g.cover || g.icon || "" : ""
    }
    function fmtSize(b) {
        return b >= Math.pow(1024, 3) ? (b / Math.pow(1024, 3)).toFixed(1).replace(".", ",") + " Go" : Math.round(b / Math.pow(1024, 2)) + " Mo"
    }
    function fmtSpeed(b) {
        return b >= Math.pow(1024, 2) ? (b / Math.pow(1024, 2)).toFixed(1).replace(".", ",") + " Mo/s" : Math.round(b / 1024) + " Ko/s"
    }
    function fmtEta(d) {
        if (!d.speed)
            return ""
        const s = (d.total - d.done) / d.speed
        return s < 60 ? "moins d’1 min" : s < 3600 ? Math.round(s / 60) + " min" : Math.floor(s / 3600) + " h " + Ilot.pad(Math.round((s % 3600) / 60))
    }
    function fmtDur(s) {
        const m = Math.round(s / 60)
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + Ilot.pad(m % 60)
    }
    function dlPct(d) {
        return Math.min(100, d.done / Math.max(1, d.total) * 100)
    }
    // pastille de la pilule repliee et ligne du survol
    readonly property var chip: {
        tick
        if (dl) {
            const inst = dl.phase === "install"
            return { icon: inst ? "install_desktop" : "download", text: Math.floor(dlPct(dl)) + " %", hot: false, away: false }
        }
        if (game) {
            const awayFor = game.away ? Ilot.fmtTime((Date.now() - game.away) / 1000) : ""
            if (awayFor)
                return { icon: "hourglass_top", text: awayFor, hot: false, away: true }
            const mins = Math.max(0, Math.floor((Date.now() - game.since) / 60000))
            return { icon: "sports_esports", text: gpu ? gpu.temp + "°" : mins < 60 ? mins + " min" : Math.floor(mins / 60) + " h " + Ilot.pad(mins % 60), hot: !!gpu && gpu.temp >= 80, away: false }
        }
        if (gpu)
            return { icon: "sports_esports", text: gpu.temp + "°", hot: gpu.temp >= 80, away: false }
        return null
    }
    readonly property var peek: {
        tick
        if (dl) {
            const inst = dl.phase === "install"
            const eta = fmtEta(dl)
            return {
                pic: cover("steam:" + dl.appid), icon: "download", title: dl.name, bar: dlPct(dl) / 100,
                sub: (inst ? "Installation " : "Téléchargement ") + Math.floor(dlPct(dl)) + " % · " + fmtSize(dl.done) + " / " + fmtSize(dl.total)
                    + (dl.speed ? " · " + fmtSpeed(dl.speed) : "") + (eta ? " · " + eta : "")
            }
        }
        const sys = Ilot.sys
        if (game) {
            const mins = Math.max(0, Math.floor((Date.now() - game.since) / 60000))
            const time = mins < 60 ? mins + " min" : Math.floor(mins / 60) + " h " + Ilot.pad(mins % 60)
            const awayFor = game.away ? Ilot.fmtTime((Date.now() - game.away) / 1000) : ""
            const stats = [gpu && "GPU " + gpu.load + " % · " + gpu.temp + " °C", sys && "CPU " + Math.round(sys.cpu) + " %"].filter(Boolean).join(" · ")
            return {
                pic: cover(game.id), icon: "sports_esports", title: game.name, bar: -1,
                sub: awayFor ? "En attente depuis " + awayFor + (cfg.match_alert ? " · alerte quand la partie est trouvée" : "")
                    : "En jeu depuis " + time + (stats ? " · " + stats : "")
            }
        }
        if (gpu)
            return { pic: "", icon: "sports_esports", title: gpu.name, bar: -1, sub: "GPU " + gpu.load + " % · " + gpu.temp + " °C" + (sys ? " · CPU " + Math.round(sys.cpu) + " %" : "") }
        return null
    }

    // ================================================== mode jeu
    // jeu du Launcher lance : Windows en mode Performances (retabli a la
    // sortie), notifications en silence, profil de volume « Jeu »
    property var gameOn: null
    function gameMode(g) {
        if (g && cfg.game_mode) {
            if (gameOn)
                return
            gameOn = { id: g.id, power: "" }
            if (!cfg.game_notif)
                queue = []
            if (cfg.game_perf) {
                Api.invoke("power_get").then(before => {
                    if (before && before !== "perf")
                        return Api.invoke("power_set", { mode: "perf" }).then(ok => { if (ok && w.gameOn) w.gameOn.power = before })
                })
            }
            gameMix(true)
        } else if (gameOn) {
            if (gameOn.power)
                Api.invoke("power_set", { mode: gameOn.power })
            gameOn = null
            gameMix(false)
        }
    }

    // ------------------------------------------------ profils de volume
    // %LOCALAPPDATA%\Ilot\mixprofiles.json : { jeu: { nom: niveau }, chill: {...} }
    property var mixProfiles: ({})
    readonly property var profileList: [["jeu", "Jeu", "sports_esports"], ["chill", "Chill", "self_improvement"]]
    property string mixOn: ""
    function saveProfile(id, label) {
        Api.invoke("mixer_get").then(list => {
            const p = {}
            for (const a of list)
                p[a.name] = a.muted ? 0 : Math.round(a.level * 100) / 100
            const all = Object.assign({}, w.mixProfiles)
            all[id] = p
            w.mixProfiles = all
            w.mixOn = id
            Api.invoke("store_set", { key: "mixprofiles", value: all })
            w.osd("save", null, "Profil « " + label + " » enregistré")
        })
    }
    function applyProfile(p) {
        return Api.invoke("mixer_get").then(list => {
            for (const a of list) {
                if (!(a.name in p))
                    continue
                Api.invoke("mixer_set", { pids: a.pids, level: p[a.name], muted: p[a.name] === 0 })
            }
        })
    }
    property var mixBefore: null
    function gameMix(on) {
        if (!cfg.mix_auto)
            return
        if (on && !mixBefore && mixProfiles.jeu) {
            Api.invoke("mixer_get").then(list => {
                const b = {}
                for (const a of list)
                    b[a.name] = a.muted ? 0 : a.level
                w.mixBefore = b
                w.applyProfile(w.mixProfiles.jeu)
            })
            // le son du jeu n'apparait parfois qu'apres quelques secondes
            Ilot.later(20000, () => { if (w.gameOn && w.mixProfiles.jeu) w.applyProfile(w.mixProfiles.jeu) })
        } else if (!on && mixBefore) {
            applyProfile(mixBefore)
            mixBefore = null
        }
    }

    // ============================================== partie trouvee
    // le joueur attend hors du jeu (file d'attente) : son, ilot qui clignote,
    // clic = retour dans le jeu
    property bool matchFlash: false
    Timer {
        id: matchTimer
        interval: 5000
        onTriggered: w.matchFlash = false
    }

    // ================================================== mode absent
    // 10 min sans clavier ni souris (hors jeu) : la musique se met en pause, les
    // notifications attendent le retour
    property var away: ({ on: false, since: 0, missed: [], paused: false })
    readonly property int awaySecs: 600
    readonly property var videoApps: /chrome|msedge|firefox|opera|brave|vlc|mpc|potplayer|netflix|disney|prime|twitch|youtube/i
    property int idle: 0
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: Api.invoke("idle_secs").then(s => w.onIdle(s))
    }
    function onIdle(s) {
        idle = s
        petIdle(s)
        if (s >= awaySecs)
            maybeInstall()
        if (cfg.away === "off")
            return
        if (!away.on && s >= awaySecs && !gameOn && !Ilot.fullscreen) {
            const paused = cfg.away === "on" && Ilot.hasMedia && Ilot.media.playing && !videoApps.test(Ilot.media.app)
            if (paused)
                Ilot.mediaAction("toggle")
            away = { on: true, since: Date.now() - s * 1000, missed: [], paused: paused }
        } else if (away.on && s < 5) {
            const a = away
            away = { on: false, since: 0, missed: [], paused: false }
            if (!a.missed.length && !a.paused)
                return
            const byApp = {}
            for (const n of a.missed)
                byApp[n.app] = (byApp[n.app] || 0) + 1
            const parts = Object.keys(byApp).map(k => byApp[k] > 1 ? k + " ×" + byApp[k] : k)
            const n = a.missed.length
            notify(Object.assign({
                app: "Pendant ton absence", sym: "waving_hand", recap: true, ms: 10000,
                title: "Re ! Absent " + fmtDur((Date.now() - a.since) / 1000),
                body: (n ? n + " notification" + (n > 1 ? "s" : "") + " : " + parts.join(", ") : "Aucune notification") + (a.paused ? " · musique en pause" : "")
            }, a.paused ? { action: "Reprendre", cmd: ["media_action", { action: "toggle" }] } : {}))
            // puis les notifications elles-memes (les 4 dernieres)
            for (const m of a.missed.slice(-4))
                notify(Object.assign({}, m, { recap: true }))
        }
    }

    // ============================================ extinction programmee
    // { action, at (ms) } ou { action, wait: "media" | "steam" }, garde dans ui.json
    property var off: null
    property string offAction: "shutdown"
    property int offCalm: 0
    property bool offWarned: false
    property real now: Date.now()
    readonly property var offLabel: ({ shutdown: "Extinction", sleep: "Mise en veille", restart: "Redémarrage" })
    readonly property bool offShown: !!off && !!off.at && off.at - now < 30 * 60000
    function fmtLeft(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        return s >= 3600 ? Math.floor(s / 3600) + " h " + Ilot.pad(Math.floor(s % 3600 / 60)) : Math.floor(s / 60) + ":" + Ilot.pad(s % 60)
    }
    function setOff(v) {
        off = v
        offCalm = 0
        offWarned = false
        Ilot.saveUi({ off: v })
        if (v)
            osd("timer", null, v.at ? offLabel[v.action] + " à " + Ilot.hm(new Date(v.at))
                : offLabel[v.action] + " " + (v.wait === "media" ? "à la fin du média" : "après les MAJ Steam"))
    }
    function offIn(min) {
        setOff({ action: offAction, at: Date.now() + min * 60000 })
    }
    // « 23:30 » ; heure passee : demain
    function offAt(hhmm) {
        const p = hhmm.split(":").map(Number)
        if (p.length < 2 || isNaN(p[0]) || isNaN(p[1]))
            return
        const d = new Date()
        d.setHours(p[0], p[1], 0, 0)
        if (d <= new Date())
            d.setDate(d.getDate() + 1)
        setOff({ action: offAction, at: d.getTime() })
    }
    Timer {
        interval: 1000
        running: !!w.off
        repeat: true
        onTriggered: w.offTick()
    }
    function offTick() {
        now = Date.now()
        if (!off)
            return
        if (off.wait) {
            // fin du media / des telechargements : 1 min de calme, puis 60 s
            const busy = off.wait === "media" ? Ilot.media.playing : (gaming.downloads || []).length > 0
            offCalm = busy ? 0 : offCalm + 1
            if (offCalm >= 60) {
                off = { action: off.action, at: Date.now() + 60000 }
                Ilot.saveUi({ off: off })
            }
        }
        if (off.at) {
            const left = off.at - now
            if (left <= 60000 && !offWarned) {
                offWarned = true
                notify({ app: "Extinction programmée", sym: "power_settings_new", title: offLabel[off.action] + " dans 1 minute",
                    body: "Clique pour annuler", action: "Annuler", fn: () => { w.setOff(null); w.osd("timer_off", null, "Extinction annulée") }, ms: 55000, force: true })
            }
            if (left > 60000)
                offWarned = false
            if (left <= 0) {
                const a = off.action
                setOff(null)
                Api.invoke("session_action", { action: a })
            }
        }
    }

    // ============================================ voyant camera / micro
    property var priv: ({ cam: [], mic: [] })
    readonly property bool privShown: !!cfg.privacy && (priv.cam.length > 0 || priv.mic.length > 0)

    // ================================================== Discord
    // raccourcis micro / sourdine dans la pilule : en vocal (RPC) ou Discord lance
    readonly property bool dcRpc: Ilot.dc.status === "ready"
    property bool dcRunning: false
    // sourdines Windows (mode simple, sans RPC)
    property bool dcLocalMic: false
    property bool dcLocalOut: false
    readonly property bool dcMic: dcRpc ? !!Ilot.dc.mute : dcLocalMic
    readonly property bool dcDeaf: dcRpc ? !!Ilot.dc.deaf : dcLocalOut
    readonly property bool dcShown: !!cfg.dc_pill && (dcRpc ? !!Ilot.dc.channel : dcRunning)
    readonly property bool dcSpeaking: dcRpc && (Ilot.dc.people || []).some(p => p.id === Ilot.dc.me_id && p.speaking)
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Api.invoke("procs_running", { names: ["Discord"] }).then(r => { w.dcRunning = !!r[0] })
    }
    function toggleDcMic() {
        if (dcRpc)
            return Api.invoke("discord_self", { mute: !Ilot.dc.mute })
        dcLocalMic = !dcLocalMic
        Api.invoke("app_volume_set", { app: "discord", mic: true, muted: dcLocalMic }).then(ok => { if (!ok) w.dcLocalMic = false })
    }
    function toggleDcDeaf() {
        if (dcRpc)
            return Api.invoke("discord_self", { deaf: !Ilot.dc.deaf })
        dcLocalOut = !dcLocalOut
        Api.invoke("app_volume_set", { app: "discord", muted: dcLocalOut }).then(ok => { if (!ok) w.dcLocalOut = false })
    }

    // ================================================== services
    // src/status.rs : page officielle + test depuis le PC ; alerte quand un
    // service tombe ou revient (pas au premier releve)
    property var services: []
    property var svPrev: ({})
    readonly property var svFr: ({ minor: "perturbations", major: "panne partielle", critical: "panne majeure", maintenance: "maintenance" })
    function svLevel(x) {
        if (x.ms === null || x.ms === undefined)
            return "down"
        if (x.official === "major" || x.official === "critical")
            return "down"
        if (x.official === "minor" || x.official === "maintenance" || x.ms > 2500)
            return "warn"
        return "ok"
    }
    function applyServices(list) {
        const first = !Object.keys(svPrev).length
        const prev = Object.assign({}, svPrev)
        for (const x of list) {
            const lv = svLevel(x)
            if (!first && lv === "down" && prev[x.id] !== "down")
                notify({ app: "État des services", sym: "cloud_off", title: x.name + " en panne", body: x.ms === null ? "Injoignable depuis ton PC" : svFr[x.official] || x.desc, tab: "pc", ms: 9000 })
            if (!first && lv === "ok" && prev[x.id] === "down")
                notify({ app: "État des services", sym: "cloud_done", title: x.name + " est de retour", body: "Le service répond de nouveau", ms: 6000 })
            prev[x.id] = lv
        }
        svPrev = prev
        services = list
    }

    // ================================================== mises a jour
    // src/update.rs : derniere version publiee sur GitHub, telechargement,
    // installation (un script remplace les fichiers et relance l'ilot)
    property var upd: ({ current: "", latest: "", available: false, status: "idle", progress: 0, notes: "", error: "", url: "" })
    property string updNotified: ""
    function applyUpdate(u) {
        const was = upd
        upd = u
        // nouvelle version (une fois par version)
        if (u.available && u.status === "idle" && cfg.update_mode !== "auto" && updNotified !== u.latest) {
            updNotified = u.latest
            notify({ app: "Mise à jour", sym: "system_update", title: "Îlot " + u.latest + " est disponible", body: "Voir les nouveautés",
                action: "Voir", ms: 9000, fn: () => Ilot.openSettings("updates") })
        }
        // telechargee : installee tout de suite (mode auto, quand tu ne fais
        // rien) ou au clic
        if (u.status === "ready" && was.status !== "ready") {
            if (cfg.update_mode === "auto")
                maybeInstall()
            else
                notify({ app: "Mise à jour", sym: "restart_alt", title: "Îlot " + u.latest + " est prêt", body: "Redémarrer l'îlot pour l'installer",
                    action: "Installer", ms: 12000, fn: () => w.installUpdate() })
        }
    }
    // mode auto : seulement apres 10 min sans clavier ni souris, hors jeu
    function maybeInstall() {
        if (upd.status === "ready" && cfg.update_mode === "auto" && idle >= awaySecs && !gameOn && !Ilot.fullscreen && Ilot.mode === "collapsed")
            installUpdate()
    }
    function installUpdate() {
        Api.invoke("update_install").then(ok => {
            if (ok)
                Ilot.later(400, () => Backend.quit())
        }, e => osd("error", null, String(e)))
    }
    // apres une mise a jour : proposer les notes de version
    function checkNewVersion(cur) {
        // ui.json sans version : ilot d'avant les notes de version (0.3.x)
        const seen = Ilot.ui.seenVersion || (Object.keys(Ilot.ui).length ? "0" : "")
        if (seen && seen !== cur)
            notify({ app: "Mise à jour", sym: "new_releases", title: "Îlot est passé en " + cur, body: "Voir les nouveautés",
                action: "Voir", ms: 12000, force: true, fn: () => Ilot.openSettings("updates") })
        if (seen !== cur)
            Ilot.saveUi({ seenVersion: cur })
    }

    // ================================================ Quick Share
    // (src/quickshare) : etat envoye par le coeur, fichiers en attente
    // d'envoi, demandes de reception a accepter
    property bool shareOpen: false
    property var qs: ({ name: "", visibility: "on", temp_left: 0, ready: false, ip: "", devices: [], discovering: false,
        ble: "", transfers: [], qr: null, error: "" })
    property var qsFiles: []
    // transferts deja signales (demande, fin)
    property var qsSeen: ({})
    onShareOpenChanged: {
        if (shareOpen)
            Ilot.overlay = "share"
        else if (Ilot.overlay === "share")
            Ilot.overlay = ""
        Api.invoke("qs_discover", { on: shareOpen })
        if (!shareOpen)
            clearShareFiles()
    }
    Connections {
        target: Ilot
        function onEscapeOverlay(what) {
            if (what === "share")
                w.shareOpen = false
        }
        // un onglet choisi referme Quick Share
        function onTabShown(tab) {
            w.shareOpen = false
        }
        function onModeChanged() {
            if (Ilot.mode !== "open")
                w.shareOpen = false
        }
    }
    function openShare(paths) {
        if (paths && paths.length)
            addShareFiles(paths)
        Ilot.pinned = true
        if (Ilot.mode !== "open")
            Ilot.open()
        shareOpen = true
    }
    function addShareFiles(paths) {
        qsFiles = qsFiles.concat(paths.filter(p => qsFiles.indexOf(p) < 0))
        Api.invoke("qs_pending", { paths: qsFiles })
    }
    function clearShareFiles() {
        qsFiles = []
        Api.invoke("qs_pending", { paths: [] })
    }
    function removeShareFile(p) {
        qsFiles = qsFiles.filter(x => x !== p)
        Api.invoke("qs_pending", { paths: qsFiles })
    }
    function qsSend(device, text) {
        Api.invoke("qs_send", { device: device, paths: qsFiles, text: text || null }).catch(e => w.osd("error", null, String(e)))
    }
    function qsAnswer(id, accept) {
        Api.invoke("qs_answer", { id: id, accept: accept })
        if (Ilot.act && Ilot.act.kind === "qs" && Ilot.act.qsId === id)
            Ilot.endActivity()
    }
    function qsKindIcon(k) {
        return k === 1 ? "smartphone" : k === 2 ? "tablet_android" : k === 3 ? "laptop_windows" : "devices"
    }
    // « 2 photos », « rapport.pdf », « un lien »...
    function qsSummary(t) {
        const it = t.items || []
        if (!it.length)
            return ""
        if (it.length === 1)
            return it[0].kind === "url" ? "un lien" : it[0].kind === "text" ? "un texte" : it[0].kind === "wifi" ? "le Wi-Fi « " + it[0].name + " »" : it[0].name
        return it.length + " éléments"
    }
    function onQs(s) {
        const seen = Object.assign({}, qsSeen)
        for (const t of s.transfers) {
            const key = t.id + ":" + t.status
            if (seen[key])
                continue
            seen[key] = true
            if (t.status === "ask")
                qsAsk(t)
            else if (t.status === "done" && !t.out) {
                const one = t.items.length === 1 ? t.items[0] : null
                const body = one && one.kind === "url" ? "Lien reçu" : one && one.kind === "text" ? "Copié dans le presse-papiers"
                    : one && one.kind === "wifi" ? "Mot de passe Wi-Fi reçu" : "Rangé dans Téléchargements"
                notify({ app: "Quick Share", sym: "nearby", title: "Reçu de " + t.peer + " : " + qsSummary(t), body: body,
                    action: one && one.kind === "file" ? "Ouvrir" : "Voir",
                    fn: () => one && one.kind === "file" ? Api.invoke("file_open", { path: one.path }) : w.openShare([]), ms: 8000 })
            } else if (t.status === "done" && t.out && !shareOpen)
                notify({ app: "Quick Share", sym: "nearby", title: "Envoyé à " + t.peer, body: qsSummary(t), ms: 5000 })
            else if (t.status === "rejected" && t.out)
                notify({ app: "Quick Share", sym: "nearby", title: t.peer + " a refusé", body: t.error && t.error !== "Refusé" ? t.error : qsSummary(t), ms: 6000 })
            else if (t.status === "failed")
                notify({ app: "Quick Share", sym: "nearby_error", title: (t.out ? "Envoi à " : "Réception de ") + t.peer + " impossible", body: t.error, ms: 7000 })
        }
        // la demande n'attend plus : on retire l'activite
        if (Ilot.act && Ilot.act.kind === "qs" && !s.transfers.some(t => t.id === Ilot.act.qsId && t.status === "ask"))
            Ilot.endActivity()
        qsSeen = seen
        qs = s
    }
    // demande de reception : dans la pilule (Refuser / Accepter), ou dans
    // Quick Share si l'ilot est deja ouvert
    function qsAsk(t) {
        if (Ilot.mode === "collapsed" && !Ilot.fullscreen)
            return Ilot.showActivity({ kind: "qs", qsId: t.id, ms: 120000, sym: qsKindIcon(t.kind), title: t.peer + " veut te partager",
                sub: qsSummary(t) + (t.pin ? " · code " + t.pin : ""), onClick: () => w.openShare([]) })
        openShare([])
    }

    // ================================================ sous-titres en direct
    property bool capOn: false
    property var caption: ({ text: "", status: "" })
    function toggleCaptions(on) {
        if (on === undefined)
            on = !capOn
        Api.invoke("captions_set", { on: on }).then(v => {
            w.capOn = v
            w.osd("closed_caption", null, v ? "Sous-titres en direct activés" : "Sous-titres coupés")
        })
    }

    // ============================================== raccourcis clavier
    property var keyMap: ({})
    property var keyBad: []
    function saveKeys(map) {
        keyMap = map
        Api.invoke("shortcuts_set", { map: map }).then(bad => { w.keyBad = bad || [] })
    }

    // =================================================== compagnon
    // petite bete dans la pilule repliee : danse sur la musique, met un casque
    // en jeu, transpire si le GPU chauffe, dort la nuit, saute de joie quand
    // une partie est trouvee. Apres 90 s d'inactivite, elle descend se
    // promener au-dessus de la barre des taches (PetWindow).
    readonly property bool petShown: (cfg.pet || "blob") !== "off"
    property real partyUntil: 0
    property string mood: "idle"
    signal petFx(string sym)
    signal petBlink()
    signal petHop()
    property real petLook: 0
    property int petTick: 0
    Timer {
        interval: 1000
        running: w.petShown && !Ilot.fullscreen && !Theme.reduced
        repeat: true
        onTriggered: w.petStep()
    }
    function petMood() {
        const h = new Date().getHours()
        if (Date.now() < partyUntil)
            return "party"
        if (Ilot.act && Ilot.act.kind === "notif")
            return "surprise"
        if (gaming.game && gaming.gpu && gaming.gpu.temp >= 80)
            return "hot"
        if (gaming.game)
            return "game"
        if (Ilot.media.playing)
            return "music"
        if ((h >= 23 || h < 6 || away.on) && Ilot.mode === "collapsed")
            return "sleep"
        return "idle"
    }
    function petStep() {
        petTick++
        mood = petMood()
        if (mood === "music" && petTick % 3 === 0)
            petFx(Math.random() < 0.5 ? "♪" : "♫")
        if (mood === "sleep" && petTick % 3 === 0)
            petFx("z")
        if (mood === "hot" && petTick % 4 === 0)
            petFx("💧")
        if (mood === "party" && petTick % 2 === 0)
            petFx("!")
        if (mood === "idle" || mood === "game" || mood === "music") {
            // clignement, coup d'oeil, petit saut de temps en temps
            if (Math.random() < 0.3)
                petBlink()
            if (Math.random() < 0.15)
                petLook = Math.random() * 3 - 1.5
            if (mood === "idle" && Math.random() < 0.04)
                petHop()
            if (mood === "idle" && Math.random() < 0.02)
                petFx("♥")
        }
    }
    // promenade : apres 90 s sans clavier ni souris
    property bool petOut: false
    readonly property int petIdleSecs: 90
    function petIdle(s) {
        const can = !!cfg.pet_walk && petShown && !gameOn && Ilot.mode === "collapsed" && !Ilot.fullscreen && !Ilot.act && !Theme.reduced
        if (can && s >= petIdleSecs)
            petOut = true
        else if (petOut && (!can || s < 3))
            petOut = false
    }

    // ================================================== evenements
    property var mailKnown: ({})
    property bool mailSeen: false
    function onInbox(ib) {
        // nouveaux mails depuis la derniere verification
        const fresh = ib.mails.filter(m => !m.seen && !mailKnown[m.account + m.uid])
        if (mailSeen && fresh.length === 1)
            notify({ app: fresh[0].account, title: fresh[0].from || fresh[0].from_addr, body: fresh[0].subject || "(sans objet)", sym: "mail", tab: "mail" })
        else if (mailSeen && fresh.length > 1)
            notify({ app: "Mail", title: fresh.length + " nouveaux mails", body: fresh.map(m => m.from || m.from_addr).slice(0, 3).join(", "), sym: "mail", tab: "mail" })
        const k = Object.assign({}, mailKnown)
        for (const m of ib.mails)
            k[m.account + m.uid] = true
        mailKnown = k
        mailSeen = true
    }

    Component.onCompleted: {
        Api.listen("gaming", a => {
            const before = w.gaming.game ? w.gaming.game.id : null
            w.gaming = a
            if ((a.game ? a.game.id : null) !== before)
                w.gameMode(a.game)
        })
        Api.listen("steam-done", d => {
            w.partyUntil = Date.now() + 4000
            w.notify({ app: "Steam", sym: "download_done", icon: w.cover("steam:" + d.appid), title: d.name + " est prêt",
                body: "Mise à jour terminée", action: "Jouer", url: "steam://rungameid/" + d.appid, ms: 12000 })
        })
        Api.listen("match-found", name => {
            w.partyUntil = Date.now() + 8000
            if (!w.cfg.match_alert)
                return
            Backend.chime()
            w.matchFlash = true
            matchTimer.restart()
            w.notify({ app: name, sym: "sports_esports", icon: w.gaming.game ? w.cover(w.gaming.game.id) : "", title: "Partie trouvée !",
                body: "Clique pour retourner dans le jeu", action: "Y aller", cmd: ["game_focus"], ms: 20000, force: true })
        })
        // bilan de session a la fermeture d'un jeu ;
        // %LOCALAPPDATA%\Ilot\sessions.json : { list: [...100 dernieres], total: { id: secondes } }
        Api.listen("game-session", r => {
            if (r.secs < 60)
                return
            Api.invoke("store_get", { key: "sessions" }).then(st => {
                st = st || {}
                const list = Array.isArray(st.list) ? st.list : []
                const total = st.total && typeof st.total === "object" ? st.total : {}
                total[r.id] = (total[r.id] || 0) + r.secs
                list.unshift({ id: r.id, name: r.name, since: r.since, secs: r.secs, cpu: Math.round(r.cpu_avg), gpu: r.gpu_avg, temp: r.temp_max, ram: r.ram_max })
                Api.invoke("store_set", { key: "sessions", value: { list: list.slice(0, 100), total: total } })
                const stats = [r.gpu_avg >= 0 && "GPU " + r.gpu_avg + " %", r.temp_max > 0 && r.temp_max + " °C max", "CPU " + Math.round(r.cpu_avg) + " %", "RAM " + w.fmtSize(r.ram_max)].filter(Boolean).join(" · ")
                w.notify({ app: "Bilan de session", sym: "sports_esports", icon: w.cover(r.id), ms: 15000, tab: "apps", force: true,
                    title: r.name + " · " + w.fmtDur(r.secs) + (total[r.id] > r.secs + 60 ? " (total " + w.fmtDur(total[r.id]) + ")" : ""), body: stats })
            })
        })
        Api.listen("privacy", p => {
            // une appli qui allume la camera : notification (le micro, lui, sert tout le temps en vocal)
            const fresh = p.cam.filter(a => w.priv.cam.indexOf(a) < 0)
            w.priv = p
            if (fresh.length && w.cfg.privacy)
                w.notify({ app: "Confidentialité", sym: "videocam", title: fresh.join(", ") + " utilise ta caméra", body: "Le voyant vert reste allumé tant qu’elle filme", ms: 7000, force: true })
        })
        Api.listen("services", l => w.applyServices(l))
        Api.listen("disk-low", d => w.notify({ app: "Santé du PC", sym: "hard_drive", title: "Disque " + d.mount + " presque plein",
            body: "Plus que " + w.fmtSize(d.free) + " libres sur " + w.fmtSize(d.total), action: "Voir", tab: "pc", ms: 12000 }))
        Api.listen("qs", s => w.onQs(s))
        Api.invoke("qs_get").then(s => w.onQs(s))
        Api.listen("captions", c => { w.caption = c })
        Api.listen("mail", ib => w.onInbox(ib))
        Api.listen("update", u => w.applyUpdate(u))
        Api.listen("shortcut", a => {
            if (a === "play")
                return Api.invoke("media_action", { action: "toggle" })
            if (a === "next")
                return Api.invoke("media_action", { action: "next" })
            if (a === "captions")
                return w.toggleCaptions()
            if (a === "toggle") {
                if (Ilot.mode === "open")
                    return Ilot.close()
                Ilot.pinned = true
                return Ilot.open(Ilot.currentTab)
            }
            // onglet d'un addon desactive : rien
            if (!Ilot.hasTab(a))
                return
            if (Ilot.mode === "open" && Ilot.currentTab === a)
                return Ilot.close()
            Ilot.pinned = true
            Ilot.open(a)
        })
    }

    // appele par Ilot.start
    function start() {
        if (Ilot.ui.off && (!Ilot.ui.off.at || Ilot.ui.off.at > Date.now() + 5000))
            off = Ilot.ui.off
        Api.invoke("store_get", { key: "mixprofiles" }).then(p => { if (p && typeof p === "object") w.mixProfiles = p })
        Api.invoke("shortcuts_get").then(m => { w.keyMap = m || {} })
        Api.invoke("captions_on").then(v => { w.capOn = v })
        if (Ilot.hasTab("pc"))
            Api.invoke("services_get").then(l => w.applyServices(l)).catch(() => {})
        Api.invoke("mail_get").then(ib => w.onInbox(ib))
        Api.invoke("update_get").then(u => {
            w.applyUpdate(u)
            w.checkNewVersion(u.current)
        })
        Api.invoke("motion_reduced").then(r => {
            Theme.systemReduced = r
            Theme.applyLook(Ilot.cfg)
        })
        refreshBoost()
    }
}
