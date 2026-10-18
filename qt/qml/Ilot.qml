pragma Singleton
import QtQuick
import IlotCore
import "rank.mjs" as Rank

// Etat de l'ilot et ce qui ne depend pas d'une page (app.js) : reglages,
// theme, etats replie / survol / ouvert, activites de la pilule, lecteur,
// visualiseur, volume, systeme, meteo, notifications, minuteur, mail...
// Les fenetres (Main.qml, Bar.qml) et les pages s'y lient.
Item {
    id: root

    // ===================================================== reglages
    property var cfg: ({
        variant: "tonalspot", mode: "dark", win_accent: false, win_mode: false, island_bg: "solid", city: null, icals: [],
        rotate_min: 0, notif_popups: true, dnd: false, osd: true, bar: false, hide_taskbar: true,
        bar_islands: true, bar_tasks: false, bar_autohide: true, win_key: false, addons: [], update_mode: "notify",
        // apparence de la pilule, compagnon, accessibilite, mode jeu... (gardes
        // tels quels par le coeur dans settings.json)
        color: "auto", day: "07:00", night: "20:00", border: "none", shape: "round", anim: "normal",
        text_size: 100, contrast: "normal", motion: "system", cvd: "off", activity: true, game_mode: true,
        game_perf: true, game_notif: false, match_alert: true, valorant: true, mix_auto: true, away: "on", pet: "blob",
        pet_walk: true, clock: "digital", privacy: true, wxfx: true, dc_pill: true, media_bg: "art", pill_size: "m",
        assist_tr: true, assist_claude: true, bar_titles: true,
        // Claude Code (hooks) : animation, son de fin, duree minimale (s)
        cc_on: true, cc_sound: true, cc_min: 30,
        // compagnon (Reglages > Compagnon)
        pet_color: "nature", pet_eyes: "dot", pet_hat: "none", pet_face: "none", pet_neck: "none", pet_name: "",
        pet_trail: "sparkle", pet_afk: 90, pet_size: "m"
    })
    signal settingsChanged()

    function setCfg(patch) {
        cfg = Object.assign({}, cfg, patch)
        onSettings()
        Api.invoke("settings_set", { patch: patch }).then(c => {
            cfg = Object.assign({}, cfg, c)
        })
    }

    // l'etat de l'interface garde d'une fois sur l'autre (palette, minuteur...)
    property var ui: ({})
    function saveUi(patch) {
        ui = Object.assign({}, ui, patch)
        uiSave.restart()
    }
    property Timer uiSave: Timer {
        interval: 400
        onTriggered: Api.invoke("store_set", { key: "ui", value: root.ui })
    }

    // ======================================================= ilot
    // collapsed -> (survol) peek -> (clic / molette) open
    // En replie, une « activite » (OSD, notification...) peut agrandir la pilule.
    // Apparence > Taille du texte : le panneau grandit avec le texte
    readonly property var openSize: ({ w: Math.round(740 * Theme.textK), h: Math.round(540 * Theme.textK) })
    readonly property int earMax: 22
    readonly property int barH: 30
    property string mode: "collapsed"
    property bool hovered: false
    // ouvert au clavier : ne se referme pas en sortant la souris
    property bool pinned: false
    property bool locked: false
    property bool big: false
    property bool fullscreen: false
    // barre affichee (masquage automatique) et souris dans la bande du haut
    property bool barPeek: false
    property bool atTop: false
    property var act: null
    property string currentTab: "home"
    property int tabDir: 1

    // ================================================== onglets, addons
    // Tous les onglets, dans l'ordre du panneau. Les essentiels (`core`) sont
    // toujours la ; les autres sont des addons a activer dans Reglages >
    // Addons (cfg.addons). Un addon desactive n'a ni onglet, ni page, ni
    // releve en arriere-plan (mail, etat des services, soundboard).
    readonly property var catalog: [
        { id: "home", icon: "dashboard", label: "Accueil", page: "HomePage", core: true },
        { id: "media", icon: "music_note", label: "Média", page: "MediaPage", core: true },
        { id: "ctrl", icon: "tune", label: "Contrôles", page: "CtrlPage", core: true },
        { id: "apps", icon: "apps", label: "Apps", page: "AppsPage", core: true },
        { id: "mail", icon: "mail", label: "Mail", page: "MailPage",
          desc: "Boîtes de réception IMAP (Gmail, Outlook, iCloud…), non lus dans la pilule et notification à chaque nouveau mail" },
        { id: "pc", icon: "sports_esports", label: "PC", page: "PcPage",
          desc: "Discord (micro, volumes du salon), état des services, santé du PC, extinction programmée, mode d'alimentation, sensibilité entre jeux" },
        { id: "sounds", icon: "graphic_eq", label: "Soundboard", page: "SoundsPage",
          desc: "Sons joués dans le vocal Discord par un micro virtuel, avec votre vrai micro" },
        { id: "tasks", icon: "monitoring", label: "Tâches", page: "TasksPage",
          desc: "Gestionnaire des tâches : CPU, mémoire, disque, GPU et réseau par programme, fin de tâche" },
        { id: "clips", icon: "content_paste", label: "Presse-papiers", page: "ClipsPage",
          desc: "Les 40 derniers textes et images copiés, et un bloc-notes" },
        { id: "assist", icon: "translate", label: "Assistant", page: "AssistPage", tip: "Traduction, sous-titres en direct et Claude",
          desc: "Traduction, sous-titres en direct traduits, questions envoyées à Claude",
          // parties de l'addon, a desactiver une a une (cfg)
          parts: [{ key: "assist_tr", label: "Traduction", sub: "Traduction de textes et sous-titres en direct" },
                  { key: "assist_claude", label: "Claude", sub: "Questions envoyées à l'application Claude" }] },
        { id: "walls", icon: "wallpaper", label: "Fonds", page: "WallsPage",
          desc: "Vos fonds d'écran et ceux de Wallpaper Engine ; choisir un fond recalcule les couleurs" },
        { id: "settings", icon: "settings", label: "", tip: "Réglages", page: "SettingsPage", core: true }
    ]
    readonly property var addons: catalog.filter(t => !t.core)
    // onglets affiches : essentiels + addons actives
    readonly property var tabItems: catalog.filter(t => t.core || (cfg.addons || []).indexOf(t.id) >= 0)
    readonly property var tabs: tabItems.map(t => t.id)
    function hasTab(id) {
        return tabs.indexOf(id) >= 0
    }
    function setAddon(id, on) {
        const list = (cfg.addons || []).filter(a => a !== id)
        if (on)
            list.push(id)
        setCfg({ addons: catalog.filter(t => list.indexOf(t.id) >= 0).map(t => t.id) })
        // soundboard coupee : le moteur audio s'arrete (micro rendu)
        if (id === "sounds" && !on)
            Api.invoke("sb_config", { cfg: { on: false, cable: "", mic: "", monitor: false, mic_gain: 1 } })
        if (id === "mail" && on)
            Api.invoke("mail_refresh")
    }
    // un addon desactive alors que son onglet est ouvert : retour a l'accueil
    onTabsChanged: if (!hasTab(currentTab)) currentTab = "home"

    // section ouverte dans Reglages (general, bar, look, pill, pet, game, access,
    // weather, keys, addons, updates)
    property string settingsSection: "general"
    function openSettings(section) {
        if (section)
            settingsSection = section
        pinned = true
        open("settings")
    }
    // taille de l'ecran de l'ilot (pixels logiques), pour le panneau agrandi
    property real screenW: 1920
    property real screenH: 1080
    // apercu des fenetres de la barre de l'ilot ouvert
    property bool previewOpen: false
    // fichiers glisses sur l'ilot replie : il se referme si on ressort
    property bool fileDragOpened: false
    // fichiers glisses au-dessus de l'ilot (le bouton Quick Share s'allume).
    // Passer d'une zone de depot a l'autre fait sortir puis entrer : la
    // sortie n'est prise en compte qu'apres un court delai.
    property bool fileDrag: false
    function dragIn() {
        fileDrag = true
        dragOut.stop()
    }
    function dragLeft() {
        dragOut.restart()
    }
    function dragDone() {
        dragOut.stop()
        fileDrag = false
        fileDragOpened = false
    }
    property Timer dragOut: Timer {
        interval: 250
        onTriggered: {
            root.fileDrag = false
            if (root.fileDragOpened) {
                root.fileDragOpened = false
                root.close()
            }
        }
    }
    // chemins Windows des fichiers deposes depuis l'Explorateur
    function dropPaths(urls) {
        return (urls || []).map(u => decodeURIComponent(String(u).replace(/^file:\/\/\//, "")).replace(/\//g, "\\"))
    }
    // info-bulle affichee : { text, x, y, owner } (TipWindow)
    property var tip: null

    readonly property bool barAuto: !!(cfg.bar && cfg.bar_autohide)
    readonly property bool barVisible: !!cfg.bar && !fullscreen && (!cfg.bar_autohide || barPeek)
    readonly property bool barDocked: barVisible && !cfg.bar_islands

    signal focusSearch()
    signal focusCity()
    signal closeSheets()
    signal closeDay()
    // ce qu'Echap referme avant l'ilot : "sheet" (feuille des controles),
    // "day" (jour du calendrier), "reader" (mail)...
    property string overlay: ""
    signal escapeOverlay(string what)
    function escapeKey() {
        const o = overlay
        overlay = ""
        if (o === "sheet")
            closeSheets()
        else if (o === "day")
            closeDay()
        else
            escapeOverlay(o)
    }

    readonly property var bigSize: ({
        w: Math.max(openSize.w, Math.min(1400, screenW - 160)),
        h: Math.max(openSize.h, Math.min(860, screenH - 120))
    })

    // indicateurs de la pilule repliee
    readonly property int unread: hasTab("mail") ? inbox.accounts.reduce((n, a) => n + a.unread, 0) : 0
    readonly property int indCount: (caffeine ? 1 : 0) + (cfg.dnd ? 1 : 0) + (unread > 0 ? 1 : 0)
    readonly property bool timerShown: tmr.running
    // Apparence > Taille de la pilule (replie / survol ; pas le panneau ouvert)
    readonly property real pillK: mode === "open" ? 1 : ({ s: 0.85, m: 1, l: 1.2 })[cfg.pill_size] || 1
    // largeur de l'horloge selon son style (Apparence > Horloge de la pilule)
    readonly property int clockExtra: ({ flip: 10, analog: -16, pixel: 6 })[cfg.clock] || 0

    function sizeFor(s) {
        if (s === "open")
            return big ? bigSize : openSize
        if (s === "peek") {
            // sans musique ni activite : le compagnon se montre a cote de l'heure
            const p = hasMedia ? { w: 420, h: 66 } : Watch.actShown ? { w: 380, h: 60 }
                : { w: (weather ? 320 : 250) + (Watch.petShown ? 40 : 0), h: 50 }
            return Watch.dcShown ? { w: p.w + 70, h: p.h } : p
        }
        if (act)
            return act.size
        let w = hasMedia ? 200 : 132
        w += indCount * 24 + clockExtra
        if (timerShown)
            w += 70
        // compagnon, activite (telechargement, jeu), Discord, voyant, extinction
        w += (Watch.petShown ? 24 : 0) + (Watch.actShown ? 72 : 0) + (Watch.dcShown ? 26 : 0)
            + (Watch.privShown ? 18 : 0) + (Watch.offShown ? 62 : 0) + (Watch.ccWide ? (Watch.ccText.length > 4 ? 90 : 80) : 0)
        return { w: w, h: 30 }
    }
    // rayon des coins bas
    function radiusFor(s) {
        const r = s === "open" ? 30 : s === "peek" ? (hasMedia ? 26 : 22) : act ? 20 : 15
        // Apparence > Forme de l'ilot (le panneau ouvert garde ses coins)
        if (s === "open")
            return r
        return cfg.shape === "pill" ? Math.min(sizeFor(s).h, r * 1.6) : cfg.shape === "square" ? r * 0.35 : r
    }
    readonly property var size: sizeFor(mode)
    readonly property real radius: radiusFor(mode)
    // un coin concave s'arrete ou commence l'arrondi du bas (sinon il depasse) ;
    // avec la barre (pleine et affichee), il ne pousse que sous son bord
    readonly property real ear: Math.max(0, Math.min(earMax, size.h - radius - (barDocked ? barH : 0)))

    function setMode(s) {
        if (s === mode)
            return
        if (mode === "open")
            releaseFocus()
        mode = s
        // la souris peut quitter l'ilot sans que Qt le voie (zones
        // cliquables reduites) : l'info-bulle ne doit pas rester
        tip = null
        Backend.setIslandOpen(s === "open")
        if (s !== "open") {
            pinned = false
            closeSheets()
            if (!atTop)
                hideBarLater()
        }
        if (s !== "collapsed" && act)
            endActivity(false)
        if (s === "open")
            opened()
        updateViz()
    }
    signal opened()
    signal tabShown(string tab)
    // rendu du clavier (la fenetre de l'ilot le fait, voir Main.qml)
    signal releaseFocus()
    signal grabFocus()

    function open(tab) {
        if (tab)
            showTab(tab)
        setMode("open")
    }
    function close() {
        setMode(hovered ? "peek" : "collapsed")
    }

    function showTab(tab) {
        // onglet d'un addon desactive (raccourci, notification...) : accueil
        if (!hasTab(tab))
            tab = "home"
        tabDir = tabs.indexOf(tab) > tabs.indexOf(currentTab) ? 1 : -1
        if (tab !== currentTab)
            closeSheets()
        currentTab = tab
        tabShown(tab)
        updateViz()
    }

    property Timer leaveTimer: Timer {
        property string to: "collapsed"
        onTriggered: root.setMode(to)
    }
    function setHovered(h) {
        hovered = h
        leaveTimer.stop()
        if (h) {
            if (mode === "collapsed" && !act)
                setMode("peek")
        } else if (mode === "peek") {
            leaveTimer.interval = 120
            leaveTimer.start()
        } else if (mode === "open" && !pinned && !locked) {
            leaveTimer.interval = 450
            leaveTimer.start()
        }
    }
    function setFullscreen(fs) {
        fullscreen = fs
        if (fs) {
            setMode("collapsed")
            endActivity()
        }
        updateViz()
    }
    // la fenetre de l'ilot a perdu le clavier
    function blurred() {
        if (mode === "open" && !hovered && !locked)
            setMode("collapsed")
    }

    // ------------------------------------------- agrandir / verrouiller
    function setBig(on, save) {
        big = on
        const s = on ? bigSize : openSize
        // la fenetre grandit avant le panneau, et retrecit apres l'animation
        if (on)
            Backend.winResize(s.w + 60, s.h + 60)
        else
            later(550, () => { if (!root.big) Backend.winResize(openSize.w + 60, openSize.h + 60) })
        if (save !== false)
            saveLayout()
    }
    // taille du texte changee : la fenetre suit le panneau normal
    onOpenSizeChanged: if (!big) Backend.winResize(openSize.w + 60, openSize.h + 60)
    function setLocked(on, save) {
        locked = on
        if (on)
            leaveTimer.stop()
        if (save !== false)
            saveLayout()
    }
    function saveLayout() {
        Api.invoke("store_set", { key: "layout", value: { big: big, locked: locked } })
    }

    // ================================================== activites
    readonly property var actSize: ({ osd: { w: 300, h: 40 }, small: { w: 290, h: 40 }, notif: { w: 420, h: 66 }, shot: { w: 300, h: 62 }, qs: { w: 470, h: 66 } })
    // change a chaque nouvelle activite (l'OSD se met a jour sans rejouer l'animation)
    property int actSerial: 0
    property Timer actTimer: Timer { onTriggered: root.endActivity() }

    function showActivity(a) {
        if (mode !== "collapsed" || fullscreen)
            return
        const same = act && act.kind === a.kind && a.kind === "osd"
        a.size = actSize[a.size || a.kind] || actSize.small
        act = a
        if (!same)
            actSerial++
        actTimer.interval = a.ms || 2600
        actTimer.restart()
    }
    function endActivity(resize) {
        actTimer.stop()
        if (!act)
            return
        act = null
        if (hovered && mode === "collapsed")
            setMode("peek")
    }
    function simpleActivity(icon, title, sub, extra) {
        showActivity(Object.assign({ kind: "small", icon: icon, title: title, sub: sub || "" }, extra || {}))
    }
    // clic sur la pilule
    function pillClicked() {
        if (act) {
            const tab = act.tab
            const onClick = act.onClick
            endActivity(false)
            if (onClick)
                return onClick()
            return open(tab || null)
        }
        open(hasMedia && currentTab === "home" ? "home" : null)
    }

    // ================================================== horloge
    property date now: new Date()
    property Timer clock: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date()
            if (d.getMinutes() !== root.now.getMinutes() || d.getHours() !== root.now.getHours() || d.getDate() !== root.now.getDate())
                root.now = d
        }
    }
    // ================================================== ambiance
    // Animations d'ambiance (compagnon, meteo animee, aurore, contour, neon) :
    // une animation Qt fait redessiner la fenetre a chaque rafraichissement
    // de l'ecran (jusqu'a 240 images/s). Elles suivent donc une horloge
    // commune a 25 images/s, en pause quand personne ne regarde (1 min sans
    // clavier ni souris) ou en plein ecran.
    readonly property bool ambient: !fullscreen && !Theme.reduced && Watch.idle < 60
    readonly property bool ambientUsed: Watch.petShown || !!cfg.wxfx || cfg.island_bg === "aurora"
        || cfg.border === "rgb" || cfg.border === "pulse" || cfg.clock === "neon" || Watch.ccShown
    readonly property int ambStep: 40
    // millisecondes d'ambiance ecoulees
    property real amb: 0
    property Timer ambClock: Timer {
        interval: root.ambStep
        repeat: true
        // la promenade du compagnon (quand on ne fait rien) et le
        // clignotement « partie trouvee » continuent sans personne
        running: (root.ambient && root.ambientUsed) || ((Watch.petWinOn || Watch.matchFlash) && !Theme.reduced && !root.fullscreen)
        onTriggered: root.amb += root.ambStep
    }
    // va-et-vient 0 -> 1 -> 0 en `period` ms (deux NumberAnimation InOutSine)
    function wave(t, period) {
        return 0.5 - 0.5 * Math.cos(2 * Math.PI * t / period)
    }

    function pad(n) {
        return String(n).padStart(2, "0")
    }
    function hm(d) {
        return pad(d.getHours()) + ":" + pad(d.getMinutes())
    }
    // text-transform: capitalize
    function capitalize(s) {
        return s.replace(/(^|[\s'-])(\S)/g, (m, a, b) => a + b.toUpperCase())
    }
    function upperFirst(s) {
        return s ? s[0].toUpperCase() + s.slice(1) : s
    }
    function fmt(d, f) {
        return d.toLocaleString(Theme.locale, f)
    }

    // ================================================== lecteur
    property var media: ({ has: false, title: "", artist: "", album: "", app: "", playing: false, position: 0, duration: 0 })
    property real mediaAt: 0
    property bool hasMedia: false
    property string art: ""
    // position affichee (secondes), relue toutes les 500 ms pendant la lecture
    property real pos: 0

    function position() {
        if (!media.has)
            return 0
        let p = media.position + (media.playing ? (Date.now() - mediaAt) / 1000 : 0)
        return media.duration ? Math.min(p, media.duration) : p
    }
    function applyMedia(m) {
        media = m
        mediaAt = Date.now()
        hasMedia = m.has && !!(m.title || m.artist)
        pos = position()
        updateViz()
    }
    function mediaAction(action) {
        if (action === "toggle") {
            // retour visuel immediat
            const m = Object.assign({}, media, { playing: !media.playing, position: position() })
            applyMedia(m)
        }
        Api.invoke("media_action", { action: action })
    }
    function seek(v) {
        Api.invoke("media_action", { action: "seek", value: v })
        media = Object.assign({}, media, { position: v })
        mediaAt = Date.now()
        pos = v
    }
    function fmtTime(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + pad(s % 60)
    }
    property Timer progress: Timer {
        interval: 500
        repeat: true
        running: root.media.playing && root.mode !== "collapsed" && !root.fullscreen
        onTriggered: root.pos = root.position()
    }

    // ============================================== visualiseur
    // Le backend capture le son du PC (loopback) et envoie 24 bandes (0..100).
    property bool vizOn: false
    property var bands: []
    // niveaux affiches (0..1) : montent d'un coup, retombent en douceur
    property var shown: new Array(24).fill(0)
    // egaliseur de la pilule anime par le visualiseur (sinon : animation idle)
    property bool live: false

    function updateViz() {
        const visible = mode !== "open" || currentTab === "home" || currentTab === "media"
        const want = !!(hasMedia && media.playing && !fullscreen && visible)
        if (want === vizOn)
            return
        vizOn = want
        Api.invoke("viz_set", { on: want })
        if (!want)
            vizFade.start()
    }
    function drawViz(target) {
        let energy = 0
        const s = shown.slice()
        for (let i = 0; i < s.length; i++) {
            const t = (target[i] || 0) / 100
            s[i] = t > s[i] ? t : s[i] + (t - s[i]) * 0.3
            energy += s[i]
        }
        shown = s
        live = true
        return energy
    }
    property Timer vizFade: Timer {
        interval: 33
        repeat: true
        onTriggered: {
            if (root.drawViz([]) < 0.01) {
                stop()
                root.live = false
                root.shown = new Array(24).fill(0)
            }
        }
    }

    // ================================================== volume
    property var vol: ({ level: 0, muted: false })
    function refreshVolume() {
        Api.invoke("volume_get").then(v => { root.vol = v })
    }
    function setVolume(level, muted) {
        vol = { level: level === undefined ? vol.level : level, muted: !!muted }
        Api.invoke("volume_set", level === undefined ? { muted: !!muted } : { level: level, muted: !!muted })
    }

    // ================================================ ressources
    property var sys: null
    function gb(b) {
        return (b / Math.pow(1024, 3)).toFixed(b > 100 * Math.pow(1024, 3) ? 0 : 1)
    }
    function fmtUptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
        if (d)
            return d + " j " + h + " h"
        if (h)
            return h + " h " + pad(m)
        return m + " min"
    }

    property var user: ({ name: "", avatar: "" })

    // ================================================== meteo
    // Open-Meteo : gratuit, sans cle. Codes meteo OMM -> icone + libelle.
    readonly property var wmo: ({
        0: ["clear_day", "Ciel dégagé"], 1: ["partly_cloudy_day", "Plutôt dégagé"], 2: ["partly_cloudy_day", "Partiellement nuageux"],
        3: ["cloud", "Couvert"], 45: ["foggy", "Brouillard"], 48: ["foggy", "Brouillard givrant"],
        51: ["rainy_light", "Bruine légère"], 53: ["rainy_light", "Bruine"], 55: ["rainy_light", "Bruine dense"],
        56: ["weather_mix", "Bruine verglaçante"], 57: ["weather_mix", "Bruine verglaçante"],
        61: ["rainy_light", "Pluie faible"], 63: ["rainy", "Pluie"], 65: ["rainy_heavy", "Forte pluie"],
        66: ["weather_mix", "Pluie verglaçante"], 67: ["weather_mix", "Pluie verglaçante"],
        71: ["weather_snowy", "Neige faible"], 73: ["weather_snowy", "Neige"], 75: ["snowing_heavy", "Forte neige"], 77: ["weather_snowy", "Grains de neige"],
        80: ["rainy_light", "Averses"], 81: ["rainy", "Averses"], 82: ["rainy_heavy", "Fortes averses"],
        85: ["weather_snowy", "Averses de neige"], 86: ["snowing_heavy", "Averses de neige"],
        95: ["thunderstorm", "Orage"], 96: ["thunderstorm", "Orage et grêle"], 99: ["thunderstorm", "Orage et grêle"]
    })
    readonly property var night: ({ clear_day: "clear_night", partly_cloudy_day: "partly_cloudy_night" })
    property var weather: null

    function refreshWeather() {
        const c = cfg.city
        if (!c) {
            weather = null
            return
        }
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + c.lat + "&longitude=" + c.lon
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=1"
        Api.invoke("http_get", { url: url }).then(text => {
            const j = JSON.parse(text)
            const w = wmo[j.current.weather_code] || ["cloud", "—"]
            // « 2026-10-16T08:12 » -> minutes (theme clair / sombre « soleil »)
            const mins = t => t ? Number(t.slice(11, 13)) * 60 + Number(t.slice(14, 16)) : NaN
            const sun = [mins((j.daily.sunrise || [])[0]), mins((j.daily.sunset || [])[0])]
            if (sun.every(Number.isFinite))
                root.sunTimes = sun
            root.weather = {
                icon: j.current.is_day ? w[0] : night[w[0]] || w[0], label: w[1],
                temp: Math.round(j.current.temperature_2m), feels: Math.round(j.current.apparent_temperature),
                min: Math.round(j.daily.temperature_2m_min[0]), max: Math.round(j.daily.temperature_2m_max[0]),
                code: j.current.weather_code, day: !!j.current.is_day
            }
        }).catch(e => console.warn("météo", e))
    }
    property Timer weatherTimer: Timer {
        interval: 20 * 60000
        running: true
        repeat: true
        onTriggered: root.refreshWeather()
    }

    // =========================================== reseau, cafeine
    property var net: ({ radios: { wifi: null, bluetooth: null }, ssid: "", bt_devices: [] })
    property bool caffeine: false
    function toggleRadio(kind) {
        const key = kind === "wifi" ? "wifi" : "bluetooth"
        const on = !net.radios[key]
        const radios = Object.assign({}, net.radios)
        radios[key] = on
        net = Object.assign({}, net, { radios: radios })
        Api.invoke("radio_set", { kind: kind, on: on }).then(() => Api.invoke("net_get")).then(n => { root.net = n })
    }
    function toggleCaffeine() {
        Api.invoke("caffeine_set", { on: !caffeine }).then(v => { root.caffeine = v })
    }
    function toggleDnd() {
        setCfg({ dnd: !cfg.dnd })
    }

    // ============================================ notifications
    property var notifs: []
    function norm(s) {
        return String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    }
    function appFor(id) {
        const low = (id || "").toLowerCase()
        const a = apps.find(x => x.id.toLowerCase() === low)
        if (a)
            return { name: a.name, icon: a.icon }
        const base = (id || "").split(/[\\/!]/).pop().replace(/\.exe$/i, "").replace(/_[a-z0-9]{13}$/i, "")
        const b = apps.find(x => norm(x.name) === norm(base))
        return { name: b ? b.name : base || "Application", icon: b ? b.icon : "" }
    }
    function ago(ms) {
        const s = (Date.now() - ms) / 1000
        if (s < 60)
            return "à l'instant"
        if (s < 3600)
            return "il y a " + Math.floor(s / 60) + " min"
        const d = new Date(ms)
        if (d.toDateString() === new Date().toDateString())
            return hm(d)
        const y = new Date()
        y.setDate(y.getDate() - 1)
        if (d.toDateString() === y.toDateString())
            return "hier"
        return fmt(d, "d MMM")
    }

    // =============================================== minuteur
    // Minuteur simple ou Pomodoro (25 min de travail / 5 min de pause).
    property var tmr: ({ total: 300000, remaining: 300000, end: 0, running: false, pomo: null })
    readonly property var pomo: ({ focus: 25 * 60000, "break": 5 * 60000 })
    // relu toutes les 250 ms tant que le minuteur tourne
    property real tick: Date.now()
    readonly property real timerLeft: tmr.running ? Math.max(0, tmr.end - tick) : tmr.remaining

    function fmtMs(ms) {
        const s = Math.ceil(ms / 1000)
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
        return h ? h + ":" + pad(m) + ":" + pad(r) : pad(m) + ":" + pad(r)
    }
    function saveTimer() {
        saveUi({ timer: tmr })
    }
    function timerSet(ms, p) {
        tmr = { total: ms, remaining: ms, end: 0, running: false, pomo: p || null }
        tick = Date.now()
        saveTimer()
    }
    function timerStart() {
        const t = Object.assign({}, tmr)
        if (t.remaining <= 0)
            t.remaining = t.total
        t.end = Date.now() + t.remaining
        t.running = true
        tick = Date.now()
        tmr = t
        saveTimer()
    }
    function timerPause() {
        tmr = Object.assign({}, tmr, { remaining: timerLeft, running: false })
        saveTimer()
    }
    function timerToggle() {
        tmr.running ? timerPause() : timerStart()
    }
    function timerReset() {
        timerSet(tmr.pomo ? pomo.focus : tmr.total, null)
    }
    function startPomodoro() {
        timerSet(pomo.focus, "focus")
        timerStart()
    }
    function startTimer(min) {
        timerSet(min * 60000)
        timerStart()
    }
    function adjustTimer(d) {
        const left = Math.max(60000, timerLeft + d)
        const t = Object.assign({}, tmr)
        t.total = Math.max(t.total + d, left)
        if (t.running)
            t.end = Date.now() + left
        else
            t.remaining = left
        tick = Date.now()
        tmr = t
        saveTimer()
    }
    function timerDone() {
        Backend.beep()
        if (tmr.pomo) {
            const next = tmr.pomo === "focus" ? "break" : "focus"
            simpleActivity(next === "break" ? "self_improvement" : "psychology", next === "break" ? "Pause !" : "Au travail !",
                next === "break" ? "5 minutes de repos" : "25 minutes de concentration", { ms: 6000, tab: "ctrl" })
            timerSet(pomo[next], next)
            timerStart()
        } else {
            simpleActivity("alarm", "Minuteur terminé", fmtMs(tmr.total), { ms: 8000, tab: "ctrl" })
            tmr = Object.assign({}, tmr, { running: false, remaining: tmr.total })
            saveTimer()
        }
    }
    property Timer timerTick: Timer {
        interval: 250
        repeat: true
        running: root.tmr.running
        onTriggered: {
            root.tick = Date.now()
            if (root.timerLeft <= 0)
                root.timerDone()
        }
    }

    // ========================================== applis, jeux, dossiers
    property var apps: []
    property var games: []
    // %LOCALAPPDATA%\Ilot\folders.json : { list: [{ id, name, apps: [id...] }], sel... }
    property var folders: ({ list: [], sel: "" })
    function saveFolders() {
        folders = Object.assign({}, folders)
        Api.invoke("store_set", { key: "folders", value: folders })
    }
    // %LOCALAPPDATA%\Ilot\usage.json : lancements notés pour classer les résultats (rank.mjs)
    property var usage: Rank.empty()
    function noteLaunch(id, query) {
        if (!id)
            return
        usage = Object.assign({}, Rank.record(usage, id, norm(query || ""), Date.now()))
        Api.invoke("store_set", { key: "usage", value: usage })
    }
    function forgetUsage() {
        usage = Rank.empty()
        Api.invoke("store_set", { key: "usage", value: usage })
    }
    readonly property var gameHints: /steam|epic games|roblox|minecraft|riot client|valorant|league of legends|battle\.net|ubisoft|ea app|gog galaxy|fortnite|rockstar|xbox|playnite|heroic|curseforge|lunar client|genshin|hoyoplay/
    function newFolder(name) {
        const f = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), name: name, apps: [] }
        folders.list.push(f)
        return f
    }
    // range les jeux reconnus dans « Jeux » au premier lancement
    function seedGames() {
        if (folders.seeded !== false || !apps.length)
            return
        const jeux = folders.list.find(f => f.name === "Jeux")
        if (jeux)
            jeux.apps = apps.filter(a => gameHints.test(a.name.toLowerCase()) && !/studio|editor|server/i.test(a.name)).map(a => a.id)
        delete folders.seeded
        saveFolders()
    }

    // ================================================== mail
    property var inbox: ({ accounts: [], mails: [], google: false })

    // ========================================= presse-papiers, notes
    property var clips: []
    // bloc-notes : [{ id, text, t }], note ouverte, mise en forme Markdown
    property var notes: []
    property string noteCur: ""
    property bool notesMd: true
    signal notesLoaded()

    // ========================================= fonds d'ecran
    property var we: ({ installed: false, running: false, current: "" })
    property string currentThumb: ""
    signal wallChanged(var current)

    function syncWall() {
        Api.invoke("we_state").then(w => {
            root.we = w
            return Api.invoke("wall_current")
        }).then(w => {
            if (w && w.thumb !== root.currentThumb) {
                root.currentThumb = w.thumb
                root.themeFrom(w.thumb)
            }
            root.wallChanged(w)
        })
    }

    // ========================================= agenda, notes du calendrier
    property var icalTexts: []
    property real icalAt: 0
    // %LOCALAPPDATA%\Ilot\calnotes.json : { "AAAA-MM-JJ": "texte" }
    property var calNotes: ({})
    function refreshEvents(force) {
        if (!cfg.icals.length) {
            if (icalTexts.length)
                icalTexts = []
            return
        }
        if (!force && Date.now() - icalAt < 15 * 60000)
            return
        icalAt = Date.now()
        Promise.all(cfg.icals.map(u => Api.invoke("http_get", { url: u }).catch(() => ""))).then(texts => {
            root.icalTexts = texts.filter(Boolean)
        })
    }
    property Timer icalTimer: Timer {
        interval: 15 * 60000
        running: true
        repeat: true
        onTriggered: root.refreshEvents()
    }

    // ================================================ Discord
    property var dc: ({ status: "setup", people: [] })

    // ================================================ playlists
    property var playlists: []

    // ==================================================== barre
    property var barWins: ({ windows: [], active: 0, desktops: 1, desktop: 0 })
    // cle d'icone -> URL ('' : pas d'icone, null : en cours)
    property var taskIcons: ({})
    property int taskIconsRev: 0
    property var iconTries: ({})
    property bool taskbarPeek: false
    // derniere capture de chaque fenetre (gardee une fois reduite)
    property var thumbs: ({})
    property var minimized: ({})
    property int thumbsRev: 0
    property real lastActive: 0

    function taskGroups(t) {
        const keys = []
        const groups = {}
        for (const w of t.windows) {
            if (!groups[w.icon]) {
                groups[w.icon] = []
                keys.push(w.icon)
            }
            groups[w.icon].push(w)
        }
        return keys.map(k => ({ key: k, wins: groups[k] }))
    }
    function loadTaskIcon(key, id) {
        if (taskIcons[key] !== undefined)
            return
        taskIcons[key] = null
        Api.invoke("task_icon", { key: key, id: id }).then(src => {
            root.taskIcons[key] = src || ""
            root.taskIconsRev++
            if (src)
                return
            // echec passager (demarrage de Windows, appli qui se lance) : on reessaie
            const n = (root.iconTries[key] = (root.iconTries[key] || 0) + 1)
            if (n <= 5)
                root.later(2000 * n, () => { delete root.taskIcons[key]; root.taskIconsRev++ })
        })
    }
    readonly property int pvW: 220
    readonly property int pvH: 124
    function loadThumb(id, dpr) {
        return Api.invoke("task_thumb", { id: id, w: Math.round(pvW * dpr), h: Math.round(pvH * dpr) }).then(src => {
            if (src === "min")
                root.minimized[id] = true
            else {
                delete root.minimized[id]
                root.thumbs[id] = src
            }
            if (src === "min" && root.thumbs[id] === undefined)
                root.thumbs[id] = ""
            root.thumbsRev++
        })
    }
    function applyBarWins(t) {
        barWins = t
        const ids = {}
        for (const w of t.windows)
            ids[w.id] = true
        for (const id in thumbs)
            if (!ids[id])
                delete thumbs[id]
        // la fenetre qui vient d'etre activee est capturee : une fois reduite,
        // son apercu montrera encore son contenu
        if (t.active !== lastActive) {
            lastActive = t.active
            const id = t.active
            if (id)
                later(800, () => { if (root.barWins.active === id) root.loadThumb(id, 1.5) })
        }
    }

    // ==================================================== theme
    property bool winLight: false
    property var sourceArgb: null
    // couleur tiree de la pochette en cours (Apparence > Couleur : Pochette)
    property var artArgb: null
    // lever / coucher du soleil, en minutes depuis minuit (donnes par la meteo)
    property var sunTimes: null
    // minute courante, pour les modes « selon l'heure » et « soleil »
    readonly property int nowMin: now.getHours() * 60 + now.getMinutes()
    function hmMin(s) {
        const p = String(s || "0:0").split(":").map(Number)
        return p[0] * 60 + (p[1] || 0)
    }
    readonly property bool dark: {
        const m = cfg.mode
        if (m === "auto")
            return !winLight
        if (m === "time" || m === "sun") {
            const ab = m === "sun" && sunTimes ? sunTimes : [hmMin(cfg.day), hmMin(cfg.night)]
            const a = ab[0], b = ab[1], n = nowMin
            return a <= b ? !(n >= a && n < b) : (n >= b && n < a)
        }
        return m !== "light"
    }
    onDarkChanged: applyTheme()
    property int themeSerial: 0
    // couleur source effective : fixe, pochette (sinon fond d'ecran), fond d'ecran
    readonly property var themeArgb: {
        const c = cfg.color || "auto"
        if (/^#[0-9a-fA-F]{6}$/.test(c))
            return 0xff000000 | parseInt(c.slice(1), 16)
        if (c === "art" && hasMedia && artArgb !== null)
            return artArgb
        return sourceArgb
    }
    onThemeArgbChanged: applyTheme()

    function applyTheme() {
        Theme.light = !dark
        const src = themeArgb
        if (src === null || src === undefined)
            return
        const s = Theme.scheme(src, cfg.variant, dark)
        const p = Theme.paletteOf(s)
        Theme.applyPalette(p)
        Theme.applyLook(cfg)
        saveUi({ palette: p, light: !dark })
        syncWindows(s, dark)
        themeSerial++
    }
    function syncWindows(s, isDark) {
        if (cfg.win_mode && cfg.mode !== "auto" && winLight === isDark) {
            winLight = !isDark
            Api.invoke("win_theme_apply", { light: !isDark, palette: null })
        }
        if (cfg.win_accent) {
            const list = Theme.accentList(s)
            const key = list.join(",")
            if (key !== ui.winAccent) {
                saveUi({ winAccent: key })
                Api.invoke("win_theme_apply", { light: null, palette: list })
            }
        }
    }
    // couleur source tiree d'une image (miniature du fond d'ecran), calculee
    // par le coeur (theme_source : quantification de material-color-utilities)
    property int quantId: 0
    function themeFrom(src) {
        if (!src)
            return
        const id = ++quantId
        Api.invoke("theme_source", { url: src, max: 128 }).then(argb => {
            if (argb === null || id !== root.quantId)
                return
            root.sourceArgb = argb
            root.saveUi({ source: argb })
            root.applyTheme()
        })
    }
    // couleur de la pochette, seulement si elle sert (Apparence > Couleur : Pochette)
    property int artSeq: 0
    function artColor() {
        if (cfg.color !== "art" || !art)
            return
        const id = ++artSeq
        Api.invoke("theme_source", { url: art, max: 64 }).then(argb => {
            if (argb !== null && id === root.artSeq)
                root.artArgb = argb
        })
    }
    onArtChanged: artColor()

    // --- fond de l'ilot : opacite de la couleur de surface, ou flou acrylique
    // de Windows derriere (WinCtl.setBackdrop)
    readonly property var islandAlpha: ({ solid: 1, glass: 0.8, clear: 0.55, wall: 0.5 })
    property bool acrylic: false
    function applyIslandBg() {
        const m = cfg.island_bg || "solid"
        // contraste eleve : fond toujours opaque
        Theme.islandAlpha = cfg.contrast === "high" ? 1 : islandAlpha[m] !== undefined ? islandAlpha[m] : 1
        Theme.islandBlack = m === "black"
        acrylic = m === "wall" && cfg.contrast !== "high"
    }

    // les reglages ont change (ici ou par une commande)
    function onSettings() {
        Theme.applyLook(cfg)
        applyTheme()
        artColor()
        applyIslandBg()
        if (!barAuto)
            barPeek = false
        settingsChanged()
    }

    // ================================================ barre (affichage)
    property Timer barTimer: Timer {
        interval: 500
        onTriggered: {
            if (root.mode !== "open" && !root.atTop && !root.previewOpen)
                root.showBar(false)
        }
    }
    function showBar(on) {
        barTimer.stop()
        barPeek = on
    }
    // la barre reste tant que le panneau de l'ilot est ouvert
    function hideBarLater() {
        barTimer.stop()
        if (barPeek)
            barTimer.start()
    }
    function setAtTop(on) {
        atTop = on
        if (on)
            showBar(true)
        else
            hideBarLater()
    }
    // module de la barre : ouvre l'onglet de l'ilot, un second clic le referme
    function openFromBar(tab) {
        if (mode === "open" && currentTab === tab)
            return setMode("collapsed")
        pinned = true
        open(tab)
        grabFocus()
    }

    // ============================================== utilitaires
    property Component timerComp: Component { Timer {} }
    // setTimeout
    function later(ms, fn) {
        const t = timerComp.createObject(root, { interval: ms })
        t.triggered.connect(() => {
            fn()
            t.destroy()
        })
        t.start()
        return t
    }
    function cancel(t) {
        if (t) {
            t.stop()
            t.destroy()
        }
    }

    // ================================================== evenements
    Component.onCompleted: {
        Api.listen("media", p => applyMedia(p))
        Api.listen("media-art", p => { root.art = p })
        Api.listen("viz", p => {
            root.bands = p
            root.vizFade.stop()
            root.drawViz(root.vizOn ? p : [])
        })
        Api.listen("osd", o => {
            if (o.kind === "volume")
                root.vol = { level: o.value, muted: o.muted }
            if (!root.cfg.osd)
                return
            const v = o.muted ? 0 : o.value
            const icon = o.kind === "brightness"
                ? (v < 0.34 ? "brightness_low" : v < 0.67 ? "brightness_medium" : "brightness_high")
                : (o.muted || v === 0 ? "volume_off" : v < 0.5 ? "volume_down" : "volume_up")
            root.showActivity({ kind: "osd", icon: icon, value: v, label: o.muted ? "–" : String(Math.round(v * 100)), ms: 1600 })
        })
        Api.listen("activity", a => {
            switch (a.kind) {
            case "caps":
                root.simpleActivity(a.on ? "keyboard_capslock_badge" : "keyboard_capslock", a.on ? "Verr. Maj activé" : "Verr. Maj désactivé", "", { ms: 1400 })
                break
            case "power":
                root.simpleActivity(a.on ? "battery_charging_full" : "battery_full", a.on ? "En charge" : "Sur batterie", a.battery >= 0 ? a.battery + " %" : "")
                break
            case "bt":
                root.simpleActivity(a.on ? "bluetooth_connected" : "bluetooth_disabled", a.name, a.on ? "Connecté" : "Déconnecté", { tab: "ctrl" })
                break
            case "shot":
                root.showActivity({ kind: "shot", ms: 3200, tab: "clips", thumb: a.thumb, title: "Image copiée", sub: "Dans le presse-papiers" })
                break
            }
        })
        Api.listen("sys", r => { root.sys = r })
        Api.listen("net", n => { root.net = n })
        Api.listen("caffeine", c => { root.caffeine = c })
        Api.listen("notifs", l => { root.notifs = l })
        // notifications Windows : par la file de Watch (mode jeu, mode absent)
        Api.listen("notif", x => {
            const app = root.appFor(x.app)
            Watch.notify({ app: app.name, icon: x.image || app.icon, title: x.title, body: x.body || "", tab: "ctrl", ms: 5200 })
        })
        Api.listen("apps", l => {
            root.apps = l
            root.seedGames()
        })
        Api.listen("games", l => { root.games = l })
        Api.listen("mail", ib => { root.inbox = ib })
        Api.listen("discord", s => { root.dc = s })
        Api.listen("clips", l => { root.clips = l })
        Api.listen("wall-changed", () => root.syncWall())
        Api.listen("tasks", t => root.applyBarWins(t))
        Api.listen("taskbar-peek", p => { root.taskbarPeek = p })
        Api.listen("win-theme", l => {
            root.winLight = l
            if (root.cfg.mode === "auto")
                root.applyTheme()
        })
        Api.listen("settings", c => {
            const icalsChanged = JSON.stringify(c.icals) !== JSON.stringify(root.cfg.icals)
            const cityChanged = JSON.stringify(c.city) !== JSON.stringify(root.cfg.city)
            root.cfg = Object.assign({}, root.cfg, c)
            root.onSettings()
            if (icalsChanged)
                root.refreshEvents(true)
            if (cityChanged)
                root.refreshWeather()
        })
        Api.listen("open", tab => {
            root.pinned = true
            root.open(tab)
        })
        Api.listen("launcher", () => {
            if (root.mode === "open" && root.currentTab === "apps")
                return root.setMode("collapsed")
            root.pinned = true
            root.open("apps")
            root.later(60, () => root.focusSearch())
        })
    }

    // Appele par Main.qml une fois le coeur Rust demarre
    function start() {
        // etat garde de la derniere fois (palette d'abord : pas d'eclair violet)
        try {
            ui = Api.call("store_get", { key: "ui" }) || {}
        } catch (e) {
            ui = {}
        }
        if (ui.palette)
            Theme.applyPalette(ui.palette)
        if (ui.source !== undefined)
            sourceArgb = ui.source
        if (ui.timer)
            tmr = ui.timer
        try {
            winLight = Api.call("win_theme_get")
            cfg = Object.assign({}, cfg, Api.call("settings_get"))
            caffeine = Api.call("caffeine_get")
        } catch (e) {
            console.warn("démarrage", e)
        }
        onSettings()
        refreshWeather()
        refreshEvents(true)
        Api.invoke("store_get", { key: "layout" }).then(l => {
            if (l && l.big)
                root.setBig(true, false)
            if (l && l.locked)
                root.setLocked(true, false)
        })
        Api.invoke("media_get").then(m => root.applyMedia(m))
        Api.invoke("media_art").then(a => { root.art = a })
        Api.invoke("volume_get").then(v => { root.vol = v })
        Api.invoke("user_info").then(u => { root.user = u })
        Api.invoke("net_get").then(n => { root.net = n })
        Api.invoke("notifs_get").then(l => { root.notifs = l })
        Api.invoke("apps_get").then(l => {
            if (l.length) {
                root.apps = l
                root.seedGames()
            }
        })
        Api.invoke("games_get").then(l => { if (l.length) root.games = l })
        Api.invoke("mail_get").then(ib => { root.inbox = ib })
        Api.invoke("discord_get").then(s => { root.dc = s })
        Api.invoke("clips_get").then(l => { root.clips = l })
        Api.invoke("bar_windows").then(t => root.applyBarWins(t))
        Api.invoke("store_get", { key: "calnotes" }).then(n => { if (n && typeof n === "object") root.calNotes = n })
        Api.invoke("store_get", { key: "notes" }).then(n => {
            if (!n)
                return
            if (Array.isArray(n.notes)) {
                root.notes = n.notes.filter(x => x && x.id && typeof x.text === "string")
                root.noteCur = n.cur || ""
                root.notesMd = n.md !== false
            } else if (typeof n.text === "string" && n.text) {
                // ancien bloc-notes (une seule note)
                root.notes = [{ id: "n" + Date.now().toString(36), text: n.text, t: Date.now() }]
            }
            root.notesLoaded()
        })
        Api.invoke("store_get", { key: "playlists" }).then(l => { if (Array.isArray(l)) root.playlists = l })
        Api.invoke("store_get", { key: "usage" }).then(u => { root.usage = Rank.clean(u) })
        Api.invoke("store_get", { key: "folders" }).then(saved => {
            if (saved && Array.isArray(saved.list)) {
                root.folders = Object.assign({}, saved, {
                    sel: saved.sel || "", hidden: saved.hidden || [], added: saved.added || {}, sort: saved.sort || "name",
                    games: saved.games || [], hiddenGames: saved.hiddenGames || []
                })
            } else {
                root.folders = { list: [], sel: "" }
                root.newFolder("Jeux")
                root.newFolder("Apps")
                root.newFolder("Cours")
                root.folders.seeded = false
            }
            root.seedGames()
        })
        syncWall()
        Watch.start()
        const t = Backend.startupTab()
        if (t) {
            pinned = true
            open(t)
        }
    }
}
