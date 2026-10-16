import QtQuick
import QtQuick.Shapes

// Controles : tuiles (Wi-Fi, Bluetooth, cafeine, ne pas deranger, mode
// sombre, minuteur), luminosite, sortie audio et melangeur ; feuilles
// (reseaux, sorties, minuteur) ; notifications a droite
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "ctrl"
    property string sheet: ""
    onSheetChanged: {
        if (sheet !== "")
            Ilot.overlay = "sheet"
        else if (Ilot.overlay === "sheet")
            Ilot.overlay = ""
    }
    Connections {
        target: Ilot
        function onCloseSheets() { page.sheet = "" }
    }
    function openSheet(name) {
        sheet = name
        if (name === "wifi")
            loadWifi(true)
        if (name === "out")
            refreshOut()
    }

    onShownChanged: if (shown) enter()
    Component.onCompleted: if (shown) enter()
    function enter() {
        Api.invoke("net_get").then(n => { Ilot.net = n })
        Api.invoke("brightness_get").then(b => {
            page.bright = b
            if (b)
                brightSlider.value = Math.round(b.level * 100)
        })
        refreshOut()
        refreshMixer()
    }
    Timer {
        interval: 2000
        repeat: true
        running: page.shown
        onTriggered: page.refreshMixer()
    }

    // ------------------------------------------------- sortie, melangeur
    property var devices: []
    property var mixer: []
    property bool mixDragging: false
    function refreshOut() {
        Api.invoke("audio_devices").then(l => { page.devices = l })
    }
    function refreshMixer() {
        if (mixDragging)
            return
        Api.invoke("mixer_get").then(l => {
            if (!page.mixDragging)
                page.mixer = l
        })
    }

    // ------------------------------------------------------ luminosite
    property var bright: null
    property bool brightBusy: false
    property var brightPending: null
    // DDC/CI est lent : on n'envoie que la derniere valeur demandee
    function pushBright() {
        if (brightBusy || brightPending === null)
            return
        brightBusy = true
        const v = brightPending
        brightPending = null
        Api.invoke("brightness_set", { level: v }).then(() => {
            page.brightBusy = false
            page.pushBright()
        }, () => {
            page.brightBusy = false
            page.pushBright()
        })
    }

    // ----------------------------------------------------------- Wi-Fi
    property var wifi: []
    property bool scanning: false
    property bool wifiBusy: false
    property string wifiMsg: ""
    function loadWifi(scan) {
        if (Ilot.net.radios.wifi === false) {
            wifi = []
            wifiMsg = "Le Wi-Fi est désactivé."
            return
        }
        if (!wifi.length)
            wifiMsg = "Recherche des réseaux…"
        Api.invoke("wifi_list", { scan: false }).then(l => page.showWifi(l))
        if (scan) {
            scanning = true
            Api.invoke("wifi_list", { scan: true }).then(l => {
                page.scanning = false
                page.showWifi(l)
            })
        }
    }
    function showWifi(l) {
        if (wifiBusy)
            return
        wifi = l
        wifiMsg = l.length ? "" : "Aucun réseau trouvé."
    }

    Item {
        id: main
        width: parent.width - 250 - 10
        height: parent.height
        clip: true

        // les autres elements disparaissent sous une feuille ouverte
        Column {
            id: mainCol
            width: parent.width
            height: parent.height
            spacing: 10
            visible: page.sheet === "" || hideDelay.running
            Timer {
                id: hideDelay
                interval: 200
            }
            Connections {
                target: page
                function onSheetChanged() { if (page.sheet !== "") hideDelay.restart() }
            }

            Grid {
                id: tiles
                width: parent.width
                columns: 3
                spacing: 8
                readonly property real tw: (width - 16) / 3
                readonly property var r: Ilot.net.radios
                Tile {
                    visible: tiles.r.wifi !== null
                    on: !!tiles.r.wifi
                    icon: "wifi"
                    title: "Wi-Fi"
                    sub: tiles.r.wifi ? Ilot.net.ssid || "Non connecté" : "Désactivé"
                    more: true
                    onMain: Ilot.toggleRadio("wifi")
                    onMoreClicked: page.openSheet("wifi")
                }
                Tile {
                    visible: tiles.r.bluetooth !== null
                    on: !!tiles.r.bluetooth
                    icon: "bluetooth"
                    title: "Bluetooth"
                    sub: tiles.r.bluetooth ? (Ilot.net.bt_devices.length ? Ilot.net.bt_devices.join(", ") : "Activé") : "Désactivé"
                    onMain: Ilot.toggleRadio("bluetooth")
                }
                Tile {
                    on: Ilot.caffeine
                    icon: "coffee"
                    title: "Caféine"
                    sub: Ilot.caffeine ? "Veille bloquée" : "Veille normale"
                    onMain: Ilot.toggleCaffeine()
                }
                Tile {
                    on: !!Ilot.cfg.dnd
                    icon: "do_not_disturb_on"
                    title: "Ne pas déranger"
                    sub: Ilot.cfg.dnd ? "Activé" : "Désactivé"
                    onMain: Ilot.toggleDnd()
                }
                Tile {
                    on: Ilot.dark
                    icon: Ilot.dark ? "dark_mode" : "light_mode"
                    title: "Mode sombre"
                    sub: Ilot.cfg.mode === "auto" ? "Auto (" + (Ilot.dark ? "sombre" : "clair") + ")" : Ilot.dark ? "Activé" : "Désactivé"
                    onMain: Ilot.setCfg({ mode: Ilot.dark ? "light" : "dark" })
                }
                Tile {
                    readonly property bool active: Ilot.tmr.running || Ilot.tmr.remaining < Ilot.tmr.total
                    on: Ilot.tmr.running
                    icon: "timer"
                    title: "Minuteur"
                    sub: active ? Ilot.fmtMs(Ilot.timerLeft) + (Ilot.tmr.running ? "" : " · en pause") : "Arrêté"
                    more: true
                    onMain: {
                        if (active)
                            Ilot.timerToggle()
                        else
                            page.openSheet("timer")
                    }
                    onMoreClicked: page.openSheet("timer")
                }
            }

            // luminosite (ecran compatible DDC/CI ou portable)
            Card {
                visible: !!page.bright
                width: parent.width
                height: 40
                radius: height / 2
                Ms {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    name: "brightness_6"
                    color: Theme.inkVariant
                }
                M3Slider {
                    id: brightSlider
                    x: 16 + 20 + 12
                    width: parent.width - x - 12 - 28 - 18
                    anchors.verticalCenter: parent.verticalCenter
                    onMoved: v => {
                        page.brightPending = v / 100
                        page.pushBright()
                    }
                }
                Txt {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    horizontalAlignment: Text.AlignRight
                    text: brightSlider.value
                    px: 12
                    tnum: true
                    color: Theme.inkVariant
                }
            }

            // sortie audio et melangeur
            Card {
                width: parent.width
                height: parent.height - tiles.height - 10 - (page.bright ? 50 : 0)
                Btn {
                    id: outBtn
                    x: 8
                    y: 8
                    width: parent.width - 16
                    height: 38
                    radius: 14
                    color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                    onClicked: page.openSheet("out")
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "speaker"
                        size: 19
                        color: Theme.inkVariant
                    }
                    Txt {
                        x: 12 + 19 + 10
                        width: parent.width - x - 41
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property var cur: page.devices.find(d => d.default)
                        text: cur ? cur.name : "Sortie audio"
                        weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Ms {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "unfold_more"
                        size: 19
                        color: Theme.inkVariant
                    }
                }
                Flickable {
                    id: mixFlick
                    x: 8
                    y: outBtn.y + outBtn.height + 6
                    width: parent.width - 18
                    height: parent.height - y - 8
                    contentHeight: mixCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: mixCol
                        width: parent.width
                        spacing: 2
                        Empty {
                            visible: page.mixer.length === 0
                            width: parent.width
                            small: true
                            text: "Aucune application ne joue de son."
                        }
                        Repeater {
                            model: page.mixer
                            Item {
                                id: mix
                                required property var modelData
                                width: mixCol.width
                                height: 38
                                property bool muted: modelData.muted
                                property real level: modelData.level
                                onModelDataChanged: {
                                    if (!slider.dragging) {
                                        muted = modelData.muted
                                        level = modelData.level
                                    }
                                }
                                Btn {
                                    id: mixIcon
                                    x: 4
                                    width: 30
                                    height: 30
                                    radius: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    tip: "Couper / rétablir"
                                    onClicked: {
                                        mix.muted = !mix.muted
                                        Api.invoke("mixer_set", { pids: mix.modelData.pids, muted: mix.muted })
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        visible: !!mix.modelData.icon
                                        width: 24
                                        height: 24
                                        source: mix.modelData.icon || ""
                                        sourceSize.width: 48
                                        asynchronous: true
                                        mipmap: true
                                    }
                                    Ms {
                                        anchors.centerIn: parent
                                        visible: !mix.modelData.icon
                                        name: "notifications"
                                        size: 19
                                        color: Theme.inkVariant
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: mix.muted
                                        radius: 9
                                        color: Theme.alpha(Theme.surfaceC, 0.7)
                                        Ms {
                                            anchors.centerIn: parent
                                            name: "volume_off"
                                            size: 18
                                            color: Theme.error
                                        }
                                    }
                                }
                                Txt {
                                    x: 4 + 30 + 10
                                    width: 100
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: mix.modelData.name
                                    px: 12
                                    elide: Text.ElideRight
                                }
                                M3Slider {
                                    id: slider
                                    x: 4 + 30 + 10 + 100 + 10
                                    width: parent.width - x - 10 - 28 - 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    trackH: 8
                                    thumbH: 18
                                    value: Math.round(mix.level * 100)
                                    fill: mix.muted ? 0 : value / 100
                                    onDraggingChanged: page.mixDragging = dragging
                                    onMoved: v => {
                                        mix.level = v / 100
                                        mix.muted = false
                                        Api.invoke("mixer_set", { pids: mix.modelData.pids, level: v / 100, muted: false })
                                    }
                                }
                                Txt {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28
                                    horizontalAlignment: Text.AlignRight
                                    text: mix.muted ? "–" : Math.round(mix.level * 100)
                                    px: 12
                                    tnum: true
                                    color: Theme.inkVariant
                                }
                            }
                        }
                    }
                }
                Scroller { flick: mixFlick }
            }
        }

        // ---------------------------------------------- feuilles
        Sheet {
            id: wifiSheet
            on: page.sheet === "wifi"
            title: "Réseaux Wi-Fi"
            onBack: page.sheet = ""
            action: IconBtn {
                small: true
                icon: "refresh"
                tip: "Rechercher"
                RotationAnimator on rotation {
                    running: page.scanning
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
                onClicked: page.loadWifi(true)
            }
            Column {
                width: parent.width
                spacing: 4
                Empty {
                    visible: page.wifiMsg !== ""
                    width: parent.width
                    small: true
                    text: page.wifiMsg
                }
                Repeater {
                    model: page.wifi
                    WifiRow {
                        width: parent.width
                    }
                }
            }
        }
        Sheet {
            on: page.sheet === "out"
            title: "Sortie audio"
            onBack: page.sheet = ""
            Column {
                width: parent.width
                spacing: 4
                Empty {
                    visible: page.devices.length === 0
                    width: parent.width
                    small: true
                    text: "Aucune sortie audio."
                }
                Repeater {
                    model: page.devices
                    Btn {
                        required property var modelData
                        width: parent.width
                        height: 40
                        radius: 16
                        color: modelData.default ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
                        readonly property color fg: modelData.default ? Theme.inkSecondaryContainer : Theme.ink
                        onClicked: Api.invoke("audio_set_default", { id: modelData.id }).then(() => {
                            page.refreshOut()
                            Ilot.refreshVolume()
                            page.refreshMixer()
                        })
                        Ms {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: /casque|headphone|headset|écouteur|airpods|buds/i.test(parent.modelData.name) ? "headphones" : "speaker"
                            color: parent.fg
                        }
                        Txt {
                            x: 44
                            width: parent.width - 44 - 44
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.name
                            weight: Font.Medium
                            elide: Text.ElideRight
                            color: parent.fg
                        }
                        Ms {
                            visible: parent.modelData.default
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            color: parent.fg
                        }
                    }
                }
            }
        }
        Sheet {
            on: page.sheet === "timer"
            title: "Minuteur"
            onBack: page.sheet = ""
            scroll: false
            TimerBody {
                width: parent.width
                height: parent.height
            }
        }
    }

    // ------------------------------------------------ notifications
    Card {
        x: parent.width - 250
        width: 250
        height: parent.height
        Item {
            id: nHead
            x: 16
            y: 12
            width: parent.width - 28
            height: 26
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    text: "Notifications"
                    px: 14
                    weight: Font.Medium
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Ilot.notifs.length || ""
                    px: 12
                    color: Theme.inkVariant
                }
            }
            IconBtn {
                anchors.right: parent.right
                small: true
                icon: "clear_all"
                tip: "Tout effacer"
                onClicked: {
                    notifCol.gone = true
                    Ilot.later(220, () => Api.invoke("notifs_dismiss", { id: null }))
                }
            }
        }
        // l'heure relative (« il y a 5 min ») se met a jour toutes les minutes
        property int tick: 0
        Timer {
            interval: 60000
            repeat: true
            running: page.shown
            onTriggered: parent.tick++
        }
        Flickable {
            id: nFlick
            x: 10
            y: nHead.y + nHead.height + 8
            width: parent.width - 20
            height: parent.height - y - 10
            contentHeight: notifCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: notifCol
                width: parent.width
                spacing: 6
                property bool gone: false
                Connections {
                    target: Ilot
                    function onNotifsChanged() { notifCol.gone = false }
                }
                Empty {
                    visible: Ilot.notifs.length === 0
                    width: parent.width
                    small: true
                    icon: Ilot.cfg.dnd ? "do_not_disturb_on" : "notifications_none"
                    text: Ilot.cfg.dnd ? "Ne pas déranger est activé" : "Aucune notification"
                }
                Repeater {
                    model: Ilot.notifs
                    NotifRow {
                        width: notifCol.width
                        tick: nFlick.parent.tick
                        gone: notifCol.gone
                    }
                }
            }
        }
        Scroller { flick: nFlick }
    }

    // ------------------------------------------------ composants
    component Tile: Item {
        id: tile
        property bool on: false
        property string icon
        property string title
        property string sub
        property bool more: false
        signal main()
        signal moreClicked()
        width: tiles.tw
        height: 52
        readonly property color fg: on ? Theme.inkPrimary : Theme.ink
        Rectangle {
            id: tbg
            anchors.fill: parent
            radius: hov.hovered ? 24 : 20
            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            color: tile.on ? Theme.primary : Theme.surfaceC
            Behavior on color { ColorAnimation { duration: 250 } }
            clip: true
            HoverHandler { id: hov }
            Btn {
                id: mainBtn
                width: parent.width - (tile.more ? 28 : 0)
                height: parent.height
                color: hovered ? Theme.alpha(tile.fg, 0.08) : "transparent"
                onClicked: tile.main()
                Row {
                    x: 10
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Ms {
                        name: tile.icon
                        size: 22
                        color: tile.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        width: mainBtn.width - 10 - 22 - 8 - 6
                        spacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            width: parent.width
                            text: tile.title
                            px: 12.5
                            weight: Font.Medium
                            elide: Text.ElideRight
                            color: tile.fg
                        }
                        Txt {
                            width: parent.width
                            text: tile.sub
                            px: 11
                            opacity: 0.8
                            elide: Text.ElideRight
                            color: tile.fg
                        }
                    }
                }
            }
            Btn {
                visible: tile.more
                x: parent.width - 28
                width: 28
                height: parent.height
                color: hovered ? Theme.alpha(tile.fg, 0.08) : "transparent"
                onClicked: tile.moreClicked()
                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.alpha(tile.fg, 0.18)
                }
                Ms {
                    anchors.centerIn: parent
                    name: "chevron_right"
                    color: tile.fg
                }
            }
        }
    }

    component Sheet: Rectangle {
        id: sh
        property bool on: false
        property string title
        property bool scroll: true
        property Item action
        default property alias content: body.data
        signal back()
        anchors.fill: parent
        z: 2
        radius: 22
        color: Theme.surfaceC
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        transform: Translate {
            y: sh.on ? 0 : 16
            Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        }
        Item {
            id: head
            x: 12
            y: 12
            width: parent.width - 24
            height: 26
            IconBtn {
                small: true
                icon: "arrow_back"
                onClicked: sh.back()
            }
            Txt {
                anchors.centerIn: parent
                text: sh.title
                px: 14
                weight: Font.Medium
            }
            Item {
                id: actionBox
                anchors.right: parent.right
                width: 26
                height: 26
                children: sh.action ? [sh.action] : []
            }
        }
        Flickable {
            id: flick
            x: 10
            y: head.y + head.height + 10
            width: parent.width - 20
            height: parent.height - y - 10
            contentHeight: sh.scroll ? body.childrenRect.height : height
            interactive: sh.scroll
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Item {
                id: body
                width: flick.width
                height: sh.scroll ? childrenRect.height : flick.height
            }
        }
        Scroller { flick: flick }
    }

    component WifiRow: Rectangle {
        id: net
        required property var modelData
        property bool asking: false
        property string state2: modelData.connected ? "Connecté" : modelData.known ? "Enregistré" : modelData.secure ? "Sécurisé" : "Ouvert"
        property bool busy: false
        height: 40 + (asking ? 44 : 0)
        radius: 16
        color: modelData.connected ? Theme.secondaryContainer : netBtn.hovered ? Theme.surfaceHigh : "transparent"
        opacity: busy ? 0.7 : 1
        readonly property color fg: modelData.connected ? Theme.inkSecondaryContainer : Theme.ink
        function connect(password) {
            busy = true
            page.wifiBusy = true
            state2 = "Connexion…"
            Api.invoke("wifi_connect", { ssidName: modelData.ssid, password: password === undefined ? null : password }).then(() => {
                Ilot.later(4000, () => {
                    page.wifiBusy = false
                    net.busy = false
                    Api.invoke("net_get").then(n => { Ilot.net = n })
                    page.loadWifi(false)
                })
            }).catch(e => {
                page.wifiBusy = false
                net.busy = false
                if (e === "password") {
                    net.asking = true
                    pass.input.forceActiveFocus()
                    return
                }
                net.state2 = String(e)
            })
        }
        Btn {
            id: netBtn
            width: parent.width
            height: 40
            radius: 16
            onClicked: {
                if (net.modelData.connected) {
                    net.state2 = "Déconnexion…"
                    Api.invoke("wifi_disconnect").then(() => Ilot.later(1500, () => {
                        Api.invoke("net_get").then(n => { Ilot.net = n })
                        page.loadWifi(false)
                    }))
                    return
                }
                if (net.modelData.secure && !net.modelData.known) {
                    net.asking = true
                    Ilot.grabFocus()
                    pass.input.forceActiveFocus()
                    return
                }
                net.connect()
            }
            Ms {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                readonly property int s: net.modelData.signal
                name: s > 66 ? "wifi" : s > 33 ? "wifi_2_bar" : "wifi_1_bar"
                color: net.fg
            }
            Column {
                x: 44
                width: parent.width - 44 - 36
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: net.modelData.ssid
                    weight: Font.Medium
                    elide: Text.ElideRight
                    color: net.fg
                }
                Txt {
                    text: net.state2
                    px: 11.5
                    opacity: 0.75
                    color: net.fg
                }
            }
            Ms {
                visible: net.modelData.secure
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: 15
                opacity: 0.6
                color: net.fg
            }
        }
        Row {
            visible: net.asking
            x: 44
            y: 40
            spacing: 8
            Field {
                id: pass
                width: net.width - 44 - 12 - 26 - 8
                password: true
                placeholder: "Mot de passe"
                onAccepted: net.connect(text)
            }
            IconBtn {
                small: true
                filled: true
                icon: "arrow_forward"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: net.connect(pass.text)
            }
        }
    }
}
