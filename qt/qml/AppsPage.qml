import QtQuick
import IlotCore
import "calc.mjs" as Calc
import "emoji.mjs" as Emoji
import "rank.mjs" as Rank

// Apps : recherche (> commandes, = calcul, : emoji, ? web), dossiers,
// Launcher de jeux, tri, menu contextuel, glisser-deposer vers un dossier,
// fichiers deposes depuis l'Explorateur. Les resultats sont classes selon
// les habitudes (rank.mjs) : les applis les plus lancees passent devant.
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "apps"
    readonly property string games: "@games"
    readonly property string filePrefix: "file:"
    property string q: search.text
    property int sel: 0
    property int listSel: 0
    // "apps" | "list" | "emoji"
    property string listMode: "apps"
    property var view: []
    property var listItems: []
    property var mathRow: null
    property bool mathDone: false
    // fichiers deposes : chemin -> { id, file, name, icon, missing, added }
    property var fileCache: ({})
    property int fileRev: 0

    Connections {
        target: Ilot
        function onFocusSearch() {
            Ilot.grabFocus()
            search.input.forceActiveFocus()
        }
        function onAppsChanged() { page.refreshSoon() }
        function onGamesChanged() { page.refreshSoon() }
        function onFoldersChanged() { page.refreshSoon() }
        function onModeChanged() { if (Ilot.mode !== "open") ctx.hide() }
    }
    onShownChanged: if (shown) refresh()
    Component.onCompleted: if (shown) refresh()
    onQChanged: {
        sel = 0
        listSel = 0
        refresh()
    }
    onFileRevChanged: refreshSoon()
    function refreshSoon() {
        Qt.callLater(refresh)
    }

    // ------------------------------------------------------------ outils
    readonly property var sorts: ({
        name: ["sort_by_alpha", "Nom", "Nom (A → Z)"],
        frequent: ["bolt", "Fréquentes", "Les plus utilisées"],
        "name-desc": ["sort_by_alpha", "Nom ↓", "Nom (Z → A)"],
        recent: ["schedule", "Récentes", "Ajout le plus récent"],
        old: ["history", "Anciennes", "Ajout le plus ancien"]
    })
    readonly property var sourceNames: ({ steam: "Steam", epic: "Epic", ubisoft: "Ubisoft", gog: "GOG" })
    readonly property var folderIcons: [
        [/jeu|game|gaming/, "sports_esports"], [/cours|ecole|etude|school|fac|lycee/, "school"],
        [/travail|boulot|work|bureau/, "work"], [/musique|music|audio/, "music_note"],
        [/video|film|stream/, "movie"], [/dev|code|prog/, "code"], [/photo|image|design|dessin/, "palette"],
        [/internet|web|navigat/, "language"], [/social|discu|chat|message/, "forum"],
        [/outil|util|tool|systeme/, "build"], [/app/, "apps"]
    ]
    function folderIcon(name) {
        const f = folderIcons.find(x => x[0].test(Ilot.norm(name)))
        return f ? f[1] : "folder"
    }
    function isHidden(id) {
        return (Ilot.folders.hidden || []).includes(id)
    }
    function isHiddenGame(id) {
        return (Ilot.folders.hiddenGames || []).includes(id)
    }
    function fmtAdded(t) {
        return Ilot.fmt(new Date(t), "d MMMM yyyy")
    }
    function fileItem(id) {
        const path = id.slice(filePrefix.length)
        if (!fileCache[path]) {
            const base = path.split("\\").pop() || path
            fileCache[path] = { id: id, file: path, name: base.replace(/\.(lnk|url|exe)$/i, ""), icon: "", added: (Ilot.folders.added || {})[id] || 0 }
            Api.invoke("file_info", { path: path }).then(info => {
                if (info)
                    Object.assign(page.fileCache[path], info)
                else
                    page.fileCache[path].missing = true
                page.fileRev++
            })
        }
        return fileCache[path]
    }
    function launcherFolder() {
        return {
            id: games, name: "Launcher",
            get apps() { return Ilot.folders.games || [] },
            set apps(v) { Ilot.folders.games = v }
        }
    }
    function findFolder(id) {
        return id === games ? launcherFolder() : Ilot.folders.list.find(f => f.id === id)
    }
    function launcherItems() {
        const extra = (Ilot.folders.games || [])
            .map(id => id.startsWith(filePrefix) ? fileItem(id) : Ilot.apps.find(a => a.id === id))
            .filter(Boolean)
        return Ilot.games.filter(g => !isHiddenGame(g.id)).concat(extra)
    }
    function folderItems(f) {
        return f.apps
            .map(id => id.startsWith(filePrefix) ? fileItem(id) : Ilot.apps.find(a => a.id === id))
            .filter(a => a && (a.file || !isHidden(a.id)))
    }
    function sortItems(list) {
        const late = a => a.added || Number.MAX_SAFE_INTEGER
        const byName = (x, y) => x.name.localeCompare(y.name, "fr")
        const by = {
            name: byName,
            "name-desc": (x, y) => byName(y, x),
            recent: (x, y) => (y.added || 0) - (x.added || 0) || byName(x, y),
            old: (x, y) => late(x) - late(y) || byName(x, y)
        }[Ilot.folders.sort] || byName
        const sorted = list.slice().sort(by)
        return Ilot.folders.sort === "frequent" ? Rank.byHabit(Ilot.usage, sorted, Date.now()) : sorted
    }
    function save() {
        Ilot.saveFolders()
    }

    // --------------------------------------------------------- commandes
    function commands(text) {
        const num = parseInt((text.match(/\d+/) || [])[0], 10)
        const timers = num > 0
            ? [{ icon: "timer", title: "Minuteur " + num + " min", keys: "minuteur timer " + num, run: () => Ilot.startTimer(num) }]
            : [5, 10, 25].map(m => ({ icon: "timer", title: "Minuteur " + m + " min", keys: "minuteur timer " + m, run: () => Ilot.startTimer(m) }))
        const r = Ilot.net.radios
        const list = [
            { icon: "shuffle", title: "Fond d'écran au hasard", keys: "fond ecran aleatoire hasard wallpaper random", run: () => Api.invoke("wall_random") }
        ].concat(
            Theme.variants.map(v => ({ icon: "palette", title: "Variante de couleurs : " + v.label, keys: "variante couleurs theme palette " + v.id + " " + v.label, run: () => Ilot.setCfg({ variant: v.id }), stay: true })),
            [
                { icon: "dark_mode", title: "Mode sombre", keys: "mode sombre dark nuit theme", run: () => Ilot.setCfg({ mode: "dark" }), stay: true },
                { icon: "light_mode", title: "Mode clair", keys: "mode clair light jour theme", run: () => Ilot.setCfg({ mode: "light" }), stay: true },
                { icon: "brightness_auto", title: "Mode automatique (suit Windows)", keys: "mode auto automatique theme windows", run: () => Ilot.setCfg({ mode: "auto" }), stay: true },
                { icon: "coffee", title: Ilot.caffeine ? "Désactiver la caféine" : "Caféine : empêcher la mise en veille", keys: "cafeine caffeine veille sleep reveille", run: () => Ilot.toggleCaffeine() },
                { icon: "do_not_disturb_on", title: Ilot.cfg.dnd ? "Désactiver Ne pas déranger" : "Activer Ne pas déranger", keys: "ne pas deranger dnd silence notifications", run: () => Ilot.toggleDnd() }
            ],
            timers,
            [{ icon: "nest_eco_leaf", title: "Pomodoro (25 / 5 min)", keys: "pomodoro concentration focus travail", run: () => Ilot.startPomodoro() }],
            Ilot.tmr.running ? [{ icon: "timer_off", title: "Arrêter le minuteur", keys: "arreter minuteur stop timer", run: () => Ilot.timerReset() }] : [],
            r.wifi !== null ? [{ icon: "wifi", title: r.wifi ? "Couper le Wi-Fi" : "Activer le Wi-Fi", keys: "wifi wi-fi reseau", run: () => Ilot.toggleRadio("wifi") }] : [],
            r.bluetooth !== null ? [{ icon: "bluetooth", title: r.bluetooth ? "Couper le Bluetooth" : "Activer le Bluetooth", keys: "bluetooth bt", run: () => Ilot.toggleRadio("bluetooth") }] : [],
            [
                { icon: "tune", title: "Contrôles", keys: "controles reglages rapides son melangeur sortie audio", run: () => Ilot.open("ctrl"), stay: true },
                { icon: "settings", title: "Réglages", keys: "reglages parametres settings options", run: () => Ilot.open("settings"), stay: true },
                { icon: "content_paste_off", title: "Vider l'historique du presse-papiers", keys: "vider effacer presse-papiers clipboard", run: () => Api.invoke("clips_clear") },
                { icon: "notifications_off", title: "Effacer les notifications", keys: "effacer notifications", run: () => Api.invoke("notifs_dismiss", { id: null }) },
                { icon: "settings_backup_restore", title: "Oublier les applications fréquentes", keys: "oublier effacer reinitialiser historique habitudes frequentes lancements recherche", danger: true, run: () => Ilot.forgetUsage(), stay: true },
                { icon: "close", title: "Quitter l'îlot", keys: "quitter fermer ilot exit quit", danger: true, run: () => Backend.quit() },
                { icon: "lock", title: "Verrouiller", keys: "verrouiller lock session", run: () => Api.invoke("session_action", { action: "lock" }) },
                { icon: "bedtime", title: "Mettre en veille", keys: "veille sleep suspendre", run: () => Api.invoke("session_action", { action: "sleep" }) },
                { icon: "logout", title: "Se déconnecter", keys: "deconnexion logout session", danger: true, run: () => Api.invoke("session_action", { action: "logout" }) },
                { icon: "restart_alt", title: "Redémarrer", keys: "redemarrer restart reboot", danger: true, run: () => Api.invoke("session_action", { action: "restart" }) },
                { icon: "power_settings_new", title: "Éteindre", keys: "eteindre shutdown arreter", danger: true, run: () => Api.invoke("session_action", { action: "shutdown" }) }
            ])
        const words = Ilot.norm(text.replace(/\d+/g, "")).split(/\s+/).filter(Boolean)
        if (!words.length)
            return list
        return list.filter(c => {
            const hay = Ilot.norm(c.title + " " + c.keys)
            return words.every(w => hay.split(/[\s:()/]+/).some(h => h.startsWith(w)))
        })
    }

    // -------------------------------------------------------- affichage
    function refresh() {
        if (!shown && view.length)
            return
        const t = q.replace(/^\s+/, "")
        const pre = t[0]
        if (pre === ">" || pre === "=" || pre === ":" || pre === "?") {
            const s = t.slice(1).trim()
            if (pre === ":") {
                listMode = "emoji"
                listItems = Emoji.searchEmoji(s).slice(0, 200)
            } else {
                listMode = "list"
                if (pre === ">")
                    listItems = commands(s)
                else if (pre === "=") {
                    const v = s ? Calc.calc(s) : null
                    listItems = v === null
                        ? [{ icon: "calculate", title: s ? "Expression invalide" : "Tapez un calcul", sub: "+ − × ÷ % ^ ( ) sqrt sin cos ln log pi", run: null }]
                        : [{ icon: "calculate", title: Calc.fmtNumber(v), sub: s + " · Entrée pour copier", run: () => Api.invoke("clip_text", { text: String(v) }), big: true }]
                } else {
                    listItems = s
                        ? [{ icon: "travel_explore", title: "Rechercher « " + s + " » sur le web", sub: "Ouvre le navigateur", run: () => Api.invoke("open_url", { url: "https://www.google.com/search?q=" + encodeURIComponent(s) }) }]
                        : [{ icon: "travel_explore", title: "Tapez votre recherche", sub: "", run: null }]
                }
            }
            listSel = Math.min(listSel, Math.max(0, listItems.length - 1))
            return
        }
        listMode = "apps"
        const s = Ilot.norm(t.trim())
        const folder = Ilot.folders.list.find(f => f.id === Ilot.folders.sel)
        const inGames = Ilot.folders.sel === games
        const pool = sortItems(inGames ? launcherItems() : folder ? folderItems(folder) : Ilot.apps.filter(a => !isHidden(a.id)))
        view = !s ? pool : Rank.search(Ilot.usage, pool, s, Ilot.norm, Date.now())
        // un calcul tape directement s'affiche en tete
        mathRow = Calc.looksLikeMath(t.trim()) ? Calc.calc(t.trim()) : null
        mathDone = false
        sel = Math.min(sel, Math.max(0, view.length - 1))
    }
    readonly property bool inGames: Ilot.folders.sel === games

    function launch(a) {
        Ilot.noteLaunch(a.id, q.trim())
        if (a.file)
            Api.invoke("file_open", { path: a.file })
        else if (a.source)
            Api.invoke("game_launch", { id: a.id })
        else
            Api.invoke("app_launch", { id: a.id })
        search.text = ""
        Ilot.setMode("collapsed")
    }
    function runItem(i) {
        const c = listItems[i]
        if (!c || !c.run)
            return
        if (c.danger && !c.armed) {
            const l = listItems.map(x => Object.assign({}, x, { armed: false }))
            l[i].armed = true
            listItems = l
            return
        }
        c.run()
        search.text = ""
        if (!c.stay)
            Ilot.setMode("collapsed")
        else
            refresh()
    }
    function pickEmoji(e) {
        Api.invoke("clip_text", { text: e })
        Ilot.later(250, () => {
            search.text = ""
            Ilot.setMode("collapsed")
        })
    }

    // ---------------------------------------------------------- recherche
    Rectangle {
        id: searchBox
        width: parent.width
        height: 44
        radius: 22
        color: Theme.surfaceHigh
        Ms {
            id: searchIcon
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            readonly property string pre: page.q.replace(/^\s+/, "")[0] || ""
            name: ({ ">": "terminal", "=": "calculate", ":": "mood", "?": "travel_explore" })[pre] || "search"
            color: Theme.inkVariant
        }
        Field {
            id: search
            x: 16 + 20 + 4
            width: parent.width - x - sortBtn.width - 8
            height: parent.height
            bg: "transparent"
            pad: 6
            fontSize: 14
            placeholder: "Rechercher…   > commandes   = calcul   : emoji   ? web"
            onKeyPressed: e => page.keyNav(e)
        }
        // tri des applis
        Btn {
            id: sortBtn
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: sortRow.implicitWidth + 21
            height: 30
            radius: 15
            color: hovered ? Theme.secondaryContainer : Theme.surfaceHighest
            tip: "Trier les applications"
            readonly property var cur: page.sorts[Ilot.folders.sort] || page.sorts.name
            readonly property color fg: hovered ? Theme.inkSecondaryContainer : Theme.inkVariant
            onClicked: m => {
                const p = mapToItem(page, m.x, m.y)
                const cur = Ilot.folders.sort || "name"
                page.showCtx(p.x, p.y, [{ type: "title", label: "Trier par" }].concat(Object.keys(page.sorts).map(k => ({
                    icon: cur === k ? "check" : page.sorts[k][0], label: page.sorts[k][2], on: cur === k,
                    run: () => {
                        Ilot.folders.sort = k
                        page.save()
                        ctx.hide()
                    }
                }))))
            }
            Row {
                id: sortRow
                x: 9
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Ms {
                    name: sortBtn.cur[0]
                    size: 17
                    color: sortBtn.fg
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: sortBtn.cur[1]
                    px: 12
                    color: sortBtn.fg
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // flèches, Entree : selection dans la grille ou la liste
    function keyNav(e) {
        if (listMode === "list" || listMode === "emoji") {
            const cols = listMode === "emoji" ? 12 : 1
            const moves = listMode === "emoji"
                ? { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: cols, [Qt.Key_Up]: -cols }
                : { [Qt.Key_Down]: 1, [Qt.Key_Up]: -1 }
            if (moves[e.key] !== undefined) {
                listSel = Math.max(0, Math.min(listItems.length - 1, listSel + moves[e.key]))
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                e.accepted = true
                if (listMode === "emoji") {
                    if (listItems[listSel])
                        pickEmoji(listItems[listSel].e)
                } else {
                    runItem(listSel)
                }
            }
            return
        }
        const cols = grid.cols
        const moves = { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: cols, [Qt.Key_Up]: -cols }
        if (moves[e.key] !== undefined) {
            sel = Math.max(0, Math.min(view.length - 1, sel + moves[e.key]))
            grid.positionViewAtIndex(sel, GridView.Contain)
            e.accepted = true
        } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier) && mathRow !== null) {
            Api.invoke("clip_text", { text: String(mathRow) })
            mathDone = true
            e.accepted = true
        } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && view[sel]) {
            launch(view[sel])
            e.accepted = true
        }
    }

    // ------------------------------------------------------------ dossiers
    Flickable {
        id: folderBar
        visible: page.listMode === "apps"
        y: searchBox.height + 10
        width: parent.width
        height: 32
        contentWidth: chips.width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Row {
            id: chips
            height: parent.height
            spacing: 6
            FolderChip {
                fid: ""
                icon: "grid_view"
                name: "Toutes"
                onRightClicked: m => page.hiddenMenu(mapToItem(page, m.x, m.y))
            }
            FolderChip {
                fid: page.games
                icon: "stadia_controller"
                name: "Launcher"
                gamesChip: true
                count: (Ilot.games, Ilot.folders, page.fileRev, page.launcherItems().length) || -1
                onRightClicked: m => page.hiddenGamesMenu(mapToItem(page, m.x, m.y))
            }
            Repeater {
                model: Ilot.folders.list
                FolderChip {
                    required property var modelData
                    fid: modelData.id
                    icon: page.folderIcon(modelData.name)
                    name: modelData.name
                    count: modelData.apps.filter(id => id.startsWith(page.filePrefix) || (Ilot.apps.some(a => a.id === id) && !page.isHidden(id))).length
                    onRightClicked: m => page.folderMenu(modelData, mapToItem(page, m.x, m.y))
                }
            }
            FolderChip {
                fid: "@add"
                icon: "create_new_folder"
                name: ""
                tip: "Nouveau dossier"
                onClicked: m => {
                    const p = mapToItem(page, m.x, m.y)
                    page.askName(p, "Nouveau dossier", "", name => {
                        const f = Ilot.newFolder(name)
                        Ilot.folders.sel = f.id
                        page.save()
                    })
                }
            }
        }
    }
    // dossier sous un point de la page (glisser-deposer)
    function chipAt(px, py) {
        const p = chips.mapFromItem(page, px, py)
        const c = chips.childAt(p.x, p.y)
        return c && c.fid !== undefined && c.fid !== "" && c.fid !== "@add" && findFolder(c.fid) ? c : null
    }
    property Item dropChip: null

    // -------------------------------------------------------------- grille
    Item {
        id: gridArea
        y: folderBar.visible ? folderBar.y + folderBar.height + 8 : searchBox.height + 10
        width: parent.width
        height: parent.height - y

        // calcul tape directement
        Btn {
            id: calcRow
            visible: page.listMode === "apps" && page.mathRow !== null && !page.inGames
            width: parent.width - 4
            height: visible ? 50 : 0
            radius: 18
            color: Theme.primaryContainer
            onClicked: {
                Api.invoke("clip_text", { text: String(page.mathRow) })
                page.mathDone = true
            }
            Row {
                x: 16
                spacing: 12
                anchors.verticalCenter: parent.verticalCenter
                Ms {
                    name: "calculate"
                    color: Theme.inkPrimaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: page.mathRow !== null ? "= " + Calc.fmtNumber(page.mathRow) : ""
                    px: 18
                    weight: Font.Medium
                    color: Theme.inkPrimaryContainer
                    width: calcRow.width - 16 - 20 - 24 - hint.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    id: hint
                    text: "Ctrl+Entrée pour copier" + (page.mathDone ? " · copié" : "")
                    px: 11.5
                    opacity: 0.75
                    color: Theme.inkPrimaryContainer
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        GridView {
            id: grid
            visible: page.listMode === "apps"
            y: calcRow.visible ? calcRow.height + 4 : 0
            // la derniere colonne a aussi sa gouttiere (hors de la vue)
            width: parent.width - 4 + gap
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // colonnes : 7 (6 jaquettes) ; panneau agrandi : autant qu'il en tient
            readonly property real gap: page.inGames ? 10 : 4
            readonly property real minW: page.inGames ? 150 : 100
            readonly property int cols: Ilot.big ? Math.max(1, Math.floor(width / (minW + gap))) : (page.inGames ? 6 : 7)
            readonly property real rowH: page.inGames ? (Ilot.big ? 225 : 168) : 92
            cellWidth: width / cols
            cellHeight: rowH + gap
            model: page.view
            delegate: page.inGames ? gameDelegate : appDelegate
            Empty {
                visible: page.listMode === "apps" && page.view.length === 0
                width: grid.width - grid.gap
                y: 0
                readonly property var folder: Ilot.folders.list.find(f => f.id === Ilot.folders.sel)
                text: page.inGames
                    ? (page.q.trim() ? "Aucun jeu" : "Aucun jeu trouvé (Steam, Epic Games, Ubisoft Connect, GOG).")
                    : !Ilot.apps.length ? "Chargement des applications…"
                    : folder && !page.q.trim() ? "Dossier vide : glisse une appli sur le dossier, dépose un fichier ici, ou clic droit sur une application."
                    : "Aucune application"
            }
        }
        Scroller { flick: grid; visible: grid.visible && grid.contentHeight > grid.height + 1 }

        // commandes, calcul, recherche web, emoji
        GridView {
            id: list
            visible: page.listMode !== "apps"
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property bool emoji: page.listMode === "emoji"
            cellWidth: emoji ? (width - 4) / 12 : width - 4
            cellHeight: emoji ? 54 : 54
            model: page.listItems
            currentIndex: page.listSel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
            delegate: emoji ? emojiDelegate : cmdDelegate
            Empty {
                visible: list.count === 0
                width: list.width
                text: list.emoji ? "Aucun emoji" : "Aucune commande"
            }
        }
        Scroller { flick: list; visible: list.visible && list.contentHeight > list.height + 1 }

        // fichiers deposes depuis l'Explorateur
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            visible: drop.containsDrag
        }
        DropArea {
            id: drop
            anchors.fill: parent
            anchors.topMargin: -(gridArea.y - folderBar.y)
            onEntered: d => {
                // la Corbeille, Ce PC... n'apportent pas de chemin, mais des
                // donnees du Shell : on les accepte pour proposer l'emplacement
                if (!d.hasUrls && !d.formats.some(f => /Shell IDList/i.test(f)))
                    d.accepted = false
                else if (d.hasUrls)
                    Ilot.dragIn()
            }
            onPositionChanged: d => {
                const p = mapToItem(page, d.x, d.y)
                page.dropChip = page.chipAt(p.x, p.y)
            }
            onExited: {
                page.dropChip = null
                // l'ilot ouvert par le glisser se referme si on ressort (pas
                // si l'on passe sur le bouton Quick Share)
                Ilot.dragLeft()
            }
            onDropped: d => {
                Ilot.dragDone()
                const chip = page.dropChip
                page.dropChip = null
                const paths = d.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\/\//, "")).replace(/\//g, "\\"))
                if (!paths.length) {
                    // Corbeille, Ce PC... : Windows ne donne pas de chemin, on propose l'emplacement
                    const q = mapToItem(page, d.x, d.y)
                    const into = page.findFolder(chip ? chip.fid : "") || page.launcherFolder()
                    return page.showCtx(q.x, q.y, [{ type: "title", label: "Ajouter un emplacement" }].concat(page.specials.map(x => ({
                        icon: x[1], label: x[2], run: () => { ctx.hide(); page.addFiles(into, [x[0]]) }
                    }))))
                }
                d.acceptProposedAction()
                // lache sur un dossier : range directement
                const target = chip ? page.findFolder(chip.fid) : null
                if (target)
                    return page.addFiles(target, paths)
                // ailleurs : actions sur le fichier (conversion, zip, Discord,
                // telephone) ou dossier ou le ranger
                const p = mapToItem(page, d.x, d.y)
                const what = paths.length > 1 ? paths.length + " éléments" : paths[0].split("\\").pop()
                const sel = page.findFolder(Ilot.folders.sel)
                page.showCtx(p.x, p.y, [{ type: "title", label: what }].concat(page.fileActions(paths, p), [
                    { type: "sep" },
                    { type: "title", label: "Ranger dans…" }
                ], sel ? [{ icon: "check", label: sel.name, run: () => { ctx.hide(); page.addFiles(sel, paths) } }] : [], [
                    { icon: "stadia_controller", label: "Launcher de jeux", run: () => { ctx.hide(); page.addFiles(page.launcherFolder(), paths) } }
                ], Ilot.folders.list.filter(f => f !== sel).map(f => ({ icon: page.folderIcon(f.name), label: f.name, run: () => { ctx.hide(); page.addFiles(f, paths) } })),
                    [{ icon: "create_new_folder", label: "Nouveau dossier…", run: () => page.askName(p, "Nouveau dossier", "", name => page.addFiles(Ilot.newFolder(name), paths)) }]))
            }
        }
    }
    // --- actions sur les fichiers deposes (src/files.rs) : le resultat est cree
    // a cote du fichier d'origine, puis propose (afficher, ouvrir, Discord)
    readonly property var specials: [
        ["shell:RecycleBinFolder", "delete", "Corbeille"], ["shell:MyComputerFolder", "computer", "Ce PC"],
        ["shell:Downloads", "download", "Téléchargements"], ["shell:ControlPanelFolder", "tune", "Panneau de configuration"],
        ["shell:NetworkPlacesFolder", "lan", "Réseau"]
    ]
    function fileActions(paths, p) {
        const run = (label, job) => {
            page.showCtx(p.x, p.y, [{ type: "title", label: "En cours…" }])
            job().then(outs => page.doneCtx(p, label, outs), e => page.doneCtx(p, "Échec : " + e, []))
        }
        const imgs = paths.filter(f => /\.(png|jpe?g|webp|bmp|gif)$/i.test(f))
        const out = []
        if (imgs.length) {
            const toPng = imgs.every(f => /\.jpe?g$/i.test(f))
            out.push({ icon: "image", label: toPng ? "Convertir en PNG" : "Convertir en JPG", run: () => run("Converti",
                () => Promise.all(imgs.map(f => Api.invoke("img_convert", { path: f, to: toPng ? "png" : "jpg" })))) })
            out.push({ icon: "photo_size_select_large", label: "Réduire la taille (1920 px)", run: () => run("Réduit",
                () => Promise.all(imgs.map(f => Api.invoke("img_shrink", { path: f })))) })
        }
        out.push({ icon: "folder_zip", label: "Compresser (.zip)", run: () => run("Compressé", () => Api.invoke("zip_files", { paths: paths }).then(z => [z])) })
        out.push({ icon: "send", label: "Envoyer sur Discord", run: () => page.sendToDiscord(paths, p) })
        out.push({ icon: "nearby", label: "Envoyer avec Quick Share", run: () => { ctx.hide(); Watch.openShare(paths) } })
        return out
    }
    function doneCtx(p, label, outs) {
        outs = (outs || []).filter(Boolean)
        const name = f => f.split("\\").pop()
        if (!outs.length)
            return page.showCtx(p.x, p.y, [{ type: "title", label: label }, { icon: "close", label: "Fermer", run: () => ctx.hide() }])
        page.showCtx(p.x, p.y, [
            { type: "title", label: label + " : " + (outs.length > 1 ? outs.length + " fichiers" : name(outs[0])) },
            { icon: "folder_open", label: "Afficher dans l’Explorateur", run: () => { ctx.hide(); Api.invoke("file_reveal", { path: outs[0] }) } }
        ].concat(outs.length === 1 ? [{ icon: "open_in_new", label: "Ouvrir", run: () => { ctx.hide(); Api.invoke("file_open", { path: outs[0] }) } }] : [],
            [{ icon: "send", label: "Envoyer sur Discord", run: () => page.sendToDiscord(outs, p) }]))
    }
    // Discord n'a pas d'API d'envoi : les fichiers sont copies (comme dans
    // l'Explorateur), puis Discord passe au premier plan : il reste a coller
    function sendToDiscord(paths, p) {
        Api.invoke("files_copy", { paths: paths }).then(ok => {
            if (ok)
                Api.invoke("open_url", { url: "discord://-/channels/@me" })
            page.showCtx(p.x, p.y, [{ type: "title", label: ok ? "Copié ! Dans Discord : Ctrl+V" : "Copie impossible (presse-papiers occupé)" }]
                .concat(ok ? [{ icon: "check", label: "OK", run: () => ctx.hide() }] : []))
        })
    }

    function addFiles(f, paths) {
        Ilot.folders.added = Ilot.folders.added || {}
        const list = f.apps.slice()
        paths.forEach(p => {
            if (list.includes(filePrefix + p))
                return
            list.push(filePrefix + p)
            Ilot.folders.added[filePrefix + p] = Date.now()
            if (fileCache[p])
                fileCache[p].added = Ilot.folders.added[filePrefix + p]
        })
        f.apps = list
        Ilot.folders.sel = f.id
        save()
    }

    // ------------------------------------------- glisser une appli sur un dossier
    property var drag: null
    property bool dragJustEnded: false
    Rectangle {
        id: ghost
        visible: !!page.drag && page.drag.moving
        z: 99
        width: 40
        height: 40
        radius: 12
        color: Theme.surfaceHigh
        Image {
            anchors.fill: parent
            visible: !!(page.drag && page.drag.a.icon)
            source: page.drag && page.drag.a.icon ? page.drag.a.icon : ""
            sourceSize.width: 80
            mipmap: true
        }
        Ms {
            anchors.centerIn: parent
            visible: !(page.drag && page.drag.a.icon)
            name: "draft"
        }
    }
    function dragMove(a, x, y) {
        if (!drag || drag.a !== a)
            drag = { a: a, x: x, y: y, moving: false }
        if (!drag.moving) {
            if (Math.hypot(x - drag.x, y - drag.y) < 6)
                return
            drag = Object.assign({}, drag, { moving: true })
            ctx.hide()
        }
        ghost.x = x - 20
        ghost.y = y - 20
        dropChip = chipAt(x, y)
    }
    function dragEnd(x, y) {
        const d = drag
        drag = null
        dropChip = null
        if (!d || !d.moving)
            return false
        const chip = chipAt(x, y)
        const f = chip && findFolder(chip.fid)
        if (f && !f.apps.includes(d.a.id)) {
            f.apps = f.apps.concat([d.a.id])
            save()
        }
        return true
    }

    Component {
        id: appDelegate
        Btn {
            id: app
            required property var modelData
            required property int index
            readonly property bool selected: page.q.trim() !== "" && index === page.sel
            readonly property bool dragging: !!page.drag && page.drag.moving && page.drag.a === modelData
            width: grid.cellWidth - grid.gap
            height: grid.rowH
            radius: 18
            color: selected ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
            opacity: dragging ? 0.35 : modelData.missing ? 0.45 : 1
            scale: pressed && !dragging ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            tip: (modelData.file ? modelData.file : modelData.name) + (modelData.added ? "\nAjoutée le " + page.fmtAdded(modelData.added) : "")
            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 8
                Item {
                    width: 40
                    height: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    Image {
                        anchors.fill: parent
                        visible: !!app.modelData.icon
                        source: app.modelData.icon || ""
                        sourceSize.width: Math.ceil(40 * Screen.devicePixelRatio)
                        asynchronous: true
                        mipmap: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: !app.modelData.icon
                        radius: 12
                        color: Theme.tertiaryContainer
                        Txt {
                            anchors.centerIn: parent
                            text: app.modelData.name[0] || "?"
                            px: 17
                            weight: Font.DemiBold
                            color: Theme.inkTertiaryContainer
                        }
                    }
                }
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: app.modelData.name
                    px: 11.5
                    elide: Text.ElideRight
                    color: app.selected ? Theme.inkSecondaryContainer : Theme.ink
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: false
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                property bool moved: false
                onPressed: m => {
                    moved = false
                    if (m.button === Qt.LeftButton) {
                        const p = mapToItem(page, m.x, m.y)
                        page.drag = { a: app.modelData, x: p.x, y: p.y, moving: false }
                    }
                }
                onPositionChanged: m => {
                    if (!pressed || !page.drag)
                        return
                    const p = mapToItem(page, m.x, m.y)
                    page.dragMove(app.modelData, p.x, p.y)
                }
                onReleased: m => {
                    const p = mapToItem(page, m.x, m.y)
                    moved = page.dragEnd(p.x, p.y)
                }
                onClicked: m => {
                    if (moved)
                        return
                    if (m.button === Qt.RightButton) {
                        const p = mapToItem(page, m.x, m.y)
                        page.appMenu(app.modelData, p)
                    } else {
                        page.launch(app.modelData)
                    }
                }
            }
        }
    }

    Component {
        id: gameDelegate
        Btn {
            id: game
            required property var modelData
            required property int index
            readonly property bool selected: page.q.trim() !== "" && index === page.sel
            readonly property bool cover: !!modelData.cover
            width: grid.cellWidth - grid.gap
            height: grid.rowH
            radius: hovered ? 22 : 16
            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            color: Theme.surfaceHigh
            border.width: selected ? 3 : 0
            border.color: Theme.primary
            transform: Translate {
                y: game.hovered && !game.pressed ? -2 : 0
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            }
            scale: pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            tip: modelData.name + (modelData.added ? "\nInstallé le " + page.fmtAdded(modelData.added) : "")
            onClicked: page.launch(modelData)
            onRightClicked: m => page.gameMenu(modelData, mapToItem(page, m.x, m.y))

            // sans jaquette : degrade et icone
            Rectangle {
                anchors.fill: parent
                visible: !game.cover
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Theme.secondaryContainer }
                    GradientStop { position: 1; color: Theme.surfaceHigh }
                }
            }
            Item {
                visible: !game.cover
                width: 56
                height: 56
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -17
                Image {
                    anchors.fill: parent
                    visible: !!game.modelData.icon
                    source: game.modelData.icon || ""
                    sourceSize.width: Math.ceil(56 * Screen.devicePixelRatio)
                    asynchronous: true
                    mipmap: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !game.modelData.icon
                    radius: 16
                    color: Theme.tertiaryContainer
                    Txt {
                        anchors.centerIn: parent
                        text: game.modelData.name[0] || "?"
                        px: 24
                        weight: Font.DemiBold
                        color: Theme.inkTertiaryContainer
                    }
                }
            }
            RoundImage {
                anchors.fill: parent
                visible: game.cover
                radius: parent.radius
                source: game.modelData.cover || ""
            }
            // legende : nom et boutique
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: cap.height + 29
                bottomLeftRadius: parent.radius
                bottomRightRadius: parent.radius
                gradient: game.cover ? capGradient : null
                color: "transparent"
                Gradient {
                    id: capGradient
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
                }
                Column {
                    id: cap
                    x: 8
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 7
                    width: parent.width - 16
                    spacing: 3
                    Txt {
                        width: parent.width
                        text: game.modelData.name
                        px: 11.5
                        weight: Font.Medium
                        elide: Text.ElideRight
                        color: game.cover ? "#ffffff" : Theme.ink
                    }
                    Txt {
                        text: page.sourceNames[game.modelData.source] || ""
                        px: 9.5
                        opacity: 0.75
                        color: game.cover ? "#ffffff" : Theme.ink
                    }
                }
            }
            // mise a jour Steam en cours : progression posee sur la jaquette
            Rectangle {
                id: dlBox
                readonly property var d: (Watch.gaming.downloads || []).find(x => "steam:" + x.appid === game.modelData.id) || null
                visible: !!d
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(0, 0, 0, 0.55)
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 4
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Ms {
                            name: !dlBox.d ? "" : !dlBox.d.active ? "pause" : dlBox.d.phase === "install" ? "install_desktop" : "download"
                            size: 18
                            color: "#ffffff"
                        }
                        Txt {
                            text: dlBox.d ? Math.floor(Watch.dlPct(dlBox.d)) + " %" : ""
                            px: 15
                            weight: Font.DemiBold
                            color: "#ffffff"
                        }
                    }
                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        px: 10
                        color: "#ffffff"
                        opacity: 0.85
                        text: !dlBox.d ? "" : !dlBox.d.active ? "En pause" : dlBox.d.phase === "install" ? "Installation"
                            : ["Téléchargement", dlBox.d.speed && Watch.fmtSpeed(dlBox.d.speed), Watch.fmtEta(dlBox.d)].filter(Boolean).join(" · ")
                    }
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.25)
                        Rectangle {
                            width: parent.width * (dlBox.d ? Watch.dlPct(dlBox.d) / 100 : 0)
                            height: parent.height
                            radius: 2
                            color: dlBox.d && dlBox.d.active ? Theme.primary : "#cccccc"
                            Behavior on width { NumberAnimation { duration: 900 } }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cmdDelegate
        Btn {
            id: cmd
            required property var modelData
            required property int index
            readonly property bool selected: index === page.listSel
            readonly property bool armed: !!modelData.armed
            width: list.cellWidth
            height: modelData.big ? 64 : 52
            radius: 16
            color: armed ? Theme.error : selected ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
            opacity: modelData.run ? 1 : 0.7
            cursor: modelData.run ? Qt.PointingHandCursor : Qt.ArrowCursor
            readonly property color fg: armed ? Theme.inkError : selected ? Theme.inkSecondaryContainer : Theme.ink
            onClicked: page.runItem(index)
            Row {
                x: 14
                spacing: 14
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 34
                    height: 34
                    radius: 11
                    color: cmd.selected && !cmd.armed ? Theme.primary : Theme.surfaceHigh
                    anchors.verticalCenter: parent.verticalCenter
                    Ms {
                        anchors.centerIn: parent
                        name: cmd.modelData.icon
                        size: 19
                        color: cmd.selected && !cmd.armed ? Theme.inkPrimary : Theme.inkVariant
                    }
                }
                Column {
                    spacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                    Txt {
                        text: cmd.modelData.title
                        px: cmd.modelData.big ? 26 : 13
                        weight: Font.Medium
                        color: cmd.fg
                    }
                    Txt {
                        visible: text !== ""
                        text: cmd.armed ? "Encore une fois pour confirmer" : (cmd.modelData.sub || "")
                        px: 11.5
                        color: cmd.armed ? Theme.inkError : Theme.inkVariant
                    }
                }
            }
        }
    }

    Component {
        id: emojiDelegate
        Btn {
            id: emo
            required property var modelData
            required property int index
            readonly property bool selected: index === page.listSel
            property bool done: false
            width: list.cellWidth - 2
            height: 52
            radius: 14
            color: selected ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
            tip: modelData.words.split(" ").slice(0, 3).join(" ")
            scale: done ? 1.3 : 1
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            onClicked: {
                done = true
                page.pickEmoji(modelData.e)
            }
            Text {
                anchors.centerIn: parent
                text: emo.modelData.e
                font.family: "Segoe UI Emoji"
                font.pointSize: 26 * 0.75
            }
        }
    }

    // ---------------------------------------------------- menus contextuels
    CtxMenu {
        id: ctx
        area: page
    }
    // clic hors du menu : il se ferme
    MouseArea {
        anchors.fill: parent
        visible: ctx.visible
        z: 9
        acceptedButtons: Qt.AllButtons
        onPressed: m => {
            ctx.hide()
            m.accepted = false
        }
    }
    Keys.onEscapePressed: e => {
        if (ctx.visible) {
            ctx.hide()
            e.accepted = true
        } else {
            e.accepted = false
        }
    }
    property point lastCtx: Qt.point(0, 0)
    function showCtx(x, y, entries) {
        lastCtx = Qt.point(x, y)
        ctx.show(x, y, entries)
    }
    function askName(p, title, value, done) {
        showCtx(p.x, p.y, [{ type: "title", label: title }, { type: "input", value: value, done: done }])
    }
    // ouvre l'Explorateur puis replie l'ilot ; sinon le signale dans le menu
    function openFolder(call) {
        call().then(ok => {
            if (ok) {
                ctx.hide()
                Ilot.setMode("collapsed")
                return
            }
            page.showCtx(page.lastCtx.x, page.lastCtx.y, [{ type: "title", label: "Dossier introuvable" }])
            Ilot.later(1500, () => ctx.hide())
        })
    }
    function parentDir(p) {
        return p.replace(/\\[^\\]*$/, "")
    }

    function appMenu(a, p) {
        const cur = Ilot.folders.list.find(f => f.id === Ilot.folders.sel)
        const entries = [
            { type: "title", label: a.name },
            { icon: "folder_open", label: "Ouvrir l’emplacement du fichier", run: () => page.openFolder(() =>
                a.file ? Api.invoke("folder_open", { path: page.parentDir(a.file) }) : Api.invoke("app_folder", { id: a.id, name: a.name })) }
        ]
        if (cur && cur.apps.includes(a.id)) {
            entries.push({ icon: "remove_circle_outline", label: "Retirer de « " + cur.name + " »", run: () => {
                cur.apps = cur.apps.filter(x => x !== a.id)
                page.save()
                ctx.hide()
            } })
        }
        // fichier depose : on l'enleve de tous les dossiers ; appli : on la masque
        entries.push({ icon: a.file ? "delete" : "visibility_off", label: a.file ? "Supprimer de l’îlot" : "Masquer de l’îlot", danger: true, run: () => {
            Ilot.folders.list.forEach(f => { f.apps = f.apps.filter(x => x !== a.id) })
            Ilot.folders.games = (Ilot.folders.games || []).filter(x => x !== a.id)
            if (!a.file)
                Ilot.folders.hidden = (Ilot.folders.hidden || []).concat([a.id])
            page.save()
            ctx.hide()
        } })
        entries.push({ type: "sep" })
        ;[launcherFolder()].concat(Ilot.folders.list).forEach(f => {
            const inside = f.apps.includes(a.id)
            entries.push({ icon: inside ? "check_box" : "check_box_outline_blank", label: f.name, run: () => {
                f.apps = inside ? f.apps.filter(x => x !== a.id) : f.apps.concat([a.id])
                page.save()
                ctx.hide()
            } })
        })
        entries.push({ icon: "create_new_folder", label: "Nouveau dossier…", run: () => page.askName(p, "Nouveau dossier pour " + a.name, "", name => {
            Ilot.newFolder(name).apps.push(a.id)
            page.save()
        }) })
        showCtx(p.x, p.y, entries)
    }

    function gameMenu(g, p) {
        // ajoute a la main (fichier depose ou appli)
        const extra = !g.source
        showCtx(p.x, p.y, [
            { type: "title", label: g.name },
            { icon: "play_arrow", label: "Lancer", run: () => { ctx.hide(); page.launch(g) } },
            { icon: "folder_open", label: "Ouvrir le dossier du jeu", run: () => page.openFolder(() =>
                g.file ? Api.invoke("folder_open", { path: page.parentDir(g.file) })
                    : extra ? Api.invoke("app_folder", { id: g.id, name: g.name })
                    : Api.invoke("game_folder", { id: g.id })) },
            { type: "sep" },
            // jeu detecte : masque (reaffichable) ; ajout manuel : retire du Launcher
            { icon: "delete", label: "Supprimer de l’îlot", danger: true, run: () => {
                if (extra)
                    Ilot.folders.games = (Ilot.folders.games || []).filter(x => x !== g.id)
                else
                    Ilot.folders.hiddenGames = (Ilot.folders.hiddenGames || []).concat([g.id])
                page.save()
                ctx.hide()
            } }
        ])
    }

    // clic droit sur « Toutes » : reafficher les applis masquees
    function hiddenMenu(p) {
        const list = (Ilot.folders.hidden || []).map(id => Ilot.apps.find(a => a.id === id)).filter(Boolean)
        const entries = [{ type: "title", label: list.length ? "Applis masquées" : "Aucune appli masquée" }]
        list.forEach(a => entries.push({ icon: "visibility", label: a.name, run: () => {
            Ilot.folders.hidden = Ilot.folders.hidden.filter(x => x !== a.id)
            page.save()
            ctx.hide()
        } }))
        if (list.length > 1) {
            entries.push({ icon: "select_all", label: "Tout réafficher", run: () => {
                Ilot.folders.hidden = []
                page.save()
                ctx.hide()
            } })
        }
        showCtx(p.x, p.y, entries)
    }

    // clic droit sur « Launcher » : reafficher les jeux supprimes
    function hiddenGamesMenu(p) {
        const list = (Ilot.folders.hiddenGames || []).map(id => Ilot.games.find(g => g.id === id)).filter(Boolean)
        const entries = [{ type: "title", label: list.length ? "Jeux supprimés de l’îlot" : "Aucun jeu supprimé" }]
        list.forEach(g => entries.push({ icon: "visibility", label: g.name, run: () => {
            Ilot.folders.hiddenGames = Ilot.folders.hiddenGames.filter(x => x !== g.id)
            page.save()
            ctx.hide()
        } }))
        if (list.length > 1) {
            entries.push({ icon: "select_all", label: "Tout réafficher", run: () => {
                Ilot.folders.hiddenGames = []
                page.save()
                ctx.hide()
            } })
        }
        showCtx(p.x, p.y, entries)
    }

    function folderMenu(f, p) {
        const entries = [
            { type: "title", label: f.name },
            // dossier reel associe (ex. Documents\Cours) pour y acceder vite
            { icon: "folder_open", label: "Ouvrir l’emplacement du fichier", run: () => {
                if (!f.path) {
                    ctx.hide()
                    Api.invoke("pick_folder", { title: "Emplacement du dossier « " + f.name + " »" }).then(path => {
                        if (!path)
                            return
                        f.path = path
                        page.save()
                        page.openFolder(() => Api.invoke("folder_open", { path: f.path }))
                    })
                    return
                }
                page.openFolder(() => Api.invoke("folder_open", { path: f.path }))
            } }
        ]
        if (f.path) {
            entries.push({ icon: "drive_file_move", label: "Changer l’emplacement…", run: () => {
                ctx.hide()
                Api.invoke("pick_folder", { title: "Emplacement du dossier « " + f.name + " »" }).then(path => {
                    if (path) {
                        f.path = path
                        page.save()
                    }
                })
            } })
        }
        entries.push({ type: "sep" })
        entries.push({ icon: "edit", label: "Renommer", run: () => page.askName(p, "Renommer", f.name, name => {
            f.name = name
            page.save()
        }) })
        // second clic pour confirmer (les applis ne sont pas supprimees)
        entries.push({ icon: "delete", label: "Supprimer le dossier", danger: true, confirm: "Confirmer la suppression", run: () => {
            Ilot.folders.list = Ilot.folders.list.filter(x => x !== f)
            if (Ilot.folders.sel === f.id)
                Ilot.folders.sel = ""
            page.save()
            ctx.hide()
        } })
        showCtx(p.x, p.y, entries)
    }

    // puce de dossier
    component FolderChip: Btn {
        id: chip
        property string fid
        property string icon
        property string name
        property int count: -1
        property bool gamesChip: false
        readonly property bool on: fid !== "@add" && Ilot.folders.sel === fid
        readonly property bool dropOn: page.dropChip === chip
        height: 32
        width: chipRow.implicitWidth + (name ? 21 : 18)
        radius: on || dropOn ? 12 : 16
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        color: dropOn ? Theme.primary : on ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : Theme.surfaceC
        scale: dropOn ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        readonly property color fg: dropOn ? Theme.inkPrimary : on ? Theme.inkSecondaryContainer : hovered ? Theme.ink : Theme.inkVariant
        onClicked: {
            if (fid === "@add")
                return
            Ilot.folders.sel = fid
            page.save()
        }
        Row {
            id: chipRow
            x: chip.name ? 9 : 9
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Ms {
                name: chip.icon
                size: 17
                color: chip.gamesChip && !chip.on && !chip.dropOn ? Theme.tertiary : chip.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                visible: chip.name !== ""
                text: chip.name
                color: chip.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                visible: chip.count >= 0
                text: chip.count
                px: 10.5
                opacity: 0.75
                color: chip.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
