import QtQuick

// Reglages : demarrage, touche Windows, ecran, barre, apparence, meteo,
// agendas, rotation des fonds, notifications
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "settings"
    readonly property var cfg: Ilot.cfg
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
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, cityCard.y - 40))
            Ilot.grabFocus()
            cityField.input.forceActiveFocus()
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
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
                SetRow {
                    icon: "palette"
                    title: "Apparence"
                    sub: "Les couleurs sont tirées du fond d'écran"
                    Seg {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        model: [{ id: "auto", label: "Auto" }, { id: "dark", label: "Sombre" }, { id: "light", label: "Clair" }]
                        current: page.cfg.mode
                        onPicked: id => Ilot.setCfg({ mode: id })
                    }
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
                    model: [["solid", "Opaque"], ["glass", "Translucide"], ["clear", "Très transparent"], ["wall", "Acrylique"]]
                    current: page.cfg.island_bg || "solid"
                    onPicked: v => Ilot.setCfg({ island_bg: v })
                }
            }

            // ------------------------------------------------------ meteo
            Block {
                id: cityCard
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
        }
    }
    Scroller { flick: flick }

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
