import QtQuick
import IlotCore

// Reglages, en onglets (a gauche) : general (demarrage, touche Windows,
// ecran, notifications, sauvegarde), barre, apparence (et rotation des
// fonds), pilule, jeu et absence, accessibilite, meteo et agenda, raccourcis
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

    onShownChanged: if (shown) load()
    Component.onCompleted: if (shown) load()
    function load() {
        Api.invoke("settings_get").then(s => {
            page.autostart = s.autostart
            page.monitors = s.monitors
            page.chosenMonitor = s.monitor === undefined ? null : s.monitor
            Ilot.cfg = Object.assign({}, Ilot.cfg, s)
        })
        refreshWinKey()
        if (!changelog.length)
            Api.invoke("changelog").then(l => { page.changelog = l })
        Api.invoke("update_get").then(u => { Watch.upd = u })
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
        Column {
            id: nav
            width: parent.width
            spacing: 3
            Repeater {
                model: page.sections
                Btn {
                    id: navBtn
                    required property var modelData
                    readonly property bool on: page.section === modelData.id
                    width: nav.width
                    height: 38
                    radius: on || hovered ? 19 : 14
                    Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
                    readonly property color fg: on ? Theme.inkSecondaryContainer : Theme.ink
                    onClicked: Ilot.settingsSection = modelData.id
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: navBtn.modelData.icon
                        size: 19
                        color: navBtn.on ? navBtn.fg : Theme.inkVariant
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
                    title: "Apparence"
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
                SubTitle { text: "Couleur" }
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
                SubTitle { text: "Thème" }
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
                    sub: "Quand le mode n'est pas « Auto »"
                    toggle: true
                    checked: !!page.cfg.win_mode
                    onToggled: on => Ilot.setCfg({ win_mode: on })
                }
                SetRow {
                    subRow: true
                    title: "Fond de l'îlot"
                    sub: "Opaque, translucide, ou flou acrylique de Windows derrière l'îlot et la barre"
                }
                Chips {
                    model: [["solid", "Opaque"], ["black", "Noir pur"], ["glass", "Translucide"], ["clear", "Très transparent"], ["wall", "Acrylique"], ["aurora", "Aurore boréale"]]
                    current: page.cfg.island_bg || "solid"
                    onPicked: v => Ilot.setCfg({ island_bg: v })
                }
                SubTitle { text: "Contour de l'îlot" }
                Chips {
                    model: [["none", "Aucun"], ["line", "Liseré"], ["glow", "Lueur"], ["rgb", "Arc-en-ciel"], ["pulse", "Pulsation"]]
                    current: page.cfg.border || "none"
                    onPicked: v => Ilot.setCfg({ border: v })
                }
                SubTitle { text: "Forme de l'îlot" }
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
                SubTitle { text: "Fond de l'onglet Média" }
                Chips {
                    model: [["art", "Pochette floutée"], ["color", "Couleur"], ["gradient", "Dégradé"], ["none", "Aucun"]]
                    current: page.cfg.media_bg || "art"
                    onPicked: v => Ilot.setCfg({ media_bg: v })
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
                SubTitle { text: "Compagnon" }
                Chips {
                    model: [["blob", "Blob"], ["cat", "Chat"], ["ghost", "Fantôme"], ["off", "Masqué"]]
                    current: page.cfg.pet || "blob"
                    onPicked: v => Ilot.setCfg({ pet: v })
                }
                SetRow {
                    subRow: true
                    title: "Il se promène quand tu ne fais rien"
                    sub: "Après 90 s sans clavier ni souris, au-dessus de la barre des tâches"
                    toggle: true
                    disabled: page.cfg.pet === "off"
                    checked: !!page.cfg.pet_walk
                    onToggled: on => Ilot.setCfg({ pet_walk: on })
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

            // -------------------------------------------- mode jeu, absent
            Block {
                sec: "game"
                SetRow {
                    icon: "sports_esports"
                    title: "Mode jeu"
                    sub: "Quand un jeu du Launcher tourne"
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
                    title: "Profil de volume « Jeu »"
                    sub: "Appliqué au lancement (Contrôles › profils), volumes d'avant rétablis ensuite"
                    toggle: true
                    disabled: !page.cfg.game_mode
                    checked: !!page.cfg.mix_auto
                    onToggled: on => Ilot.setCfg({ mix_auto: on })
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
                                page.cities = []
                                cityField.text = ""
                                Ilot.setCfg({ city: { name: modelData.name, lat: modelData.latitude, lon: modelData.longitude } })
                                Ilot.later(300, () => Ilot.refreshWeather())
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
                        SetRow {
                            required property var modelData
                            icon: modelData.icon
                            title: modelData.label
                            sub: modelData.desc
                            toggle: true
                            checked: Ilot.hasTab(modelData.id)
                            onToggled: on => Ilot.setAddon(modelData.id, on)
                        }
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
                                    color: "transparent"
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
    // « Ctrl+Alt+KeyM » -> « Ctrl+Alt+M »
    function keyLabel(c) {
        return c.replace(/Key([A-Z])/g, "$1").replace(/Digit(\d)/g, "$1").replace(/Numpad/g, "Pavé ").replace(/VK(\d+)/, "touche $1")
    }
    property string keyRec: ""

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
        color: icon ? (on ? Theme.secondaryContainer : Theme.surfaceHigh) : fill
        border.width: on ? 3 : 0
        border.color: Theme.ink
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
    component KeyRow: Item {
        id: kr
        required property var modelData
        readonly property string action: modelData[0]
        readonly property string combo: Watch.keyMap[action] || ""
        readonly property bool rec: page.keyRec === action
        readonly property bool bad: Watch.keyBad.indexOf(action) >= 0
        width: parent ? parent.width : 0
        height: 34
        Txt {
            x: 54
            anchors.verticalCenter: parent.verticalCenter
            text: kr.modelData[1]
            color: kr.bad ? Theme.error : Theme.ink
        }
        Btn {
            id: keyBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(90, keyText.implicitWidth + 24)
            height: 28
            radius: 14
            color: kr.rec ? Theme.primary : kr.combo ? Theme.secondaryContainer : Theme.surfaceHigh
            border.width: kr.bad ? 2 : 0
            border.color: Theme.error
            tip: kr.bad ? "Déjà pris par une autre appli : choisis-en un autre" : "Clic puis appuie sur la combinaison · Échap : annuler · Retour arrière : effacer"
            onClicked: {
                page.keyRec = kr.rec ? "" : kr.action
                if (page.keyRec) {
                    Ilot.pinned = true
                    Ilot.grabFocus()
                    keyBtn.forceActiveFocus()
                }
            }
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
                map[kr.action] = mods.concat([k]).join("+")
                page.keyRec = ""
                Watch.saveKeys(map)
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
