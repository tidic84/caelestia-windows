import QtQuick
import IlotCore

// Reglages, en onglets (a gauche) : general (demarrage, touche Windows,
// ecran, notifications, sauvegarde), barre, apparence (et rotation des
// fonds), pilule, son (sorties affichees), compagnon, jeu et absence, accessibilite, meteo et agenda, raccourcis
// clavier, addons (onglets facultatifs), mises a jour et notes de version
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "settings"
    readonly property var cfg: Ilot.cfg
    // onglet des reglages (Ilot.openSettings l'ouvre de l'exterieur)
    readonly property string section: Ilot.settingsSection
    readonly property var sections: [
        { id: "general", icon: "settings", label: "Général" },
        { id: "bar", icon: "dashboard", label: "Barre" },
        { id: "look", icon: "palette", label: "Apparence" },
        { id: "pill", icon: "pill", label: "Pilule" },
        { id: "sound", icon: "volume_up", label: "Son" },
        { id: "pet", icon: "emoji_emotions", label: "Compagnon" },
        { id: "game", icon: "sports_esports", label: "Jeu et absence" },
        { id: "access", icon: "accessibility_new", label: "Accessibilité" },
        { id: "weather", icon: "partly_cloudy_day", label: "Météo et agenda" },
        { id: "keys", icon: "keyboard", label: "Raccourcis" },
        { id: "addons", icon: "grid_view", label: "Addons" },
        { id: "updates", icon: "system_update", label: "Mises à jour" }
    ]
    onSectionChanged: flick.contentY = 0
    // notes de version (CHANGELOG.md embarque)
    property var changelog: []
    property bool autostart: false
    property bool autostartBusy: false
    property var monitors: []
    property var chosenMonitor: null
    property var winkey: null
    property bool winkeyBusy: false

    onShownChanged: {
        if (shown)
            return load()
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
    }
    Component.onDestruction: Api.unlisten("keyrec", keyrecFn)
    function load() {
        Api.invoke("settings_get").then(s => {
            page.autostart = s.autostart
            page.monitors = s.monitors
            page.chosenMonitor = s.monitor === undefined ? null : s.monitor
            Ilot.cfg = Object.assign({}, Ilot.cfg, s, Ilot.outPatch)
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
    Connections {
        target: Ilot
        function onFocusCity() {
            Ilot.settingsSection = "weather"
            Qt.callLater(() => {
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, cityCard.y - 40))
                Ilot.grabFocus()
                cityField.input.forceActiveFocus()
            })
        }
    }

    // ------------------------------------------------- onglets (a gauche)
    Flickable {
        id: navFlick
        width: 176
        height: parent.height
        contentHeight: nav.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // un seul fond, qui glisse vers l'onglet choisi (comme les onglets du
        // panneau) : les boutons eux-memes restent sans fond
        Rectangle {
            readonly property int i: Math.max(0, page.sections.findIndex(x => x.id === page.section))
            y: i * (36 + nav.spacing)
            width: nav.width
            height: 36
            radius: 18
            color: Theme.secondaryContainer
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        }
        Column {
            id: nav
            width: parent.width
            spacing: 2
            Repeater {
                model: page.sections
                Btn {
                    id: navBtn
                    required property var modelData
                    readonly property bool on: page.section === modelData.id
                    width: nav.width
                    height: 36
                    radius: 18
                    // fond leger au survol, sauf l'actif (le surligneur glissant suffit)
                    color: hovered && !on ? Theme.alpha(Theme.ink, 0.08) : "transparent"
                    readonly property color fg: on ? Theme.inkSecondaryContainer : Theme.ink
                    onClicked: Ilot.settingsSection = modelData.id
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: navBtn.modelData.icon
                        size: 19
                        color: navBtn.on || navBtn.hovered ? navBtn.fg : Theme.inkVariant
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    Txt {
                        x: 42
                        width: parent.width - x - 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: navBtn.modelData.label
                        weight: navBtn.on ? Font.Medium : Font.Normal
                        color: navBtn.fg
                        elide: Text.ElideRight
                    }
                    // pastille : mise a jour disponible
                    Rectangle {
                        visible: navBtn.modelData.id === "updates" && !!Watch.upd.available
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.error
                    }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: navFlick.width + 12
        anchors.rightMargin: 4
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Column {
            id: col
            width: parent.width
            spacing: 10

            // ------------------------------------------------- demarrage
            Block {
                sec: "general"
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

            // ------------------------------------------- touche Windows
            Block {
                sec: "general"
                SetRow {
                    icon: "apps"
                    title: "Touche Windows"
                    sub: "Appuyée seule, elle ouvre les applications de l'îlot au lieu du menu Démarrer (Ctrl+Échap l'ouvre toujours). La touche est remappée : îlot fermé, elle ne fait plus rien"
                    toggle: true
                    checked: !!page.cfg.win_key
                    disabled: page.winkeyBusy
                    onToggled: on => page.winKeyRemap(on)
                }
                Item {
                    readonly property var st: page.winkey
                    readonly property var info: {
                        if (!st)
                            return null
                        if (st.pending)
                            return ["Redémarrez Windows pour terminer (Redémarrer, pas Arrêter).", null]
                        if (page.cfg.win_key && !st.remap)
                            return ["Windows peut encore ouvrir le menu Démarrer : la touche n'est pas remappée.", ["Remapper", true]]
                        if (!page.cfg.win_key && st.remap)
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

            // ------------------------------------------------------ ecran
            Block {
                sec: "general"
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

            // ------------------------------------------------------ barre
            Block {
                sec: "bar"
                SetRow {
                    icon: "dashboard"
                    title: "Barre en haut de l'écran"
                    sub: "Façon Waybar : bureaux, fenêtres ouvertes et état du système autour de l'îlot"
                    toggle: true
                    checked: !!page.cfg.bar
                    onToggled: on => Ilot.setCfg({ bar: on })
                }
                SetRow {
                    subRow: true
                    title: "Masquer la barre des tâches Windows"
                    sub: "Elle revient quand l'îlot est quitté"
                    toggle: true
                    checked: !!page.cfg.hide_taskbar
                    disabled: !page.cfg.bar
                    onToggled: on => Ilot.setCfg({ hide_taskbar: on })
                }
                SetRow {
                    subRow: true
                    title: "Îlots séparés"
                    sub: "Sans fond : chaque groupe flotte comme un petit îlot"
                    toggle: true
                    checked: !!page.cfg.bar_islands
                    disabled: !page.cfg.bar
                    onToggled: on => Ilot.setCfg({ bar_islands: on })
                }
                SetRow {
                    subRow: true
                    title: "Fenêtres ouvertes"
                    sub: "Les applications ouvertes, à côté des bureaux"
                    toggle: true
                    checked: !!page.cfg.bar_tasks
                    disabled: !page.cfg.bar
                    onToggled: on => Ilot.setCfg({ bar_tasks: on })
                }
                SetRow {
                    subRow: true
                    title: "Titre de la fenêtre active"
                    sub: "Le nom de la fenêtre au premier plan, à côté de son icône"
                    toggle: true
                    checked: page.cfg.bar_titles !== false
                    disabled: !page.cfg.bar || !page.cfg.bar_tasks
                    onToggled: on => Ilot.setCfg({ bar_titles: on })
                }
                SetRow {
                    subRow: true
                    title: "Masquer automatiquement"
                    sub: "La barre apparaît quand la souris touche le haut de l'écran"
                    toggle: true
                    checked: !!page.cfg.bar_autohide
                    disabled: !page.cfg.bar
                    onToggled: on => Ilot.setCfg({ bar_autohide: on })
                }
            }

            // ------------------------------------------------- apparence
            Block {
                sec: "look"
                SetRow {
                    icon: "palette"
                    title: "Couleurs"
                    sub: page.cfg.color === "art" ? "Les couleurs suivent la pochette du morceau (sinon le fond d'écran)"
                        : page.cfg.color && page.cfg.color !== "auto" ? "Couleur choisie" : "Les couleurs sont tirées du fond d'écran"
                }
                // themes prets : un clic applique couleur, style, fond, contour et forme
                SubTitle { text: "Thèmes prêts" }
                Flow {
                    width: parent.width
                    topPadding: 8
                    spacing: 6
                    Repeater {
                        model: page.presets
                        Btn {
                            required property var modelData
                            readonly property bool on: Object.keys(modelData[1]).every(k => page.cfg[k] === modelData[1][k])
                            width: prRow.implicitWidth + 22
                            height: 30
                            radius: 15
                            color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                            onClicked: Ilot.setCfg(modelData[1])
                            Row {
                                id: prRow
                                anchors.centerIn: parent
                                spacing: 6
                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: parent.parent.modelData[1].color
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Txt {
                                    text: parent.parent.modelData[0]
                                    px: 12.5
                                    color: parent.parent.on ? Theme.inkSecondaryContainer : Theme.ink
                                }
                            }
                        }
                    }
                }
                SubTitle { text: "Couleur d'accent" }
                Flow {
                    width: parent.width
                    topPadding: 8
                    spacing: 6
                    Swatch {
                        on: (page.cfg.color || "auto") === "auto"
                        icon: "wallpaper"
                        tip: "Automatique (fond d’écran)"
                        onClicked: Ilot.setCfg({ color: "auto" })
                    }
                    Swatch {
                        on: page.cfg.color === "art"
                        icon: "album"
                        tip: "Pochette du morceau en cours (sinon fond d’écran)"
                        onClicked: Ilot.setCfg({ color: "art" })
                    }
                    Repeater {
                        model: page.swatches
                        Swatch {
                            required property var modelData
                            fill: modelData
                            on: page.cfg.color === modelData
                            onClicked: Ilot.setCfg({ color: modelData })
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
                                Ilot.setCfg({ color: v.toLowerCase() })
                            }
                        }
                    }
                }
                // style de la palette : apercu de chaque variante
                SubTitle { text: "Style de la palette" }
                Flow {
                    id: variants
                    width: parent.width
                    topPadding: 12
                    spacing: 8
                    readonly property int cols: Math.max(1, Math.floor((width + 8) / (96 + 8)))
                    readonly property real cw: (width - (cols - 1) * 8) / cols
                    // apercu de chaque variante avec la couleur du fond actuel
                    readonly property var swatches: {
                        if (!page.shown && !swatchCache)
                            return []
                        Ilot.themeSerial
                        const src = Ilot.sourceArgb !== null ? Ilot.sourceArgb : 0xff6750a4
                        return Theme.variants.map(v => Object.assign({ id: v.id, label: v.label }, Theme.swatch(src, v.id, Ilot.dark)))
                    }
                    property var swatchCache: null
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
                            onClicked: Ilot.setCfg({ variant: modelData.id })
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
                SubTitle { text: "Clair ou sombre" }
                Chips {
                    model: [["auto", "Comme Windows"], ["dark", "Sombre"], ["light", "Clair"], ["time", "Selon l’heure"], ["sun", "Lever / coucher du soleil"]]
                    current: page.cfg.mode
                    onPicked: v => Ilot.setCfg({ mode: v })
                }
                Row {
                    visible: page.cfg.mode === "time"
                    topPadding: 8
                    spacing: 8
                    Txt { text: "Clair de"; anchors.verticalCenter: parent.verticalCenter }
                    TimeField { value: page.cfg.day || "07:00"; onDone: v => Ilot.setCfg({ day: v }) }
                    Txt { text: "à"; anchors.verticalCenter: parent.verticalCenter }
                    TimeField { value: page.cfg.night || "20:00"; onDone: v => Ilot.setCfg({ night: v }) }
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
                SetRow {
                    subRow: true
                    title: "Appliquer la couleur d'accent à Windows"
                    sub: "Barre des tâches, menu Démarrer, bordures de fenêtres"
                    toggle: true
                    checked: !!page.cfg.win_accent
                    onToggled: on => {
                        // force la reapplication
                        if (on)
                            Ilot.saveUi({ winAccent: null })
                        Ilot.setCfg({ win_accent: on })
                    }
                }
                SetRow {
                    subRow: true
                    title: "Appliquer le mode clair / sombre à Windows"
                    sub: "Quand le mode n'est pas « Comme Windows »"
                    toggle: true
                    checked: !!page.cfg.win_mode
                    onToggled: on => Ilot.setCfg({ win_mode: on })
                }
            }

            // ilot : fond, contour, forme, animations
            Block {
                sec: "look"
                SetRow {
                    icon: "auto_awesome"
                    title: "Îlot"
                    sub: "Fond, contour, forme et animations de l'îlot et de la barre"
                }
                SubTitle { text: "Fond" }
                Chips {
                    model: [["solid", "Opaque"], ["black", "Noir pur"], ["glass", "Translucide"], ["clear", "Très transparent"], ["wall", "Acrylique"], ["aurora", "Aurore boréale"]]
                    current: page.cfg.island_bg || "solid"
                    onPicked: v => Ilot.setCfg({ island_bg: v })
                }
                SubTitle { text: "Contour" }
                Chips {
                    model: [["none", "Aucun"], ["line", "Liseré"], ["glow", "Lueur"], ["rgb", "Arc-en-ciel"], ["pulse", "Pulsation"]]
                    current: page.cfg.border || "none"
                    onPicked: v => Ilot.setCfg({ border: v })
                }
                SubTitle { text: "Forme" }
                Chips {
                    model: [["round", "Arrondie"], ["pill", "Pilule"], ["square", "Carrée"]]
                    current: page.cfg.shape || "round"
                    onPicked: v => Ilot.setCfg({ shape: v })
                }
                SubTitle { text: "Animations" }
                Chips {
                    model: [["normal", "Normale"], ["fast", "Rapide"], ["soft", "Douce"], ["calm", "Sans rebond"], ["off", "Instantanée"]]
                    current: page.cfg.anim || "normal"
                    onPicked: v => Ilot.setCfg({ anim: v })
                }
            }

            // ------------------------------------------ rotation des fonds
            Block {
                sec: "look"
                SetRow {
                    icon: "autorenew"
                    title: "Changer de fond automatiquement"
                    sub: "Au hasard parmi vos fonds (ou ceux de Wallpaper Engine s'il tourne)"
                }
                Chips {
                    model: [[0, "Jamais"], [15, "15 min"], [30, "30 min"], [60, "1 h"], [180, "3 h"], [1440, "1 jour"]]
                    current: page.cfg.rotate_min
                    onPicked: v => Ilot.setCfg({ rotate_min: v })
                }
            }

            // lecteur : survol de la pilule, onglet Media, carte de l'accueil
            Block {
                sec: "look"
                SetRow {
                    icon: "music_note"
                    title: "Lecteur de musique"
                    sub: "Survol de la pilule, onglet Média et carte de l'accueil"
                }
                SubTitle { text: "Couleur du lecteur" }
                Flow {
                    width: parent.width
                    topPadding: 8
                    spacing: 6
                    Swatch {
                        on: (page.cfg.player_color || "art") === "art"
                        icon: "album"
                        tip: "Pochette du morceau en cours"
                        onClicked: Ilot.setCfg({ player_color: "art" })
                    }
                    Swatch {
                        on: page.cfg.player_color === "theme"
                        icon: "palette"
                        tip: "Couleurs du thème"
                        onClicked: Ilot.setCfg({ player_color: "theme" })
                    }
                    Repeater {
                        model: page.swatches
                        Swatch {
                            required property var modelData
                            fill: modelData
                            on: page.cfg.player_color === modelData
                            onClicked: Ilot.setCfg({ player_color: modelData })
                        }
                    }
                }
            }

            // bouton lecture
            Block {
                sec: "look"
                SetRow {
                    icon: "play_arrow"
                    title: "Bouton lecture"
                }
                SubTitle { text: "Forme du bouton" }
                Chips {
                    model: [["cookie", "Festonné"], ["round", "Rond"], ["none", "Icône seule"]]
                    current: page.cfg.player_btn || "cookie"
                    onPicked: v => Ilot.setCfg({ player_btn: v })
                }
                SubTitle { text: "Couleur du bouton" }
                Chips {
                    id: btnColorChips
                    // "#rrggbb" = couleur fixe ; "fixed" n'est jamais stocke
                    // (player_bigbtn reste lu par PlayBtn en mode auto)
                    readonly property string val: page.cfg.player_btn_color || "auto"
                    property string lastFixed: val.charAt(0) === "#" ? val : ""
                    model: [["auto", "Auto"], ["player", "Couleur du lecteur"], ["white", "Blanc"], ["fixed", "Couleur fixe"]]
                    current: val.charAt(0) === "#" ? "fixed" : val
                    onPicked: v => Ilot.setCfg({ player_btn_color: v !== "fixed" ? v : (lastFixed || page.swatches[0]) })
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
                                Ilot.setCfg({ player_btn_color: modelData });
                            }
                        }
                    }
                }
                SubTitle { text: "Couleur de l'icône" }
                Chips {
                    enabled: page.cfg.player_btn !== "none"
                    opacity: enabled ? 1 : 0.5
                    model: [["auto", "Auto"], ["white", "Blanche"], ["black", "Noire"]]
                    current: page.cfg.player_btn_ink || "auto"
                    onPicked: v => Ilot.setCfg({ player_btn_ink: v })
                }
                SetRow {
                    subRow: true
                    title: "Rotation pendant la lecture"
                    toggle: true
                    checked: page.cfg.player_btn_spin !== false
                    // sans morphose la forme ne tourne pas (PlayBtn)
                    disabled: (page.cfg.player_btn || "cookie") !== "cookie" || page.cfg.player_btn_morph === false
                    onToggled: on => Ilot.setCfg({ player_btn_spin: on })
                }
                SetRow {
                    subRow: true
                    title: "Change de forme entre pause et lecture"
                    toggle: true
                    checked: page.cfg.player_btn_morph !== false
                    disabled: (page.cfg.player_btn || "cookie") !== "cookie"
                    onToggled: on => Ilot.setCfg({ player_btn_morph: on })
                }
                SetRow {
                    subRow: true
                    title: "Petit rebond de l'icône au clic"
                    toggle: true
                    checked: page.cfg.player_btn_pop !== false
                    onToggled: on => Ilot.setCfg({ player_btn_pop: on })
                }
                SetRow {
                    subRow: true
                    title: "Ombre colorée"
                    toggle: true
                    checked: page.cfg.player_btn_glow !== false
                    // la lueur n'existe que sous un bouton blanc (PlayBtn)
                    disabled: page.cfg.player_btn === "none" || btnColorChips.val === "player"
                        || (btnColorChips.val.charAt(0) === "#" && btnColorChips.val.toLowerCase() !== "#ffffff")
                    onToggled: on => Ilot.setCfg({ player_btn_glow: on })
                }
            }

            // barre de progression
            Block {
                sec: "look"
                SetRow {
                    icon: "graphic_eq"
                    title: "Barre de progression"
                }
                SubTitle { text: "Style" }
                Chips {
                    model: [["wave", "Ondulée"], ["flat", "Plate"]]
                    current: page.cfg.player_bar || "wave"
                    onPicked: v => Ilot.setCfg({ player_bar: v })
                }
                SubTitle { text: "Épaisseur" }
                Chips {
                    model: [["thin", "Fine"], ["normal", "Normale"], ["thick", "Épaisse"]]
                    current: page.cfg.player_bar_size || "normal"
                    onPicked: v => Ilot.setCfg({ player_bar_size: v })
                }
                SubTitle { text: "Amplitude de l'onde" }
                Chips {
                    enabled: page.cfg.player_bar !== "flat"
                    opacity: enabled ? 1 : 0.5
                    model: [["low", "Faible"], ["normal", "Normale"], ["high", "Forte"]]
                    current: page.cfg.player_bar_amp || "normal"
                    onPicked: v => Ilot.setCfg({ player_bar_amp: v })
                }
            }

            // pilule repliee et son survol : glisser, molette
            Block {
                sec: "look"
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
                    onToggled: on => Ilot.setCfg({ player_mini_ring: on })
                }
                SetRow {
                    subRow: true
                    title: "Le disque tourne pendant la lecture"
                    toggle: true
                    checked: page.cfg.player_mini_spin !== false
                    onToggled: on => Ilot.setCfg({ player_mini_spin: on })
                }
                SetRow {
                    subRow: true
                    title: "Paroles synchronisées dans la pilule"
                    toggle: true
                    checked: page.cfg.player_mini_lyrics === true
                    onToggled: on => Ilot.setCfg({ player_mini_lyrics: on })
                }
                SetRow {
                    subRow: true
                    title: "Glisser la pochette pour changer de titre"
                    sub: "Au survol de la pilule : vers la gauche, titre suivant ; vers la droite, précédent"
                    toggle: true
                    checked: !!page.cfg.player_swipe
                    onToggled: on => Ilot.setCfg({ player_swipe: on })
                }
                SetRow {
                    subRow: true
                    title: "Molette : volume de l'appli qui joue"
                    sub: "Pendant la musique, la molette sur la pilule règle le volume de Spotify (ou de l'appli qui joue) au lieu du volume général"
                    toggle: true
                    checked: !!page.cfg.player_wheel
                    onToggled: on => Ilot.setCfg({ player_wheel: on })
                }
            }

            // onglet Media : disposition, pochette, fond
            Block {
                sec: "look"
                SetRow {
                    icon: "album"
                    title: "Onglet Média"
                }
                SubTitle { text: "Disposition" }
                Chips {
                    model: [["col", "Colonne (paroles à droite)"], ["side", "Côte à côte (paroles en bas)"]]
                    current: page.cfg.player_layout || "col"
                    onPicked: v => Ilot.setCfg({ player_layout: v })
                }
                SubTitle { text: "Pochette"; topPadding: 18; px: 12.5; color: Theme.primary }
                SubTitle { text: "Forme de la pochette" }
                Chips {
                    model: [["round", "Arrondie"], ["scallop", "Festonnée"], ["disc", "Ronde"]]
                    current: page.cfg.player_art || "scallop"
                    onPicked: v => Ilot.setCfg({ player_art: v })
                }
                SetRow {
                    subRow: true
                    title: "Spectre autour de la pochette"
                    toggle: true
                    // null = suit la pochette (festonnee -> spectre), sinon booleen
                    checked: page.cfg.player_spectrum === null || page.cfg.player_spectrum === undefined
                        ? (page.cfg.player_art || "scallop") === "scallop" : !!page.cfg.player_spectrum
                    onToggled: on => Ilot.setCfg({ player_spectrum: on })
                }
                SubTitle { text: "Fond"; topPadding: 18; px: 12.5; color: Theme.primary }
                SubTitle { text: "Type de fond" }
                Chips {
                    model: [["art", "Pochette floutée"], ["color", "Couleur"], ["gradient", "Dégradé"], ["none", "Aucun"]]
                    current: page.cfg.media_bg || "art"
                    onPicked: v => Ilot.setCfg({ media_bg: v })
                }
                Column {
                    visible: (page.cfg.media_bg || "art") === "art"
                    width: parent.width
                    SubTitle { text: "Flou" }
                    Chips {
                        model: [["low", "Léger"], ["medium", "Moyen"], ["high", "Fort"]]
                        current: page.cfg.media_blur || "medium"
                        onPicked: v => Ilot.setCfg({ media_blur: v })
                    }
                    SetRow {
                        subRow: true
                        title: "Le fond dérive lentement"
                        toggle: true
                        checked: page.cfg.media_drift !== false
                        onToggled: on => Ilot.setCfg({ media_drift: on })
                    }
                    SubTitle { text: "Assombrissement en bas" }
                    Chips {
                        model: [["light", "Léger"], ["normal", "Normal"], ["strong", "Fort"]]
                        current: page.cfg.media_dim || "normal"
                        onPicked: v => Ilot.setCfg({ media_dim: v })
                    }
                }
            }

            // ---------------------------------------------------- pilule
            Block {
                sec: "pill"
                SetRow {
                    icon: "pill"
                    title: "Pilule"
                    sub: "Ce que l'îlot replié affiche"
                }
                SubTitle { text: "Taille de la pilule" }
                Chips {
                    model: [["s", "Petite"], ["m", "Moyenne"], ["l", "Grande"]]
                    current: page.cfg.pill_size || "m"
                    onPicked: v => Ilot.setCfg({ pill_size: v })
                }
                SubTitle { text: "Horloge" }
                Chips {
                    model: [["digital", "Classique"], ["flip", "À volets"], ["analog", "À aiguilles"], ["neon", "Néon"], ["pixel", "Pixel"]]
                    current: page.cfg.clock || "digital"
                    onPicked: v => Ilot.setCfg({ clock: v })
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
                SetRow {
                    subRow: true
                    title: "Activités en cours"
                    sub: "Téléchargements Steam, jeu lancé, charge et température du GPU"
                    toggle: true
                    checked: !!page.cfg.activity
                    onToggled: on => Ilot.setCfg({ activity: on })
                }
                SetRow {
                    subRow: true
                    title: "Raccourcis Discord"
                    sub: "Micro et sourdine dans la pilule quand tu es en vocal"
                    toggle: true
                    checked: !!page.cfg.dc_pill
                    onToggled: on => Ilot.setCfg({ dc_pill: on })
                }
                SetRow {
                    subRow: true
                    title: "Voyant caméra / micro"
                    sub: "Vert : une appli filme ; orange : une appli écoute le micro"
                    toggle: true
                    checked: !!page.cfg.privacy
                    onToggled: on => Ilot.setCfg({ privacy: on })
                }
                SetRow {
                    subRow: true
                    title: "Météo animée"
                    sub: "Pluie, neige, soleil ou étoiles derrière la pilule"
                    toggle: true
                    checked: !!page.cfg.wxfx
                    onToggled: on => Ilot.setCfg({ wxfx: on })
                }
            }

            // ------------------------------------------------------- son
            Block {
                id: soundBlock
                sec: "sound"
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

            // ------------------------------------------------- compagnon
            Block {
                sec: "pet"
                SetRow {
                    icon: "emoji_emotions"
                    title: "Compagnon"
                    sub: "Une petite bête dans la pilule. Survole la pilule pour la caresser ; quand tu t'absentes, elle se promène au-dessus de la barre des tâches."
                }
                SubTitle { text: "Espèce" }
                Chips {
                    model: [["blob", "Blob"], ["cat", "Chat"], ["ghost", "Fantôme"], ["bunny", "Lapin"], ["frog", "Grenouille"], ["penguin", "Pingouin"],
                            ["chick", "Poussin"], ["robot", "Robot"], ["axolotl", "Axolotl"], ["mush", "Champignon"], ["off", "Masqué"]]
                    current: page.cfg.pet || "blob"
                    onPicked: v => Ilot.setCfg({ pet: v })
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
                            x: 40
                            y: stage.height - 34 - 18 * 4.5 + 6
                            sourceComponent: Pet {
                                k: 4.5
                                listen: false
                                interactive: true
                                look: 0
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
                    SubTitle { text: "Nom" }
                    Item { width: 1; height: 8 }
                    Field {
                        id: petName
                        width: Math.min(parent.width, 260)
                        height: 34
                        placeholder: Watch.petNames[Watch.petSpecies] || ""
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
                            onTriggered: if (petName.text.trim() !== (page.cfg.pet_name || "")) Ilot.setCfg({ pet_name: petName.text.trim().slice(0, 24) })
                        }
                    }
                    SubTitle { text: "Couleur" }
                    Flow {
                        width: parent.width
                        topPadding: 8
                        spacing: 6
                        Swatch {
                            on: (page.cfg.pet_color || "nature") === "nature"
                            icon: "eco"
                            tip: "Couleurs naturelles de l'espèce"
                            onClicked: Ilot.setCfg({ pet_color: "nature" })
                        }
                        Swatch {
                            on: page.cfg.pet_color === "theme"
                            icon: "palette"
                            tip: "Couleur du thème"
                            onClicked: Ilot.setCfg({ pet_color: "theme" })
                        }
                        Repeater {
                            model: ["#ff8fb8", "#ff7a59", "#ffd447", "#7cc65b", "#5ec8ff", "#6d8cff", "#b28dff", "#f3f0fa", "#9e9e9e", "#3c4363"]
                            Swatch {
                                required property var modelData
                                fill: modelData
                                on: page.cfg.pet_color === modelData
                                onClicked: Ilot.setCfg({ pet_color: modelData })
                            }
                        }
                    }
                    SubTitle { text: "Yeux" }
                    Chips {
                        model: [["dot", "Points"], ["shine", "Brillants"], ["big", "Grands"], ["lash", "Cils"], ["sleepy", "Endormis"], ["square", "Carrés"]]
                        current: page.cfg.pet_eyes || "dot"
                        onPicked: v => Ilot.setCfg({ pet_eyes: v })
                    }
                    SubTitle { text: "Chapeau" }
                    Chips {
                        model: [["none", "Aucun"], ["party", "Fête"], ["crown", "Couronne"], ["cap", "Casquette"], ["beanie", "Bonnet"], ["top", "Haut-de-forme"],
                                ["wizard", "Sorcier"], ["chef", "Toque"], ["flower", "Fleur"], ["bow", "Nœud"], ["halo", "Auréole"], ["horns", "Cornes"], ["headphones", "Casque audio"]]
                        current: page.cfg.pet_hat || "none"
                        onPicked: v => Ilot.setCfg({ pet_hat: v })
                    }
                    SubTitle { text: "Visage" }
                    Chips {
                        model: [["none", "Rien"], ["glasses", "Lunettes"], ["sun", "Lunettes de soleil"], ["monocle", "Monocle"], ["mask", "Masque"],
                                ["blush", "Joues roses"], ["freckles", "Taches de rousseur"]]
                        current: page.cfg.pet_face || "none"
                        onPicked: v => Ilot.setCfg({ pet_face: v })
                    }
                    SubTitle { text: "Cou" }
                    Chips {
                        model: [["none", "Rien"], ["bowtie", "Nœud papillon"], ["scarf", "Écharpe"], ["bell", "Grelot"], ["bandana", "Bandana"]]
                        current: page.cfg.pet_neck || "none"
                        onPicked: v => Ilot.setCfg({ pet_neck: v })
                    }

                    // promenade
                    Item { width: 1; height: 8 }
                    SetRow {
                        subRow: true
                        title: "Il se promène quand tu ne fais rien"
                        sub: "Au-dessus de la barre des tâches : balade, sieste, ballon, papillon, pêche, skate… selon l'heure, la météo et la musique. Il remonte en te faisant coucou dès que tu reviens."
                        toggle: true
                        checked: !!page.cfg.pet_walk
                        onToggled: on => Ilot.setCfg({ pet_walk: on })
                    }
                    Column {
                        visible: !!page.cfg.pet_walk
                        width: parent.width
                        SubTitle { text: "Au bout de" }
                        Chips {
                            model: [[30, "30 s"], [90, "1 min 30"], [180, "3 min"], [300, "5 min"]]
                            current: Number(page.cfg.pet_afk) || 90
                            onPicked: v => Ilot.setCfg({ pet_afk: v })
                        }
                        SubTitle { text: "Taille en promenade" }
                        Chips {
                            model: [["s", "Petite"], ["m", "Moyenne"], ["l", "Grande"]]
                            current: page.cfg.pet_size || "m"
                            onPicked: v => Ilot.setCfg({ pet_size: v })
                        }
                        SubTitle { text: "Traînée derrière lui" }
                        Chips {
                            model: [["none", "Aucune"], ["sparkle", "Étincelles"], ["hearts", "Cœurs"], ["bubbles", "Bulles"], ["flowers", "Fleurs"],
                                    ["steps", "Empreintes"], ["rainbow", "Arc-en-ciel"]]
                            current: page.cfg.pet_trail || "sparkle"
                            onPicked: v => Ilot.setCfg({ pet_trail: v })
                        }
                    }
                    SubTitle { text: "Voir une scène tout de suite (40 s)" }
                    Chips {
                        model: [["stroll", "Balade"], ["sleep", "Sieste"], ["ball", "Ballon"], ["butterfly", "Papillon"], ["balloon", "Montgolfière"],
                                ["fishing", "Pêche"], ["skate", "Skate"], ["bubbles", "Bulles"], ["read", "Lecture"], ["plane", "Avion en papier"],
                                ["garden", "Jardinage"], ["hide", "Cache-cache"], ["meditate", "Méditation"], ["dance", "Danse"], ["stars", "Étoiles filantes"],
                                ["coffee", "Café"], ["umbrella", "Parapluie"], ["snow", "Bonhomme de neige"], ["special", "Son tour secret"]]
                        current: ""
                        onPicked: v => Watch.petDemo(v)
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

            // -------------------------------------------- mode jeu, absent
            Block {
                sec: "game"
                SetRow {
                    icon: "sports_esports"
                    title: "Mode jeu"
                    sub: "Quand un jeu détecté (Steam, Epic, Ubisoft, GOG) tourne"
                    toggle: true
                    checked: !!page.cfg.game_mode
                    onToggled: on => Ilot.setCfg({ game_mode: on })
                }
                SetRow {
                    subRow: true
                    title: "Passer en mode Performances"
                    sub: "Le mode d'alimentation d'avant revient à la fermeture du jeu"
                    toggle: true
                    disabled: !page.cfg.game_mode
                    checked: !!page.cfg.game_perf
                    onToggled: on => Ilot.setCfg({ game_perf: on })
                }
                SetRow {
                    subRow: true
                    title: "Garder les notifications"
                    sub: "Sinon, l'îlot reste silencieux pendant la partie"
                    toggle: true
                    disabled: !page.cfg.game_mode
                    checked: !!page.cfg.game_notif
                    onToggled: on => Ilot.setCfg({ game_notif: on })
                }
                SetRow {
                    subRow: true
                    title: "Alerte « partie trouvée »"
                    sub: "Son et îlot qui clignote quand tu attends hors du jeu"
                    toggle: true
                    checked: !!page.cfg.match_alert
                    onToggled: on => Ilot.setCfg({ match_alert: on })
                }
                SetRow {
                    subRow: true
                    title: "Valorant"
                    sub: "Partie trouvée et temps restant de la sélection des agents dans l'îlot"
                    toggle: true
                    checked: page.cfg.valorant !== false
                    onToggled: on => Ilot.setCfg({ valorant: on })
                }
                SetRow {
                    icon: "bedtime"
                    title: "Mode absent"
                    sub: "10 min sans clavier ni souris : les notifications attendent ton retour"
                }
                Chips {
                    model: [["on", "Pause musique + récap"], ["recap", "Récap seulement"], ["off", "Désactivé"]]
                    current: page.cfg.away || "on"
                    onPicked: v => Ilot.setCfg({ away: v })
                }
            }

            // ------------------------------------- ilot en plein ecran
            Block {
                sec: "game"
                SetRow {
                    icon: "visibility"
                    title: "Îlot en plein écran"
                    sub: "Quand un jeu ou une vidéo occupe tout l'écran"
                }
                Chips {
                    model: [["normal", "Normal"], ["show", "Toujours affiché"], ["auto", "Masquer auto"], ["custom", "Personnalisé"]]
                    current: page.cfg.fs_hide || "normal"
                    onPicked: v => Ilot.setCfg({ fs_hide: v })
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
                            onAccepted: page.fsAddTyped()
                        }
                        TextBtn {
                            icon: "add"
                            text: "Ajouter"
                            onClicked: page.fsAddTyped()
                        }
                    }
                }
            }

            // --------------------------------------------- accessibilite
            Block {
                sec: "access"
                SetRow {
                    icon: "accessibility_new"
                    title: "Accessibilité"
                    sub: "Texte, contraste, animations et couleurs des voyants"
                }
                SubTitle { text: "Taille du texte du panneau" }
                Chips {
                    model: [[100, "Normale"], [112, "Grande"], [125, "Très grande"]]
                    current: Number(page.cfg.text_size) || 100
                    onPicked: v => Ilot.setCfg({ text_size: v })
                }
                SubTitle { text: "Contraste" }
                Chips {
                    model: [["normal", "Normal"], ["high", "Élevé"]]
                    current: page.cfg.contrast || "normal"
                    onPicked: v => Ilot.setCfg({ contrast: v })
                }
                SubTitle { text: "Mouvements et animations" }
                Chips {
                    model: [["system", "Comme Windows"], ["full", "Toutes"], ["reduced", "Réduites"]]
                    current: page.cfg.motion || "system"
                    onPicked: v => Ilot.setCfg({ motion: v })
                }
                SubTitle { text: "Couleurs des voyants (vert / orange / rouge)" }
                Chips {
                    model: [["off", "Standard"], ["rg", "Daltonien rouge-vert"], ["by", "Daltonien bleu-jaune"]]
                    current: page.cfg.cvd || "off"
                    onPicked: v => Ilot.setCfg({ cvd: v })
                }
            }

            // ------------------------------------------------------ meteo
            Block {
                id: cityCard
                sec: "weather"
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
                    onTriggered: page.searchCity()
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
                sec: "weather"
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

            // ---------------------------------------------- notifications
            Block {
                sec: "general"
                SetRow {
                    icon: "notifications"
                    title: "Notifications dans l'îlot"
                    sub: "Les notifications Windows s'affichent aussi dans la pilule"
                    toggle: true
                    checked: !!page.cfg.notif_popups
                    onToggled: on => Ilot.setCfg({ notif_popups: on })
                }
                SetRow {
                    subRow: true
                    title: "Indicateurs de volume et de luminosité"
                    sub: "La pilule s'agrandit quand le volume ou la luminosité change"
                    toggle: true
                    checked: !!page.cfg.osd
                    onToggled: on => Ilot.setCfg({ osd: on })
                }
            }

            // ----------------------------------------- raccourcis clavier
            Block {
                sec: "keys"
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
                sec: "keys"
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

            // ---------------------------------------------- sauvegarde
            Block {
                sec: "general"
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

            // ---------------------------------------------------- addons
            Block {
                sec: "addons"
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
                sec: "addons"
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
                                    onToggled: v => Ilot.setCfg({ [modelData.key]: v })
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
                    onToggled: on => Ilot.setCfg({ cc_on: on })
                }
                SetRow {
                    subRow: true
                    title: "Son à la fin"
                    sub: "Quand la tâche a duré au moins :"
                    toggle: true
                    disabled: page.cfg.cc_on === false
                    checked: page.cfg.cc_sound !== false
                    onToggled: on => Ilot.setCfg({ cc_sound: on })
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
                    onPicked: v => Ilot.setCfg({ cc_min: v })
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

            // ----------------------------------------------- mises a jour
            Block {
                sec: "updates"
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
                SubTitle { text: "Mises à jour automatiques" }
                Chips {
                    model: [["auto", "Télécharger et installer"], ["notify", "Prévenir seulement"], ["off", "Ne pas vérifier"]]
                    current: page.cfg.update_mode || "notify"
                    onPicked: v => Ilot.setCfg({ update_mode: v })
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
            // notes de version de chaque version (CHANGELOG.md)
            Block {
                sec: "updates"
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
    Scroller { flick: flick }

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
    function searchCity() {
        const q = cityField.text.trim()
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
    readonly property var presets: [
        ["Minuit", { color: "#1e88e5", variant: "neutral", mode: "dark", island_bg: "glass", border: "line", shape: "round" }],
        ["Néon", { color: "#d81b60", variant: "vibrant", mode: "dark", island_bg: "black", border: "rgb", shape: "pill" }],
        ["Forêt", { color: "#43a047", variant: "tonalspot", mode: "dark", island_bg: "solid", border: "none", shape: "round" }],
        ["Coucher de soleil", { color: "#fb8c00", variant: "expressive", mode: "dark", island_bg: "wall", border: "glow", shape: "round" }],
        ["Glace", { color: "#4fc3f7", variant: "tonalspot", mode: "light", island_bg: "clear", border: "line", shape: "pill" }],
        ["Rétro", { color: "#c0ca33", variant: "fruitsalad", mode: "dark", island_bg: "solid", border: "pulse", shape: "square" }],
        ["Monochrome", { color: "#9e9e9e", variant: "monochrome", mode: "dark", island_bg: "black", border: "none", shape: "pill" }]
    ]
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
    function fsAddTyped() {
        let e = fsExeField.text.trim().split(/[\\/]/).pop().toLowerCase()
        if (!e)
            return
        if (!/\.exe$/.test(e))
            e += ".exe"
        fsExeField.text = ""
        fsSet(e, true)
    }
    property bool appPick: false
    readonly property var appMatches: {
        const q = appSearch.text.trim().toLowerCase()
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

    // carte de reglages
    component Block: Card {
        default property alias content: inner.data
        // onglet des reglages ou la carte s'affiche
        property string sec
        visible: sec === page.section
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
            width: row.width - x - (sw.visible ? sw.width + 14 : 0) - (extraBox.children.length ? 220 : 0)
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
        topPadding: 14
        px: 12
        weight: Font.Medium
        color: Theme.inkVariant
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
