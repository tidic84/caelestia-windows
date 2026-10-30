import QtQuick
import IlotCore

// Reglages, en onglets groupes (a gauche). Personnaliser : theme, ilot et
// pilule, lecteur, compagnon. Comportement : alertes, barre et ecran, jeu et
// absence, son. Systeme : clavier, meteo et agenda, accessibilite, addons,
// mises a jour (et demarrage, sauvegarde). Maquette :
// docs/dev/maquettes/reglages.html
//
// Brouillon : un reglage change ne s'applique qu'a « Enregistrer » (barre en
// bas, Ctrl+S) ; « Annuler » l'oublie. Tant qu'il reste des modifications,
// on ne quitte pas l'onglet Reglages (Ilot.settingsDirty). Restent immediats :
// sorties audio, ville, agendas, addons, applis du plein ecran, raccourcis,
// ecran, demarrage, et les boutons d'action (exporter, tester...)
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "settings"
    // reglages affiches : ceux de l'ilot, et le brouillon par-dessus
    readonly property var cfg: Object.assign({}, Ilot.cfg, draft)
    // Compagnon : pack de sprites choisi dans le brouillon (Watch.petPacks)
    readonly property var petPackDraft: Watch.petPackOf(cfg.pet)
    // pack absent du poste : traite comme une espece dessinee (blob)
    readonly property bool petIsPack: !!petPackDraft
    // promenade : elle montre le reglage enregistre (Watch), pas le brouillon
    readonly property bool petSaved: (cfg.pet || "blob") === (Ilot.cfg.pet || "blob")
    // packs caches tant qu'ils ne sont pas debloques (ui.json) ; un pack deja
    // choisi (enregistre ou brouillon) garde sa puce
    readonly property bool petPacksUnlocked: !!Ilot.ui.petPacksUnlocked
    // chaines intermediaires : cfg change a chaque reglage, elles seulement si
    // l'espece change (sinon toutes les puces seraient recreees)
    readonly property string petDraftId: cfg.pet || ""
    readonly property string petSavedId: Ilot.cfg.pet || ""
    readonly property var petPacksShown: Watch.petPacks.filter(p => petPacksUnlocked
        || "pack:" + p.id === petDraftId || "pack:" + p.id === petSavedId)
    // deblocage : taper le nom exact d'un pack dans la recherche le propose
    // (searchHits) ; le choisir ajoute les packs aux puces de Compagnon
    signal petUnlocked()
    function unlockPacks() {
        if (!petPacksUnlocked)
            Ilot.saveUi({ petPacksUnlocked: true })
        Ilot.settingsSection = "pet"
        // apres le chargement de l'apercu de l'onglet
        Qt.callLater(() => page.petUnlocked())
    }
    // onglet des reglages (Ilot.openSettings l'ouvre de l'exterieur ; les
    // anciens noms d'onglets y menent encore)
    readonly property string section: {
        const s = ({ general: "updates", look: "theme", pill: "island" })[Ilot.settingsSection] || Ilot.settingsSection
        return sections.some(x => x.id === s) ? s : "theme"
    }
    readonly property var sections: [
        { id: "theme", icon: "palette", label: "Thème", group: "Personnaliser" },
        { id: "island", icon: "pill", label: "Îlot et pilule" },
        { id: "player", icon: "music_note", label: "Lecteur" },
        { id: "pet", icon: "emoji_emotions", label: "Compagnon" },
        { id: "alerts", icon: "notifications", label: "Alertes", group: "Comportement" },
        { id: "bar", icon: "dashboard", label: "Barre et écran" },
        { id: "game", icon: "sports_esports", label: "Jeu et absence" },
        { id: "sound", icon: "volume_up", label: "Son" },
        { id: "keys", icon: "keyboard", label: "Clavier", group: "Système" },
        { id: "weather", icon: "partly_cloudy_day", label: "Météo et agenda" },
        { id: "access", icon: "accessibility_new", label: "Accessibilité" },
        { id: "addons", icon: "grid_view", label: "Addons" },
        { id: "updates", icon: "system_update", label: "Mises à jour" }
    ]
    onSectionChanged: flick.contentY = 0

    // --------------------------------------------------------- brouillon
    // reglages changes, pas encore enregistres ({ cle: valeur })
    property var draft: ({})
    readonly property int dirtyCount: Object.keys(draft).length
    readonly property bool dirty: dirtyCount > 0
    onDirtyChanged: Ilot.settingsDirty = dirty
    // remplace Ilot.setCfg dans la page : une valeur revenue a celle de
    // l'ilot sort du brouillon
    function set(patch) {
        const d = Object.assign({}, draft)
        for (const k in patch) {
            // interrupteur jamais enregistre (affiche par defaut), coupe puis
            // rallume : revenu a l'etat de depart
            const back = Ilot.cfg[k] === undefined && typeof patch[k] === "boolean"
                && typeof d[k] === "boolean" && d[k] !== patch[k]
            if (back || JSON.stringify(patch[k]) === JSON.stringify(Ilot.cfg[k]))
                delete d[k]
            else
                d[k] = patch[k]
        }
        draft = d
    }
    function save() {
        if (!dirty)
            return
        const patch = Object.assign({}, draft)
        // touche Windows : invite administrateur, puis win_key si elle a reussi
        const winKey = patch.win_key
        delete patch.win_key
        // couleur d'accent de Windows : force la reapplication
        if (patch.win_accent)
            Ilot.saveUi({ winAccent: null })
        draft = ({})
        changesOpen = false
        if (Object.keys(patch).length)
            Ilot.setCfg(patch)
        if (winKey !== undefined)
            winKeyRemap(winKey)
    }
    function cancel() {
        draft = ({})
        changesOpen = false
    }
    // onglet de chaque reglage (points sur les onglets, liste des changements)
    function secOf(k) {
        const m = {
            color: "theme", variant: "theme", mode: "theme", day: "theme", night: "theme", win_accent: "theme",
            win_mode: "theme", rotate_min: "theme", preset: "theme",
            shape: "island", island_bg: "island", oled: "island", border: "island", pill_size: "island", clock: "island", anim: "island",
            pet: "pet", notif_popups: "alerts", osd: "alerts", activity: "alerts", dc_pill: "alerts", privacy: "alerts", wxfx: "alerts",
            bar: "bar", hide_taskbar: "bar", fs_hide: "bar", game_mode: "game", game_perf: "game", game_notif: "game",
            match_alert: "game", valorant: "game", away: "game", win_key: "keys", text_size: "access", contrast: "access",
            motion: "access", cvd: "access", update_mode: "updates"
        }
        if (m[k])
            return m[k]
        for (const [pre, s] of [["player_", "player"], ["media_", "player"], ["pet_", "pet"], ["bar_", "bar"]])
            if (k.startsWith(pre))
                return s
        return "addons"
    }
    // { onglet: nombre de reglages changes }
    readonly property var dirtySecs: {
        const r = {}
        for (const k in draft) {
            const s = secOf(k)
            r[s] = (r[s] || 0) + 1
        }
        return r
    }
    property bool changesOpen: false
    // titres et libelles des choix, notes par les onglets crees (SubTitle,
    // SetRow, Chips) ; complets pour les reglages sans titre a eux
    property var titles: ({
        day: "Clair de", night: "Clair jusqu'à", cc_min: "Son de Claude Code, après", preset: "Thème prêt",
        shape: "Forme", island_bg: "Fond", oled: "Cartes noires (OLED)", border: "Contour", clock: "Horloge", anim: "Animations"
    })
    // (choix de l'ilot ici : les themes prets les changent sans ouvrir son onglet)
    property var choices: ({
        shape: [["round", "Arrondie"], ["pill", "Pilule"], ["square", "Carrée"]],
        island_bg: [["solid", "Opaque"], ["black", "Noir pur"], ["glass", "Translucide"], ["clear", "Très transparent"], ["wall", "Acrylique"], ["aurora", "Aurore boréale"]],
        border: [["none", "Aucun"], ["line", "Liseré"], ["glow", "Lueur"], ["rgb", "Arc-en-ciel"], ["pulse", "Pulsation"]],
        clock: [["digital", "Classique"], ["flip", "À volets"], ["analog", "À aiguilles"], ["neon", "Néon"], ["pixel", "Pixel"]],
        anim: [["normal", "Normale"], ["fast", "Rapide"], ["soft", "Douce"], ["calm", "Sans rebond"], ["off", "Instantanée"]]
    })
    readonly property var namedValues: ({ auto: "Automatique", art: "Pochette", theme: "Thème", nature: "Naturelle" })
    // valeur lisible : choix, oui / non, couleur
    function fmt(k, v) {
        if (v === undefined || v === null)
            return "par défaut"
        if (typeof v === "boolean")
            return v ? "oui" : "non"
        const c = (choices[k] || []).find(x => x[0] === v)
        if (c)
            return c[1]
        if (k === "variant") {
            const t = Theme.variants.find(x => x.id === v)
            if (t)
                return t.label
        }
        return namedValues[v] || String(v)
    }
    // [cle, titre, avant, apres], dans l'ordre des onglets
    readonly property var changes: {
        const order = sections.map(s => s.id)
        return Object.keys(draft).sort((a, b) => order.indexOf(secOf(a)) - order.indexOf(secOf(b)))
            .map(k => [k, titles[k] || k, fmt(k, Ilot.cfg[k]), fmt(k, draft[k])])
    }
    // on a voulu quitter Reglages avec des modifications : la barre tremble
    signal nudge()
    Connections {
        target: Ilot
        function onSettingsLeaveBlocked() {
            page.nudge()
        }
    }
    Shortcut {
        sequence: "Ctrl+S"
        enabled: page.shown && page.dirty
        onActivated: page.save()
    }

    // ------------------------------------------- apercus (brouillon)
    // couleur source, mode et palette du brouillon, sans toucher au theme
    readonly property var pArgb: {
        const c = cfg.color || "auto"
        if (/^#[0-9a-fA-F]{6}$/.test(c))
            return 0xff000000 | parseInt(c.slice(1), 16)
        // (comme Ilot.themeArgb, mais pour la couleur du brouillon)
        const src = c === "art" && Ilot.hasMedia && Ilot.artArgb !== null ? Ilot.artArgb : Ilot.sourceArgb
        return src !== null && src !== undefined ? src : 0xff6750a4
    }
    readonly property bool pDark: Ilot.darkFor(cfg)
    readonly property var pal: {
        if (!preview.want || !shown)
            return null
        const s = Theme.scheme(pArgb, cfg.variant, pDark)
        const p = Theme.paletteOf(s)
        if (pDark && cfg.oled)
            Theme.oled(p, s)
        return p
    }
    // notes de version (CHANGELOG.md embarque)
    property var changelog: []
    property bool autostart: false
    property bool autostartBusy: false
    property var monitors: []
    property var chosenMonitor: null
    property var winkey: null
    property bool winkeyBusy: false

    onShownChanged: {
        if (shown) {
            // packs de compagnon ajoutes ou retires sur le poste
            Watch.petPacksReload()
            return load()
        }
        keyRec = ""
        appPick = false
    }
    // page dechargeable (Panel) : l'ecouteur part avec elle
    property var keyrecFn: null
    Component.onCompleted: {
        if (shown)
            load()
        // page creee deja sur Son (« Gerer » depuis la feuille Sortie audio)
        if (soundShown)
            loadOuts()
        keyrecFn = r => page.recorded(r)
        Api.listen("keyrec", keyrecFn)
        Qt.callLater(navReveal)
    }
    Component.onDestruction: {
        Api.unlisten("keyrec", keyrecFn)
        Ilot.settingsDirty = false
    }
    function load() {
        Api.invoke("settings_get").then(s => {
            page.autostart = s.autostart
            page.monitors = s.monitors
            page.chosenMonitor = s.monitor === undefined ? null : s.monitor
            // seulement si quelque chose a change : remplacer Ilot.cfg fait
            // recalculer tout ce qui en depend (≈ 80 ms a chaque ouverture)
            const next = Object.assign({}, Ilot.cfg, s, Ilot.outPatch)
            if (Object.keys(next).some(k => JSON.stringify(next[k]) !== JSON.stringify(Ilot.cfg[k])))
                Ilot.cfg = next
        })
        refreshWinKey()
        if (!changelog.length)
            Api.invoke("changelog").then(l => { page.changelog = l })
        Api.invoke("update_get").then(u => { Watch.upd = u })
        Api.invoke("cc_hooks_status").then(v => { page.ccHooks = v; page.ccHooksErr = "" }, e => { page.ccHooksErr = String(e) })
    }
    // ------------------------------------------- Son : sorties affichees
    // sorties actives avec leurs applis (mixer_all), relues pendant l'onglet
    property var outs: []
    // liste lue au moins une fois : avant, rien n'est « absent »
    property bool outsLoaded: false
    readonly property bool soundShown: shown && section === "sound"
    onSoundShownChanged: {
        outEdit = ""
        outsEmpty = false
        if (soundShown)
            loadOuts()
    }
    Timer {
        interval: 3000
        repeat: true
        running: page.soundShown
        onTriggered: page.loadOuts()
    }
    // les lignes ne sont refaites que si ce qui s'y affiche change (pas a
    // chaque volume, ni aux applis une fois le choix fait : elles ne servent
    // qu'au tri automatique), et pas pendant qu'on renomme
    property string outsSig: ""
    property bool outsEmpty: false
    function outsSigOf(l, auto) {
        return JSON.stringify(l.map(d => [d.id, d.name, !!d.default,
            auto ? (d.apps || []).map(a => a.icon === "" ? "" : a.name).sort() : []]))
    }
    function loadOuts() {
        Api.invoke("mixer_all").then(l => {
            if (!Array.isArray(l))
                return
            if (page.outEdit !== "") {
                // ignoree pendant un renommage, mais une lecture pleine
                // casse quand meme la suite de lectures vides
                if (l.length)
                    page.outsEmpty = false
                return
            }
            // liste vide alors qu'on en avait une, ou des la premiere
            // lecture : sans doute une lecture ratee (COM, mixer_all rend []
            // sur erreur) ; on ne la croit qu'a la deuxieme de suite
            if (!l.length && (page.outs.length || !page.outsLoaded) && !page.outsEmpty) {
                page.outsEmpty = true
                return
            }
            page.outsEmpty = false
            const sig = page.outsSigOf(l, Ilot.outHiddenMap === null)
            page.outsLoaded = true
            if (sig === page.outsSig)
                return
            page.outsSig = sig
            page.outs = l
        })
    }
    // sortie dont on modifie le nom ; outCancel : Echap, on ne garde pas
    property string outEdit: ""
    property bool outCancel: false
    Connections {
        target: Ilot
        function onEscapeOverlay(what) {
            if (what === "outname") {
                page.outCancel = true
                page.outEdit = ""
                page.outCancel = false
            }
        }
    }
    // une ligne par sortie presente, dans l'ordre et avec les noms du
    // melangeur (Sonar d'abord, doublons « HDMI 2 »).
    // auto : ce que montre le tri automatique du melangeur (Mixer.rebuild)
    readonly property var outRows: {
        const rank = d => {
            const c = Ilot.outInfo(d.name)
            const i = c.sonar ? ["Game", "Chat", "Media", "Aux", "Micro"].indexOf(c.short) : -1
            return i < 0 ? 9 : i
        }
        const ordered = outs.map((d, i) => [rank(d), i, d]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map(x => x[2])
        const sonar = ordered.some(d => { const c = Ilot.outInfo(d.name); return c.sonar && c.short !== "Micro" })
        const rows = []
        const seen = {}
        for (const d of ordered) {
            const c = Ilot.outInfo(d.name)
            seen[c.short] = (seen[c.short] || 0) + 1
            const real = (d.apps || []).some(a => !(a.icon === "" && a.name === "Sons système"))
            rows.push({
                id: d.id, name: d.name, def: !!d.default, gone: false, icon: c.icon,
                title: c.label + (seen[c.short] > 1 ? " " + seen[c.short] : ""),
                virt: Ilot.outVirtual(d.name),
                auto: !!d.default || real || (sonar && c.sonar && c.short !== "Micro")
            })
        }
        return rows
    }
    // sorties masquees absentes (debranchees, ou id change par un pilote),
    // avec le nom garde dans audio_hidden
    readonly property var outGone: {
        const h = outsLoaded && Ilot.outHiddenMap || {}
        const rows = []
        for (const id in h) {
            if (outs.some(d => d.id === id))
                continue
            const name = typeof h[id] === "string" && h[id] !== "" ? h[id] : id
            const c = Ilot.outInfo(name)
            rows.push({ id: id, name: name, def: false, gone: true, icon: c.icon, title: c.label, virt: Ilot.outVirtual(name), auto: false })
        }
        return rows
    }
    // listes separees : basculer un interrupteur ne refait pas les lignes
    readonly property var outPhys: outRows.filter(r => !r.virt)
    readonly property var outVirt: outRows.filter(r => r.virt)
    readonly property var outPhysGone: outGone.filter(r => !r.virt)
    readonly property var outVirtGone: outGone.filter(r => r.virt)
    // affichee dans le melangeur (hors « +N »)
    function outOn(r) {
        return Ilot.outHiddenMap === null ? r.auto : !Ilot.outHidden(r.id)
    }
    // masque / affiche `ids`. Au premier choix, on part de ce que montre le
    // tri automatique : rien d'autre ne bouge que ce qu'on vient de toucher
    function outSetHidden(ids, hide) {
        outEdit = ""
        const h = Object.assign({}, Ilot.outHiddenMap || {})
        if (Ilot.outHiddenMap === null) {
            for (const r of outRows) {
                if (!r.def && !r.auto)
                    h[r.id] = r.name
            }
        }
        for (const id of ids) {
            const r = outRows.find(x => x.id === id)
            if (hide)
                h[id] = r ? r.name : id
            else
                delete h[id]
        }
        // premier choix : les applis ne comptent plus, la signature les
        // retire tout de suite (sinon la relecture suivante referait les lignes)
        if (Ilot.outHiddenMap === null)
            outsSig = outsSigOf(outs, false)
        Ilot.setOutCfg({ audio_hidden: h })
    }
    // oublie une sortie absente (masquage et nom choisi)
    function outForget(id) {
        outEdit = ""
        const h = Object.assign({}, Ilot.outHiddenMap || {})
        delete h[id]
        const a = Object.assign({}, Ilot.outAliasMap)
        delete a[id]
        Ilot.setOutCfg({ audio_hidden: h, audio_alias: a })
    }
    // nom choisi ; vide ou identique au nom d'origine : on revient a celui-ci
    function outRename(r, text) {
        const t = text.trim().slice(0, 32)
        const a = Object.assign({}, Ilot.outAliasMap)
        // (le champ coupe a 32 : un nom long garde tel quel n'est pas un choix)
        if (t === "" || t === r.title || t === r.title.slice(0, 32).trim())
            delete a[r.id]
        else
            a[r.id] = t
        if (JSON.stringify(a) !== JSON.stringify(Ilot.outAliasMap))
            Ilot.setOutCfg({ audio_alias: a })
    }

    // hooks Claude Code (src/claude.rs) : null tant que l'etat n'est pas lu
    property var ccHooks: null
    property string ccHooksErr: ""
    function ccHooksSet(on) {
        Api.invoke(on ? "cc_hooks_install" : "cc_hooks_remove").then(v => { page.ccHooks = v; page.ccHooksErr = "" },
            e => { page.ccHooksErr = String(e) })
    }
    function refreshWinKey() {
        Api.invoke("winkey_status").then(st => { page.winkey = st })
    }
    // Touche Windows : remappee au niveau du pilote (invite administrateur),
    // sinon Windows ouvre quand meme le menu Demarrer
    function winKeyRemap(on) {
        winkeyBusy = true
        Api.invoke("winkey_remap", { on: on }).then(ok => {
            // couper reste possible si le remappage n'a pas pu etre retire
            if (ok || !on)
                Ilot.setCfg({ win_key: on })
        }).then(() => {
            page.winkeyBusy = false
            page.refreshWinKey()
        }, () => {
            page.winkeyBusy = false
            page.refreshWinKey()
        })
    }
    // Ilot.focusCity : l'onglet Meteo met le focus dans la recherche de ville
    // (des sa creation s'il n'existait pas encore)
    property bool cityFocus: false
    Connections {
        target: Ilot
        function onFocusCity() {
            Ilot.settingsSection = "weather"
            page.cityFocus = true
        }
    }

    // ------------------------------------------------- onglets (a gauche)
    // recherche d'un reglage, puis les onglets par groupe
    Field {
        id: navSearch
        width: navFlick.width
        height: 34
        pad: 12
        fontSize: 12.5
        bg: Theme.surfaceHigh
        placeholder: "Rechercher un réglage"
        onFocused: {
            Ilot.pinned = true
            Ilot.grabFocus()
        }
        onKeyPressed: e => {
            if (e.key === Qt.Key_Escape && text !== "") {
                e.accepted = true
                text = ""
            }
        }
    }
    readonly property string query: navSearch.text.trim()
    // sans accents ni majuscules
    function fold(t) {
        return t.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    }
    // [titre, onglet, mots en plus, ancien onglet s'il a change de place]
    // (les anciens noms d'onglets trouvent aussi ce qu'ils contenaient)
    readonly property var searchIndex: [
        ["Thèmes prêts", "theme", "preset ardoise brume oled minuit aurore neon coucher foret glace papier bonbon retro monochrome apparence", "Apparence"],
        ["Couleur d'accent", "theme", "couleur pochette fond d'ecran apparence", "Apparence"],
        ["Style de la palette", "theme", "variante tonal vibrant expressive fidelite neutre apparence", "Apparence"],
        ["Clair ou sombre", "theme", "mode sombre clair nuit heure soleil apparence", "Apparence"],
        ["Couleur et mode de Windows", "theme", "windows accent barre des taches apparence", "Apparence"],
        ["Changer de fond automatiquement", "theme", "fond d'ecran rotation wallpaper apparence", "Apparence"],
        ["Forme de l'îlot", "island", "arrondie pilule carree apparence", "Apparence"],
        ["Fond de l'îlot", "island", "opaque noir pur translucide transparent acrylique aurore apparence", "Apparence"],
        ["Cartes noires (OLED)", "island", "oled noir apparence", "Apparence"],
        ["Contour de l'îlot", "island", "lisere lueur arc-en-ciel pulsation bordure apparence", "Apparence"],
        ["Taille de la pilule", "island", "petite grande pilule", "Pilule"],
        ["Horloge", "island", "heure volets aiguilles neon pixel pilule", "Pilule"],
        ["Animations", "island", "vitesse rebond rapide douce instantanee apparence", "Apparence"],
        ["Couleur du lecteur", "player", "musique pochette apparence", "Apparence"],
        ["Bouton lecture", "player", "forme festonne rond rotation ombre rebond icone apparence", "Apparence"],
        ["Barre de progression", "player", "ondulee plate epaisseur amplitude onde apparence", "Apparence"],
        ["Lecteur dans la pilule", "player", "anneau disque paroles glisser molette volume apparence", "Apparence"],
        ["Onglet Média", "player", "disposition pochette spectre fond flou apparence", "Apparence"],
        ["Compagnon", "pet", "animal espece chat nom couleur yeux chapeau visage cou"],
        ["Promenade du compagnon", "pet", "balade trainee absent scene"],
        ["Notifications dans l'îlot", "alerts", "notification général", "Général"],
        ["Indicateurs de volume et de luminosité", "alerts", "osd général", "Général"],
        ["Activités en cours", "alerts", "steam gpu telechargement pilule", "Pilule"],
        ["Raccourcis Discord", "alerts", "micro sourdine vocal pilule", "Pilule"],
        ["Voyant caméra / micro", "alerts", "confidentialite pilule", "Pilule"],
        ["Météo animée", "alerts", "pluie neige pilule", "Pilule"],
        ["Barre en haut de l'écran", "bar", "waybar bureaux fenetres barre des taches masquer"],
        ["Écran de l'îlot", "bar", "moniteur ecran principal général", "Général"],
        ["Îlot en plein écran", "bar", "jeu video masquer jeu et absence", "Jeu et absence"],
        ["Mode jeu", "game", "performances notifications"],
        ["Alerte « partie trouvée »", "game", "valorant match"],
        ["Mode absent", "game", "afk recap pause"],
        ["Sorties affichées", "sound", "audio son melangeur sortie masquer renommer"],
        ["Touche Windows", "keys", "win demarrer menu général", "Général"],
        ["Raccourcis clavier", "keys", "touches combinaison raccourcis", "Raccourcis"],
        ["Raccourcis d'applications", "keys", "lancer appli raccourcis", "Raccourcis"],
        ["Météo", "weather", "ville"],
        ["Agenda", "weather", "ical google outlook calendrier"],
        ["Taille du texte", "access", "texte police"],
        ["Contraste", "access", "eleve"],
        ["Mouvements et animations", "access", "reduits"],
        ["Couleurs des voyants", "access", "daltonien"],
        ["Addons", "addons", "onglets"],
        ["Claude Code", "addons", "hooks son"],
        ["Lancer au démarrage de Windows", "updates", "demarrage autostart général", "Général"],
        ["Mises à jour", "updates", "version telecharger"],
        ["Sauvegarde des réglages", "updates", "exporter importer général", "Général"],
        ["Notes de version", "updates", "changelog nouveautes"]
    ]
    readonly property var searchHits: {
        if (query === "")
            return []
        const words = fold(query).split(/\s+/)
        // pack de compagnon : seulement sur son nom exact (easter egg) ;
        // 5e case = id du pack
        const packs = Watch.petPacks.filter(p => p.name && fold(p.name) === fold(query))
                                    .map(p => [p.name, "pet", "", "", p.id])
        return packs.concat(searchIndex.filter(e => {
            const t = fold(e[0] + " " + e[2])
            return words.every(w => t.indexOf(w) >= 0)
        })).slice(0, 10)
    }
    // onglets et titres de groupe, a plat
    readonly property var navItems: {
        const r = []
        for (const s of sections) {
            if (s.group)
                r.push({ head: s.group })
            r.push(s)
        }
        return r
    }
    // position du surligneur : hauteurs des lignes au-dessus
    readonly property real navY: {
        let y = 0
        for (const it of navItems) {
            if (it.id === section)
                return y
            y += (it.head ? 22 : 32) + 2
        }
        return 0
    }

    Flickable {
        id: navFlick
        y: navSearch.height + 8
        width: 176
        height: parent.height - y
        contentHeight: page.query === "" ? nav.height : hits.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        // un seul fond, qui glisse vers l'onglet choisi (comme les onglets du
        // panneau) : les boutons eux-memes restent sans fond
        Rectangle {
            visible: page.query === ""
            y: page.navY
            width: nav.width
            height: 32
            radius: 16
            color: Theme.secondaryContainer
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        }
        Column {
            id: nav
            visible: page.query === ""
            // place pour la barre de defilement
            width: parent.width - 8
            spacing: 2
            Repeater {
                model: page.navItems
                Item {
                    id: navIt
                    required property var modelData
                    width: nav.width
                    height: modelData.head ? 22 : 32
                    Txt {
                        visible: !!navIt.modelData.head
                        x: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        text: navIt.modelData.head || ""
                        px: 11
                        weight: Font.Medium
                        color: Theme.inkVariant
                    }
                    Btn {
                        id: navBtn
                        visible: !navIt.modelData.head
                        readonly property var modelData: navIt.modelData
                        readonly property bool on: page.section === modelData.id
                        width: nav.width
                        height: 32
                        radius: 16
                        // fond leger au survol, sauf l'actif (le surligneur glissant suffit)
                        color: hovered && !on ? Theme.alpha(Theme.ink, 0.08) : "transparent"
                        readonly property color fg: on ? Theme.inkSecondaryContainer : Theme.ink
                        onClicked: Ilot.settingsSection = modelData.id
                        Ms {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: navBtn.modelData.icon || ""
                            size: 19
                            color: navBtn.on || navBtn.hovered ? navBtn.fg : Theme.inkVariant
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Txt {
                            x: 42
                            width: parent.width - x - 22
                            anchors.verticalCenter: parent.verticalCenter
                            text: navBtn.modelData.label || ""
                            weight: navBtn.on ? Font.Medium : Font.Normal
                            color: navBtn.fg
                            elide: Text.ElideRight
                        }
                        // pastille : modifications non enregistrees (orange),
                        // mise a jour disponible (rouge)
                        Rectangle {
                            readonly property bool changed: !!page.dirtySecs[navBtn.modelData.id]
                            visible: changed || (navBtn.modelData.id === "updates" && !!Watch.upd.available)
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: changed ? Theme.warn : Theme.error
                        }
                    }
                }
            }
        }
        // resultats de la recherche
        Column {
            id: hits
            visible: page.query !== ""
            width: parent.width
            spacing: 2
            Repeater {
                model: page.searchHits
                Btn {
                    id: hit
                    required property var modelData
                    readonly property var sec: page.sections.find(s => s.id === modelData[1])
                    width: parent.width
                    height: 44
                    radius: 14
                    color: hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
                    onClicked: {
                        if (modelData[4])
                            page.unlockPacks()
                        else
                            Ilot.settingsSection = modelData[1]
                        navSearch.text = ""
                    }
                    Column {
                        x: 12
                        width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            width: parent.width
                            text: hit.modelData[0]
                            px: 12.5
                            weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Txt {
                            width: parent.width
                            text: hit.modelData[4] ? (page.petPacksUnlocked ? "Compagnon" : "Compagnon secret · l'ajouter")
                                : (hit.sec ? hit.sec.label : "") + (hit.modelData[3] ? " · avant : " + hit.modelData[3] : "")
                            px: 11
                            color: Theme.inkVariant
                            elide: Text.ElideRight
                        }
                    }
                }
            }
            Txt {
                visible: !page.searchHits.length
                x: 12
                topPadding: 8
                width: parent.width - 24
                wrapMode: Text.Wrap
                text: "Aucun réglage trouvé"
                px: 12
                color: Theme.inkVariant
            }
        }
    }

    // ------------------------------------- apercu anime (brouillon)
    Loader {
        id: preview
        readonly property bool want: ["theme", "island", "player", "alerts"].indexOf(page.section) >= 0
        active: want && page.shown
        visible: want
        x: flick.x
        width: flick.width - 8
        height: want ? 112 : 0
        sourceComponent: SettingsPreview {
            kind: page.section
            cfg: page.cfg
            pal: page.pal
        }
    }

    // « Ton ilot » : l'ilot tel qu'il est enregistre, pendant qu'un brouillon
    // change l'apercu
    Rectangle {
        visible: preview.want && page.dirty
        x: preview.x + 10
        y: preview.y + preview.height - height - 10
        width: savedRow.implicitWidth + 16
        height: 30
        radius: 15
        color: Theme.surfaceHighest
        Row {
            id: savedRow
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Ton îlot"
                px: 11.5
                color: Theme.inkVariant
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 58
                height: 18
                radius: (Ilot.cfg.shape || "round") === "square" ? 5 : 9
                color: Theme.islandSurface
                border.width: (Ilot.cfg.border || "none") === "none" ? 0 : 1
                border.color: Theme.primary
                Txt {
                    anchors.centerIn: parent
                    text: "12:34"
                    px: 10
                    tnum: true
                    weight: Font.Medium
                    color: Theme.ink
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: navFlick.width + 12
        anchors.rightMargin: 4
        anchors.topMargin: preview.want ? preview.height + 10 : 0
        anchors.bottomMargin: draftBar.room
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Column {
            id: col
            width: parent.width
            spacing: 10

            // un onglet n'est cree qu'a sa premiere ouverture, puis garde (la
            // page entiere est dechargee apres 5 min de panneau ferme, Panel)
            Repeater {
                model: page.sections
                Loader {
                    required property var modelData
                    readonly property bool on: modelData.id === page.section
                    property bool wanted: false
                    onOnChanged: if (on) wanted = true
                    Component.onCompleted: if (on) wanted = true
                    active: wanted
                    visible: on
                    width: col.width
                    sourceComponent: ({
                        theme: secTheme, island: secIsland, player: secPlayer, pet: secPet, alerts: secAlerts,
                        bar: secBar, game: secGame, sound: secSound, keys: secKeys, weather: secWeather,
                        access: secAccess, addons: secAddons, updates: secUpdates
                    })[modelData.id]
                }
            }
        }
    }
    Scroller { flick: flick }
    Scroller { flick: navFlick }
    // l'onglet choisi reste visible dans la liste
    onNavYChanged: navReveal()
    function navReveal() {
        let y = Math.min(navFlick.contentY, navY)
        y = Math.max(y, navY + 32 - navFlick.height)
        navFlick.contentY = Math.max(0, Math.min(y, navFlick.contentHeight - navFlick.height))
    }

    // ------------------------------------------ barre du brouillon
    // monte du bas quand un reglage change ; tremble et rougit si on veut
    // quitter Reglages sans enregistrer ni annuler
    Rectangle {
        id: draftBar
        // place laissee sous la page
        readonly property real room: page.dirty ? height + 10 : 0
        property bool alarm: false
        property real dx: 0
        x: flick.x
        width: flick.width - 8
        height: 50
        y: page.dirty ? page.height - height : page.height + 10
        visible: y < page.height
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        radius: 18
        color: alarm ? Theme.mix(Theme.error, Theme.surfaceHighest, 0.4) : Theme.surfaceHighest
        Behavior on color { ColorAnimation { duration: 200 } }
        border.width: 1
        border.color: alarm ? Theme.error : Theme.outlineVariant
        transform: Translate { x: draftBar.dx }
        Connections {
            target: page
            function onNudge() {
                draftBar.alarm = true
                shake.restart()
                alarmOff.restart()
            }
        }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: draftBar; property: "dx"; to: -10; duration: 50 }
            NumberAnimation { target: draftBar; property: "dx"; to: 10; duration: 70 }
            NumberAnimation { target: draftBar; property: "dx"; to: -7; duration: 70 }
            NumberAnimation { target: draftBar; property: "dx"; to: 6; duration: 70 }
            NumberAnimation { target: draftBar; property: "dx"; to: 0; duration: 60 }
        }
        Timer {
            id: alarmOff
            interval: 1800
            onTriggered: draftBar.alarm = false
        }
        // nombre de modifications : un clic les liste par onglet
        Btn {
            id: countBtn
            x: 6
            width: parent.width - x - draftBtns.width - 14
            height: parent.height - 12
            anchors.verticalCenter: parent.verticalCenter
            radius: 14
            color: hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
            tip: "Voir les modifications (avant → après)"
            onClicked: page.changesOpen = !page.changesOpen
            Rectangle {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: Theme.warn
            }
            Txt {
                x: 26
                width: parent.width - x - 8
                anchors.verticalCenter: parent.verticalCenter
                text: draftBar.alarm ? "Enregistre ou annule d'abord"
                    : page.dirtyCount + (page.dirtyCount > 1 ? " modifications non enregistrées" : " modification non enregistrée")
                px: 12.5
                weight: Font.Medium
                elide: Text.ElideRight
            }
        }
        Row {
            id: draftBtns
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            TextBtn {
                icon: "close"
                text: "Annuler"
                onClicked: page.cancel()
            }
            TextBtn {
                primary: true
                icon: "check"
                text: "Enregistrer"
                tip: "Ctrl+S"
                onClicked: page.save()
            }
        }
    }
    // liste des modifications, avant -> apres (clic sur le nombre)
    Rectangle {
        visible: page.changesOpen && page.dirty
        x: draftBar.x
        width: Math.min(360, draftBar.width)
        height: Math.min(changesCol.height, 280) + 16
        y: draftBar.y - height - 8
        radius: 18
        color: Theme.surfaceHighest
        border.width: 1
        border.color: Theme.outlineVariant
        Flickable {
            x: 8
            y: 8
            width: parent.width - 16
            height: parent.height - 16
            contentHeight: changesCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: changesCol
                width: parent.width
                Repeater {
                    model: page.changes
                    Btn {
                        id: chg
                        required property var modelData
                        readonly property var sec: page.sections.find(s => s.id === page.secOf(modelData[0]))
                        width: changesCol.width
                        height: 40
                        radius: 12
                        color: hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
                        tip: "Aller à " + (sec ? sec.label : "")
                        onClicked: {
                            Ilot.settingsSection = page.secOf(modelData[0])
                            page.changesOpen = false
                        }
                        Ms {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            name: chg.sec ? chg.sec.icon : ""
                            size: 18
                            color: Theme.inkVariant
                        }
                        Column {
                            x: 36
                            width: parent.width - x - 8
                            anchors.verticalCenter: parent.verticalCenter
                            Txt {
                                width: parent.width
                                text: chg.modelData[1]
                                px: 12.5
                                weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Txt {
                                width: parent.width
                                text: chg.modelData[2] + "  →  " + chg.modelData[3]
                                px: 11.5
                                color: Theme.inkVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // etat de la mise a jour, en une phrase
    function updateText(u) {
        switch (u.status) {
        case "checking":
            return "Recherche d'une nouvelle version…"
        case "downloading":
            return "Téléchargement de la version " + u.latest + "… " + Math.round((u.progress || 0) * 100) + " %"
        case "ready":
            return "Version " + u.latest + " téléchargée, prête à installer"
        case "installing":
            return "Installation : l'îlot va redémarrer…"
        case "error":
            return u.error || "La recherche a échoué"
        }
        if (u.available)
            return "La version " + u.latest + " est disponible"
        if (!u.checked)
            return "Pas encore vérifié"
        const d = new Date(u.checked * 1000)
        return "Tu as la dernière version · vérifié à " + Ilot.pad(d.getHours()) + ":" + Ilot.pad(d.getMinutes())
    }

    // recherche de ville (geocodage Open-Meteo)
    property var cities: []
    property string cityMsg: ""
    function searchCity(text) {
        const q = text.trim()
        if (q.length < 2) {
            cities = []
            cityMsg = ""
            return
        }
        Api.invoke("http_get", { url: "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(q) + "&count=6&language=fr" }).then(t => {
            const j = JSON.parse(t)
            page.cities = j.results || []
            page.cityMsg = page.cities.length ? "" : "Aucune ville trouvée"
        }).catch(e => {
            page.cities = []
            page.cityMsg = "Recherche impossible (" + e + ")"
        })
    }

    // ------------------------------------------------- donnees des choix
    readonly property var swatches: ["#6750a4", "#3f51b5", "#1e88e5", "#00bcd4", "#00897b", "#43a047", "#c0ca33", "#fbc02d", "#fb8c00", "#e53935", "#d81b60", "#8e24aa", "#795548", "#607d8b"]
    // themes prets : [nom, description, reglages]
    readonly property var presets: [
        ["Ardoise", "Gris-bleu opaque, horloge classique", { color: "#78909c", variant: "tonalspot", mode: "dark", island_bg: "solid", border: "none", shape: "round", clock: "digital", anim: "normal" }],
        ["Brume", "Gris-bleu sur acrylique", { color: "#78909c", variant: "neutral", mode: "dark", island_bg: "wall", border: "line", shape: "round", clock: "digital", anim: "calm" }],
        ["OLED", "Noir 100 %, cartes noires", { color: "#78909c", variant: "neutral", mode: "dark", island_bg: "black", oled: true, border: "none", shape: "round", clock: "digital", anim: "normal" }],
        ["Minuit", "Bleu nuit, noir pur", { color: "#3949ab", variant: "tonalspot", mode: "dark", island_bg: "black", border: "line", shape: "round", clock: "digital", anim: "normal" }],
        ["Aurore", "Fond animé, lueur", { color: "#26a69a", variant: "expressive", mode: "dark", island_bg: "aurora", border: "glow", shape: "pill", clock: "digital", anim: "soft" }],
        ["Néon", "Arc-en-ciel, horloge néon", { color: "#ff2d95", variant: "vibrant", mode: "dark", island_bg: "black", border: "rgb", shape: "pill", clock: "neon", anim: "fast" }],
        ["Coucher de soleil", "Acrylique chaud, volets", { color: "#ff7043", variant: "expressive", mode: "dark", island_bg: "wall", border: "glow", shape: "round", clock: "flip", anim: "normal" }],
        ["Forêt", "Vert profond, aiguilles", { color: "#2e7d32", variant: "tonalspot", mode: "dark", island_bg: "solid", border: "none", shape: "round", clock: "analog", anim: "soft" }],
        ["Glace", "Clair et transparent", { color: "#4fc3f7", variant: "tonalspot", mode: "light", island_bg: "clear", border: "line", shape: "pill", clock: "digital", anim: "calm" }],
        ["Papier", "Clair, carré, sans rebond", { color: "#8d6e63", variant: "neutral", mode: "light", island_bg: "solid", border: "line", shape: "square", clock: "analog", anim: "calm" }],
        ["Bonbon", "Pastel, tout en douceur", { color: "#f48fb1", variant: "rainbow", mode: "light", island_bg: "glass", border: "glow", shape: "pill", clock: "flip", anim: "soft" }],
        ["Rétro", "Pixel, pulsation", { color: "#c0ca33", variant: "fruitsalad", mode: "dark", island_bg: "solid", border: "pulse", shape: "square", clock: "pixel", anim: "fast" }],
        ["Monochrome", "Gris, sans couleur", { color: "#9e9e9e", variant: "monochrome", mode: "dark", island_bg: "black", border: "none", shape: "pill", clock: "digital", anim: "calm" }]
    ]
    // valeur d'un reglage jamais choisi
    readonly property var presetDefaults: ({ island_bg: "solid", border: "none", shape: "round", clock: "digital", anim: "normal", oled: false })
    function presetMatch(c) {
        return Object.keys(c).every(k => (cfg[k] !== undefined ? cfg[k] : presetDefaults[k]) === c[k])
            && (!!cfg.oled === !!c.oled)
    }
    // theme pret qui correspond aux reglages, sinon ""
    readonly property string presetOn: {
        const p = presets.find(x => presetMatch(x[2]))
        return p ? p[0] : ""
    }
    function presetOf(name) {
        const p = presets.find(x => x[0] === name)
        return p ? { name: p[0], desc: p[1], cfg: p[2] } : null
    }
    function applyPreset(p) {
        // (theme deja en place : rien a changer)
        if (p && presetOn !== p.name)
            set(Object.assign({ oled: false }, p.cfg, { preset: p.name }))
    }
    // actions, puis un raccourci par onglet affiche (essentiels + addons actives)
    readonly property var keyActions: [
        ["toggle", "Ouvrir / fermer l’îlot"], ["play", "Lecture / pause"], ["next", "Morceau suivant"], ["captions", "Sous-titres en direct"]
    ].concat(Ilot.tabItems.map(t => [t.id, t.label || t.tip]))
    // raccourcis d'applications : action « app:<id> » -> [action, nom, icone]
    readonly property var appKeys: Object.keys(Watch.keyMap).filter(k => k.startsWith("app:")).map(k => {
        const id = k.slice(4)
        const a = Ilot.apps.find(x => x.id === id)
        return [k, a ? a.name : id.split(/[\\!]/).pop(), a ? a.icon || "" : ""]
    }).sort((a, b) => a[1].localeCompare(b[1]))

    // Jeu et absence > Îlot en plein écran, « Personnalisé » : fenetres
    // ouvertes par executable ({exe: {key, id, title}}), relues a l'affichage
    property var fsOpen: ({})
    function loadFsOpen() {
        Api.invoke("bar_windows").then(t => {
            const m = {}
            for (const w of (t && t.windows) || []) {
                const exe = String(w.icon || "").split("\n").pop().split("\\").pop().toLowerCase()
                if (/\.exe$/.test(exe) && Ilot.fsSkip.indexOf(exe) < 0 && !m[exe])
                    m[exe] = { key: w.icon, id: w.id, title: w.title }
            }
            page.fsOpen = m
        })
    }
    // proposees : deja vues en plein ecran, puis ouvertes, sauf les choisies
    readonly property var fsChoices: {
        const seen = Array.isArray(cfg.fs_seen) ? cfg.fs_seen : []
        const out = []
        for (const e of seen.concat(Object.keys(fsOpen)))
            if (typeof e === "string" && out.indexOf(e) < 0 && Ilot.fsApps.indexOf(e) < 0)
                out.push(e)
        return out
    }
    function fsSet(exe, on) {
        const l = Ilot.fsApps.filter(a => a !== exe)
        Ilot.setCfg({ fs_apps: on ? l.concat([exe]) : l })
    }
    function fsAddTyped(text) {
        let e = text.trim().split(/[\\/]/).pop().toLowerCase()
        if (!e)
            return
        if (!/\.exe$/.test(e))
            e += ".exe"
        fsSet(e, true)
    }
    property bool appPick: false
    // texte du champ de recherche d'appli (Clavier)
    property string appQuery: ""
    readonly property var appMatches: {
        const q = appQuery.trim().toLowerCase()
        return Ilot.apps.filter(a => !Watch.keyMap.hasOwnProperty("app:" + a.id) && (!q || a.name.toLowerCase().indexOf(q) >= 0))
            .sort((a, b) => (q && b.name.toLowerCase().startsWith(q)) - (q && a.name.toLowerCase().startsWith(q)) || a.name.localeCompare(b.name))
            .slice(0, 8)
    }
    // ajoute l'appli puis attend sa combinaison
    function addAppKey(a) {
        appPick = false
        const map = Object.assign({}, Watch.keyMap)
        map["app:" + a.id] = ""
        Watch.saveKeys(map)
        Qt.callLater(() => { page.keyRec = "app:" + a.id })
    }
    // « Ctrl+Alt+KeyM » -> « Ctrl+Alt+M »
    function keyLabel(c) {
        return c.replace(/Key([A-Z])/g, "$1").replace(/Digit(\d)/g, "$1").replace(/Numpad/g, "Pavé ").replace(/VK(\d+)/, "touche $1").replace(/Super/, "Win")
    }
    // une combinaison n'appartient qu'a une action
    function setKey(action, combo) {
        const map = Object.assign({}, Watch.keyMap)
        for (const k in map)
            if (map[k] === combo && k !== action)
                map[k] = k.startsWith("app:") ? "" : undefined
        for (const k in map)
            if (map[k] === undefined)
                delete map[k]
        map[action] = combo
        keyRec = ""
        Watch.saveKeys(map)
    }
    property string keyRec: ""
    // pendant l'enregistrement, le coeur prend les combinaisons avec la touche
    // Windows (sinon Windows les garde pour lui) et les renvoie (`keyrec`)
    onKeyRecChanged: Api.invoke("shortcuts_record", { on: keyRec !== "" })
    function recorded(r) {
        if (!page.keyRec)
            return
        const mods = []
        if (r.mods & 2) mods.push("Ctrl")
        if (r.mods & 1) mods.push("Alt")
        if (r.mods & 4) mods.push("Shift")
        mods.push("Super")
        const vk = r.vk
        const k = vk >= 0x41 && vk <= 0x5A ? "Key" + String.fromCharCode(vk)
            : vk >= 0x30 && vk <= 0x39 ? "Digit" + String.fromCharCode(vk)
            : vk >= 0x60 && vk <= 0x69 ? "Numpad" + (vk - 0x60)
            : vk >= 0x70 && vk <= 0x87 ? "F" + (vk - 0x6F)
            : "VK" + vk
        page.setKey(page.keyRec, mods.concat([k]).join("+"))
    }

    // ------------------------------------------- contenu des onglets
    // (crees a leur premiere ouverture, voir `col`)
    Component {
        id: secTheme
        Column {
            spacing: 10
                // themes prets : un clic remplit le brouillon (couleur, style, mode,
                // fond, contour, forme, horloge, animations), pas le lecteur, le
                // compagnon ni la taille de la pilule
                Block {
                    SetRow {
                        icon: "auto_awesome"
                        title: "Thèmes prêts"
                        sub: page.presetOn ? "Thème « " + page.presetOn + " »"
                            : page.presetOf(page.cfg.preset) ? "Thème perso, d'après « " + page.cfg.preset + " »"
                            : "Un clic règle les couleurs, le fond, le contour, la forme, l'horloge et les animations"
                        TextBtn {
                            visible: !page.presetOn && !!page.presetOf(page.cfg.preset)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "refresh"
                            text: "Revenir à " + (page.cfg.preset || "")
                            onClicked: page.applyPreset(page.presetOf(page.cfg.preset))
                        }
                    }
                    Flow {
                        id: presetGrid
                        width: parent.width
                        topPadding: 12
                        spacing: 8
                        readonly property int cols: Math.max(2, Math.floor((width + 8) / (150 + 8)))
                        readonly property real cw: (width - (cols - 1) * 8) / cols
                        // couleurs de chaque theme : fond de carte, pilule, pastilles
                        readonly property var cards: page.presets.map(p => {
                            const c = p[2]
                            const dark = c.mode !== "light"
                            const s = Theme.swatch(0xff000000 | parseInt(c.color.slice(1), 16), c.variant, dark)
                            const card = c.oled ? "#000000" : s.bg
                            const pill = c.island_bg === "black" ? "#000000"
                                : Theme.mix(Qt.color(card), dark ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1), 0.5)
                            return { name: p[0], desc: p[1], cfg: c, dots: s.dots, card: card, pill: pill }
                        })
                        Repeater {
                            model: presetGrid.cards
                            Btn {
                                id: pc
                                required property var modelData
                                readonly property bool on: page.presetOn === modelData.name
                                width: presetGrid.cw
                                height: 104
                                radius: hovered ? 20 : 16
                                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                color: on ? Theme.primaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                                onClicked: page.applyPreset(modelData)
                                // fond teinte et mini pilule
                                Rectangle {
                                    x: 6
                                    y: 6
                                    width: parent.width - 12
                                    height: 50
                                    radius: 12
                                    color: pc.modelData.card
                                    border.width: pc.modelData.cfg.oled ? 1 : 0
                                    border.color: Theme.outlineVariant
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 74
                                        height: 22
                                        radius: pc.modelData.cfg.shape === "square" ? 6 : 11
                                        color: pc.modelData.pill
                                        border.width: pc.modelData.cfg.border === "none" ? 0 : 1
                                        border.color: pc.modelData.dots[0]
                                        Txt {
                                            anchors.centerIn: parent
                                            text: "12:34"
                                            px: 11
                                            tnum: true
                                            weight: Font.Medium
                                            color: pc.modelData.dots[0]
                                        }
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 6
                                        spacing: -3
                                        Repeater {
                                            model: pc.modelData.dots
                                            Rectangle {
                                                required property var modelData
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: modelData
                                                border.width: 1
                                                border.color: pc.modelData.card
                                            }
                                        }
                                    }
                                }
                                Txt {
                                    x: 12
                                    y: 62
                                    width: parent.width - 24
                                    text: pc.modelData.name
                                    px: 13
                                    weight: Font.Medium
                                    elide: Text.ElideRight
                                    color: pc.on ? Theme.inkPrimaryContainer : Theme.ink
                                }
                                Txt {
                                    x: 12
                                    y: 81
                                    width: parent.width - 24
                                    text: pc.modelData.desc
                                    px: 11
                                    elide: Text.ElideRight
                                    color: pc.on ? Theme.inkPrimaryContainer : Theme.inkVariant
                                }
                            }
                        }
                    }
                }

                // couleur, style, clair ou sombre
                Block {
                    SetRow {
                        icon: "palette"
                        title: "Couleurs"
                        sub: page.cfg.color === "art" ? "Les couleurs suivent la pochette du morceau (sinon le fond d'écran)"
                            : page.cfg.color && page.cfg.color !== "auto" ? "Couleur choisie" : "Les couleurs sont tirées du fond d'écran"
                    }
                    SubTitle { text: "Couleur d'accent"; key: "color" }
                    Flow {
                        width: parent.width
                        topPadding: 8
                        spacing: 6
                        Swatch {
                            on: (page.cfg.color || "auto") === "auto"
                            icon: "wallpaper"
                            tip: "Automatique (fond d’écran)"
                            onClicked: page.set({ color: "auto" })
                        }
                        Swatch {
                            on: page.cfg.color === "art"
                            icon: "album"
                            tip: "Pochette du morceau en cours (sinon fond d’écran)"
                            onClicked: page.set({ color: "art" })
                        }
                        Repeater {
                            model: page.swatches
                            Swatch {
                                required property var modelData
                                fill: modelData
                                on: page.cfg.color === modelData
                                onClicked: page.set({ color: modelData })
                            }
                        }
                        // autre couleur : #rrggbb
                        Rectangle {
                            width: 100
                            height: 30
                            radius: 15
                            color: Theme.surfaceHigh
                            border.width: hexField.bad ? 2 : 0
                            border.color: Theme.error
                            Ms {
                                x: 8
                                name: "colorize"
                                size: 16
                                color: Theme.inkVariant
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Field {
                                id: hexField
                                x: 26
                                width: parent.width - 28
                                height: parent.height
                                bg: "transparent"
                                pad: 4
                                fontSize: 12
                                placeholder: "#6750a4"
                                text: /^#[0-9a-f]{6}$/i.test(page.cfg.color || "") && page.swatches.indexOf(page.cfg.color) < 0 ? page.cfg.color : ""
                                onFocused: Ilot.pinned = true
                                onEdited: bad = false
                                onAccepted: {
                                    const v = text.trim().startsWith("#") ? text.trim() : "#" + text.trim()
                                    if (!/^#[0-9a-fA-F]{6}$/.test(v))
                                        return bad = true
                                    page.set({ color: v.toLowerCase() })
                                }
                            }
                        }
                    }
                    // style de la palette : apercu de chaque variante
                    SubTitle { text: "Style de la palette"; key: "variant" }
                    Flow {
                        id: variants
                        width: parent.width
                        topPadding: 12
                        spacing: 8
                        readonly property int cols: Math.max(1, Math.floor((width + 8) / (96 + 8)))
                        readonly property real cw: (width - (cols - 1) * 8) / cols
                        // apercu de chaque variante avec la couleur et le mode du brouillon
                        readonly property var swatches: {
                            if (!page.shown)
                                return []
                            return Theme.variants.map(v => Object.assign({ id: v.id, label: v.label }, Theme.swatch(page.pArgb, v.id, page.pDark)))
                        }
                        Repeater {
                            model: variants.swatches
                            Btn {
                                required property var modelData
                                readonly property bool on: modelData.id === page.cfg.variant
                                width: variants.cw
                                height: 66
                                radius: hovered ? 20 : 16
                                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                color: on ? Theme.primaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                                onClicked: page.set({ variant: modelData.id })
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 16 * 3 - 6 + 10
                                        height: 26
                                        radius: 13
                                        color: parent.parent.modelData.bg
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: -3
                                            Repeater {
                                                model: parent.parent.parent.parent.modelData.dots
                                                Rectangle {
                                                    required property var modelData
                                                    width: 20
                                                    height: 20
                                                    radius: 10
                                                    color: Theme.surfaceHigh
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 16
                                                        height: 16
                                                        radius: 8
                                                        color: parent.modelData
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Txt {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: parent.parent.modelData.label
                                        px: 11
                                        color: parent.parent.on ? Theme.inkPrimaryContainer : Theme.ink
                                    }
                                }
                            }
                        }
                    }
                    SubTitle { text: "Clair ou sombre"; key: "mode" }
                    Chips {
                        model: [["auto", "Comme Windows"], ["dark", "Sombre"], ["light", "Clair"], ["time", "Selon l’heure"], ["sun", "Lever / coucher du soleil"]]
                        current: page.cfg.mode
                        key: "mode"
                        onPicked: v => page.set({ mode: v })
                    }
                    Row {
                        visible: page.cfg.mode === "time"
                        topPadding: 8
                        spacing: 8
                        Txt { text: "Clair de"; anchors.verticalCenter: parent.verticalCenter }
                        TimeField { value: page.cfg.day || "07:00"; onDone: v => page.set({ day: v }) }
                        Txt { text: "à"; anchors.verticalCenter: parent.verticalCenter }
                        TimeField { value: page.cfg.night || "20:00"; onDone: v => page.set({ night: v }) }
                        // heures changees, pas encore enregistrees
                        Rectangle {
                            visible: page.draft.day !== undefined || page.draft.night !== undefined
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.warn
                        }
                        }
                    Txt {
                        visible: page.cfg.mode === "sun"
                        topPadding: 6
                        width: parent.width
                        wrapMode: Text.Wrap
                        px: 11.5
                        color: Theme.inkVariant
                        text: Ilot.sunTimes ? "Clair de " + Ilot.pad(Math.floor(Ilot.sunTimes[0] / 60)) + ":" + Ilot.pad(Ilot.sunTimes[0] % 60)
                            + " à " + Ilot.pad(Math.floor(Ilot.sunTimes[1] / 60)) + ":" + Ilot.pad(Ilot.sunTimes[1] % 60) + " (" + (page.cfg.city ? page.cfg.city.name : "") + ")"
                            : "Choisis une ville dans Météo pour connaître les heures du soleil."
                    }
                }

                // couleurs et mode appliques a Windows
                Block {
                    SetRow {
                        icon: "desktop_windows"
                        title: "Windows"
                        sub: "La couleur d'accent et le mode clair / sombre de l'îlot, appliqués à Windows"
                    }
                    SetRow {
                        subRow: true
                        title: "Appliquer la couleur d'accent à Windows"
                        sub: "Barre des tâches, menu Démarrer, bordures de fenêtres"
                        toggle: true
                        checked: !!page.cfg.win_accent
                        // (reapplication forcee a l'enregistrement : page.save)
                        key: "win_accent"
                        onToggled: on => page.set({ win_accent: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Appliquer le mode clair / sombre à Windows"
                        sub: "Quand le mode n'est pas « Comme Windows »"
                        toggle: true
                        checked: !!page.cfg.win_mode
                        key: "win_mode"
                        onToggled: on => page.set({ win_mode: on })
                    }
                }

                // ------------------------------------------ rotation des fonds
                Block {
                    SetRow {
                        key: "rotate_min"
                        icon: "autorenew"
                        title: "Changer de fond automatiquement"
                        sub: "Au hasard parmi vos fonds (ou ceux de Wallpaper Engine s'il tourne)"
                    }
                    Chips {
                        model: [[0, "Jamais"], [15, "15 min"], [30, "30 min"], [60, "1 h"], [180, "3 h"], [1440, "1 jour"]]
                        current: page.cfg.rotate_min
                        key: "rotate_min"
                        onPicked: v => page.set({ rotate_min: v })
                    }
                }
        }
    }

    Component {
        id: secIsland
        Column {
            spacing: 10
                // ilot : forme, fond, contour
                Block {
                    SetRow {
                        icon: "auto_awesome"
                        title: "Forme et matière"
                        sub: "Forme, fond et contour de l'îlot et de la barre"
                    }
                    SubTitle { text: "Forme"; key: "shape" }
                    Chips {
                        model: page.choices.shape
                        current: page.cfg.shape || "round"
                        key: "shape"
                        onPicked: v => page.set({ shape: v })
                    }
                    SubTitle { text: "Fond"; key: "island_bg" }
                    Chips {
                        model: page.choices.island_bg
                        current: page.cfg.island_bg || "solid"
                        key: "island_bg"
                        onPicked: v => page.set({ island_bg: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Cartes noires (OLED)"
                        sub: "Fond noir pur et cartes presque noires, en mode sombre"
                        toggle: true
                        checked: !!page.cfg.oled
                        key: "oled"
                        onToggled: on => page.set({ oled: on })
                    }
                    SubTitle { text: "Contour"; key: "border" }
                    Chips {
                        model: page.choices.border
                        current: page.cfg.border || "none"
                        key: "border"
                        onPicked: v => page.set({ border: v })
                    }
                }

                // pilule repliee : taille, horloge, compagnon
                Block {
                    SetRow {
                        icon: "schedule"
                        title: "Pilule repliée"
                        sub: "Ce que l'îlot replié affiche"
                    }
                    SubTitle { text: "Taille de la pilule"; key: "pill_size" }
                    Chips {
                        model: [["s", "Petite"], ["m", "Moyenne"], ["l", "Grande"]]
                        current: page.cfg.pill_size || "m"
                        key: "pill_size"
                        onPicked: v => page.set({ pill_size: v })
                    }
                    SubTitle { text: "Horloge"; key: "clock" }
                    Chips {
                        model: page.choices.clock
                        current: page.cfg.clock || "digital"
                        key: "clock"
                        onPicked: v => page.set({ clock: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Compagnon"
                        sub: page.cfg.pet === "off" ? "Masqué" : Watch.petName + " : espèce, couleur, accessoires et promenade"
                        TextBtn {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "emoji_emotions"
                            text: "Personnaliser"
                            onClicked: Ilot.settingsSection = "pet"
                        }
                    }
                }

                // animations de l'ilot, du panneau et de la barre
                Block {
                    SetRow {
                        key: "anim"
                        icon: "bolt"
                        title: "Animations"
                        sub: "Vitesse et rebond de l'îlot, du panneau et de la barre"
                    }
                    Chips {
                        model: page.choices.anim
                        current: page.cfg.anim || "normal"
                        key: "anim"
                        onPicked: v => page.set({ anim: v })
                    }
                }
        }
    }

    Component {
        id: secPlayer
        Column {
            spacing: 10
                // lecteur : survol de la pilule, onglet Media, carte de l'accueil
                Block {
                    SetRow {
                        icon: "music_note"
                        title: "Lecteur de musique"
                        sub: "Survol de la pilule, onglet Média et carte de l'accueil"
                    }
                    SubTitle { text: "Couleur du lecteur"; key: "player_color" }
                    Flow {
                        width: parent.width
                        topPadding: 8
                        spacing: 6
                        Swatch {
                            on: (page.cfg.player_color || "art") === "art"
                            icon: "album"
                            tip: "Pochette du morceau en cours"
                            onClicked: page.set({ player_color: "art" })
                        }
                        Swatch {
                            on: page.cfg.player_color === "theme"
                            icon: "palette"
                            tip: "Couleurs du thème"
                            onClicked: page.set({ player_color: "theme" })
                        }
                        Repeater {
                            model: page.swatches
                            Swatch {
                                required property var modelData
                                fill: modelData
                                on: page.cfg.player_color === modelData
                                onClicked: page.set({ player_color: modelData })
                            }
                        }
                    }
                }

                // bouton lecture
                Block {
                    SetRow {
                        icon: "play_arrow"
                        title: "Bouton lecture"
                    }
                    SubTitle { text: "Forme du bouton"; key: "player_btn" }
                    Chips {
                        model: [["cookie", "Festonné"], ["round", "Rond"], ["none", "Icône seule"]]
                        current: page.cfg.player_btn || "cookie"
                        key: "player_btn"
                        onPicked: v => page.set({ player_btn: v })
                    }
                    SubTitle { text: "Couleur du bouton"; key: "player_btn_color" }
                    Chips {
                        id: btnColorChips
                        // "#rrggbb" = couleur fixe ; "fixed" n'est jamais stocke
                        // (player_bigbtn reste lu par PlayBtn en mode auto)
                        readonly property string val: page.cfg.player_btn_color || "auto"
                        property string lastFixed: val.charAt(0) === "#" ? val : ""
                        model: [["auto", "Auto"], ["player", "Couleur du lecteur"], ["white", "Blanc"], ["fixed", "Couleur fixe"]]
                        current: val.charAt(0) === "#" ? "fixed" : val
                        key: "player_btn_color"
                        onPicked: v => page.set({ player_btn_color: v !== "fixed" ? v : (lastFixed || page.swatches[0]) })
                    }
                    Txt {
                        visible: btnColorChips.current === "auto"
                        topPadding: 6
                        width: parent.width
                        wrapMode: Text.Wrap
                        px: 11.5
                        color: Theme.inkVariant
                        // ancien reglage « gros bouton : couleur du lecteur » encore lu en auto
                        text: page.cfg.player_bigbtn === "accent"
                            ? "Auto : couleur du lecteur partout (ancien réglage conservé)"
                            : "Auto : blanc lumineux dans l'onglet Média, couleur du lecteur ailleurs"
                    }
                    Flow {
                        visible: btnColorChips.current === "fixed"
                        width: parent.width
                        topPadding: 8
                        spacing: 6
                        Repeater {
                            model: page.swatches
                            Swatch {
                                required property var modelData
                                fill: modelData
                                on: page.cfg.player_btn_color === modelData
                                onClicked: {
                                    btnColorChips.lastFixed = modelData;
                                    page.set({ player_btn_color: modelData });
                                }
                            }
                        }
                    }
                    SubTitle { text: "Couleur de l'icône"; key: "player_btn_ink" }
                    Chips {
                        enabled: page.cfg.player_btn !== "none"
                        opacity: enabled ? 1 : 0.5
                        model: [["auto", "Auto"], ["white", "Blanche"], ["black", "Noire"]]
                        current: page.cfg.player_btn_ink || "auto"
                        key: "player_btn_ink"
                        onPicked: v => page.set({ player_btn_ink: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Rotation pendant la lecture"
                        toggle: true
                        checked: page.cfg.player_btn_spin !== false
                        // sans morphose la forme ne tourne pas (PlayBtn)
                        disabled: (page.cfg.player_btn || "cookie") !== "cookie" || page.cfg.player_btn_morph === false
                        key: "player_btn_spin"
                        onToggled: on => page.set({ player_btn_spin: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Change de forme entre pause et lecture"
                        toggle: true
                        checked: page.cfg.player_btn_morph !== false
                        disabled: (page.cfg.player_btn || "cookie") !== "cookie"
                        key: "player_btn_morph"
                        onToggled: on => page.set({ player_btn_morph: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Petit rebond de l'icône au clic"
                        toggle: true
                        checked: page.cfg.player_btn_pop !== false
                        key: "player_btn_pop"
                        onToggled: on => page.set({ player_btn_pop: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Ombre colorée"
                        toggle: true
                        checked: page.cfg.player_btn_glow !== false
                        // la lueur n'existe que sous un bouton blanc (PlayBtn)
                        disabled: page.cfg.player_btn === "none" || btnColorChips.val === "player"
                            || (btnColorChips.val.charAt(0) === "#" && btnColorChips.val.toLowerCase() !== "#ffffff")
                        key: "player_btn_glow"
                        onToggled: on => page.set({ player_btn_glow: on })
                    }
                }

                // barre de progression
                Block {
                    SetRow {
                        icon: "graphic_eq"
                        title: "Barre de progression"
                    }
                    SubTitle { text: "Style"; key: "player_bar" }
                    Chips {
                        model: [["wave", "Ondulée"], ["flat", "Plate"]]
                        current: page.cfg.player_bar || "wave"
                        key: "player_bar"
                        onPicked: v => page.set({ player_bar: v })
                    }
                    SubTitle { text: "Épaisseur"; key: "player_bar_size" }
                    Chips {
                        model: [["thin", "Fine"], ["normal", "Normale"], ["thick", "Épaisse"]]
                        current: page.cfg.player_bar_size || "normal"
                        key: "player_bar_size"
                        onPicked: v => page.set({ player_bar_size: v })
                    }
                    SubTitle { text: "Amplitude de l'onde"; key: "player_bar_amp" }
                    Chips {
                        enabled: page.cfg.player_bar !== "flat"
                        opacity: enabled ? 1 : 0.5
                        model: [["low", "Faible"], ["normal", "Normale"], ["high", "Forte"]]
                        current: page.cfg.player_bar_amp || "normal"
                        key: "player_bar_amp"
                        onPicked: v => page.set({ player_bar_amp: v })
                    }
                }

                // pilule repliee et son survol : glisser, molette
                Block {
                    SetRow {
                        icon: "pill"
                        title: "Lecteur dans la pilule"
                        sub: "La pilule repliée, et son survol"
                    }
                    SetRow {
                        subRow: true
                        title: "Anneau de progression autour du disque"
                        toggle: true
                        checked: page.cfg.player_mini_ring !== false
                        key: "player_mini_ring"
                        onToggled: on => page.set({ player_mini_ring: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Le disque tourne pendant la lecture"
                        toggle: true
                        checked: page.cfg.player_mini_spin !== false
                        key: "player_mini_spin"
                        onToggled: on => page.set({ player_mini_spin: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Paroles synchronisées dans la pilule"
                        toggle: true
                        checked: page.cfg.player_mini_lyrics === true
                        key: "player_mini_lyrics"
                        onToggled: on => page.set({ player_mini_lyrics: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Glisser la pochette pour changer de titre"
                        sub: "Au survol de la pilule : vers la gauche, titre suivant ; vers la droite, précédent"
                        toggle: true
                        checked: !!page.cfg.player_swipe
                        key: "player_swipe"
                        onToggled: on => page.set({ player_swipe: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Molette : volume de l'appli qui joue"
                        sub: "Pendant la musique, la molette sur la pilule règle le volume de Spotify (ou de l'appli qui joue) au lieu du volume général"
                        toggle: true
                        checked: !!page.cfg.player_wheel
                        key: "player_wheel"
                        onToggled: on => page.set({ player_wheel: on })
                    }
                }

                // onglet Media : disposition, pochette, fond
                Block {
                    SetRow {
                        icon: "album"
                        title: "Onglet Média"
                    }
                    SubTitle { text: "Disposition"; key: "player_layout" }
                    Chips {
                        model: [["col", "Colonne (paroles à droite)"], ["side", "Côte à côte (paroles en bas)"]]
                        current: page.cfg.player_layout || "col"
                        key: "player_layout"
                        onPicked: v => page.set({ player_layout: v })
                    }
                    SubTitle { text: "Pochette"; topPadding: 18; px: 12.5; color: Theme.primary }
                    SubTitle { text: "Forme de la pochette"; key: "player_art" }
                    Chips {
                        model: [["round", "Arrondie"], ["scallop", "Festonnée"], ["disc", "Ronde"]]
                        current: page.cfg.player_art || "scallop"
                        key: "player_art"
                        onPicked: v => page.set({ player_art: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Spectre autour de la pochette"
                        toggle: true
                        // null = suit la pochette (festonnee -> spectre), sinon booleen
                        checked: page.cfg.player_spectrum === null || page.cfg.player_spectrum === undefined
                            ? (page.cfg.player_art || "scallop") === "scallop" : !!page.cfg.player_spectrum
                        key: "player_spectrum"
                        onToggled: on => page.set({ player_spectrum: on })
                    }
                    SubTitle { text: "Fond"; topPadding: 18; px: 12.5; color: Theme.primary }
                    SubTitle { text: "Type de fond"; key: "media_bg" }
                    Chips {
                        model: [["art", "Pochette floutée"], ["color", "Couleur"], ["gradient", "Dégradé"], ["none", "Aucun"]]
                        current: page.cfg.media_bg || "art"
                        key: "media_bg"
                        onPicked: v => page.set({ media_bg: v })
                    }
                    Column {
                        visible: (page.cfg.media_bg || "art") === "art"
                        width: parent.width
                        SubTitle { text: "Flou"; key: "media_blur" }
                        Chips {
                            model: [["low", "Léger"], ["medium", "Moyen"], ["high", "Fort"]]
                            current: page.cfg.media_blur || "medium"
                            key: "media_blur"
                            onPicked: v => page.set({ media_blur: v })
                        }
                        SetRow {
                            subRow: true
                            title: "Le fond dérive lentement"
                            toggle: true
                            checked: page.cfg.media_drift !== false
                            key: "media_drift"
                            onToggled: on => page.set({ media_drift: on })
                        }
                        SubTitle { text: "Assombrissement en bas"; key: "media_dim" }
                        Chips {
                            model: [["light", "Léger"], ["normal", "Normal"], ["strong", "Fort"]]
                            current: page.cfg.media_dim || "normal"
                            key: "media_dim"
                            onPicked: v => page.set({ media_dim: v })
                        }
                    }
                }
        }
    }

    Component {
        id: secPet
        Column {
            spacing: 10
                // ------------------------------------------------- compagnon
                Block {
                    SetRow {
                        icon: "emoji_emotions"
                        title: "Compagnon"
                        sub: "Une petite bête dans la pilule. Survole la pilule pour la caresser ; quand tu t'absentes, elle se promène au-dessus de la barre des tâches."
                    }
                    SubTitle { text: "Espèce"; key: "pet" }
                    Chips {
                        model: [["blob", "Blob"], ["cat", "Chat"], ["ghost", "Fantôme"], ["bunny", "Lapin"], ["frog", "Grenouille"], ["penguin", "Pingouin"],
                                ["chick", "Poussin"], ["robot", "Robot"], ["axolotl", "Axolotl"], ["mush", "Champignon"]]
                               // packs de sprites du poste (debloques, ou celui deja choisi)
                               .concat(page.petPacksShown.map(p => ["pack:" + p.id, p.name]), [["off", "Masqué"]])
                        current: page.cfg.pet || "blob"
                        key: "pet"
                        onPicked: v => page.set({ pet: v })
                    }
                    Txt {
                        visible: page.cfg.pet === "off"
                        topPadding: 10
                        width: parent.width
                        wrapMode: Text.Wrap
                        px: 11.5
                        color: Theme.inkVariant
                        text: "Masqué, le compagnon est complètement retiré : ni dessin, ni animations, ni promenade."
                    }

                    // apercu : on peut le caresser, le nourrir, jouer avec lui
                    Item {
                        visible: page.cfg.pet !== "off"
                        width: parent.width
                        height: 186
                        Rectangle {
                            id: stage
                            y: 14
                            width: parent.width
                            height: 172
                            radius: 18
                            color: Theme.surfaceHigh
                            clip: true
                            // deblocage : un bref eclat sur l'apercu
                            Rectangle {
                                id: unlockFlash
                                anchors.fill: parent
                                radius: parent.radius
                                color: Theme.primary
                                opacity: 0
                                SequentialAnimation {
                                    id: unlockA
                                    NumberAnimation { target: unlockFlash; property: "opacity"; to: 0.22; duration: 140; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: unlockFlash; property: "opacity"; to: 0; duration: 700; easing.type: Easing.InQuad }
                                }
                                Connections {
                                    target: page
                                    function onPetUnlocked() {
                                        unlockA.restart()
                                        if (stagePet.item)
                                            stagePet.item.trick("flip")
                                    }
                                }
                            }
                            // sol
                            Rectangle {
                                y: parent.height - 34
                                width: 150
                                height: 34
                                bottomLeftRadius: 18
                                color: Theme.alpha(Theme.primary, 0.08)
                            }
                            Loader {
                                id: stagePet
                                active: page.shown && page.section === "pet"
                                // buste d'un pack : centre au-dessus du sol (150 px)
                                x: page.petPackDraft && item ? 75 - item.width / 2 : 40
                                y: stage.height - 34 - (item ? item.height : 18 * 4.5) + 6
                                sourceComponent: page.petPackDraft ? stageBust : stagePetVec
                                // pack de sprites : son buste, plus grand
                                Component {
                                    id: stageBust
                                    PetBust {
                                        // planches par hauteur : la plus grande, 1:1 ;
                                        // ancien format : meme taille quel que soit json.bust.scale
                                        k: multi ? 4.5 : 6.5 / zoom
                                        centered: false
                                        listen: false
                                        interactive: true
                                        pack: page.petPackDraft
                                        mood: Watch.mood === "sleep" || Watch.mood === "surprise" ? "idle" : Watch.mood
                                        tip: "Clic : un tour · appui long : caresse"
                                        onPoked: Watch.petLoved(1, false)
                                        onCaressed: Watch.petLoved(2, true)
                                    }
                                }
                            }
                            Component {
                                id: stagePetVec
                                Pet {
                                    k: 4.5
                                    listen: false
                                    interactive: true
                                    look: 0
                                    // apercu du brouillon
                                    species: page.cfg.pet && page.cfg.pet !== "off" && String(page.cfg.pet).indexOf("pack:") !== 0 ? page.cfg.pet : "blob"
                                    hat: page.cfg.pet_hat || "none"
                                    faceAcc: page.cfg.pet_face || "none"
                                    neck: page.cfg.pet_neck || "none"
                                    eyeStyle: page.cfg.pet_eyes || "dot"
                                    tint: page.cfg.pet_color || "nature"
                                    mood: Watch.mood === "sleep" || Watch.mood === "surprise" ? "idle" : Watch.mood
                                    tip: "Clic : un tour · double clic : salto · appui long : caresse"
                                    onPoked: Watch.petLoved(1, false)
                                    onCaressed: Watch.petLoved(2, true)
                                }
                            }
                            // biscuit et balle
                            Txt {
                                id: cookie
                                text: "🍪"
                                px: 26
                                x: stagePet.x + 45 - width / 2
                                y: -40
                            }
                            SequentialAnimation {
                                id: feedA
                                NumberAnimation { target: cookie; property: "y"; from: -40; to: stagePet.y + 10; duration: 600; easing.type: Easing.InQuad }
                                ScriptAction { script: { cookie.y = -40; stagePet.item.trick("eat"); Watch.petLoved(2, false) } }
                            }
                            Rectangle {
                                id: toy
                                width: 22
                                height: 22
                                radius: 11
                                x: -30
                                y: stage.height - 34 - 22
                                color: "#ff5d6c"
                                border.width: 3
                                border.color: "#ffd84a"
                            }
                            SequentialAnimation {
                                id: playA
                                ParallelAnimation {
                                    NumberAnimation { target: toy; property: "x"; from: stage.width; to: stagePet.x + 100; duration: 900; easing.type: Easing.OutQuad }
                                    RotationAnimation { target: toy; from: 0; to: -540; duration: 900 }
                                }
                                ScriptAction { script: stagePet.item.trick("kick") }
                                ParallelAnimation {
                                    NumberAnimation { target: toy; property: "x"; to: stage.width + 30; duration: 700; easing.type: Easing.InQuad }
                                    SequentialAnimation {
                                        NumberAnimation { target: toy; property: "y"; to: 20; duration: 350; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: toy; property: "y"; to: stage.height - 34 - 22; duration: 350; easing.type: Easing.InQuad }
                                    }
                                    RotationAnimation { target: toy; to: 180; duration: 700 }
                                }
                                ScriptAction { script: { stagePet.item.trick("love"); Watch.petLoved(1, false) } }
                            }
                            // nom, niveau d'affection
                            Column {
                                x: 160
                                y: 18
                                width: parent.width - x - 16
                                spacing: 4
                                Txt {
                                    width: parent.width
                                    text: Watch.petName
                                    px: 20
                                    weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Txt {
                                    width: parent.width
                                    text: (Watch.petMoodLabels[Watch.mood] || "") + " · niveau " + Watch.petLevel
                                    px: 12
                                    color: Theme.inkVariant
                                }
                                Row {
                                    spacing: 2
                                    Repeater {
                                        model: 10
                                        Txt {
                                            required property int index
                                            text: "♥"
                                            px: 13
                                            color: index < Watch.petLevel ? "#ff5d8f" : Theme.surfaceHighest
                                        }
                                    }
                                }
                                Item { width: 1; height: 6 }
                                Flow {
                                width: parent.width
                                spacing: 6
                                TextBtn {
                                    icon: "waving_hand"
                                    text: "Caresser"
                                    onClicked: {
                                        stagePet.item.caress(true)
                                        Ilot.later(1800, () => { if (stagePet.item) stagePet.item.caress(false) })
                                    }
                                }
                                TextBtn {
                                    text: "🍪 Nourrir"
                                    onClicked: feedA.restart()
                                }
                                TextBtn {
                                    icon: "sports_esports"
                                    text: "Jouer"
                                    onClicked: playA.restart()
                                }
                                TextBtn {
                                    icon: "auto_awesome"
                                    text: "Un tour"
                                    onClicked: stagePet.item.trick(["flip", "spin", "dance", "wave", "jump", "giggle", "stretch", "blep", "sneeze", "melt", "dizzy", "boo"][Math.floor(Math.random() * 12)])
                                }
                                }
                            }
                        }
                    }

                    Column {
                        visible: page.cfg.pet !== "off"
                        width: parent.width
                        SubTitle { text: "Nom"; key: "pet_name" }
                        Item { width: 1; height: 8 }
                        Field {
                            id: petName
                            width: Math.min(parent.width, 260)
                            height: 34
                            placeholder: page.petPackDraft ? page.petPackDraft.name : Watch.petNames[Watch.petSpecies] || ""
                            text: page.cfg.pet_name || ""
                            onFocused: {
                                Ilot.pinned = true
                                Ilot.grabFocus()
                            }
                            onEdited: petNameSave.restart()
                            onAccepted: petNameSave.triggered()
                            Timer {
                                id: petNameSave
                                interval: 600
                                onTriggered: if (petName.text.trim() !== (page.cfg.pet_name || "")) page.set({ pet_name: petName.text.trim().slice(0, 24) })
                            }
                        }
                        // pack de sprites : ni couleur, ni yeux, ni accessoires
                        SubTitle { text: "Couleur"; key: "pet_color"; visible: !page.petIsPack }
                        Flow {
                            visible: !page.petIsPack
                            width: parent.width
                            topPadding: 8
                            spacing: 6
                            Swatch {
                                on: (page.cfg.pet_color || "nature") === "nature"
                                icon: "eco"
                                tip: "Couleurs naturelles de l'espèce"
                                onClicked: page.set({ pet_color: "nature" })
                            }
                            Swatch {
                                on: page.cfg.pet_color === "theme"
                                icon: "palette"
                                tip: "Couleur du thème"
                                onClicked: page.set({ pet_color: "theme" })
                            }
                            Repeater {
                                model: ["#ff8fb8", "#ff7a59", "#ffd447", "#7cc65b", "#5ec8ff", "#6d8cff", "#b28dff", "#f3f0fa", "#9e9e9e", "#3c4363"]
                                Swatch {
                                    required property var modelData
                                    fill: modelData
                                    on: page.cfg.pet_color === modelData
                                    onClicked: page.set({ pet_color: modelData })
                                }
                            }
                        }
                        SubTitle { text: "Yeux"; key: "pet_eyes"; visible: !page.petIsPack }
                        Chips {
                            visible: !page.petIsPack
                            model: [["dot", "Points"], ["shine", "Brillants"], ["big", "Grands"], ["lash", "Cils"], ["sleepy", "Endormis"], ["square", "Carrés"]]
                            current: page.cfg.pet_eyes || "dot"
                            key: "pet_eyes"
                            onPicked: v => page.set({ pet_eyes: v })
                        }
                        SubTitle { text: "Chapeau"; key: "pet_hat"; visible: !page.petIsPack }
                        Chips {
                            visible: !page.petIsPack
                            model: [["none", "Aucun"], ["party", "Fête"], ["crown", "Couronne"], ["cap", "Casquette"], ["beanie", "Bonnet"], ["top", "Haut-de-forme"],
                                    ["wizard", "Sorcier"], ["chef", "Toque"], ["flower", "Fleur"], ["bow", "Nœud"], ["halo", "Auréole"], ["horns", "Cornes"], ["headphones", "Casque audio"]]
                            current: page.cfg.pet_hat || "none"
                            key: "pet_hat"
                            onPicked: v => page.set({ pet_hat: v })
                        }
                        SubTitle { text: "Visage"; key: "pet_face"; visible: !page.petIsPack }
                        Chips {
                            visible: !page.petIsPack
                            model: [["none", "Rien"], ["glasses", "Lunettes"], ["sun", "Lunettes de soleil"], ["monocle", "Monocle"], ["mask", "Masque"],
                                    ["blush", "Joues roses"], ["freckles", "Taches de rousseur"]]
                            current: page.cfg.pet_face || "none"
                            key: "pet_face"
                            onPicked: v => page.set({ pet_face: v })
                        }
                        SubTitle { text: "Cou"; key: "pet_neck"; visible: !page.petIsPack }
                        Chips {
                            visible: !page.petIsPack
                            model: [["none", "Rien"], ["bowtie", "Nœud papillon"], ["scarf", "Écharpe"], ["bell", "Grelot"], ["bandana", "Bandana"]]
                            current: page.cfg.pet_neck || "none"
                            key: "pet_neck"
                            onPicked: v => page.set({ pet_neck: v })
                        }

                        // promenade
                        Item { width: 1; height: 8 }
                        SetRow {
                            subRow: true
                            title: "Il se promène quand tu ne fais rien"
                            sub: "Au-dessus de la barre des tâches : balade, sieste, ballon, papillon, pêche, skate… selon l'heure, la météo et la musique. Il remonte en te faisant coucou dès que tu reviens."
                            toggle: true
                            checked: !!page.cfg.pet_walk
                            key: "pet_walk"
                            onToggled: on => page.set({ pet_walk: on })
                        }
                        Column {
                            visible: !!page.cfg.pet_walk
                            width: parent.width
                            SubTitle { text: "Au bout de"; key: "pet_afk" }
                            Chips {
                                model: [[30, "30 s"], [90, "1 min 30"], [180, "3 min"], [300, "5 min"]]
                                current: Number(page.cfg.pet_afk) || 90
                                key: "pet_afk"
                                onPicked: v => page.set({ pet_afk: v })
                            }
                            SubTitle { text: "Taille en promenade"; key: "pet_size" }
                            Chips {
                                model: [["s", "Petite"], ["m", "Moyenne"], ["l", "Grande"]]
                                current: page.cfg.pet_size || "m"
                                key: "pet_size"
                                onPicked: v => page.set({ pet_size: v })
                            }
                            SubTitle { text: "Traînée derrière lui"; key: "pet_trail" }
                            Chips {
                                model: [["none", "Aucune"], ["sparkle", "Étincelles"], ["hearts", "Cœurs"], ["bubbles", "Bulles"], ["flowers", "Fleurs"],
                                        ["steps", "Empreintes"], ["rainbow", "Arc-en-ciel"]]
                                current: page.cfg.pet_trail || "sparkle"
                                key: "pet_trail"
                                onPicked: v => page.set({ pet_trail: v })
                            }
                        }
                        // scenes du compagnon dessine enregistre (pas pour un pack)
                        SubTitle { text: "Voir une scène tout de suite (40 s)"; visible: !Watch.petPack && !page.petIsPack }
                        Chips {
                            visible: !Watch.petPack && !page.petIsPack
                            model: [["stroll", "Balade"], ["sleep", "Sieste"], ["ball", "Ballon"], ["butterfly", "Papillon"], ["balloon", "Montgolfière"],
                                    ["fishing", "Pêche"], ["skate", "Skate"], ["bubbles", "Bulles"], ["read", "Lecture"], ["plane", "Avion en papier"],
                                    ["garden", "Jardinage"], ["hide", "Cache-cache"], ["meditate", "Méditation"], ["dance", "Danse"], ["stars", "Étoiles filantes"],
                                    ["coffee", "Café"], ["umbrella", "Parapluie"], ["snow", "Bonhomme de neige"], ["special", "Son tour secret"]]
                            current: ""
                            onPicked: v => Watch.petDemo(v)
                        }
                        // pack de sprites enregistre : pas de scenes, sa propre promenade
                        TextBtn {
                            visible: !!Watch.petPack && page.petSaved && !Watch.petOut
                            icon: "play_arrow"
                            text: "Le voir se promener (40 s)"
                            onClicked: Watch.petDemo("stroll")
                        }
                        Txt {
                            visible: (!!Watch.petPack || page.petIsPack) && !page.petSaved
                            topPadding: 10
                            width: parent.width
                            wrapMode: Text.Wrap
                            px: 11.5
                            color: Theme.inkVariant
                            text: "Enregistre pour le voir se promener."
                        }
                        Txt {
                            visible: Theme.reduced
                            topPadding: 8
                            width: parent.width
                            wrapMode: Text.Wrap
                            px: 11.5
                            color: Theme.inkVariant
                            text: "Mouvements réduits (Accessibilité) : il reste dans la pilule."
                        }
                        Item { width: 1; height: 10 }
                        TextBtn {
                            visible: Watch.petOut
                            icon: "close"
                            text: "Le faire rentrer"
                            onClicked: Watch.petDemoStop()
                        }
                    }
                }
        }
    }

    Component {
        id: secAlerts
        Column {
            spacing: 10
                // ---------------------------------------------- notifications
                Block {
                    SetRow {
                        icon: "notifications"
                        title: "Notifications dans l'îlot"
                        sub: "Les notifications Windows s'affichent aussi dans la pilule"
                        toggle: true
                        checked: !!page.cfg.notif_popups
                        key: "notif_popups"
                        onToggled: on => page.set({ notif_popups: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Indicateurs de volume et de luminosité"
                        sub: "La pilule s'agrandit quand le volume ou la luminosité change"
                        toggle: true
                        checked: !!page.cfg.osd
                        key: "osd"
                        onToggled: on => page.set({ osd: on })
                    }
                }

                // ce que la pilule affiche d'elle-meme
                Block {
                    SetRow {
                        icon: "pill"
                        title: "Dans la pilule"
                        sub: "Ce que la pilule affiche d'elle-même"
                    }
                    SetRow {
                        subRow: true
                        title: "Activités en cours"
                        sub: "Téléchargements Steam, jeu lancé, charge et température du GPU"
                        toggle: true
                        checked: !!page.cfg.activity
                        key: "activity"
                        onToggled: on => page.set({ activity: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Raccourcis Discord"
                        sub: "Micro et sourdine dans la pilule quand tu es en vocal"
                        toggle: true
                        checked: !!page.cfg.dc_pill
                        key: "dc_pill"
                        onToggled: on => page.set({ dc_pill: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Voyant caméra / micro"
                        sub: "Vert : une appli filme ; orange : une appli écoute le micro"
                        toggle: true
                        checked: !!page.cfg.privacy
                        key: "privacy"
                        onToggled: on => page.set({ privacy: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Météo animée"
                        sub: "Pluie, neige, soleil ou étoiles derrière la pilule"
                        toggle: true
                        checked: !!page.cfg.wxfx
                        key: "wxfx"
                        onToggled: on => page.set({ wxfx: on })
                    }
                }
        }
    }

    Component {
        id: secBar
        Column {
            spacing: 10
                // ------------------------------------------------------ barre
                Block {
                    SetRow {
                        icon: "dashboard"
                        title: "Barre en haut de l'écran"
                        sub: "Façon Waybar : bureaux, fenêtres ouvertes et état du système autour de l'îlot"
                        toggle: true
                        checked: !!page.cfg.bar
                        key: "bar"
                        onToggled: on => page.set({ bar: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Masquer la barre des tâches Windows"
                        sub: "Elle revient quand l'îlot est quitté"
                        toggle: true
                        checked: !!page.cfg.hide_taskbar
                        disabled: !page.cfg.bar
                        key: "hide_taskbar"
                        onToggled: on => page.set({ hide_taskbar: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Îlots séparés"
                        sub: "Sans fond : chaque groupe flotte comme un petit îlot"
                        toggle: true
                        checked: !!page.cfg.bar_islands
                        disabled: !page.cfg.bar
                        key: "bar_islands"
                        onToggled: on => page.set({ bar_islands: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Fenêtres ouvertes"
                        sub: "Les applications ouvertes, à côté des bureaux"
                        toggle: true
                        checked: !!page.cfg.bar_tasks
                        disabled: !page.cfg.bar
                        key: "bar_tasks"
                        onToggled: on => page.set({ bar_tasks: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Titre de la fenêtre active"
                        sub: "Le nom de la fenêtre au premier plan, à côté de son icône"
                        toggle: true
                        checked: page.cfg.bar_titles !== false
                        disabled: !page.cfg.bar || !page.cfg.bar_tasks
                        key: "bar_titles"
                        onToggled: on => page.set({ bar_titles: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Masquer automatiquement"
                        sub: "La barre apparaît quand la souris touche le haut de l'écran"
                        toggle: true
                        checked: !!page.cfg.bar_autohide
                        disabled: !page.cfg.bar
                        key: "bar_autohide"
                        onToggled: on => page.set({ bar_autohide: on })
                    }
                }

                // ------------------------------------------------------ ecran
                Block {
                    SetRow {
                        icon: "desktop_windows"
                        title: "Écran de l'îlot"
                        sub: "Si l'écran choisi est débranché, l'îlot revient sur l'écran principal"
                    }
                    Flow {
                        width: parent.width
                        topPadding: 12
                        spacing: 8
                        readonly property var cur: page.monitors.some(m => m.id === page.chosenMonitor) ? page.chosenMonitor : null
                        readonly property var primary: page.monitors.find(m => m.primary)
                        readonly property int cols: Math.max(1, Math.floor((width + 8) / (150 + 8)))
                        readonly property real cw: (width - (cols - 1) * 8) / cols
                        Repeater {
                            model: [{ id: null, label: "Automatique", sub: parent.primary ? "Écran principal (" + parent.primary.label + ")" : "Écran principal", icon: "auto_awesome" }]
                                .concat(page.monitors.map(m => ({ id: m.id, label: m.label, icon: "monitor", sub: m.width + " × " + m.height + (m.primary ? " · principal" : "") })))
                            Btn {
                                required property var modelData
                                readonly property bool on: modelData.id === parent.cur
                                width: parent.cw
                                height: 84
                                radius: hovered ? 22 : 18
                                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                color: on ? Theme.primaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                                readonly property color fg: on ? Theme.inkPrimaryContainer : Theme.ink
                                onClicked: {
                                    page.chosenMonitor = modelData.id
                                    Api.invoke("settings_monitor", { id: modelData.id })
                                }
                                Column {
                                    x: 14
                                    y: 12
                                    spacing: 3
                                    Ms {
                                        name: parent.parent.modelData.icon
                                        size: 22
                                        color: parent.parent.on ? parent.parent.fg : Theme.inkVariant
                                    }
                                    Item { width: 1; height: 1 }
                                    Txt {
                                        text: parent.parent.modelData.label
                                        weight: Font.Medium
                                        color: parent.parent.fg
                                    }
                                    Txt {
                                        text: parent.parent.modelData.sub
                                        px: 11.5
                                        color: parent.parent.on ? parent.parent.fg : Theme.inkVariant
                                    }
                                }
                            }
                        }
                    }
                }

                // ------------------------------------- ilot en plein ecran
                Block {
                    SetRow {
                        key: "fs_hide"
                        icon: "visibility"
                        title: "Îlot en plein écran"
                        sub: "Quand un jeu ou une vidéo occupe tout l'écran"
                    }
                    Chips {
                        model: [["normal", "Normal"], ["show", "Toujours affiché"], ["auto", "Masquer auto"], ["custom", "Personnalisé"]]
                        current: page.cfg.fs_hide || "normal"
                        key: "fs_hide"
                        onPicked: v => page.set({ fs_hide: v })
                    }
                    Txt {
                        topPadding: 8
                        width: parent.width
                        wrapMode: Text.Wrap
                        px: 11.5
                        color: Theme.inkVariant
                        text: page.cfg.fs_hide === "show" ? "L'îlot reste par-dessus les applis en plein écran. La barre, les notifications et le compagnon restent masqués."
                            : page.cfg.fs_hide === "auto" ? "L'îlot se masque en plein écran et revient quand la souris touche le haut de l'écran, au milieu."
                            : page.cfg.fs_hide === "custom" ? "L'îlot ne se masque que devant les applis choisies, en plein écran ou en fenêtre agrandie. Ailleurs, il reste affiché."
                            : "L'îlot se masque dès qu'une appli passe en plein écran."
                    }
                    // applis choisies, puis applis proposees (vues en plein ecran,
                    // ouvertes)
                    Column {
                        visible: page.cfg.fs_hide === "custom"
                        width: parent.width
                        topPadding: 8
                        onVisibleChanged: if (visible) page.loadFsOpen()
                        Component.onCompleted: if (visible) page.loadFsOpen()
                        SubTitle { text: "Masquer devant" }
                        Repeater {
                            model: Ilot.fsApps
                            FsAppRow { chosen: true }
                        }
                        Txt {
                            visible: !Ilot.fsApps.length
                            topPadding: 6
                            bottomPadding: 4
                            text: "Aucune appli choisie : l'îlot reste affiché partout."
                            px: 12
                            color: Theme.inkVariant
                        }
                        SubTitle {
                            visible: page.fsChoices.length > 0
                            topPadding: 10
                            text: "Ajouter (vues en plein écran, puis ouvertes)"
                        }
                        Repeater {
                            model: page.fsChoices
                            FsAppRow {}
                        }
                        // executable d'une appli qui n'est pas ouverte
                        Row {
                            topPadding: 10
                            spacing: 8
                            Field {
                                id: fsExeField
                                width: 220
                                height: 32
                                bg: Theme.surfaceHigh
                                placeholder: "Autre appli : jeu.exe"
                                onFocused: {
                                    Ilot.pinned = true
                                    Ilot.grabFocus()
                                }
                                onAccepted: {
                                    page.fsAddTyped(text)
                                    text = ""
                                }
                            }
                            TextBtn {
                                icon: "add"
                                text: "Ajouter"
                                onClicked: {
                                    page.fsAddTyped(fsExeField.text)
                                    fsExeField.text = ""
                                }
                            }
                        }
                    }
                }
        }
    }

    Component {
        id: secGame
        Column {
            spacing: 10
                // -------------------------------------------- mode jeu, absent
                Block {
                    SetRow {
                        icon: "sports_esports"
                        title: "Mode jeu"
                        sub: "Quand un jeu détecté (Steam, Epic, Ubisoft, GOG) tourne"
                        toggle: true
                        checked: !!page.cfg.game_mode
                        key: "game_mode"
                        onToggled: on => page.set({ game_mode: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Passer en mode Performances"
                        sub: "Le mode d'alimentation d'avant revient à la fermeture du jeu"
                        toggle: true
                        disabled: !page.cfg.game_mode
                        checked: !!page.cfg.game_perf
                        key: "game_perf"
                        onToggled: on => page.set({ game_perf: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Garder les notifications"
                        sub: "Sinon, l'îlot reste silencieux pendant la partie"
                        toggle: true
                        disabled: !page.cfg.game_mode
                        checked: !!page.cfg.game_notif
                        key: "game_notif"
                        onToggled: on => page.set({ game_notif: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Alerte « partie trouvée »"
                        sub: "Son et îlot qui clignote quand tu attends hors du jeu"
                        toggle: true
                        checked: !!page.cfg.match_alert
                        key: "match_alert"
                        onToggled: on => page.set({ match_alert: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Valorant"
                        sub: "Partie trouvée et temps restant de la sélection des agents dans l'îlot"
                        toggle: true
                        checked: page.cfg.valorant !== false
                        key: "valorant"
                        onToggled: on => page.set({ valorant: on })
                    }
                    SetRow {
                        key: "away"
                        icon: "bedtime"
                        title: "Mode absent"
                        sub: "10 min sans clavier ni souris : les notifications attendent ton retour"
                    }
                    Chips {
                        model: [["on", "Pause musique + récap"], ["recap", "Récap seulement"], ["off", "Désactivé"]]
                        current: page.cfg.away || "on"
                        key: "away"
                        onPicked: v => page.set({ away: v })
                    }
                }
        }
    }

    Component {
        id: secSound
        Column {
            spacing: 10
                // ------------------------------------------------------- son
                Block {
                    id: soundBlock
                    readonly property bool chosen: Ilot.outHiddenMap !== null
                    // clic dans le vide de la carte : valide le nom en cours (les
                    // boutons et le champ prennent leurs clics avant)
                    TapHandler {
                        // toute la carte, marges comprises (sinon la colonne `inner`)
                        parent: soundBlock
                        enabled: page.outEdit !== ""
                        // un clic lent compte aussi
                        longPressThreshold: 0
                        onTapped: page.outEdit = ""
                    }
                    SetRow {
                        icon: "tune"
                        title: "Sorties affichées" + (soundBlock.chosen
                            ? " · " + page.outRows.filter(r => r.def || page.outOn(r)).length + " sur " + page.outRows.length : "")
                        sub: "Les sorties proposées dans « Sortie audio » et dans le mélangeur. Une sortie masquée fonctionne toujours dans Windows et dans la soundboard, et « +N » la montre au besoin."
                    }
                    Empty {
                        visible: page.outsLoaded && page.outRows.length === 0 && page.outGone.length === 0
                        width: parent.width
                        small: true
                        text: "Aucune sortie audio."
                    }
                    SubTitle {
                        visible: page.outPhys.length + page.outPhysGone.length > 0
                        text: "Appareils"
                    }
                    Column {
                        width: parent.width
                        Repeater {
                            model: page.outPhys
                            OutRow {}
                        }
                        Repeater {
                            model: page.outPhysGone
                            OutRow {}
                        }
                    }
                    Item {
                        id: virtHead
                        visible: page.outVirt.length + page.outVirtGone.length > 0
                        width: parent.width
                        // meme ecart que « Appareils » ; bouton centre sur le titre
                        height: visible ? Math.max(virtTitle.height, virtBtn.y + virtBtn.height) : 0
                        // la sortie par defaut ne compte pas : elle reste affichee
                        readonly property bool allOff: page.outVirt.some(r => !r.def) && page.outVirt.every(r => r.def || !page.outOn(r))
                        SubTitle {
                            id: virtTitle
                            text: "Virtuelles"
                        }
                        TextBtn {
                            id: virtBtn
                            // inutile si la seule virtuelle est la sortie par defaut
                            visible: page.outVirt.some(r => !r.def)
                            anchors.right: parent.right
                            y: virtTitle.topPadding + (virtTitle.height - virtTitle.topPadding - height) / 2
                            icon: virtHead.allOff ? "visibility" : "visibility_off"
                            text: virtHead.allOff ? "Afficher les virtuelles" : "Masquer les virtuelles"
                            onClicked: page.outSetHidden(page.outVirt.map(r => r.id), !virtHead.allOff)
                        }
                    }
                    Column {
                        width: parent.width
                        Repeater {
                            model: page.outVirt
                            OutRow {}
                        }
                        Repeater {
                            model: page.outVirtGone
                            OutRow {}
                        }
                    }
                    // sous les listes, a hauteur fixe (la plus grande des deux) :
                    // l'explication cede la place aux boutons au premier choix sans
                    // que la carte raccourcisse (page defilee en bas, les lignes
                    // descendraient sous la souris)
                    Item {
                        visible: soundBlock.chosen || page.outRows.length > 0
                        width: parent.width
                        height: Math.max(autoNote.height, outBtns.height)
                        Txt {
                            id: autoNote
                            visible: !soundBlock.chosen
                            width: parent.width
                            topPadding: 14
                            text: "Pour l'instant, le mélangeur trie seul (sortie par défaut, sorties où une appli joue, canaux Sonar) et « Sortie audio » les montre toutes. Touche un interrupteur pour choisir toi-même : les interrupteurs ci-dessus deviendront ton choix, pour les deux."
                            px: 12
                            color: Theme.inkVariant
                            wrapMode: Text.Wrap
                        }
                        Row {
                            id: outBtns
                            visible: soundBlock.chosen
                            topPadding: 14
                            spacing: 8
                            TextBtn {
                                icon: "visibility"
                                text: "Tout afficher"
                                disabled: Object.keys(Ilot.outHiddenMap || {}).length === 0
                                onClicked: {
                                    page.outEdit = ""
                                    Ilot.setOutCfg({ audio_hidden: {} })
                                }
                            }
                            TextBtn {
                                icon: "auto_awesome"
                                text: "Revenir au tri automatique"
                                onClicked: {
                                    page.outEdit = ""
                                    Ilot.setOutCfg({ audio_hidden: null })
                                    // les applis comptent de nouveau : relire tout de suite
                                    page.outsSig = ""
                                    page.loadOuts()
                                }
                            }
                        }
                    }
                }
        }
    }

    Component {
        id: secKeys
        Column {
            spacing: 10
                // ------------------------------------------- touche Windows
                Block {
                    SetRow {
                        icon: "apps"
                        title: "Touche Windows"
                        sub: "Appuyée seule, elle ouvre les applications de l'îlot au lieu du menu Démarrer (Ctrl+Échap l'ouvre toujours). La touche est remappée : îlot fermé, elle ne fait plus rien"
                        toggle: true
                        checked: !!page.cfg.win_key
                        disabled: page.winkeyBusy
                        key: "win_key"
                        onToggled: on => page.set({ win_key: on })
                    }
                    Item {
                        readonly property var st: page.winkey
                        readonly property var info: {
                            if (!st)
                                return null
                            if (st.pending)
                                return ["Redémarrez Windows pour terminer (Redémarrer, pas Arrêter).", null]
                            if (Ilot.cfg.win_key && !st.remap)
                                return ["Windows peut encore ouvrir le menu Démarrer : la touche n'est pas remappée.", ["Remapper", true]]
                            if (!Ilot.cfg.win_key && st.remap)
                                return ["La touche Windows est encore remappée.", ["Rétablir", false]]
                            return null
                        }
                        visible: !!info
                        width: parent.width
                        height: visible ? Math.max(noteText.implicitHeight, 32) + 12 : 0
                        Txt {
                            id: noteText
                            x: 54
                            y: 12
                            width: parent.width - 54 - (noteBtn.visible ? noteBtn.width + 14 : 0)
                            wrapMode: Text.Wrap
                            text: parent.info ? parent.info[0] : ""
                            px: 12
                            color: Theme.inkVariant
                        }
                        TextBtn {
                            id: noteBtn
                            visible: !!(parent.info && parent.info[1])
                            anchors.right: parent.right
                            y: 12
                            text: parent.info && parent.info[1] ? parent.info[1][0] : ""
                            onClicked: page.winKeyRemap(parent.info[1][1])
                        }
                    }
                }

                // ----------------------------------------- raccourcis clavier
                Block {
                    SetRow {
                        icon: "keyboard"
                        title: "Raccourcis clavier"
                        sub: "Partout dans Windows. Clic puis la combinaison · Échap : annuler · Retour arrière : effacer"
                    }
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: page.keyActions
                        KeyRow {}
                    }
                }

                // ------------------------------- raccourcis d'applications
                Block {
                    SetRow {
                        icon: "open_in_new"
                        title: "Raccourcis d'applications"
                        sub: "Une combinaison ouvre l'application de ton choix, par exemple Win+T pour le Terminal. Les combinaisons avec la touche Windows passent avant celles de Windows"
                    }
                    Item { width: 1; height: page.appKeys.length ? 8 : 0 }
                    Repeater {
                        model: page.appKeys
                        KeyRow {}
                    }
                    Item { width: 1; height: 10 }
                    TextBtn {
                        x: 54
                        visible: !page.appPick
                        icon: "add"
                        text: "Ajouter une application"
                        onClicked: {
                            page.appPick = true
                            appSearch.text = ""
                            Ilot.pinned = true
                            Ilot.grabFocus()
                            Qt.callLater(() => appSearch.input.forceActiveFocus())
                        }
                    }
                    // choix de l'application
                    Column {
                        visible: page.appPick
                        x: 54
                        width: parent.width - 54
                        spacing: 4
                        Row {
                            width: parent.width
                            spacing: 8
                            Field {
                                id: appSearch
                                width: parent.width - cancelPick.width - 8
                                height: 34
                                bg: Theme.surfaceHigh
                                focusRing: true
                                placeholder: "Rechercher une application (Terminal, Explorateur…)"
                                onFocused: Ilot.pinned = true
                                onTextChanged: page.appQuery = text
                                onAccepted: if (page.appMatches.length) page.addAppKey(page.appMatches[0])
                                onKeyPressed: e => {
                                    if (e.key === Qt.Key_Escape) {
                                        e.accepted = true
                                        page.appPick = false
                                    }
                                }
                            }
                            TextBtn {
                                id: cancelPick
                                text: "Annuler"
                                onClicked: page.appPick = false
                            }
                        }
                        Repeater {
                            model: page.appPick ? page.appMatches : []
                            Btn {
                                required property var modelData
                                width: parent.width
                                height: 38
                                radius: 12
                                color: hovered ? Theme.surfaceHigh : "transparent"
                                onClicked: page.addAppKey(modelData)
                                AppIcon {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    src: parent.modelData.icon || ""
                                    name: parent.modelData.name
                                }
                                Txt {
                                    x: 42
                                    width: parent.width - x - 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.name
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Txt {
                            visible: page.appPick && !page.appMatches.length
                            topPadding: 6
                            text: Ilot.apps.length ? "Aucune application trouvée" : "Chargement des applications…"
                            px: 12
                            color: Theme.inkVariant
                        }
                    }
                }
        }
    }

    Component {
        id: secWeather
        Column {
            spacing: 10
                // ------------------------------------------------------ meteo
                Block {
                    id: cityCard
                    function takeFocus() {
                        if (!page.cityFocus)
                            return
                        page.cityFocus = false
                        Qt.callLater(() => {
                            const y = cityCard.mapToItem(col, 0, 0).y
                            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - 40))
                            Ilot.grabFocus()
                            cityField.input.forceActiveFocus()
                        })
                    }
                    Component.onCompleted: takeFocus()
                    Connections {
                        target: page
                        function onCityFocusChanged() {
                            cityCard.takeFocus()
                        }
                    }
                    SetRow {
                        icon: "partly_cloudy_day"
                        title: "Météo"
                        sub: page.cfg.city ? page.cfg.city.name : "Aucune ville choisie"
                    }
                    Rectangle {
                        width: parent.width
                        height: 38 + 12
                        color: "transparent"
                        Rectangle {
                            y: 12
                            width: parent.width
                            height: 38
                            radius: 19
                            color: Theme.surfaceHigh
                            Ms {
                                x: 16
                                anchors.verticalCenter: parent.verticalCenter
                                name: "search"
                                color: Theme.inkVariant
                            }
                            Field {
                                id: cityField
                                x: 16 + 20 + 4
                                width: parent.width - x - 10
                                height: parent.height
                                bg: "transparent"
                                pad: 6
                                fontSize: 13
                                placeholder: "Rechercher une ville…"
                                onFocused: Ilot.grabFocus()
                                onEdited: cityTimer.restart()
                            }
                        }
                    }
                    Timer {
                        id: cityTimer
                        interval: 350
                        onTriggered: page.searchCity(cityField.text)
                    }
                    Column {
                        width: parent.width
                        topPadding: page.cities.length || page.cityMsg ? 6 : 0
                        spacing: 2
                        Empty {
                            visible: page.cityMsg !== ""
                            width: parent.width
                            small: true
                            text: page.cityMsg
                        }
                        Repeater {
                            model: page.cities
                            Btn {
                                required property var modelData
                                width: parent.width
                                height: 36
                                radius: 12
                                color: hovered ? Theme.surfaceHigh : "transparent"
                                onClicked: {
                                    // copie avant de vider la liste : elle detruit ce delegue (modelData compris)
                                    const c = { name: modelData.name, lat: modelData.latitude, lon: modelData.longitude }
                                    Ilot.setCfg({ city: c })
                                    Ilot.refreshWeather()
                                    cityField.text = ""
                                    page.cities = []
                                }
                                Ms {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "location_on"
                                    size: 18
                                    color: Theme.inkVariant
                                }
                                Txt {
                                    id: cityName
                                    x: 42
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData.name
                                    weight: Font.Medium
                                }
                                Txt {
                                    x: cityName.x + cityName.width + 8
                                    anchors.baseline: cityName.baseline
                                    width: parent.width - x - 10
                                    text: [parent.modelData.admin1, parent.modelData.country].filter(Boolean).join(", ")
                                    px: 11.5
                                    color: Theme.inkVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------- agendas
                Block {
                    SetRow {
                        icon: "event"
                        title: "Agenda"
                        sub: "Adresse iCal secrète (Google Agenda : Paramètres › Intégrer l'agenda ; Outlook : Publier un calendrier)"
                    }
                    Column {
                        width: parent.width
                        topPadding: (page.cfg.icals || []).length ? 10 : 0
                        spacing: 4
                        Repeater {
                            model: page.cfg.icals || []
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 38
                                radius: 14
                                color: Theme.surfaceHigh
                                Ms {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "calendar_month"
                                    size: 18
                                    color: Theme.inkVariant
                                }
                                // l'adresse est secrete : on n'en montre que le debut
                                Txt {
                                    x: 40
                                    width: parent.width - 40 - 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    readonly property string u: parent.modelData
                                    text: u.replace(/^(https?:\/\/[^/]+\/).*$/, "$1…") + (u.length > 40 ? "  " + u.slice(-12) : "")
                                    px: 12
                                    elide: Text.ElideRight
                                }
                                IconBtn {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    small: true
                                    icon: "close"
                                    tip: "Retirer"
                                    onClicked: {
                                        const i = parent.index
                                        Ilot.setCfg({ icals: Ilot.cfg.icals.filter((_, k) => k !== i) })
                                        Ilot.later(300, () => Ilot.refreshEvents(true))
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        topPadding: 10
                        spacing: 8
                        Field {
                            id: icalField
                            width: parent.width - icalAdd.width - 8
                            placeholder: "https://… .ics"
                            onFocused: Ilot.grabFocus()
                            onEdited: bad = false
                            onAccepted: icalAdd.clicked(null)
                        }
                        TextBtn {
                            id: icalAdd
                            icon: "add"
                            text: "Ajouter"
                            onClicked: {
                                const u = icalField.text.trim()
                                if (!/^(https|webcal):\/\//i.test(u)) {
                                    icalField.bad = true
                                    Ilot.later(800, () => { icalField.bad = false })
                                    return
                                }
                                icalField.text = ""
                                Ilot.setCfg({ icals: (Ilot.cfg.icals || []).concat([u]) })
                                Ilot.later(300, () => Ilot.refreshEvents(true))
                            }
                        }
                    }
                }
        }
    }

    Component {
        id: secAccess
        Column {
            spacing: 10
                // --------------------------------------------- accessibilite
                Block {
                    SetRow {
                        icon: "accessibility_new"
                        title: "Accessibilité"
                        sub: "Texte, contraste, animations et couleurs des voyants"
                    }
                    SubTitle { text: "Taille du texte du panneau"; key: "text_size" }
                    Chips {
                        model: [[100, "Normale"], [112, "Grande"], [125, "Très grande"]]
                        current: Number(page.cfg.text_size) || 100
                        key: "text_size"
                        onPicked: v => page.set({ text_size: v })
                    }
                    SubTitle { text: "Contraste"; key: "contrast" }
                    Chips {
                        model: [["normal", "Normal"], ["high", "Élevé"]]
                        current: page.cfg.contrast || "normal"
                        key: "contrast"
                        onPicked: v => page.set({ contrast: v })
                    }
                    SubTitle { text: "Mouvements et animations"; key: "motion" }
                    Chips {
                        model: [["system", "Comme Windows"], ["full", "Toutes"], ["reduced", "Réduites"]]
                        current: page.cfg.motion || "system"
                        key: "motion"
                        onPicked: v => page.set({ motion: v })
                    }
                    SubTitle { text: "Couleurs des voyants (vert / orange / rouge)"; key: "cvd" }
                    Chips {
                        model: [["off", "Standard"], ["rg", "Daltonien rouge-vert"], ["by", "Daltonien bleu-jaune"]]
                        current: page.cfg.cvd || "off"
                        key: "cvd"
                        onPicked: v => page.set({ cvd: v })
                    }
                }
        }
    }

    Component {
        id: secAddons
        Column {
            spacing: 10
                // ---------------------------------------------------- addons
                Block {
                    SetRow {
                        icon: "grid_view"
                        title: "Addons"
                        sub: "Choisis les onglets du panneau. Les essentiels sont toujours là ; un addon désactivé n'a plus d'onglet et ne tourne plus en arrière-plan"
                    }
                    SubTitle { text: "Essentiels" }
                    Flow {
                        width: parent.width
                        topPadding: 8
                        spacing: 6
                        Repeater {
                            model: Ilot.catalog.filter(t => t.core)
                            Rectangle {
                                required property var modelData
                                width: coreRow.implicitWidth + 22
                                height: 30
                                radius: 15
                                color: Theme.surfaceHigh
                                Row {
                                    id: coreRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Ms {
                                        name: parent.parent.modelData.icon
                                        size: 16
                                        color: Theme.inkVariant
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Txt {
                                        text: parent.parent.modelData.label || parent.parent.modelData.tip
                                        px: 12.5
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        topPadding: 14
                        spacing: 8
                        TextBtn {
                            icon: "check"
                            text: "Tout activer"
                            disabled: Ilot.addons.every(a => Ilot.hasTab(a.id))
                            onClicked: Ilot.setCfg({ addons: Ilot.addons.map(a => a.id) })
                        }
                        TextBtn {
                            icon: "remove"
                            text: "Essentiels seulement"
                            disabled: !(Ilot.cfg.addons || []).length
                            onClicked: {
                                if (Ilot.hasTab("sounds"))
                                    Ilot.setAddon("sounds", false)
                                Ilot.setCfg({ addons: [] })
                            }
                        }
                    }
                }
                Block {
                    SetRow {
                        title: "Disponibles"
                        sub: (Ilot.cfg.addons || []).length + " sur " + Ilot.addons.length + " activés"
                    }
                    Column {
                        width: parent.width
                        topPadding: 6
                        spacing: 12
                        Repeater {
                            model: Ilot.addons
                            Column {
                                id: addon
                                required property var modelData
                                width: parent.width
                                SetRow {
                                    icon: addon.modelData.icon
                                    title: addon.modelData.label
                                    sub: addon.modelData.desc
                                    toggle: true
                                    checked: Ilot.hasTab(addon.modelData.id)
                                    onToggled: on => Ilot.setAddon(addon.modelData.id, on)
                                }
                                // parties de l'addon (Assistant : traduction, Claude) ;
                                // la derniere active ne se coupe pas
                                Repeater {
                                    model: addon.modelData.parts || []
                                    SetRow {
                                        required property var modelData
                                        readonly property bool on: page.cfg[modelData.key] !== false
                                        subRow: true
                                        title: modelData.label
                                        sub: modelData.sub
                                        toggle: true
                                        checked: on
                                        disabled: !Ilot.hasTab(addon.modelData.id)
                                            || (on && addon.modelData.parts.filter(p => page.cfg[p.key] !== false).length < 2)
                                        key: modelData.key
                                        onToggled: v => page.set({ [modelData.key]: v })
                                    }
                                }
                            }
                        }
                    }

                    SubTitle { text: "Claude Code" }
                    SetRow {
                        subRow: true
                        title: "Claude Code dans l'îlot"
                        sub: "Animation et temps écoulé dans la pilule pendant que Claude travaille"
                        toggle: true
                        checked: page.cfg.cc_on !== false
                        key: "cc_on"
                        onToggled: on => page.set({ cc_on: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Son à la fin"
                        sub: "Quand la tâche a duré au moins :"
                        toggle: true
                        disabled: page.cfg.cc_on === false
                        checked: page.cfg.cc_sound !== false
                        key: "cc_sound"
                        onToggled: on => page.set({ cc_sound: on })
                    }
                    SetRow {
                        subRow: true
                        title: "Écouter le son"
                        sub: "Le petit « pop » joué à la fin d'une tâche"
                        TextBtn {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "volume_up"
                            text: "Tester"
                            onClicked: Backend.bubble()
                        }
                    }
                    Chips {
                        model: [[10, "10 s"], [30, "30 s"], [60, "1 min"], [120, "2 min"]]
                        current: page.cfg.cc_min !== undefined ? page.cfg.cc_min : 30
                        key: "cc_min"
                        onPicked: v => page.set({ cc_min: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Hooks Claude Code"
                        sub: page.ccHooksErr || (page.ccHooks === null ? "…" : page.ccHooks
                            ? "Installés dans ~/.claude/settings.json (Windows et WSL)"
                            : "Pas installés : sans eux, l'îlot ne sait pas quand Claude travaille")
                        TextBtn {
                            visible: page.ccHooks !== null
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: page.ccHooks ? "delete" : "download"
                            text: page.ccHooks ? "Retirer" : "Installer"
                            onClicked: page.ccHooksSet(!page.ccHooks)
                        }
                    }
                }
        }
    }

    Component {
        id: secUpdates
        Column {
            spacing: 10
                // ------------------------------------------------- demarrage
                Block {
                    SetRow {
                        icon: "rocket_launch"
                        title: "Lancer au démarrage de Windows"
                        sub: "L'îlot s'ouvre automatiquement à l'ouverture de session"
                        toggle: true
                        checked: page.autostart
                        disabled: page.autostartBusy
                        onToggled: on => {
                            page.autostartBusy = true
                            Api.invoke("settings_autostart", { on: on }).then(v => { page.autostart = v }).then(() => { page.autostartBusy = false }, () => { page.autostartBusy = false })
                        }
                    }
                }

                // ----------------------------------------------- mises a jour
                Block {
                    SetRow {
                        icon: "system_update"
                        title: "Îlot " + (Watch.upd.current || "")
                        sub: page.updateText(Watch.upd)
                    }
                    // avancement du telechargement
                    Item {
                        visible: Watch.upd.status === "downloading"
                        width: parent.width
                        height: visible ? 18 : 0
                        Rectangle {
                            x: 54
                            y: 12
                            width: parent.width - 54
                            height: 6
                            radius: 3
                            color: Theme.surfaceHighest
                            Rectangle {
                                width: parent.width * Math.max(0.02, Watch.upd.progress || 0)
                                height: parent.height
                                radius: 3
                                color: Theme.primary
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                    }
                    Flow {
                        x: 54
                        width: parent.width - 54
                        topPadding: 12
                        spacing: 8
                        TextBtn {
                            icon: "refresh"
                            text: "Rechercher"
                            busy: Watch.upd.status === "checking"
                            disabled: ["checking", "downloading", "installing"].indexOf(Watch.upd.status) >= 0
                            onClicked: Api.invoke("update_check").then(u => { Watch.upd = u })
                        }
                        TextBtn {
                            visible: !!Watch.upd.available && ["idle", "error"].indexOf(Watch.upd.status) >= 0
                            primary: true
                            icon: "download"
                            text: "Télécharger " + Watch.upd.latest + (Watch.upd.size ? " (" + Watch.fmtSize(Watch.upd.size) + ")" : "")
                            onClicked: Api.invoke("update_download").then(u => { Watch.upd = u })
                        }
                        TextBtn {
                            visible: Watch.upd.status === "ready" || Watch.upd.status === "installing"
                            primary: true
                            icon: "restart_alt"
                            text: "Installer et redémarrer"
                            busy: Watch.upd.status === "installing"
                            disabled: Watch.upd.status === "installing"
                            onClicked: Watch.installUpdate()
                        }
                        TextBtn {
                            visible: !!Watch.upd.url
                            icon: "open_in_new"
                            text: "Sur GitHub"
                            onClicked: Api.invoke("open_url", { url: Watch.upd.url })
                        }
                    }
                    // notes de la version disponible
                    Column {
                        visible: !!Watch.upd.available && !!Watch.upd.notes
                        x: 54
                        width: parent.width - 54
                        topPadding: 6
                        SubTitle { text: "Nouveautés de la version " + Watch.upd.latest }
                        Txt {
                            topPadding: 6
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            text: Watch.upd.notes || ""
                            px: 12.5
                            onLinkActivated: l => Api.invoke("open_url", { url: l })
                        }
                    }
                    SubTitle { text: "Mises à jour automatiques"; key: "update_mode" }
                    Chips {
                        model: [["auto", "Télécharger et installer"], ["notify", "Prévenir seulement"], ["off", "Ne pas vérifier"]]
                        current: page.cfg.update_mode || "notify"
                        key: "update_mode"
                        onPicked: v => page.set({ update_mode: v })
                    }
                    Txt {
                        topPadding: 8
                        width: parent.width
                        wrapMode: Text.Wrap
                        px: 11.5
                        color: Theme.inkVariant
                        text: page.cfg.update_mode === "auto"
                            ? "Vérifié au démarrage puis toutes les 6 h. La nouvelle version est installée après 10 min sans clavier ni souris (hors jeu), ou au lancement suivant ; l'îlot redémarre tout seul."
                            : page.cfg.update_mode === "off" ? "Le bouton Rechercher vérifie quand tu veux."
                            : "Vérifié au démarrage puis toutes les 6 h ; la pilule te prévient quand une version sort."
                    }
                }

                // ---------------------------------------------- sauvegarde
                Block {
                    SetRow {
                        icon: "settings_backup_restore"
                        title: "Sauvegarde des réglages"
                        sub: "Thème, dossiers, profils, notes, soundboard… (sans les mots de passe)"
                    }
                    Row {
                        topPadding: 10
                        x: 54
                        spacing: 8
                        TextBtn {
                            icon: "download"
                            text: "Exporter"
                            onClicked: Api.invoke("settings_export").then(p => Watch.osd(p ? "download_done" : "error", null, p ? "Réglages exportés dans Téléchargements" : "Export impossible"))
                        }
                        TextBtn {
                            icon: "upload"
                            text: "Importer"
                            onClicked: Api.invoke("settings_import").then(ok => {
                                if (!ok)
                                    return
                                Watch.osd("upload", null, "Réglages restaurés")
                                // relance l'ilot pour tout relire
                                Ilot.later(900, () => Backend.restart())
                            }, e => Watch.osd("error", null, String(e)))
                        }
                    }
                }

                // notes de version de chaque version (CHANGELOG.md)
                Block {
                    SetRow {
                        icon: "new_releases"
                        title: "Notes de version"
                        sub: "Ce qui a changé dans chaque version"
                    }
                    Column {
                        width: parent.width
                        topPadding: 8
                        spacing: 8
                        Repeater {
                            model: page.changelog
                            Rectangle {
                                id: rel
                                required property var modelData
                                required property int index
                                readonly property bool cur: modelData.version === Watch.upd.current
                                // les deux dernieres versions depliees
                                property bool open: index < 2
                                width: parent.width
                                height: relCol.height + 20
                                radius: 16
                                color: cur ? Theme.secondaryContainer : Theme.surfaceHigh
                                Column {
                                    id: relCol
                                    x: 14
                                    y: 10
                                    width: parent.width - 28
                                    spacing: 4
                                    Btn {
                                        width: parent.width
                                        height: 28
                                        radius: 10
                                        color: hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
                                        onClicked: rel.open = !rel.open
                                        Txt {
                                            id: relVer
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: rel.modelData.version
                                            px: 15
                                            weight: Font.DemiBold
                                            color: rel.cur ? Theme.inkSecondaryContainer : Theme.ink
                                        }
                                        Txt {
                                            x: relVer.width + 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (rel.cur ? "Version actuelle" : "") + (rel.cur && rel.modelData.date ? " · " : "") + rel.modelData.date
                                            px: 12
                                            color: rel.cur ? Theme.inkSecondaryContainer : Theme.inkVariant
                                        }
                                        Ms {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "expand_more"
                                            size: 20
                                            rotation: rel.open ? 180 : 0
                                            color: rel.cur ? Theme.inkSecondaryContainer : Theme.inkVariant
                                            Behavior on rotation { NumberAnimation { duration: 250 } }
                                        }
                                    }
                                    Txt {
                                        visible: rel.open
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        textFormat: Text.MarkdownText
                                        text: rel.modelData.notes
                                        px: 12.5
                                        color: rel.cur ? Theme.inkSecondaryContainer : Theme.ink
                                        onLinkActivated: l => Api.invoke("open_url", { url: l })
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }

    // carte de reglages
    component Block: Card {
        default property alias content: inner.data
        width: col.width
        height: inner.height + 28
        Column {
            id: inner
            x: 14
            y: 14
            width: parent.width - 28
        }
    }

    // ligne : icone, titre, explication, interrupteur
    component SetRow: Item {
        id: row
        property string icon: ""
        property string title
        property string sub
        property bool subRow: false
        property bool checked: false
        property bool disabled: false
        // ligne avec interrupteur
        property bool toggle: false
        // reglage concerne : point orange s'il est dans le brouillon, titre
        // dans la liste des modifications
        property string key: ""
        Component.onCompleted: if (key) page.titles[key] = title
        default property alias extra: extraBox.data
        signal toggled(bool on)
        width: parent ? parent.width : 0
        height: Math.max(subRow ? 32 : 40, texts.height) + (subRow ? 12 : 0)
        Rectangle {
            visible: row.icon !== ""
            width: 40
            height: 40
            radius: 14
            y: (row.height - height) / 2
            color: Theme.secondaryContainer
            Ms {
                anchors.centerIn: parent
                name: row.icon
                color: Theme.inkSecondaryContainer
            }
        }
        Column {
            id: texts
            x: row.subRow || row.icon !== "" ? 54 : 0
            y: (row.height - height) / 2 + (row.subRow ? 6 : 0)
            width: row.width - x - (sw.visible ? sw.width + 14 : 0) - (extraBox.visibleChildren.length ? 220 : 0)
            spacing: 2
            Txt {
                width: parent.width
                text: row.title
                px: 14
                weight: Font.Medium
                wrapMode: Text.Wrap
            }
            Txt {
                width: parent.width
                text: row.sub
                px: 12
                color: Theme.inkVariant
                wrapMode: Text.Wrap
            }
        }
        Rectangle {
            visible: row.key !== "" && page.draft[row.key] !== undefined
            x: texts.x - 12
            y: texts.y + 7
            width: 6
            height: 6
            radius: 3
            color: Theme.warn
        }
        M3Switch {
            id: sw
            visible: row.toggle
            anchors.right: parent.right
            y: (row.height - height) / 2 + (row.subRow ? 6 : 0)
            checked: row.checked
            disabled: row.disabled
            onToggled: on => row.toggled(on)
        }
        Item {
            id: extraBox
            anchors.fill: parent
        }
    }

    // Reglages > Son : une sortie (icone, nom, nom Windows, renommer, afficher)
    component OutRow: Item {
        id: orow
        required property var modelData
        readonly property bool on: !modelData.gone && page.outOn(modelData)
        readonly property bool editing: page.outEdit === modelData.id
        readonly property string shownName: Ilot.outLabel(modelData.id, modelData.title)
        // le champ a eu le focus : le perdre valide
        property bool focusSeen: false
        width: parent ? parent.width : 0
        height: 54
        opacity: modelData.gone ? 0.6 : 1
        function startEdit() {
            focusSeen = false
            field.text = shownName
            // l'ilot ne se replie pas pendant la saisie
            Ilot.pinned = true
            Ilot.grabFocus()
            Ilot.overlay = "outname"
            Qt.callLater(() => {
                field.input.forceActiveFocus()
                field.input.selectAll()
                // focus deja la : « focused » ne sera pas emis
                orow.focusSeen = field.input.activeFocus
            })
        }
        onEditingChanged: {
            if (editing)
                return startEdit()
            if (!page.outCancel)
                page.outRename(modelData, field.text)
            // un champ cache garderait le focus (et les touches tapees) ; la
            // page le reprend, Echap remonte encore jusqu'a Main. `focus` et
            // non `activeFocus` : fenetre inactive, il le reprendrait au retour
            if (field.input.focus)
                page.forceActiveFocus()
            // passage a une autre ligne : elle garde l'overlay (Echap annule)
            if (Ilot.overlay === "outname" && page.outEdit === "")
                Ilot.overlay = ""
        }
        Component.onCompleted: if (editing) startEdit()
        Rectangle {
            width: 40
            height: 40
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            color: orow.on ? Theme.secondaryContainer : Theme.surfaceHigh
            Behavior on color { ColorAnimation { duration: 200 } }
            Ms {
                anchors.centerIn: parent
                name: orow.modelData.icon
                color: orow.on ? Theme.inkSecondaryContainer : Theme.outline
            }
        }
        Column {
            visible: !orow.editing
            x: 54
            width: parent.width - x - ctl.width - 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Row {
                width: parent.width
                spacing: 8
                Txt {
                    id: nm
                    width: Math.min(implicitWidth, parent.width - (chip.visible ? chip.width + 8 : 0))
                    text: orow.shownName
                    px: 14
                    weight: Font.Medium
                    elide: Text.ElideRight
                    color: orow.on ? Theme.ink : Theme.inkVariant
                }
                Chip {
                    id: chip
                    anchors.verticalCenter: nm.verticalCenter
                    text: orow.modelData.gone ? "Absente" : !orow.modelData.def ? ""
                        : Ilot.outHidden(orow.modelData.id) ? "Par défaut · reste affichée" : "Par défaut"
                }
            }
            Txt {
                width: parent.width
                text: orow.modelData.gone ? "Débranchée, ou son pilote a changé · " + orow.modelData.name : orow.modelData.name
                px: 12
                color: Theme.inkVariant
                elide: Text.ElideRight
            }
        }
        Field {
            id: field
            visible: orow.editing
            x: 54
            width: parent.width - x - ctl.width - 12
            anchors.verticalCenter: parent.verticalCenter
            focusRing: true
            placeholder: orow.modelData.title
            Component.onCompleted: input.maximumLength = 32
            onFocused: {
                orow.focusSeen = true
                Ilot.pinned = true
                Ilot.grabFocus()
            }
            onAccepted: page.outEdit = ""
            // marges arrondies du champ : un clic y reste dans le champ (sinon
            // le TapHandler de la carte validerait)
            MouseArea {
                z: -1
                anchors.fill: parent
                onPressed: field.input.forceActiveFocus()
            }
        }
        Connections {
            target: field.input
            function onActiveFocusChanged() {
                if (!field.input.activeFocus && orow.editing && orow.focusSeen)
                    page.outEdit = ""
            }
        }
        Row {
            id: ctl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            IconBtn {
                visible: !orow.modelData.gone
                anchors.verticalCenter: parent.verticalCenter
                small: true
                icon: orow.editing ? "check" : "edit"
                tip: orow.editing ? "Valider" : "Renommer"
                onClicked: page.outEdit = orow.editing ? "" : orow.modelData.id
            }
            M3Switch {
                visible: !orow.modelData.gone
                anchors.verticalCenter: parent.verticalCenter
                checked: orow.on
                onToggled: on => page.outSetHidden([orow.modelData.id], !on)
            }
            TextBtn {
                visible: orow.modelData.gone
                anchors.verticalCenter: parent.verticalCenter
                icon: "delete"
                text: "Oublier"
                onClicked: page.outForget(orow.modelData.id)
            }
        }
    }

    component SubTitle: Txt {
        id: st
        // reglage concerne : point orange s'il est dans le brouillon, titre
        // dans la liste des modifications
        property string key: ""
        Component.onCompleted: if (key) page.titles[key] = text
        topPadding: 14
        px: 12
        weight: Font.Medium
        color: Theme.inkVariant
        Rectangle {
            visible: st.key !== "" && page.draft[st.key] !== undefined
            x: st.contentWidth + 6
            y: st.topPadding + (st.height - st.topPadding) / 2 - 3
            width: 6
            height: 6
            radius: 3
            color: Theme.warn
        }
    }
    // pastille de couleur (ou icone : fond d'ecran, pochette)
    component Swatch: Btn {
        id: sw
        property color fill: Theme.surfaceHigh
        property string icon: ""
        property bool on: false
        width: 30
        height: 30
        radius: 15
        color: icon ? (on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh) : fill
        border.width: on ? 3 : 0
        border.color: Theme.ink
        // survol d'une pastille de couleur : voile leger par-dessus la teinte
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: !sw.icon && !sw.on
            color: sw.hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Ms {
            anchors.centerIn: parent
            visible: sw.icon !== ""
            name: sw.icon
            size: 17
            color: sw.on ? Theme.inkSecondaryContainer : Theme.inkVariant
        }
    }
    // heure « HH:MM » (Entree pour valider)
    component TimeField: Field {
        id: tf
        property string value
        signal done(string v)
        width: 70
        height: 30
        radius: 10
        pad: 8
        fontSize: 12.5
        bg: Theme.surfaceHigh
        text: value
        input.inputMask: "99:99;_"
        onFocused: Ilot.pinned = true
        onAccepted: {
            const m = text.match(/^(\d\d):(\d\d)$/)
            if (m && Number(m[1]) < 24 && Number(m[2]) < 60)
                tf.done(text)
            else
                bad = true
        }
        onEdited: bad = false
    }
    // une action et sa combinaison ; clic : enregistrement de la combinaison
    // (raccourci d'application : icone, bouton pour le retirer)
    component KeyRow: Item {
        id: kr
        required property var modelData
        readonly property string action: modelData[0]
        readonly property bool isApp: action.startsWith("app:")
        readonly property string combo: Watch.keyMap[action] || ""
        readonly property bool rec: page.keyRec === action
        readonly property bool bad: Watch.keyBad.indexOf(action) >= 0
        width: parent ? parent.width : 0
        height: isApp ? 40 : 34
        onRecChanged: if (rec) {
            Ilot.pinned = true
            Ilot.grabFocus()
            keyBtn.forceActiveFocus()
        }
        AppIcon {
            visible: kr.isApp
            x: 54 - 34
            anchors.verticalCenter: parent.verticalCenter
            src: kr.modelData[2] || ""
            name: kr.modelData[1]
        }
        Txt {
            x: 54
            width: delBtn.x - x - 10
            anchors.verticalCenter: parent.verticalCenter
            text: kr.modelData[1]
            elide: Text.ElideRight
            color: kr.bad ? Theme.error : Theme.ink
        }
        IconBtn {
            id: delBtn
            x: kr.isApp ? keyBtn.x - width - 6 : keyBtn.x
            visible: kr.isApp
            anchors.verticalCenter: parent.verticalCenter
            small: true
            icon: "close"
            tip: "Retirer ce raccourci"
            onClicked: {
                const map = Object.assign({}, Watch.keyMap)
                delete map[kr.action]
                if (page.keyRec === kr.action)
                    page.keyRec = ""
                Watch.saveKeys(map)
            }
        }
        Btn {
            id: keyBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(90, keyText.implicitWidth + 24)
            height: 28
            radius: 14
            color: kr.rec ? Theme.primary
                : kr.combo ? (hovered ? Theme.mix(Theme.ink, Theme.secondaryContainer, 0.08) : Theme.secondaryContainer)
                : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
            border.width: kr.bad ? 2 : 0
            border.color: Theme.error
            tip: kr.bad ? "Déjà pris par une autre appli : choisis-en un autre" : "Clic puis appuie sur la combinaison · Échap : annuler · Retour arrière : effacer"
            onClicked: page.keyRec = kr.rec ? "" : kr.action
            Keys.onPressed: e => {
                if (!kr.rec)
                    return
                e.accepted = true
                if (e.key === Qt.Key_Escape) {
                    page.keyRec = ""
                    return
                }
                const map = Object.assign({}, Watch.keyMap)
                if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) {
                    // une appli garde sa ligne (croix pour la retirer)
                    if (kr.isApp)
                        map[kr.action] = ""
                    else
                        delete map[kr.action]
                    page.keyRec = ""
                    return Watch.saveKeys(map)
                }
                if ([Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift, Qt.Key_Meta, Qt.Key_AltGr].indexOf(e.key) >= 0)
                    return
                const mods = []
                if (e.modifiers & Qt.ControlModifier) mods.push("Ctrl")
                if (e.modifiers & Qt.AltModifier) mods.push("Alt")
                if (e.modifiers & Qt.ShiftModifier) mods.push("Shift")
                if (e.modifiers & Qt.MetaModifier) mods.push("Super")
                let k
                if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z)
                    k = "Key" + String.fromCharCode(e.key)
                else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9)
                    k = (e.modifiers & Qt.KeypadModifier ? "Numpad" : "Digit") + String.fromCharCode(e.key)
                else if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24)
                    k = "F" + (e.key - Qt.Key_F1 + 1)
                else if (e.nativeVirtualKey)
                    k = "VK" + e.nativeVirtualKey
                else
                    return
                // une touche seule bloquerait la frappe partout dans Windows (sauf F1-F24)
                if (!mods.length && !/^F\d+$/.test(k)) {
                    Watch.osd("keyboard", null, "Ajoute Ctrl, Alt ou Maj")
                    return
                }
                page.setKey(kr.action, mods.concat([k]).join("+"))
            }
            Txt {
                id: keyText
                anchors.centerIn: parent
                text: kr.rec ? "Appuie…" : kr.combo ? page.keyLabel(kr.combo) : "—"
                px: 12
                weight: kr.combo ? Font.Medium : Font.Normal
                color: kr.rec ? Theme.inkPrimary : kr.combo ? Theme.inkSecondaryContainer : Theme.inkVariant
            }
        }
    }

    // Îlot en plein écran : une appli (executable), choisie (croix pour la
    // retirer) ou proposee (plus pour l'ajouter)
    component FsAppRow: Item {
        id: fr
        required property var modelData
        property bool chosen: false
        readonly property var win: page.fsOpen[modelData] || null
        width: parent ? parent.width : 0
        height: 40
        TaskIcon {
            x: 54 - 34
            anchors.verticalCenter: parent.verticalCenter
            size: 26
            key: fr.win ? fr.win.key : ""
            winId: fr.win ? fr.win.id : 0
            title: fr.modelData
        }
        Column {
            x: 54
            width: fsBtn.x - x - 10
            anchors.verticalCenter: parent.verticalCenter
            Txt {
                width: parent.width
                text: fr.modelData.replace(/\.exe$/, "")
                elide: Text.ElideRight
            }
            Txt {
                visible: !!fr.win && !!fr.win.title
                width: parent.width
                text: fr.win ? fr.win.title : ""
                px: 11.5
                color: Theme.inkVariant
                elide: Text.ElideRight
            }
        }
        IconBtn {
            id: fsBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            small: true
            icon: fr.chosen ? "close" : "add"
            tip: fr.chosen ? "Ne plus masquer devant cette appli" : "Masquer l'îlot devant cette appli"
            onClicked: page.fsSet(fr.modelData, !fr.chosen)
        }
    }

    // icone d'application (lettre sur fond colore sans icone)
    component AppIcon: Item {
        property string src
        property string name
        width: 26
        height: 26
        Image {
            anchors.fill: parent
            visible: parent.src !== ""
            source: parent.src
            sourceSize.width: Math.ceil(26 * Screen.devicePixelRatio)
            asynchronous: true
            mipmap: true
        }
        Rectangle {
            anchors.fill: parent
            visible: parent.src === ""
            radius: 8
            color: Theme.tertiaryContainer
            Txt {
                anchors.centerIn: parent
                text: (parent.parent.name || "?").charAt(0).toUpperCase()
                px: 12
                weight: Font.Medium
                color: Theme.inkTertiaryContainer
            }
        }
    }

    // pastilles a choix unique (.chips)
    component Chips: Flow {
        id: chips
        property var model: []
        property var current
        // reglage concerne : libelles des choix pour la liste des modifications
        property string key: ""
        Component.onCompleted: if (key) page.choices[key] = model
        // choix ajoutes ensuite (packs de compagnon)
        onModelChanged: if (key) page.choices[key] = model
        signal picked(var v)
        width: parent ? parent.width : 0
        topPadding: 12
        spacing: 6
        Repeater {
            model: chips.model
            Btn {
                required property var modelData
                readonly property bool on: modelData[0] === chips.current
                width: t.implicitWidth + 24
                height: 30
                radius: 15
                color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                onClicked: chips.picked(modelData[0])
                Txt {
                    id: t
                    anchors.centerIn: parent
                    text: parent.modelData[1]
                    px: 12.5
                    color: parent.on ? Theme.inkSecondaryContainer : Theme.ink
                }
            }
        }
    }
}
